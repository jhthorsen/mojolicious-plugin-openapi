package JSON::Validator::OpenAPI::Mojolicious;
use Mojo::Base 'JSON::Validator';

use Carp 'confess';
use Mojo::Util;
use Scalar::Util 'looks_like_number';
use Time::Local ();

use constant DEBUG   => $ENV{JSON_VALIDATOR_DEBUG} || 0;
use constant IV_SIZE => eval 'require Config;$Config::Config{ivsize}';

our %COLLECTION_RE = (pipes => qr{\|}, csv => qr{,}, ssv => qr{\s}, tsv => qr{\t});
our %VERSIONS      = (
  v2 => 'http://swagger.io/v2/schema.json',
  v3 => 'https://spec.openapis.org/oas/3.0/schema/2019-04-02'
);

has version => 2;

sub E { JSON::Validator::Error->new(@_) }

sub load_and_validate_schema {
  my ($self, $spec, $args) = @_;

  $spec = $self->bundle({replace => 1, schema => $spec}) if $args->{allow_invalid_ref};
  local $args->{schema}
    = $args->{schema} ? $VERSIONS{$args->{schema}} || $args->{schema} : $VERSIONS{v2};

  $self->version($1) if !$self->{version} and $args->{schema} =~ m!(?:/v||/oas/)(\d)!;

  my @errors;
  my $gather = sub {
    push @errors, E($_[1], 'Only one parameter can have "in":"body"')
      if 1 < grep { $_->{in} eq 'body' } @{$_[0] || []};
  };

  $self->_get($self->_resolve($spec), ['paths', undef, undef, 'parameters'], '', $gather);
  confess join "\n", "Invalid JSON specification $spec:", map {"- $_"} @errors if @errors;
  $self->SUPER::load_and_validate_schema($spec, $args);

  if (my $class = $args->{version_from_class}) {
    if (UNIVERSAL::can($class, 'VERSION') and $class->VERSION) {
      $self->schema->data->{info}{version} ||= $class->VERSION;
    }
  }

  return $self;
}

sub validate_input {
  my $self = shift;
  local $self->{validate_input} = 1;
  local $self->{root}           = $self->schema;
  $self->validate(@_);
}

sub validate_request {
  my ($self, $c, $schema, $input) = @_;
  my @errors;

  local $self->{cache};

  # v3 Content-Type
  if (my $body_schema = $schema->{requestBody}) {
    push @errors, $self->_validate_request_body($c, $body_schema);
  }

  for my $p (@{$schema->{parameters} || []}) {
    my ($in, $name, $type) = @$p{qw(in name type)};
    $type ||= $p->{schema}{type} if $p->{schema}; # v3
    my ($exists, $value) = (0, undef);

    if ($in eq 'body') {
      $value = $self->_get_request_data($c, $in);
      $exists = length $value if defined $value;
    }
    elsif ($in eq 'formData' and $type eq 'file') {
      $value = $self->_get_request_uploads($c, $name)->[-1];
      $exists = $value ? 1 : 0;
    }
    else {
      my $key = $in eq 'header' ? lc $name : $name;
      $value  = $self->_get_request_data($c, $in);
      $exists = exists $value->{$key};
      $value  = $value->{$key};
    }

    if (defined $value and ref $p->{items} eq 'HASH' and $p->{collectionFormat}) {
      $value = $self->_coerce_by_collection_format($value, $p);
    }

    {
      local $p->{default} //= $p->{schema}{default}
        if $p->{schema} && exists $p->{schema}{default}; # v3
      ($exists, $value) = (1, $p->{default}) if !$exists and exists $p->{default};
    }

    if ($type and defined $value) {
      if ($type ne 'array' and ref $value eq 'ARRAY') {
        $value = $value->[-1];
      }
      if (($type eq 'integer' or $type eq 'number') and Scalar::Util::looks_like_number($value)) {
        $value += 0;
      }
      elsif ($type eq 'boolean') {
        if (!$value or $value =~ /^(?:false)$/) {
          $value = Mojo::JSON->false;
        }
        elsif ($value =~ /^(?:1|true)$/) {
          $value = Mojo::JSON->true;
        }
      }
    }

    if (my @e = $self->_validate_request_value($p, $name => $value)) {
      push @errors, @e;
    }
    elsif ($exists) {
      $input->{$name} = $value;
      $self->_set_request_data($c, $in, $name => $value) if defined $value;
    }
  }

  return @errors;
}

