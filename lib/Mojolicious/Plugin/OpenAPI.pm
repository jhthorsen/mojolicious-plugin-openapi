package Mojolicious::Plugin::OpenAPI;
use Mojo::Base 'Mojolicious::Plugin';

use JSON::Validator::OpenAPI;
use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

our $VERSION = '0.01';

my $EXCEPTION = {errors => [{message => 'Internal server error.', path => '/'}], status => 500};
my $NOT_IMPLEMENTED = {errors => [{message => 'Not implemented.', path => '/'}], status => 501};
my $X_RE = qr{^x-};

has _validator => sub { JSON::Validator::OpenAPI->new; };

sub register {
  my ($self, $app, $config) = @_;
  my $api_spec = $self->_load_spec($app, $config);

  $app->helper('openapi.input'    => \&_input);
  $app->helper('openapi.spec'     => sub { shift->stash('openapi.op_spec') });
  $app->helper('openapi.validate' => sub { $self->_validate(@_) });
  $app->helper('reply.openapi'    => \&_reply);
  $app->hook(before_render => \&_before_render);

  $self->{log_level} = $config->{log_level} || 'warn';    # TODO: Is warn a nice default?
  $self->_validator->schema($api_spec->data)->coerce($config->{coerce} // 1);
  $self->_add_routes($app, $api_spec, $config->{route});
}

sub _add_routes {
  my ($self, $app, $api_spec, $route) = @_;
  my $base_path = $api_spec->get('/basePath') || '/';
  my $paths = $api_spec->get('/paths');

  $route = $route->any($base_path) if $route and !$route->pattern->unparsed;
  $route = $app->routes->any($base_path) unless $route;
  $base_path = $api_spec->data->{basePath} = $route->to_string;
  $base_path =~ s!/$!!;

  $route->to('openapi.api_spec' => $api_spec);
  $route->get->to(cb => \&_reply_spec);

  for my $path (sort { length $a <=> length $b } keys %$paths) {
    next if $path =~ $X_RE;

    for my $http_method (keys %{$paths->{$path}}) {
      next if $http_method =~ $X_RE;
      my $route_path = $path;
      my $op_spec    = $paths->{$path}{$http_method};
      my $name       = $op_spec->{'x-mojo-name'} || $op_spec->{operationId};
      my $to         = $op_spec->{'x-mojo-to'};
      my $parameters = $op_spec->{parameters} || [];
      my %parameters = map { ($_->{name}, $_) } @{$op_spec->{parameters} || []};
      my $endpoint;

      $route_path =~ s/{([^}]+)}/{
        my $name = $1;
        my $type = $parameters{$name}{'x-mojo-placeholder'} || ':';
        "($type$name)";
      }/ge;

      $endpoint = $route->root->find($name) if $name;
      $endpoint ? $route->add_child($endpoint) : ($endpoint = $route->any($route_path));
      $endpoint->to(ref $to eq 'ARRAY' ? @$to : $to) if $to;
      $endpoint->to($_ => $_->{default})
        for grep { $_->{in} eq 'path' and exists $_->{default} } @$parameters;
      $endpoint->to({'openapi.op_spec' => $op_spec});
      $endpoint->name($name) if $name;
      warn "[OpenAPI] Add route $http_method @{[$endpoint->render]}\n" if DEBUG;
    }
  }
}

sub _before_render {
  my ($c, $args) = @_;
  return if !$args->{exception} and grep {/^\w+$/} keys %$args;    # TODO: Is this robust?
  return unless $c->stash('openapi.op_spec');
  my $format = $c->stash('format') || 'json';
  my $io = $args->{exception} ? $EXCEPTION : $c->stash('openapi.io') || $NOT_IMPLEMENTED;
  $args->{status}  = delete $io->{status};
  $args->{$format} = $io;                                          # TODO: Is $format good enough?
}

sub _input {
  my $c     = shift;
  my $stash = $c->stash;
  return $stash->{'openapi.input'} if $stash->{'openapi.input'};
  return undef if $c->openapi->validate;
  return $stash->{'openapi.input'};
}

