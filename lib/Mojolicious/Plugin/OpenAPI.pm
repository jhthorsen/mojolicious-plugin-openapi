package Mojolicious::Plugin::OpenAPI;
use Mojo::Base 'Mojolicious::Plugin';

use JSON::Validator;
use Mojo::JSON;
use Mojo::Util;
use Mojolicious::Plugin::OpenAPI::Parameters;

use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

our $VERSION = '5.05';

has route     => sub {undef};
has validator => sub { JSON::Validator::Schema->new; };

sub register {
  my ($self, $app, $config) = @_;

  $self->validator(JSON::Validator->new->schema($config->{url} || $config->{spec})->schema);
  $self->validator->coerce($config->{coerce}) if defined $config->{coerce};

  if (my $class = $config->{version_from_class} // ref $app) {
    $self->validator->data->{info}{version} = sprintf '%s', $class->VERSION if $class->VERSION;
  }

  my $errors = $config->{skip_validating_specification} ? [] : $self->validator->errors;
  die @$errors if @$errors;

  unless ($app->defaults->{'openapi.base_paths'}) {
    $app->helper('openapi.spec'        => \&_helper_get_spec);
    $app->helper('openapi.valid_input' => \&_helper_valid_input);
    $app->helper('openapi.validate'    => \&_helper_validate);
    $app->helper('reply.openapi'       => \&_helper_reply);
    $app->hook(before_render => \&_before_render);
    $app->renderer->add_handler(openapi => \&_render);
  }

  $self->{log_level} = $ENV{MOJO_OPENAPI_LOG_LEVEL} || $config->{log_level} || 'warn';
  $self->_build_route($app, $config);

  # This plugin is required
  my @plugins = (Mojolicious::Plugin::OpenAPI::Parameters->new->register($app, $config));

  for my $plugin (@{$config->{plugins} || [qw(+Cors +SpecRenderer +Security)]}) {
    $plugin = "Mojolicious::Plugin::OpenAPI::$plugin" if $plugin =~ s!^\+!!;
    eval "require $plugin;1" or Carp::confess("require $plugin: $@");
    push @plugins, $plugin->new->register($app, {%$config, openapi => $self});
  }

  my %default_response = %{$config->{default_response} || {}};
  $default_response{name}   ||= $config->{default_response_name}  || 'DefaultResponse';
  $default_response{status} ||= $config->{default_response_codes} || [400, 401, 404, 500, 501];
  $default_response{location} = 'definitions';
  $self->validator->add_default_response(\%default_response) if @{$default_response{status}};

  $self->_add_routes($app, $config);

  return $self;
}

sub _add_routes {
  my ($self, $app, $config) = @_;
  my $op_spec_to_route = $config->{op_spec_to_route} || '_op_spec_to_route';
  my (@routes, %uniq);

  for my $route ($self->validator->routes->each) {
    my $op_spec = $self->validator->get([paths => @$route{qw(path method)}]);
    my $name    = $op_spec->{'x-mojo-name'} || $op_spec->{operationId};
    my $r;

    die qq([OpenAPI] operationId "$op_spec->{operationId}" is not unique)
      if $op_spec->{operationId} and $uniq{o}{$op_spec->{operationId}}++;
    die qq([OpenAPI] Route name "$name" is not unique.) if $name and $uniq{r}{$name}++;

    if (!$op_spec->{'x-mojo-to'} and $name) {
      $r = $self->route->root->find($name);
      warn "[OpenAPI] Found existing route by name '$name'.\n" if DEBUG and $r;
      $self->route->add_child($r)                              if $r;
    }
    if (!$r) {
      my $http_method = $route->{method};
      my $route_path  = $self->_openapi_path_to_route_path(@$route{qw(method path)});
      $name ||= $op_spec->{operationId};
      warn "[OpenAPI] Creating new route for '$route_path'.\n" if DEBUG;
      $r = $self->route->$http_method($route_path);
      $r->name("$self->{route_prefix}$name") if $name;
    }

    $r->to(format => undef, 'openapi.method' => $route->{method}, 'openapi.path' => $route->{path});
    $self->$op_spec_to_route($op_spec, $r, $config);
    warn "[OpenAPI] Add route $route->{method} @{[$r->to_string]} (@{[$r->name // '']})\n" if DEBUG;

    push @routes, $r;
  }

  $app->plugins->emit_hook(openapi_routes_added => $self, \@routes);
}

