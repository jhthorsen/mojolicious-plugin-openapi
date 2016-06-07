package Mojolicious::Plugin::OpenAPI;
use Mojo::Base 'Mojolicious::Plugin';
use Swagger2;
use Swagger2::SchemaValidator;
use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

our $VERSION = '0.01';

my $X_RE = qr{^x-};

has _validator => sub { Swagger2::SchemaValidator->new; };

sub register {
  my ($self, $app, $config) = @_;
  my $swagger = $self->_load_spec($app, $config);
  my $route = $self->_base_route($app, $config, $swagger);

  $app->helper('openapi.input'    => sub { shift->stash('openapi.input') });
  $app->helper('openapi.spec'     => sub { shift->stash('openapi.operation_spec') });
  $app->helper('openapi.validate' => sub { $self->_validate(@_) });
  $app->helper('reply.openapi'    => \&_reply);

  $self->_validator->coerce($config->{coerce} // 1);
  $self->_validator->_api_spec($swagger->api_spec);
  $self->_add_routes($swagger, $route);
}

sub _add_routes {
  my ($self, $swagger, $route) = @_;
  my $paths = $swagger->api_spec->get('/paths');
  my $base_path = $swagger->api_spec->data->{basePath} = $route->to_string;

  $base_path =~ s!/$!!;

  for my $path (sort { length $a <=> length $b } keys %$paths) {
    next if $path =~ $X_RE;
    for my $http_method (keys %{$paths->{$path}}) {
      next if $http_method =~ $X_RE;
      my $route_path = $path;
      my $spec       = $paths->{$path}{$http_method};
      my $name       = $spec->{'x-mojo-name'} || $spec->{operationId};
      my $to         = $spec->{'x-mojo-to'};
      my %parameters = map { ($_->{name}, $_) } @{$spec->{parameters} || []};
      my ($endpoint, $under);

      $route_path =~ s/{([^}]+)}/{
        my $name = $1;
        my $type = $parameters{$name}{'x-mojo-placeholder'} || ':';
        "($type$name)";
      }/ge;

      $under = $route->$http_method($route_path)->under($self->_under($spec));
      $endpoint = $route->root->find($name) if $name;
      $endpoint ? $under->add_child($endpoint->remove) : ($endpoint = $under->any);
      $endpoint->to(ref $to eq 'ARRAY' ? @$to : $to) if $to;
      $endpoint->to($_ => $parameters{$_}{default})
        for grep { $parameters{$_}{in} eq 'path' and exists $parameters{$_}{default} }
        keys %parameters;
      $endpoint->pattern->parse('/');
      warn $endpoint->pattern->render;
      $endpoint->name($name) if $name;
      warn "[OpenAPI] Add route $http_method $base_path$route_path\n" if DEBUG;
    }
  }
}

sub _base_route {
  my ($self, $app, $config, $swagger) = @_;
  my $r = $config->{route};

  if ($r and !$r->pattern->unparsed) {
    $r = $r->any($swagger->base_url->path->to_string);
  }
  if (!$r) {
    $r = $app->routes->any($swagger->base_url->path->to_string);
    $r->to(swagger => $swagger);
  }

  return $r;
}

sub _load_spec {
  my ($self, $app, $config) = @_;
  my $swagger = Swagger2->new->load($config->{url})->expand;
  my @errors  = $swagger->validate;
  die join "\n", "Invalid Open API spec:", @errors if @errors;
  warn "[OpenAPI] Loaded $config->{url}\n" if DEBUG;
  return $swagger;
}

sub _reply {
  my ($c, $output, $status) = @_;
  $c->render(json => $output, status => $status || 200);
}

sub _validate {
  my ($self, $c, $output, $status) = @_;
  my $spec = $c->openapi->spec;
  my @errors;

  if (defined $output) {
    $status //= 200;
    @errors = $self->_validator->validate_response($c, $spec, $status, $output);
    warn "[OpenAPI] >>> @{[$c->req->url]} == (@errors)\n" if DEBUG and @errors;
  }
  else {
    @errors = $self->_validator->validate_request($c, $spec, \my %input);
    $c->stash('openapi.input' => \%input) unless @errors;
    warn "[OpenAPI] <<< @{[$c->req->url]} == (@errors)\n" if DEBUG and @errors;
  }

  return @errors;
}