sub validate_response {
  my ($self, $c, $schema, $status, $data) = @_;

  return JSON::Validator::E('/' => "No responses rules defined for status $status.")
    unless my $res_schema = $schema->{responses}{$status} || $schema->{responses}{default};

  if ($self->version eq '3') {
    my $accept = $self->_negotiate_accept_header($c, $res_schema);
    return JSON::Validator::E('/' => "No responses rules defined for Accept $accept.")
      unless $res_schema = $res_schema->{content}{$accept};
    $c->stash(openapi_negotiated_content_type => $accept);
  }

  my @errors;
  push @errors, $self->_validate_response_headers($c, $res_schema->{headers})
    if $res_schema->{headers};

  if ($res_schema->{'x-json-schema'}) {
    warn "[OpenAPI] Validate using x-json-schema\n" if DEBUG;
    push @errors, $self->validate($data, $res_schema->{'x-json-schema'});
  }
  elsif ($res_schema->{schema}) {
    warn "[OpenAPI] Validate using schema\n" if DEBUG;
    push @errors, $self->validate($data, $res_schema->{schema});
  }

  return @errors;
}

sub _build_formats {
  my $self    = shift;
  my $formats = $self->SUPER::_build_formats;

  $formats->{byte}     = \&_match_byte_string;
  $formats->{double}   = sub { _match_number(double => $_[0], '') };
  $formats->{float}    = sub { _match_number(float => $_[0], '') };
  $formats->{int32}    = sub { _match_number(int32 => $_[0], 'l') };
  $formats->{int64}    = sub { _match_number(int64 => $_[0], IV_SIZE >= 8 ? 'q' : '') };
  $formats->{password} = sub {undef};

  return $formats;
}