sub _before_render {
  my ($c, $args) = @_;
  return unless _self($c);
  my $handler = $args->{handler} || 'openapi';

  # Call _render() for response data
  return if $handler eq 'openapi' and exists $c->stash->{openapi} or exists $args->{openapi};

  # Fallback to default handler for things like render_to_string()
  return $args->{handler} = $c->app->renderer->default_handler unless exists $args->{handler};

  # Call _render() for errors
  my $status = $args->{status} || $c->stash('status') || '200';
  if ($handler eq 'openapi' and ($status eq '404' or $status eq '500')) {
    $args->{handler} = 'openapi';
    $args->{status}  = $status;
    $c->stash(
      status  => $args->{status},
      openapi => {
        errors => [{message => $c->res->default_message($args->{status}) . '.', path => '/'}],
        status => $args->{status},
      }
    );
  }
}

sub _build_route {
  my ($self, $app, $config) = @_;
  my $validator = $self->validator;
  my $base_path = $validator->base_url->path->to_string;
  my $route     = $config->{route};

  $route     = $route->any($base_path) if $route and !$route->pattern->unparsed;
  $route     = $app->routes->any($base_path) unless $route;
  $base_path = $route->to_string;
  $base_path =~ s!/$!!;

  push @{$app->defaults->{'openapi.base_paths'}}, [$base_path, $self];
  $route->to({format => undef, handler => 'openapi', 'openapi.object' => $self});
  $validator->base_url($base_path);

  if (my $spec_route_name = $config->{spec_route_name} || $validator->get('/x-mojo-name')) {
    $self->{route_prefix} = "$spec_route_name.";
  }

  $self->{route_prefix} //= '';
  $self->route($route);
}

sub _helper_get_spec {
  my $c    = shift;
  my $path = shift // 'for_current';
  my $self = _self($c);

  # Get spec by valid JSON pointer
  return $self->validator->get($path) if ref $path or $path =~ m!^/! or !length $path;

  # Find spec by current request
  my ($stash) = grep { $_->{'openapi.path'} } reverse @{$c->match->stack};
  return undef unless $stash;

  my $jp = [paths => $stash->{'openapi.path'}];
  push @$jp, $stash->{'openapi.method'} if $path ne 'for_path';    # Internal for now
  return $self->validator->get($jp);
}

sub _helper_reply {
  my $c      = shift;
  my $status = ref $_[0] ? 200 : shift;
  my $output = shift;
  my @args   = @_;

  Mojo::Util::deprecated(
    '$c->reply->openapi() is DEPRECATED in favor of $c->render(openapi => ...)');

  if (UNIVERSAL::isa($output, 'Mojo::Asset')) {
    my $h = $c->res->headers;
    if (!$h->content_type and $output->isa('Mojo::Asset::File')) {
      my $types = $c->app->types;
      my $type  = $output->path =~ /\.(\w+)$/ ? $types->type($1) : undef;
      $h->content_type($type || $types->type('bin'));
    }
    return $c->reply->asset($output);
  }

  push @args, status => $status if $status;
  return $c->render(@args, openapi => $output);
}

sub _helper_valid_input {
  my $c = shift;
  return undef if $c->res->code;
  return $c unless my @errors = _helper_validate($c);
  $c->stash(status => 400)
    ->render(data => $c->openapi->build_response_body({errors => \@errors, status => 400}));
  return undef;
}