sub _under {
  my ($self, $spec) = @_;

  my $cb = sub {
    my $c      = shift;
    my @errors = $c->openapi->validate;
    return $c->reply->openapi({errors => \@errors}, 400) if @errors;
    return $c->continue;
  };

  return $cb, {'openapi.operation_spec' => $spec};
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI - OpenAPI / Swagger plugin for Mojolicious

=head1 SYNOPSIS

=head2 Specification

  {
    "paths": {
      "/pets": {
        "get": {
          "x-mojo-to": "pet#list",
          "summary": "Finds pets in the system",
          "responses": {
          "200": {
            "description": "Pet response",
            "schema": { "type": "array", "items": { "$ref": "#/definitions/Pet" } }
          },
          "default": {
            "description": "Unexpected error",
            "schema": { "$ref": "http://git.io/vcKD4#" }
          }
        }
      }
    }
  }

The important part in the spec above is "x-mojo-to". The "x-mojo-to" key can
either a plain string, object (hash) or an array. The string and hash will be
passed directly to L<Mojolicious::Routes::Route/to>, while the array ref, will
be flattened first.

  "x-mojo-to": "pet#list"
  $route->to("pet#list");

  "x-mojo-to": {"controller": "pet", "action": "list", "foo": 123}
  $route->to({controller => "pet", action => "list", foo => 123);

  "x-mojo-to": ["pet#list", {"foo": 123}]
  $route->to("pet#list", {foo => 123});

=head2 Application

  package Myapp;
  use Mojolicious;

  sub register {
    my $app = shift;
    $app->plugin("OpenAPI" => {url => "myapi.json"});
  }

See L</register> for information about what the plugin config can be, in
addition to "url".

=head2 Controller

  package Myapp::Controller::Pet;

  sub list {
    my $c = shift;

    # You might want to introspect the specification for the current route
    my $spec = $c->openapi->spec;
    unless ($spec->{'x-opening-hour'} == (localtime)[2]) {
      return $c->reply->openapi([], 498);
    }

    # $input has been validated by the OpenAPI spec
    my $input = $c->openapi->input;

    # $output will be validated by the OpenAPI spec before rendered
    my $output = {pets => [{name => "kit-e-cat"}]};
    $c->reply->openapi($output, 200);
  }

The controller input and output will only be validated if the L</openapi.input>
and L</reply.openapi> methods are used.

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI> will replace L<Mojolicious::Plugin::Swagger2>.

This plugin is currently EXPERIMENTAL.

=head1 HELPERS

=head2 openapi.input

  $hash = $c->openapi->input;

Returns the data which has been L<validated|/openapi.validate> by the in
OpenAPI specification.

=head2 openapi.spec

  $hash = $c->openapi->spec;

Returns the OpenAPI specification for the current route:

  {
    "paths": {
      "/pets": {
        "get": {
          // This datastructure
        }
      }
    }
  }

Note: This might return a JSON pointer in the future.

=head2 openapi.validate

  # validate request
  @errors = $c->openapi->validate;

  # validate response
  @errors = $c->openapi->validate($output, $http_status);

Used to validate input or output data. This is done automatically by default,
but can be useful if you need to override L</reply.openapi>.

=head2 reply.openapi

  $c->reply->openapi($output, $http_status);

Will L<validate|/openapi.validate> C<$output> before passing it on to
L<Mojolicious::Controller/render>.

=head1 METHODS

=head2 register

  $self->register($app, \%config);

Loads the OpenAPI specification, validates it and add routes to L<$app>.
It will also set up L</HELPERS>. C<%config> can have:

  {
    coerce => 0,                           # default: 1
    route  => $app->routes->under(...)     # not required
    url    => "path/to/specification.json" # required
  }

C<route> can be specified in case you want to have a protected API.

See L<JSON::Validator/coerce> for possible values that C<coerce> can take.

See L<JSON::Validator/schema> for the different C<url> formats that is
accepted. Note that relative paths will be relative to L<Mojo/home>.

=head1 TODO

=over 2

=item * Add WebSockets support.

=item * Ensure structured response on exception.

=item * Figure out if/how to respond "501 Not Implemented".

=item * Never add support for "x-mojo-around-action", but possibly "before action".

=back

=head1 AUTHOR

Jan Henning Thorsen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojolicious::Plugin::Swagger2>.

=cut
