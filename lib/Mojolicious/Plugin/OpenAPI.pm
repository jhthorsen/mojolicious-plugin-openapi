package Mojolicious::Plugin::OpenAPI;
use Mojo::Base 'Mojolicious::Plugin';

use JSON::Validator::OpenAPI::Mojolicious;
use JSON::Validator::Ref;
use Mojo::JSON;
use Mojo::Util;
use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

our $VERSION = '3.40';
my $X_RE = qr{^x-};

has route     => sub {undef};
has validator => sub { JSON::Validator::OpenAPI::Mojolicious->new; };

has _renderer => sub {
  return sub {
    my $c = shift;
    return $_[0]->slurp if UNIVERSAL::isa($_[0], 'Mojo::Asset');
    $c->res->headers->content_type('application/json;charset=UTF-8')
      unless $c->res->headers->content_type;
    return Mojo::JSON::encode_json($_[0]);
  };
};

sub register {
  my ($self, $app, $config) = @_;

  $self->validator->coerce($config->{coerce} // 'booleans,numbers,strings');
  $self->validator->load_and_validate_schema(
    $config->{url} || $config->{spec},
    {
      allow_invalid_ref  => $config->{allow_invalid_ref},
      schema             => $config->{schema},
      version_from_class => $config->{version_from_class} // ref $app,
    }
  );

  unless ($app->defaults->{'openapi.base_paths'}) {
    $app->helper('openapi.spec'        => \&_helper_get_spec);
    $app->helper('openapi.valid_input' => \&_helper_valid_input);
    $app->helper('openapi.validate'    => \&_helper_validate);
    $app->helper('reply.openapi'       => \&_helper_reply);
    $app->hook(before_render => \&_before_render);
    $app->renderer->add_handler(openapi => \&_render);
  }

  # Removed in 2.00
  die "[OpenAPI] default_response is no longer supported in config" if $config->{default_response};

  $self->{default_response_codes} = $config->{default_response_codes} || [400, 401, 404, 500, 501];
  $self->{default_response_name}  = $config->{default_response_name}  || 'DefaultResponse';
  $self->{log_level} = $ENV{MOJO_OPENAPI_LOG_LEVEL} || $config->{log_level} || 'warn';
  $self->_renderer($config->{renderer}) if $config->{renderer};
  $self->_build_route($app, $config);

  my @plugins;
  for my $plugin (@{$config->{plugins} || [qw(+Cors +SpecRenderer +Security)]}) {
    $plugin = "Mojolicious::Plugin::OpenAPI::$plugin" if $plugin =~ s!^\+!!;
    eval "require $plugin;1" or Carp::confess("require $plugin: $@");
    push @plugins, $plugin->new->register($app, {%$config, openapi => $self});
  }

  $self->_add_routes($app, $config);
  $self;
}

sub _add_default_response {
  my ($self, $op_spec) = @_;
  my $name        = $self->{default_response_name};
  my $schema_data = $self->validator->schema->data;

  # turn off with config { default_response_codes => [] }
  return unless @{$self->{default_response_codes}};

  my $ref
    = $self->validator->version ge '3'
    ? ($schema_data->{components}{schemas}{$name} ||= $self->_default_schema)
    : ($schema_data->{definitions}{$name} ||= $self->_default_schema);

  my %schema
    = $self->validator->version ge '3'
    ? ('$ref' => "#/components/schemas/$name")
    : ('$ref' => "#/definitions/$name");

  tie %schema, 'JSON::Validator::Ref', $ref, $schema{'$ref'}, $schema{'$ref'};
  for my $code (@{$self->{default_response_codes}}) {
    if ($self->validator->version ge '3') {
      $op_spec->{responses}{$code} ||= $self->_default_schema_v3(\%schema);
    }
    else {
      $op_spec->{responses}{$code} ||= $self->_default_schema_v2(\%schema);
    }
  }
}

sub _add_routes {
  my ($self, $app, $config) = @_;
  my (@routes, %uniq);

  my @sorted_openapi_paths
    = map { $_->[0] }
    sort { $a->[1] <=> $b->[1] || length $a->[0] <=> length $b->[0] }
    map { [$_, /\{/ ? 1 : 0] } grep { !/$X_RE/ } keys %{$self->validator->get('/paths') || {}};

  for my $openapi_path (@sorted_openapi_paths) {
    my $path_parameters = $self->validator->get([paths => $openapi_path => 'parameters']) || [];

    for my $http_method (sort keys %{$self->validator->get([paths => $openapi_path]) || {}}) {
      next if $http_method =~ $X_RE or $http_method eq 'parameters';
      my $op_spec = $self->validator->get([paths => $openapi_path => $http_method]);
      my $name    = $op_spec->{'x-mojo-name'} || $op_spec->{operationId};
      my $to      = $op_spec->{'x-mojo-to'};
      my $r;

      $self->{parameters_for}{$openapi_path}{$http_method}
        = [@$path_parameters, @{$op_spec->{parameters} || []}];

      die qq([OpenAPI] operationId "$op_spec->{operationId}" is not unique)
        if $op_spec->{operationId} and $uniq{o}{$op_spec->{operationId}}++;
      die qq([OpenAPI] Route name "$name" is not unique.) if $name and $uniq{r}{$name}++;

      if (!$to and $name) {
        $r = $self->route->root->find($name);
        warn "[OpenAPI] Found existing route by name '$name'.\n" if DEBUG and $r;
        $self->route->add_child($r)                              if $r;
      }
      if (!$r) {
        my $route_path = $self->_openapi_path_to_route_path($http_method, $openapi_path);
        $name ||= $op_spec->{operationId};
        warn "[OpenAPI] Creating new route for '$route_path'.\n" if DEBUG;
        $r = $self->route->$http_method($route_path);
        $r->name("$self->{route_prefix}$name") if $name;
      }

      $self->_add_default_response($op_spec);

      $r->to(ref $to eq 'ARRAY' ? @$to : $to) if $to;
      $r->to({'openapi.method' => $http_method});
      $r->to({'openapi.path'   => $openapi_path});
      warn "[OpenAPI] Add route $http_method @{[$r->to_string]} (@{[$r->name // '']})\n" if DEBUG;

      push @routes, $r;
    }
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
    $args->{status}  = ($status eq '404' and $c->stash('openapi.path')) ? 501 : $status;
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
  my $route = $config->{route};

  my $base_path
    = $self->validator->version eq '3'
    ? Mojo::URL->new($self->validator->get('/servers/0/url') || '/')->path->to_string
    : $self->validator->get('/basePath') || '/';

  $route     = $route->any($base_path) if $route and !$route->pattern->unparsed;
  $route     = $app->routes->any($base_path) unless $route;
  $base_path = $self->validator->schema->data->{basePath} = $route->to_string;
  $base_path =~ s!/$!!;

  push @{$app->defaults->{'openapi.base_paths'}}, [$base_path, $self];
  $route->to({handler => 'openapi', 'openapi.object' => $self});

  if (my $spec_route_name = $config->{spec_route_name} || $self->validator->get('/x-mojo-name')) {
    $self->{route_prefix} = "$spec_route_name.";
  }

  $self->{route_prefix} //= '';
  $self->route($route);
}

sub _default_schema {
  +{
    type       => 'object',
    required   => ['errors'],
    properties => {
      errors => {
        type  => 'array',
        items => {
          type       => 'object',
          required   => ['message'],
          properties => {message => {type => 'string'}, path => {type => 'string'}}
        }
      }
    }
  };
}

sub _default_schema_v2 {
  my ($self, $schema) = @_;
  +{description => 'Default response.', schema => $schema};
}

sub _default_schema_v3 {
  my ($self, $schema) = @_;
  +{
    description => 'default Mojolicious::Plugin::OpenAPI response',
    content     => {'application/json' => {schema => $schema}},
  };
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
    ->render(data => _self($c)->_renderer->($c, {errors => \@errors, status => 400}));
  return undef;
}

sub _helper_validate {
  my $c       = shift;
  my $self    = _self($c);
  my $op_spec = $c->openapi->spec;
  local $op_spec->{parameters}
    = $self->_parameters_for($c->req->method, $c->stash('openapi.path'),);
  return $self->validator->validate_request($c, $op_spec, $c->validation->output);
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

sub _parameters_for { $_[0]->{parameters_for}{$_[2]}{lc($_[1])} || [] }

sub _render {
  my ($renderer, $c, $output, $args) = @_;
  return unless exists $c->stash->{openapi};
  return unless my $self = _self($c);

  my $res     = $c->stash('openapi');
  my $status  = $args->{status} ||= ($c->stash('status') || 200);
  my $op_spec = $c->openapi->spec || {responses => {$status => {schema => $self->_default_schema}}};
  my @errors;

  delete $args->{encoding};
  $c->stash->{format} ||= 'json';

  if ($op_spec->{responses}{$status} or $op_spec->{responses}{default}) {
    @errors = $self->validator->validate_response($c, $op_spec, $status, $res);
    $args->{status} = 500 if @errors;
  }
  else {
    $args->{status} = 501;
    @errors = ({message => qq(No response rule for "$status".)});
  }

  $self->_log($c, '>>>', \@errors) if @errors;
  $c->stash(status => $args->{status});
  $$output = $self->_renderer->($c, @errors ? {errors => \@errors, status => $status} : $res);
}

sub _openapi_path_to_route_path {
  my ($self, $http_method, $openapi_path) = @_;
  my %params = map { ($_->{name}, $_) } @{$self->_parameters_for($http_method, $openapi_path)};

  $openapi_path =~ s/{([^}]+)}/{
    my $name = $1;
    my $type = $params{$name}{'x-mojo-placeholder'} || ':';
    "<$type$name>";
  }/ge;

  return $openapi_path;
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

  use Mojolicious::Lite;

  # Will be moved under "basePath", resulting in "POST /api/echo"
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
  # Use "v3" instead of "v2" for "schema" if you are using OpenAPI v3
  # The plugin must be loaded *after* defining the routes in a Lite app
  plugin OpenAPI => {url => "data:///spec.json", schema => "v2"};
  app->start;

  __DATA__
  @@ spec.json
  {
    "swagger" : "2.0",
    "info" : { "version": "0.8", "title" : "Echo Service" },
    "schemes" : [ "http" ],
    "basePath" : "/api",
    "paths" : {
      "/echo" : {
        "post" : {
          "x-mojo-name" : "echo",
          "parameters" : [
            { "in": "body", "name": "body", "schema": { "type" : "object" } }
          ],
          "responses" : {
            "200": {
              "description": "Echo response",
              "schema": { "type": "object" }
            }
          }
        }
      }
    }
  }

See L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2> or
L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv3> for tutorials on how to
write a "full" app with application class and controllers.

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI> is L<Mojolicious::Plugin> that add routes and
input/output validation to your L<Mojolicious> application based on a OpenAPI
(Swagger) specification. This plugin supports both version L<2.0|/schema> and
L<3.x|/schema>, though 3.x I<might> have some missing features.

Have a look at the L</SEE ALSO> for references to more documentation.

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

Holds a L<JSON::Validator::OpenAPI::Mojolicious> object.

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

=head3 allow_invalid_ref

The OpenAPI specification does not allow "$ref" at every level, but setting
this flag to a true value will ignore the $ref check.

Note that setting this attribute is discourage.

=head3 coerce

See L<JSON::Validator/coerce> for possible values that C<coerce> can take.

Default: booleans,numbers,strings

The default value will include "defaults" in the future, once that is stable enough.

=head3 default_response_codes

A list of response codes that will get a C<"$ref"> pointing to
"#/definitions/DefaultResponse", unless already defined in the spec.
"DefaultResponse" can be altered by setting L</default_response_name>.

The default response code list is the following:

  400 | Bad Request           | Invalid input from client / user agent
  401 | Unauthorized          | Used by Mojolicious::Plugin::OpenAPI::Security
  404 | Not Found             | Route is not defined
  500 | Internal Server Error | Internal error or failed output validation
  501 | Not Implemented       | Route exists, but the action is not implemented

Note that more default codes might be added in the future if required by the
plugin.

=head3 default_response_name

The name of the "definition" in the spec that will be used for
L</default_response_codes>. The default value is "DefaultResponse". See
L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2/"Default response schema">
for more details.

=head3 log_level

C<log_level> is used when logging invalid request/response error messages.

Default: "warn".

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

=head3 schema

Can be used to set a different schema, than the default OpenAPI 2.0 spec.
Example values: "http://swagger.io/v2/schema.json", "v2" or "v3".

See also L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv2> and
L<Mojolicious::Plugin::OpenAPI::Guides::OpenAPIv3>.

=head3 spec_route_name

Name of the route that handles the "basePath" part of the specification and
serves the specification. Defaults to "x-mojo-name" in the specification at
the top level.

=head3 url

See L<JSON::Validator/schema> for the different C<url> formats that is
accepted.

C<spec> is an alias for "url", which might make more sense if your
specification is written in perl, instead of JSON or YAML.

=head3 version_from_class

Can be used to overridden C</info/version> in the API specification, from the
return value from the C<VERSION()> method in C<version_from_class>.

This will only have an effect if "version" is "0".

Defaults to the current C<$app>.

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

Plugin for exposing your spec in human readble or JSON format.

=item * L<https://www.openapis.org/>

Official OpenAPI website.

=back

=cut