sub _helper_validate {
  my $c      = shift;
  my $self   = _self($c);
  my @errors = $self->validator->validate_request([@{$c->stash}{qw(openapi.method openapi.path)}],
    $c->openapi->build_schema_request);
  $c->openapi->coerce_request_parameters(
    delete $c->stash->{'openapi.evaluated_request_parameters'});
  return @errors;
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

sub _op_spec_to_route {
  my ($self, $op_spec, $r, $config) = @_;
  my $op_to = $op_spec->{'x-mojo-to'} // [];
  my @args
    = ref $op_to eq 'ARRAY' ? @$op_to : ref $op_to eq 'HASH' ? %$op_to : $op_to ? ($op_to) : ();

  # x-mojo-to: controller#action
  $r->to(shift @args) if @args and $args[0] =~ m!#!;

  my ($constraints, @to) = ($r->pattern->constraints);
  $constraints->{format} //= $config->{format} if $config->{format};
  while (my $arg = shift @args) {
    if    (ref $arg eq 'ARRAY') { %$constraints = (%$constraints, @$arg) }
    elsif (ref $arg eq 'HASH')  { push @to, %$arg }
    elsif (!ref $arg and @args) { push @to, $arg, shift @args }
  }

  $r->to(@to) if @to;
}

sub _render {
  my ($renderer, $c, $output, $args) = @_;
  my $stash = $c->stash;
  return unless exists $stash->{openapi};
  return unless my $self = _self($c);

  my $status             = $args->{status} || $stash->{status} || 200;
  my $method_path_status = [@$stash{qw(openapi.method openapi.path)}, $status];
  my $op_spec
    = $method_path_status->[0] && $self->validator->parameters_for_response($method_path_status);
  my @errors;

  delete $args->{encoding};
  $args->{status} = $status;
  $stash->{format} ||= 'json';

  if ($op_spec) {
    @errors = $self->validator->validate_response($method_path_status,
      $c->openapi->build_schema_response);
    $c->openapi->coerce_response_parameters(
      delete $stash->{'openapi.evaluated_response_parameters'});
    $args->{status} = $errors[0]->path eq '/header/Accept' ? 400 : 500 if @errors;
  }
  elsif (ref $stash->{openapi} eq 'HASH' and ref $stash->{openapi}{errors} eq 'ARRAY') {
    $args->{status} ||= $stash->{openapi}{status};
    @errors = @{$stash->{openapi}{errors}};
  }
  else {
    $args->{status} = 501;
    @errors = ({message => qq(No response rule for "$status".)});
  }

  $self->_log($c, '>>>', \@errors) if @errors;
  $stash->{status} = $args->{status};
  $$output = $c->openapi->build_response_body(
    @errors ? {errors => \@errors, status => $args->{status}} : $stash->{openapi});
}

sub _openapi_path_to_route_path {
  my ($self, $http_method, $path) = @_;
  my %params = map { ($_->{name}, $_) }
    grep { $_->{in} eq 'path' } @{$self->validator->parameters_for_request([$http_method, $path])};

  $path =~ s/{([^}]+)}/{
    my $name = $1;
    my $type = $params{$name}{'x-mojo-placeholder'} || ':';
    "<$type$name>";
  }/ge;

  return $path;
}

