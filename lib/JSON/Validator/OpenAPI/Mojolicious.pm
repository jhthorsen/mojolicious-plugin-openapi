package JSON::Validator::OpenAPI::Mojolicious;
use Mojo::Base 'JSON::Validator';

use Carp 'confess';
use Mojo::Util;
use Scalar::Util ();
use Time::Local  ();

use constant DEBUG => $ENV{JSON_VALIDATOR_DEBUG} || 0;
use constant IV_SIZE => eval 'require Config;$Config::Config{ivsize}';

our %COLLECTION_RE = (pipes => qr{\|}, csv => qr{,}, ssv => qr{\s}, tsv => qr{\t});
our %VERSIONS
  = (v2 => 'http://swagger.io/v2/schema.json', v3 => 'http://swagger.io/v3/schema.yaml');

has version => 2;

sub E { JSON::Validator::Error->new(@_) }

sub load_and_validate_schema {
  my ($self, $spec, $args) = @_;

  $spec = $self->bundle({replace => 1, schema => $spec}) if $args->{allow_invalid_ref};
  local $args->{schema}
    = $args->{schema} ? $VERSIONS{$args->{schema}} || $args->{schema} : $VERSIONS{v2};

  $self->version($1) if !$self->{version} and $args->{schema} =~ m!/v(\d+)/!;

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

  # v3
  if (my $body_schema = $schema->{requestBody}) {
    my $types = $self->_detect_content_type($c, 'content_type');
    my $validated;
    for my $type (@$types) {
      next unless my $type_spec = $body_schema->{content}{$type};
      my $body = $self->_get_request_data($c, $type =~ /\bform\b/ ? 'formData' : 'body');
      push @errors, $self->_validate_request_value($type_spec, body => $body);
      $validated = 1;
    }

    if (!$validated and $body_schema->{required}) {
      push @errors,
        JSON::Validator::E('/' => @$types
        ? "No requestBody rules defined for type @$types."
        : "Invalid Content-Type.");
    }
  }

  for my $p (@{$schema->{parameters} || []}) {
    my ($in, $name, $type) = @$p{qw(in name type)};
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

    ($exists, $value) = (1, $p->{default}) if !$exists and exists $p->{default};

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
  my ($blueprint, @errors);

  if ($self->version eq '3') {
    my $accept = $self->_detect_content_type($c, 'accept');
    my $for_status = $schema->{responses}{$status} || $schema->{responses}{default}
      or return JSON::Validator::E('/' => "No responses rules defined for status $status.");
    $blueprint = $for_status if $status eq '201';
    $blueprint ||= $for_status->{content}{$_} and last for @$accept;
    $blueprint or return JSON::Validator::E('/' => "No responses rules defined for type @$accept.");
  }
  else {
    $blueprint = $schema->{responses}{$status} || $schema->{responses}{default}
      or return JSON::Validator::E('/' => "No responses rules defined for status $status.");
  }

  push @errors, $self->_validate_response_headers($c, $blueprint->{headers})
    if $blueprint->{headers};

  if ($blueprint->{'x-json-schema'}) {
    warn "[OpenAPI] Validate using x-json-schema\n" if DEBUG;
    push @errors, $self->validate($data, $blueprint->{'x-json-schema'});
  }
  elsif ($blueprint->{schema}) {
    warn "[OpenAPI] Validate using schema\n" if DEBUG;
    push @errors, $self->validate($data, $blueprint->{schema});
  }

  return @errors;
}

sub _build_formats {
  my $self    = shift;
  my $formats = $self->SUPER::_build_formats;

  if ($self->version eq '3') {
    $formats->{uriref} = sub {'TODO'};
  }

  $formats->{byte}     = \&_is_byte_string;
  $formats->{date}     = \&_is_date;
  $formats->{double}   = \&Scalar::Util::looks_like_number;
  $formats->{float}    = \&Scalar::Util::looks_like_number;
  $formats->{int32}    = sub { _is_number($_[0], 'l'); };
  $formats->{int64}    = IV_SIZE >= 8 ? sub { _is_number($_[0], 'q'); } : sub {1};
  $formats->{password} = sub {1};

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

sub _detect_content_type {
  my ($self, $c, $header) = @_;
  my %types;
  /^\s*([^,; ]+)(?:\s*\;\s*q\s*=\s*(\d+(?:\.\d+)?))?\s*$/i and $types{lc $1} = $2 // 1
    for split ',', $c->req->headers->$header // '';
  return [sort { $types{$b} <=> $types{$a} } sort keys %types];
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

sub _is_byte_string { $_[0] =~ /^[A-Za-z0-9\+\/\=]+$/ }

sub _is_date { $_[0] && JSON::Validator::_is_date_time("$_[0]T00:00:00") }

sub _is_number {
  return unless $_[0] =~ /^-?\d+(\.\d+)?$/;
  return $_[0] eq unpack $_[1], pack $_[1], $_[0];
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
    $c->req->headers->header($name => $value);
  }
  elsif ($in ne 'body') {    # no need to write body back
    _confess_invalid_in($in);
  }
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
  my $input = $self->_get_response_data($c, 'header');
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
  return shift->SUPER::_validate_type_object(@_) unless $_[0]->{validate_input};

  my ($self, $data, $path, $schema) = @_;
  my $properties = $schema->{properties} || {};
  my $discriminator = $schema->{discriminator};
  my (%ro, @e);

  for my $p (keys %$properties) {
    next unless $properties->{$p}{readOnly};
    push @e, JSON::Validator::E("$path/$p", "Read-only.") if exists $data->{$p};
    $ro{$p} = 1;
  }

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