sub _coerce_by_collection_format {
  my ($self, $data, $schema) = @_;
  my $type = ($schema->{items} ? $schema->{items}{type} : $schema->{type}) || '';

  if ($schema->{collectionFormat} eq 'multi') {
    $data = [$data] unless ref $data eq 'ARRAY';
    @$data = map { $_ + 0 } @$data if $type eq 'integer' or $type eq 'number';
    return $data;
  }

  my $re = $COLLECTION_RE{$schema->{collectionFormat}} || ',';
  my $single = ref $data eq 'ARRAY' ? 0 : ($data = [$data]);

  for my $i (0 .. @$data - 1) {
    my @d = split /$re/, ($data->[$i] // '');
    $data->[$i] = ($type eq 'integer' or $type eq 'number') ? [map { $_ + 0 } @d] : \@d;
  }

  return $single ? $data->[0] : $data;
}

sub _confess_invalid_in {
  confess "Unsupported \$in: $_[0]. Please report at https://github.com/jhthorsen/json-validator";
}

sub _get_request_data {
  my ($self, $c, $in) = @_;

  if ($in eq 'query') {
    return $self->{cache}{$in} ||= $c->req->url->query->to_hash(1);
  }
  elsif ($in eq 'path') {
    return $c->match->stack->[-1];
  }
  elsif ($in eq 'formData') {
    return $self->{cache}{$in} ||= $c->req->body_params->to_hash(1);
  }
  elsif ($in eq 'cookie') {
    return $self->{cache}{$in} ||= {map { ($_->name, $_->value) } @{$c->req->cookies}};
  }
  elsif ($in eq 'header') {
    my $headers = $c->req->headers->to_hash(1);
    return $self->{cache}{$in} ||= {map { lc($_) => $headers->{$_} } keys %$headers};
  }
  elsif ($in eq 'body') {
    return $c->req->json;
  }
  else {
    _confess_invalid_in($in);
  }
}

sub _get_request_uploads {
  my ($self, $c, $name) = @_;
  return $c->req->every_upload($name);
}

sub _get_response_data {
  my ($self, $c, $in) = @_;
  return $c->res->headers->to_hash(1) if $in eq 'header';
  _confess_invalid_in($in);
}

sub _match_byte_string { $_[0] =~ /^[A-Za-z0-9\+\/\=]+$/ ? undef : 'Does not match byte format.' }

sub _match_number {
  my ($name, $val, $format) = @_;
  return 'Does not look like an integer' if $name =~ m!^int! and $val !~ /^-?\d+(\.\d+)?$/;
  return 'Does not look like a number.' unless looks_like_number $val;
  return undef unless $format;
  return undef if $val eq unpack $format, pack $format, $val;
  return "Does not match $name format.";
}

sub _negotiate_accept_header {
  my ($self, $c, $schema) = @_;
  my $accept    = $c->req->headers->accept || '*/*';
  my @in_schema = sort { length $b <=> length $a } keys %{$schema->{content}};
  my (@from_req, %from_req);

  /^\s*([^,; ]+)(?:\s*\;\s*q\s*=\s*(\d+(?:\.\d+)?))?\s*$/i and $from_req{lc $1} = $2 // 1
    for split /,/, $accept;
  @from_req = sort { $from_req{$b} <=> $from_req{$a} } sort keys %from_req;

  # Check for exact match
  for my $ct (@from_req) {
    return $ct if $schema->{content}{$ct};
  }

  # Check for closest match
  for my $re (map { s!\*!.*!g; qr{$_} } grep {/\*/} @in_schema) {
    for my $ct (@from_req) {
      return $ct if $ct =~ $re;
    }
  }
  for my $re (map { s!\*!.*!g; qr{$_} } grep {/\*/} @from_req) {
    for my $ct (@in_schema) {
      return $ct if $ct =~ $re;
    }
  }

  # Could not find any valid content type
  return $accept;
}

sub _resolve_ref {
  my ($self, $topic, $url) = @_;
  $topic->{'$ref'} = "#/definitions/$topic->{'$ref'}" if $topic->{'$ref'} =~ /^\w+$/;
  return $self->SUPER::_resolve_ref($topic, $url);
}

sub _set_request_data {
  my ($self, $c, $in, $name => $value) = @_;

  if ($in eq 'query') {
    $c->req->url->query->merge($name => $value);
    $c->req->params->merge($name => $value);
  }
  elsif ($in eq 'path') {
    $c->stash($name => $value);
  }
  elsif ($in eq 'formData') {
    $c->req->params->merge($name => $value);
    $c->req->body_params->merge($name => $value);
  }
  elsif ($in eq 'cookie') {
    $c->req->cookie($name => $value);
  }
  elsif ($in eq 'header') {
    $c->req->headers->header($name => ref $value eq 'ARRAY' ? @$value : $value);
  }
  elsif ($in ne 'body') {    # no need to write body back
    _confess_invalid_in($in);
  }
}

sub _to_list {
  return ref $_[0] eq 'ARRAY' ? @{$_[0]} : $_[0] ? ($_[0]) : ();
}

sub _validate_request_body {
  my ($self, $c, $body_schema) = @_;
  my $ct = $c->req->headers->content_type // '';

  $ct =~ s!;.*$!!;
  if (my $schema = $body_schema->{content}{$ct}) {
    my $body = $self->_get_request_data($c, $ct =~ /\bform\b/ ? 'formData' : 'body');
    local $schema->{required} //= $body_schema->{required};
    return $self->_validate_request_value($schema, body => $body);
  }

  return JSON::Validator::E('/' => "No requestBody rules defined for Content-Type $ct.") if $ct;
  return JSON::Validator::E('/', 'Invalid Content-Type.');
}

sub _validate_request_value {
  my ($self, $p, $name, $value) = @_;
  my $type = $p->{type} || 'object';
  my @e;

  return if !defined $value and !$p->{required};

  my $in     = $p->{in} // 'body';
  my $schema = {
    properties => {$name => $p->{'x-json-schema'} || $p->{schema} || $p},
    required   => [$p->{required} ? ($name) : ()]
  };

  if ($in eq 'body') {
    warn "[OpenAPI] Validate $in $name\n" if DEBUG;
    if ($p->{'x-json-schema'}) {
      return $self->validate({$name => $value}, $schema);
    }
    else {
      return $self->validate_input({$name => $value}, $schema);
    }
  }
  elsif (defined $value) {
    warn "[OpenAPI] Validate $in $name=$value\n" if DEBUG;
    return $self->validate_input({$name => $value}, $schema);
  }
  else {
    warn "[OpenAPI] Validate $in $name=undef\n" if DEBUG;
    return $self->validate_input({$name => $value}, $schema);
  }

  return;
}

sub _validate_response_headers {
  my ($self, $c, $schema) = @_;
  my $input   = $self->_get_response_data($c, 'header');
  my $version = $self->version;
  my @errors;

  for my $name (keys %$schema) {
    my $p = $schema->{$name};
    $p = $p->{schema} if $version eq '3';

    # jhthorsen: I think that the only way to make a header required,
    # is by defining "array" and "minItems" >= 1.
    if ($p->{type} eq 'array') {
      push @errors, $self->validate($input->{$name}, $p);
    }
    elsif ($input->{$name}) {
      push @errors, $self->validate($input->{$name}[0], $p);
      $c->res->headers->header($name => $input->{$name}[0] ? 'true' : 'false')
        if $p->{type} eq 'boolean' and !@errors;
    }
  }

  return @errors;
}

sub _validate_type_array {
  my ($self, $data, $path, $schema) = @_;

  if (ref $schema->{items} eq 'HASH' and $schema->{items}{collectionFormat}) {
    $data = $self->_coerce_by_collection_format($data, $schema->{items});
  }

  return $self->SUPER::_validate_type_array($data, $path, $schema);
}

sub _validate_type_file {
  my ($self, $data, $path, $schema) = @_;

  return unless $schema->{required} and (not defined $data or not length $data);
  return JSON::Validator::E($path => 'Missing property.');
}

sub _validate_type_object {
  my ($self, $data, $path, $schema) = @_;
  return shift->SUPER::_validate_type_object(@_) unless ref $data eq 'HASH';

  # Support "nullable" in v3
  # "nullable" is the same as "type":["null", ...], which is supported by many
  # tools, even though not officially supported by OpenAPI.
  my %properties = %{$schema->{properties} || {}};
  local $schema->{properties} = \%properties;
  if ($self->version eq '3') {
    for my $key (keys %properties) {
      next unless $properties{$key}{nullable};
      $properties{$key} = {%{$properties{$key}}};
      $properties{$key}{type} = ['null', _to_list($properties{$key}{type})];
    }
  }

  return shift->SUPER::_validate_type_object(@_) unless $self->{validate_input};

  my (@e, %ro);
  for my $p (keys %properties) {
    next unless $properties{$p}{readOnly};
    push @e, JSON::Validator::E("$path/$p", "Read-only.") if exists $data->{$p};
    $ro{$p} = 1;
  }

  my $discriminator = $schema->{discriminator};
  if ($discriminator and !$self->{inside_discriminator}) {
    my $name = $data->{$discriminator}
      or return JSON::Validator::E($path, "Discriminator $discriminator has no value.");
    my $dschema = $self->{root}->get("/definitions/$name")
      or return JSON::Validator::E($path, "No definition for discriminator $name.");
    local $self->{inside_discriminator} = 1;    # prevent recursion
    return $self->_validate($data, $path, $dschema);
  }

  local $schema->{required} = [grep { !$ro{$_} } @{$schema->{required} || []}];

  return @e, $self->SUPER::_validate_type_object($data, $path, $schema);
}

1;

=encoding utf8

=head1 NAME

JSON::Validator::OpenAPI::Mojolicious - JSON::Validator request/response adapter for Mojolicious

=head1 SYNOPSIS

  my $validator = JSON::Validator::OpenAPI::Mojolicious->new;
  $validator->load_and_validate_schema("myschema.json");

  my @errors = $validator->validate_request(
                 $c,
                 $validator->get([paths => "/wharever", "get"]),
                 $c->validation->output,
               );

  @errors = $validator->validate_response(
              $c,
              $validator->get([paths => "/wharever", "get"]),
              200,
              {some => {response => "data"}},
            );

=head1 DESCRIPTION

L<JSON::Validator::OpenAPI::Mojolicious> is a module for validating request and
response data from/to your L<Mojolicious> application.

Do not use this module directly. Use L<Mojolicious::Plugin::OpenAPI> instead.

=head1 STASH VARIABLES

=head2 openapi_negotiated_content_type

  $str = %c->stash("openapi_negotiated_content_type");

This value will be set when the Accept header has been validated successfully
against an OpenAPI v3 schema. Note that this could have the value of "*/*" or
other invalid "Content-Header" values. It will be C<undef> if the "Accept"
header is not accepteed.

Unfortunately, this variable is not set until you call
L<Mojolicious::Controller/render>, since we need a status code to figure out
which types are accepted.

This means that if you want to validate the "Accept" header on input, then you
have to specify that as a parameter in the spec.

=head1 ATTRIBUTES

L<JSON::Validator::OpenAPI::Mojolicious> inherits all attributes from L<JSON::Validator>.

=head2 formats

  $validator = $validator->formats({});
  $hash_ref = $validator->formats;

Open API support the same formats as L<JSON::Validator>, but adds the following
to the set:

=over 4

=item * byte

A padded, base64-encoded string of bytes, encoded with a URL and filename safe
alphabet. Defined by RFC4648.

=item * date

An RFC3339 date in the format YYYY-MM-DD

=item * double

Cannot test double values with higher precision then what
the "number" type already provides.

=item * float

Will always be true if the input is a number, meaning there is no difference
between  L</float> and L</double>. Patches are welcome.

=item * int32

A signed 32 bit integer.

=item * int64

A signed 64 bit integer. Note: This check is only available if Perl is
compiled to use 64 bit integers.

=back

=head2 version

  $str = $validator->version;

Used to get the OpenAPI Schema version to use. Will be set automatically when
using L</load_and_validate_schema>, unless already set. Supported values are
"2" an "3".

=head1 METHODS

L<JSON::Validator::OpenAPI::Mojolicious> inherits all attributes from L<JSON::Validator>.

=head2 load_and_validate_schema

  $validator = $validator->load_and_validate_schema($schema, \%args);

Will load and validate C<$schema> against the OpenAPI specification. C<$schema>
can be anything L<JSON::Validator/schema> accepts. The expanded specification
will be stored in L<JSON::Validator/schema> on success. See
L<JSON::Validator/schema> for the different version of C<$url> that can be
accepted.

C<%args> can be used to further instruct the expansion and validation process:

=over 2

=item * allow_invalid_ref

Setting this to a true value, will disable the first pass. This is useful if
you don't like the restrictions set by OpenAPI, regarding where you can use
C<$ref> in your specification.

=item * version_from_class

Setting this to a module/class name will use the version number from the
class and overwrite the version in the specification:

  {
    "info": {
      "version": "1.00" // <-- this value
    }
  }

=back

The validation is done with a two pass process:

=over 2

=item 1.

First it will check if the C<$ref> is only specified on the correct places.
This can be disabled by setting L</allow_invalid_ref> to a true value.

=item 2.

Validate the expanded version of the spec, (without any C<$ref>) against the
OpenAPI schema.

=back

=head2 validate_input

  @errors = $validator->validate_input($data, $schema);

This method will make sure "readOnly" is taken into account, when validating
data sent to your API.

=head2 validate_request

  @errors = $validator->validate_request($c, $schema, \%input);

Takes an L<Mojolicious::Controller> and a schema definition and returns a list
of errors, if any. Validated input parameters are moved into the C<%input>
hash.

=head2 validate_response

  @errors = $validator->validate_response($c, $schema, $status, $data);

=head1 SEE ALSO

L<Mojolicious::Plugin::OpenAPI>.

L<JSON::Validator>.

L<http://openapi-specification-visual-documentation.apihandyman.io/>

=cut