sub _self {
  my $c    = shift;
  my $self = $c->stash('openapi.object');
  return $self if $self;
  my $path = $c->req->url->path->to_string;
  return +(map { $_->[1] } grep { $path =~ /^$_->[0]/ } @{$c->stash('openapi.base_paths')})[0];
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI - OpenAPI / Swagger plugin for Mojolicious

=head1 SYNOPSIS

  # It is recommended to use Mojolicious::Plugin::OpenAPI with a "full app".
  # See the links after this example for more information.
  use Mojolicious::Lite;

  # Because the route name "echo" matches the "x-mojo-name", this route
  # will be moved under "basePath", resulting in "POST /api/echo"
  post "/echo" => sub {

    # Validate input request or return an error document
    my $c = shift->openapi->valid_input or return;

    # Generate some data
    my $data = {body => $c->req->json};

    # Validate the output response and render it to the user agent
    # using a custom "openapi" handler.
    $c->render(openapi => $data);
  }, "echo";

  # Load specification and start web server
  plugin OpenAPI => {url => "data:///swagger.yaml"};
  app->start;

  __DATA__
  @@ swagger.yaml
  swagger: "2.0"
  info: { version: "0.8", title: "Echo Service" }
  schemes: ["https"]
  basePath: "/api"
  paths:
    /echo:
     post:
       x-mojo-name: "echo"
       parameters:
       - { in: "body", name: "body", schema: { type: "object" } }
       responses:
         200:
           description: "Echo response"
           schema: { type: "object" }

See L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2> or
L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv3> for more in depth
information about how to use L<Mojolicious::Plugin::OpenAPI> with a "full app".
Even with a "lite app" it can be very useful to read those guides.

Looking at the documentation for
L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2/x-mojo-to> can be especially
useful. (The logic is the same for OpenAPIv2 and OpenAPIv3)

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI> is L<Mojolicious::Plugin> that add routes and
input/output validation to your L<Mojolicious> application based on a OpenAPI
(Swagger) specification. This plugin supports both version L<2.0|/schema> and
L<3.x|/schema>, though 3.x I<might> have some missing features.

Have a look at the L</SEE ALSO> for references to plugins and other useful
documentation.

Please report in L<issues|https://github.com/jhthorsen/json-validator/issues>
or open pull requests to enhance the 3.0 support.

=head1 HELPERS

=head2 openapi.spec

  $hash = $c->openapi->spec($json_pointer)
  $hash = $c->openapi->spec("/info/title")
  $hash = $c->openapi->spec;

Returns the OpenAPI specification. A JSON Pointer can be used to extract a
given section of the specification. The default value of C<$json_pointer> will
be relative to the current operation. Example:

  {
    "paths": {
      "/pets": {
        "get": {
          // This datastructure is returned by default
        }
      }
    }
  }

=head2 openapi.validate

  @errors = $c->openapi->validate;

Used to validate a request. C<@errors> holds a list of
L<JSON::Validator::Error> objects or empty list on valid input.

Note that this helper is only for customization. You probably want
L</openapi.valid_input> in most cases.

=head2 openapi.valid_input

  $c = $c->openapi->valid_input;

Returns the L<Mojolicious::Controller> object if the input is valid or
automatically render an error document if not and return false. See
L</SYNOPSIS> for example usage.

=head1 HOOKS

L<Mojolicious::Plugin::OpenAPI> will emit the following hooks on the
L<application|Mojolicious> object.

=head2 openapi_routes_added

Emitted after all routes have been added by this plugin.

  $app->hook(openapi_routes_added => sub {
    my ($openapi, $routes) = @_;

    for my $route (@$routes) {
      ...
    }
  });

This hook is EXPERIMENTAL and subject for change.

=head1 RENDERER

This plugin register a new handler called C<openapi>. The special thing about
this handler is that it will validate the data before sending it back to the
user agent. Examples:

  $c->render(json => {foo => 123});    # without validation
  $c->render(openapi => {foo => 123}); # with validation

This handler will also use L</renderer> to format the output data. The code
below shows the default L</renderer> which generates JSON data:

  $app->plugin(
    OpenAPI => {
      renderer => sub {
        my ($c, $data) = @_;
        return Mojo::JSON::encode_json($data);
      }
    }
  );

=head1 ATTRIBUTES

=head2 route

  $route = $openapi->route;

The parent L<Mojolicious::Routes::Route> object for all the OpenAPI endpoints.

=head2 validator

  $jv = $openapi->validator;

Holds either a L<JSON::Validator::Schema::OpenAPIv2> or a
L<JSON::Validator::Schema::OpenAPIv3> object.

=head1 METHODS

=head2 register

  $openapi = $openapi->register($app, \%config);
  $openapi = $app->plugin(OpenAPI => \%config);

Loads the OpenAPI specification, validates it and add routes to
L<$app|Mojolicious>. It will also set up L</HELPERS> and adds a
L<before_render|Mojolicious/before_render> hook for auto-rendering of error
documents. The return value is the object instance, which allow you to access
the L</ATTRIBUTES> after you load the plugin.

C<%config> can have:

=head3 coerce

See L<JSON::Validator/coerce> for possible values that C<coerce> can take.

Default: booleans,numbers,strings

The default value will include "defaults" in the future, once that is stable enough.

=head3 default_response

Instructions for
L<JSON::Validator::Schema::OpenAPIv2/add_default_response_schema>. (Also used
for OpenAPIv3)

=head3 format

Set this to a default list of file extensions that your API accepts. This value
can be overwritten by
L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2/x-mojo-to>.

This config parameter is EXPERIMENTAL and subject for change.

=head3 log_level

C<log_level> is used when logging invalid request/response error messages.

Default: "warn".

=head3 op_spec_to_route

C<op_spec_to_route> can be provided if you want to add route definitions
without using "x-mojo-to". Example:

  $app->plugin(OpenAPI => {op_spec_to_route => sub {
    my ($plugin, $op_spec, $route) = @_;

    # Here are two ways to customize where to dispatch the request
    $route->to(cb => sub { shift->render(openapi => ...) });
    $route->to(ucfirst "$op_spec->{operationId}#handle_request");
  }});

This feature is EXPERIMENTAL and might be altered and/or removed.

=head3 plugins

A list of OpenAPI classes to extend the functionality. Default is:
L<Mojolicious::Plugin::OpenAPI::Cors>,
L<Mojolicious::Plugin::OpenAPI::SpecRenderer> and
L<Mojolicious::Plugin::OpenAPI::Security>.

  $app->plugin(OpenAPI => {plugins => [qw(+Cors +SpecRenderer +Security)]});

You can load your own plugins by doing:

  $app->plugin(OpenAPI => {plugins => [qw(+SpecRenderer My::Cool::OpenAPI::Plugin)]});

=head3 renderer

See L</RENDERER>.

=head3 route

C<route> can be specified in case you want to have a protected API. Example:

  $app->plugin(OpenAPI => {
    route => $app->routes->under("/api")->to("user#auth"),
    url   => $app->home->rel_file("cool.api"),
  });

=head3 skip_validating_specification

Used to prevent calling L<JSON::Validator::Schema::OpenAPIv2/errors> for the
specification.

=head3 spec_route_name

Name of the route that handles the "basePath" part of the specification and
serves the specification. Defaults to "x-mojo-name" in the specification at
the top level.

=head3 spec, url

See L<JSON::Validator/schema> for the different C<url> formats that is
accepted.

C<spec> is an alias for "url", which might make more sense if your
specification is written in perl, instead of JSON or YAML.

Here are some common uses:

  $app->plugin(OpenAPI => {url  => $app->home->rel_file('openapi.yaml'));
  $app->plugin(OpenAPI => {url  => 'https://example.com/swagger.json'});
  $app->plugin(OpenAPI => {spec => JSON::Validator::Schema::OpenAPIv3->new(...)});
  $app->plugin(OpenAPI => {spec => {swagger => "2.0", paths => {...}, ...}});

=head3 version_from_class

Can be used to overridden C</info/version> in the API specification, from the
return value from the C<VERSION()> method in C<version_from_class>.

Defaults to the current C<$app>. This can be disabled by setting the
"version_from_class" to zero (0).

=head1 AUTHORS

Henrik Andersen

Ilya Rassadin

Jan Henning Thorsen

Joel Berger

=head1 COPYRIGHT AND LICENSE

Copyright (C) Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

=over 2

=item * L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2>

Guide for how to use this plugin with OpenAPI version 2.0 spec.

=item * L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv3>

Guide for how to use this plugin with OpenAPI version 3.0 spec.

=item * L<Mojolicious::Plugin::OpenAPI::Cors>

Plugin to add Cross-Origin Resource Sharing (CORS).

=item * L<Mojolicious::Plugin::OpenAPI::Security>

Plugin for handling security definitions in your schema.

=item * L<Mojolicious::Plugin::OpenAPI::SpecRenderer>

Plugin for exposing your spec in human readable or JSON format.

=item * L<https://www.openapis.org/>

Official OpenAPI website.

=back

=cut