sub _load_spec {
  my ($self, $app, $config) = @_;
  my $jv       = JSON::Validator->new;
  my $api_spec = $jv->schema($config->{url})->schema;
  my @errors
    = $jv->schema(JSON::Validator::OpenAPI::SPECIFICATION_URL())->validate($api_spec->data);
  die join "\n", "Invalid Open API spec:", @errors if @errors;
  warn "[OpenAPI] Loaded $config->{url}\n" if DEBUG;
  return $api_spec;
}

sub _log {
  my ($self, $c, $dir) = (shift, shift, shift);
  my $log_level = $self->{log_level};

  $c->app->log->$log_level(
    sprintf 'OpenAPI %s %s %s %s',
    $dir, $c->req->method,
    $c->req->url->path,
    Mojo::JSON::encode_json(@_)
  );
}

sub _reply {
  my ($c, $output, $status) = @_;
  my $format = $c->stash('format') || 'json';
  $status ||= 200;
  return $c->render if $c->openapi->validate($output, $status);
  return $c->render($format => $output, status => $status);
}

sub _reply_spec {
  my $c    = shift;
  my $spec = $c->stash('openapi.api_spec')->data;

  local $spec->{id};
  delete $spec->{id};
  local $spec->{host} = $c->req->url->to_abs->host_port;
  $c->render(json => $spec);
}

sub _validate {
  my ($self, $c, $output, $status) = @_;
  my $op_spec = $c->openapi->spec;
  my @errors;

  if (@_ > 2) {
    $status ||= 200;
    if (@errors = $self->_validator->validate_response($c, $op_spec, $status, $output)) {
      $c->stash('openapi.io' => {errors => \@errors, status => 500});
      $self->_log($c, '>>>', \@errors);
    }
    warn "[OpenAPI] >>> @{[$c->req->url]} == (@errors)\n" if DEBUG;
  }
  else {
    @errors = $self->_validator->validate_request($c, $op_spec, \my %input);
    if (@errors) {
      $c->stash('openapi.io' => {errors => \@errors, status => 400});
      $self->_log($c, '<<<', \@errors);
    }
    else {
      $c->stash('openapi.input' => \%input);
    }
    warn "[OpenAPI] <<< @{[$c->req->url]} == (@errors)\n" if DEBUG;
  }

  return @errors;
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
be flattened first. Examples:

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
    $app->plugin("OpenAPI" => {url => $app->home->rel_file("myapi.json")});
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

    # $input will be a hash ref if validated and undef on invalid input
    my $input = $c->openapi->input or return;

    # $output will be validated by the OpenAPI spec before rendered
    my $output = {pets => [{name => "kit-e-cat"}]};
    $c->reply->openapi($output, 200);
  }

The input and output to the action will only be validated if the
L</openapi.input> and L</reply.openapi> methods are used.

All OpenAPI powered actions will have auto-rendering enabled, which means that
the C<return;> above will render an error document.

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI> will replace L<Mojolicious::Plugin::Swagger2>.

This plugin is currently EXPERIMENTAL.

=head1 HELPERS

=head2 openapi.input

  $hash = $c->openapi->input;

Returns the data which has been L<validated|/openapi.validate> by the in
OpenAPI specification or returns C<undef> on invalid data.

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

=head2 openapi.validate

  # validate request
  @errors = $c->openapi->validate;

  # validate response
  @errors = $c->openapi->validate($output, $http_status);

Used to validate input or output data. Request validation is always done by
L</openapi.input>.

=head2 reply.openapi

  $c->reply->openapi(\%output, $http_status);

Will L<validate|/openapi.validate> C<%output> before passing it on to
L<Mojolicious::Controller/render>.

=head1 METHODS

=head2 register

  $self->register($app, \%config);

Loads the OpenAPI specification, validates it and add routes to L<$app>.
It will also set up L</HELPERS>. C<%config> can have:

=over 2

=item * coerce

See L<JSON::Validator/coerce> for possible values that C<coerce> can take.

Default: 1

=item * log_level

C<log_level> is used when logging invalid request/response error messages.

Default: "warn".

=item * route

C<route> can be specified in case you want to have a protected API. Example:

  $app->plugin(OpenAPI => {
    route => $app->routes->under("/api")->to("user#auth"),
    url   => $app->home->rel_file("cool.api"),
  });

=item * url

See L<JSON::Validator/schema> for the different C<url> formats that is
accepted.

=head1 TODO

=over 2

=item * Add WebSockets support.

=item * Add support for /api.html (human readable format)

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
