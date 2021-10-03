package Mojolicious::Plugin::OpenAPI::Parameters;
use Mojo::Base 'Mojolicious::Plugin';

use JSON::Validator::Util qw(is_bool schema_type);
use Mojo::JSON qw(encode_json);

sub register {
  my ($self, $app, $config) = @_;

  $app->helper('openapi.build_response_body' => $config->{renderer}
      || \&_helper_build_response_body);
  $app->helper('openapi.build_schema_request'       => \&_helper_build_schema_request);
  $app->helper('openapi.build_schema_response'      => \&_helper_build_schema_response);
  $app->helper('openapi.coerce_request_parameters'  => \&_helper_coerce_request_parameters);
  $app->helper('openapi.coerce_response_parameters' => \&_helper_coerce_response_parameters);
  $app->helper('openapi.parse_request_body'         => \&_helper_parse_request_body);
}

sub _bool {
  return map { !is_bool($_) ? $_ : $_ ? 'true' : 'false' } @_;
}

sub _helper_build_response_body {
  my $c = shift;
  return $_[0]->slurp if UNIVERSAL::isa($_[0], 'Mojo::Asset');
  $c->res->headers->content_type('application/json;charset=UTF-8')
    unless $c->res->headers->content_type;
  return encode_json($_[0]);
}

sub _helper_build_schema_request {
  my $c   = shift;
  my $req = $c->req;

  $c->stash->{'openapi.evaluated_request_parameters'} = \my @evaluated;

  return {
    body => sub {
      $evaluated[@evaluated] = $c->openapi->parse_request_body($_[1]);
    },
    formData => sub {
      my $name  = shift;
      my $value = $req->body_params->every_param($name);
      my $n     = @$value;
      return $evaluated[@evaluated] = {exists => 1, value => $n > 1 ? $value : $value->[0]}
        if $n > 0;

      $value = $req->upload($name);
      return $evaluated[@evaluated] = {exists => !!$value, value => $value && $value->size};
    },
    header => sub {
      my $name  = shift;
      my $value = $req->headers->every_header($name);
      return $evaluated[@evaluated] = {exists => !!@$value, value => $value};
    },
    path => sub {
      my $name  = shift;
      my $stash = $c->match->stack->[-1];
      return $evaluated[@evaluated] = {exists => exists $stash->{$name}, value => $stash->{$name}};
    },
    query => sub {
      return $evaluated[@evaluated] = {exists => 1, value => $req->url->query->to_hash}
        unless my $name = shift;
      my $value = $req->url->query->every_param($name);
      my $n     = @$value;
      return $evaluated[@evaluated] = {exists => !!$n, value => $n > 1 ? $value : $value->[0]};
    },
  };
}

sub _helper_build_schema_response {
  my $c   = shift;
  my $res = $c->res;

  $c->stash->{'openapi.evaluated_response_parameters'} = \my @evaluated;

  return {
    body => sub {
      my $res = $c->stash('openapi');
      return $evaluated[@evaluated]
        = {accept => $c->req->headers->accept, exists => !!$res, value => $res};
    },
    header => sub {
      my $name  = shift;
      my $value = $res->headers->every_header($name);
      return $evaluated[@evaluated] = {exists => !!@$value, value => $value};
    },
  };
}

sub _helper_coerce_request_parameters {
  my ($c, $evaluated) = @_;
  my $output = $c->validation->output;
  my $req    = $c->req;

  for my $i (@$evaluated) {
    next unless $i->{valid};
    $output->{$i->{name}} = $i->{value};
    $c->stash(@$i{qw(name value)}) if $i->{in} eq 'path';
    $req->headers->header($i->{name}, ref $i->{value} eq 'ARRAY' ? @{$i->{value}} : $i->{value})
      if $i->{in} eq 'header';
    $req->url->query->merge(@$i{qw(name value)})  if $i->{in} eq 'query';
    $req->params->merge(@$i{qw(name value)})      if $i->{in} eq 'query';
    $req->params->merge(@$i{qw(name value)})      if $i->{in} eq 'formData';
    $req->body_params->merge(@$i{qw(name value)}) if $i->{in} eq 'formData';
  }
}

sub _helper_coerce_response_parameters {
  my ($c, $evaluated) = @_;
  my $res = $c->res;

  for my $i (@$evaluated) {
    next unless $i->{valid};
    $c->stash(openapi_negotiated_content_type => $i->{content_type}) if $i->{in} eq 'body';
    $res->headers->header($i->{name},
      _bool(ref $i->{value} eq 'ARRAY' ? @{$i->{value}} : $i->{value}))
      if $i->{in} eq 'header';
  }
}

sub _helper_parse_request_body {
  my ($c, $param) = @_;

  my $content_type = $c->req->headers->content_type || '';
  my $res          = {content_type => $content_type, exists => !!$c->req->body_size};

  if (grep { $content_type eq $_ } qw(application/x-www-form-urlencoded multipart/form-data)) {
    $res->{value} = $c->req->body_params->to_hash;
  }
  elsif (ref $param->{schema} eq 'HASH' and schema_type($param->{schema}) eq 'string') {
    $res->{value} = $c->req->body;
  }
  else {
    $res->{value} = $c->req->json;
  }

  return $res;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI::Parameters - Methods for transforming data from/to JSON::Validator::Schema

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI::Parameters> adds helpers to your L<Mojolicious>
application, required by L<Mojolicious::Plugin::OpenAPI>. These helpers can be
redefined in case you have special needs.

=head1 HELPERS

=head2 openapi.build_response_body

  $bytes = $c->openapi->build_response_body(Mojo::Asset->new);
  $bytes = $c->openapi->build_response_body($data);

Takes validated data and turns it into bytes that will be used as HTTP response
body. This method is useful to override, in case you want to render some other
structure than JSON.

=head2 openapi.build_schema_request

  $hash_ref = $c->openapi->build_schema_request;

Builds input data for L<JSON::Validator::Schema::OpenAPIv2/validate_request>.

=head2 openapi.build_schema_response

  $hash_ref = $c->openapi->build_schema_response;

Builds input data for L<JSON::Validator::Schema::OpenAPIv2/validate_response>.

=head2 openapi.coerce_request_parameters

  $c->openapi->coerce_request_parameters(\@evaluated_parameters);

Used by L<Mojolicious::Plugin::OpenAPI> to write the validated data back to
L<Mojolicious::Controller/req> and
L<Mojolicious::Validator::Validation/output>.

=head2 openapi.coerce_response_parameters

  $c->openapi->coerce_response_parameters(\@evaluated_parameters);

Used by L<Mojolicious::Plugin::OpenAPI> to write the validated data to
L<Mojolicious::Controller/res>.

=head2 openapi.parse_request_body

  $hash_ref = $c->openapi->parse_request_body;

Returns a structure representing the request body. The default is to parse the
input as JSON:

  {content_type => "application/json", exists => !!$c->req->body_size, value => $c->req->json};

This method is useful to override, in case you want to parse some other
structure than JSON.

=head1 METHODS

=head2 register

  $self->register($app, \%config);

This method will add the L</HELPERS> to your L<Mojolicious> C<$app>.

=head1 SEE ALSO

L<Mojolicious::Plugin::OpenAPI>.

=cut
