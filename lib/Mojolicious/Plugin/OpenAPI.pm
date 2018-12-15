package Mojolicious::Plugin::OpenAPI;
use Mojo::Base 'Mojolicious::Plugin';

use JSON::Validator::OpenAPI::Mojolicious;
use JSON::Validator::Ref;
use Mojo::JSON;
use Mojo::Util;
use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

Mojo::Util::monkey_patch(__PACKAGE__,
  _markdown => eval 'require Text::Markdown;1'
  ? sub { Mojo::ByteStream->new(Text::Markdown::markdown($_[0])) }
  : sub { $_[0] });

our $VERSION = '2.07';
my $X_RE = qr{^x-};

has route     => sub {undef};
has validator => sub { JSON::Validator::OpenAPI::Mojolicious->new; };

has _renderer => sub {
  return sub {
    my $c = shift;
    return $_[0]->slurp if UNIVERSAL::isa($_[0], 'Mojo::Asset');
    $c->res->headers->content_type('application/json;charset=UTF-8');
    return Mojo::JSON::encode_json($_[0]);
  };
};

sub register {
  my ($self, $app, $config) = @_;

  $self->validator->coerce($config->{coerce} // 1);
  $self->validator->load_and_validate_schema(
    $config->{url} || $config->{spec},
    {
      allow_invalid_ref  => $config->{allow_invalid_ref},
      schema             => $config->{schema},
      version_from_class => $config->{version_from_class} // ref $app,
    }
  );

  unless ($app->defaults->{'openapi.base_paths'}) {
    $app->helper('openapi.render_spec' => \&_helper_reply_spec);
    $app->helper('openapi.spec'        => \&_helper_get_spec);
    $app->helper('openapi.valid_input' => sub { _helper_validate($_[0]) ? undef : $_[0] });
    $app->helper('openapi.validate'    => \&_helper_validate);
    $app->helper('reply.openapi'       => \&_helper_reply);
    $app->hook(before_render => \&_before_render);
    $app->renderer->add_handler(openapi => \&_render);
    push @{$app->renderer->classes}, __PACKAGE__;
  }

  # Removed in 2.00
  die "[OpenAPI] default_response is no longer supported in config" if $config->{default_response};

  local $config->{_plugins};    # Ugly hack, but I want the plugins to be temporarily objects
  $self->{log_level} = $ENV{MOJO_OPENAPI_LOG_LEVEL} || $config->{log_level} || 'warn';
  $self->_renderer($config->{renderer}) if $config->{renderer};
  $self->_build_route($app, $config);
  $self->_register_plugins($app, $config);
  $self->_add_routes($app, $config);
  $self;
}

sub _add_default_response {
  my ($self, $name, $op_spec, $code) = @_;
  return if $op_spec->{responses}{$code};
  my $ref = $self->validator->schema->data->{definitions}{$name} ||= $self->_default_schema;
  my %schema = ('$ref' => "#/definitions/$name");
  tie %schema, 'JSON::Validator::Ref', $ref, $schema{'$ref'}, $schema{'$ref'};
  $op_spec->{responses}{$code} = {description => 'Default response.', schema => \%schema};
}

sub _add_routes {
  my ($self, $app, $config) = @_;
  my %uniq;

  $config->{default_response_codes} ||= [400, 401, 404, 500, 501];
  $config->{default_response_name} ||= 'DefaultResponse';

  for my $path ($self->_sorted_paths) {
    next if $path =~ $X_RE;
    my $path_parameters = $self->validator->get([paths => $path => 'parameters']) || [];
    my $route_path = $path;
    my $has_options;

    for my $http_method (sort keys %{$self->validator->get([paths => $path]) || {}}) {
      next if $http_method =~ $X_RE or $http_method eq 'parameters';
      my $op_spec = $self->validator->get([paths => $path => $http_method]);
      my $name       = $op_spec->{'x-mojo-name'} || $op_spec->{operationId};
      my $to         = $op_spec->{'x-mojo-to'};
      my @parameters = (@$path_parameters, @{$op_spec->{parameters} || []});
      my $r;

      $has_options = 1 if lc $http_method eq 'options';
      $route_path = _route_path($path, \@parameters);

      die qq([OpenAPI] operationId "$op_spec->{operationId}" is not unique)
        if $op_spec->{operationId} and $uniq{o}{$op_spec->{operationId}}++;
      die qq([OpenAPI] Route name "$name" is not unique.) if $name and $uniq{r}{$name}++;

      if (!$to and $name) {
        $r = $self->route->root->find($name)
          or die "[OpenAPI] Could not find route by name '$name'.";
        warn "[OpenAPI] Found existing route by name '$name'.\n" if DEBUG;
        $self->route->add_child($r);
      }
      if (!$r) {
        $name ||= $op_spec->{operationId};
        warn "[OpenAPI] Creating new route for '$route_path'.\n" if DEBUG;
        $r = $self->route->$http_method($route_path);
        $r->name("$self->{route_prefix}$name") if $name;
      }

      $self->_add_default_response($config->{default_response_name}, $op_spec, $_)
        for @{$config->{default_response_codes}};

      $r->to(ref $to eq 'ARRAY' ? @$to : $to) if $to;
      $r->to({'openapi.op_path' => [paths => $path => $http_method]});
      $r->to({'openapi.parameters' => \@parameters});
      warn "[OpenAPI] Add route $http_method $path (@{[$r->render]}) @{[$r->name // '']}\n"
        if DEBUG;
    }

    unless ($has_options) {

      # TODO: This route name might change in future release, but is added now to prevent
      # routes with duplicate names
      my $name = $route_path;
      $name =~ s!\W+!!g;
      my $r
        = $self->route->options($route_path)
        ->to('openapi.default_options' => 1, cb => sub { _helper_reply_spec($_[0], $path) })
        ->name("$self->{route_prefix}${name}_options");
      warn "[OpenAPI] Add route options $path (@{[$r->render]}) @{[$r->name // '']}\n" if DEBUG;
    }
  }
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
    $args->{status} = ($status eq '404' and $c->stash('openapi.op_path')) ? 501 : $status;
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
  my $base_path = $self->validator->get('/basePath') || '/';
  my $route = $config->{route};

  $route = $route->any($base_path) if $route and !$route->pattern->unparsed;
  $route = $app->routes->any($base_path) unless $route;
  $base_path = $self->validator->schema->data->{basePath} = $route->to_string;
  $base_path =~ s!/$!!;

  push @{$app->defaults->{'openapi.base_paths'}}, [$base_path, $self];
  $route->to({handler => 'openapi', 'openapi.object' => $self});

  my $spec_route = $route->get('/')->to(cb => sub { shift->openapi->render_spec });
  if (my $spec_route_name = $config->{spec_route_name} || $self->validator->get('/x-mojo-name')) {
    $spec_route->name($spec_route_name);
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

sub _helper_get_spec {
  my ($c, $path) = @_;
  my $self = _self($c);

  return $self->validator->get($path) if defined $path;

  my $op_path;
  for my $s (reverse @{$c->match->stack}) {
    $op_path ||= $s->{'openapi.op_path'};
  }

  return $op_path ? $self->validator->get($op_path) : undef;
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
      my $type = $output->path =~ /\.(\w+)$/ ? $types->type($1) : undef;
      $h->content_type($type || $types->type('bin'));
    }
    return $c->reply->asset($output);
  }

  push @args, status => $status if $status;
  return $c->render(@args, openapi => $output);
}

sub _helper_reply_spec {
  my ($c, $path) = @_;
  my $self   = _self($c);
  my $spec   = $self->{bundled} ||= $self->validator->bundle;
  my $format = $c->stash('format') || 'json';
  my $method = $c->param('method');

  if (defined $path) {
    $spec = $spec->{paths}{$path};
    return $c->render(json => $spec) unless $method;
    my $method_spec = $self->validator->get([paths => $path => $method]);
    return $c->render(json => undef, status => 404) unless $method_spec;
    local $method_spec->{parameters}
      = [@{$spec->{parameters} || []}, @{$method_spec->{parameters} || []}];
    return $c->render(json => $method_spec);
  }

  local $spec->{basePath} = $c->url_for($spec->{basePath});
  local $spec->{host}     = $c->req->url->to_abs->host_port;

  return $c->render(json => $spec) unless $format eq 'html';
  return $c->render(
    handler   => 'ep',
    template  => 'mojolicious/plugin/openapi/layout',
    esc       => sub { local $_ = shift; s/\W/-/g; $_ },
    markdown  => \&_markdown,
    serialize => \&_serialize,
    spec      => $spec,
    X_RE      => $X_RE
  );
}

sub _helper_validate {
  my ($c, $args) = @_;
  my $self    = _self($c);
  my $op_spec = $c->openapi->spec;

  # code() can be set by other methods such as $c->openapi->cors_simple()
  return [{message => 'Already rendered.'}] if $c->res->code;

  # Write validated data to $c->validation->output
  local $op_spec->{parameters} = $c->stash('openapi.parameters');
  my @errors = $self->validator->validate_request($c, $op_spec, $c->validation->output);

  if (@errors) {
    $self->_log($c, '<<<', \@errors);
    $c->render(data => $self->_renderer->($c, {errors => \@errors, status => 400}), status => 400)
      if $args->{auto_render} // 1;
  }

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

sub _register_plugins {
  my ($self, $app, $config) = @_;
  my @plugins;

  for my $plugin (@{$config->{plugins} || [qw(+Cors +Security)]}) {
    $plugin = "Mojolicious::Plugin::OpenAPI::$plugin" if $plugin =~ s!^\+!!;
    eval "require $plugin;1" or Carp::confess("require $plugin: $@");
    push @plugins, $plugin->new->register($app, $self, $config);
  }

  $config->{_plugins} = \@plugins;
}

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

sub _route_path {
  my ($path, $parameters) = @_;
  my %parameters = map { ($_->{name}, $_) } @$parameters;
  $path =~ s/{([^}]+)}/{
    my $pname = $1;
    my $type = $parameters{$pname}{'x-mojo-placeholder'} || ':';
    "<$type$pname>";
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

sub _serialize { Mojo::JSON::encode_json(@_) }

sub _sorted_paths {
  return
    map { $_->[0] }
    sort { $a->[1] <=> $b->[1] || length $a->[0] <=> length $b->[0] }
    map { [$_, $_ =~ /\{/ ? 1 : 0] } keys %{$_[0]->validator->get('/paths') || {}};
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
    my $data = {body => $c->validation->param("body")};

    # Validate the output response and render it to the user agent
    # using a custom "openapi" handler.
    $c->render(openapi => $data);
  }, "echo";

  # Load specification and start web server
  plugin OpenAPI => {url => "data:///api.json"};
  app->start;

  __DATA__
  @@ api.json
  {
    "swagger" : "2.0",
    "info" : { "version": "0.8", "title" : "Pets" },
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

See L<Mojolicious::Plugin::OpenAPI::Guides::Tutorial> for a tutorial on how to
write a "full" app with application class and controllers.

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI> is L<Mojolicious::Plugin> that add routes and
input/output validation to your L<Mojolicious> application based on a OpenAPI
(Swagger) specification.

Have a look at the L</SEE ALSO> for references to more documentation, or jump
right to the L<tutorial|Mojolicious::Plugin::OpenAPI::Guides::Tutorial>.

Currently v2 is very well supported, while v3 should be considered higly
EXPERIMENTAL. Note that testing out v3 requires L<YAML::XS> to be installed.

Please report in L<issues|https://github.com/jhthorsen/json-validator/issues>
or open pull requests to enhance the 3.0 support.

=head1 AUTOMATIC RESOURCES

This module adds some extra resources automatically.

=head2 Specification renderer

The specification in JSON or human rendered format can be retrieved by
requesting the C<basePath>.

The human readable format focus on making the documentation printable, so you
can easily share it with third parties as a PDF. If this documentation format
is too basic or has missing information, then please
L<report in|https://github.com/jhthorsen/mojolicious-plugin-openapi/issues>
suggestions for enhancements.

Examples:

  GET https://api.example.com/v1.json
  GET https://api.example.com/v1.html

=head2 OPTIONS

Using the HTTP method "OPTIONS" will render the specification for a given path.

Examples:

  OPTIONS https://api.example.com/v1/users
  OPTIONS https://api.example.com/v1/users?method=get
  OPTIONS https://api.example.com/v1/users?method=post

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

=head2 openapi.render_spec

  $c = $c->openapi->render_spec;

Used to render the specification as either "html" or "json". Set the
L<Mojolicious/stash> variable "format" to change the format to render.

This helper is called by default, when accessing the "basePath" resource.

The "html" rendering needs improvement. Any help or feedback is much
appreciated.

=head2 openapi.validate

  @errors = $c->openapi->validate;

Used to validate a request. C<@errors> holds a list of
L<JSON::Validator::Error> objects or empty list on valid input.

Note that this helper is only for customization. You probably want
L</openapi.valid_input> in most cases.

Validated input parameters will be copied to
C<Mojolicious::Controller/validation>, which again can be extracted by the
"name" in the parameters list from the spec. Example:

  # specification:
  "parameters": [{"in": "body", "name": "whatever", "schema": {"type": "object"}}],

  # controller
  my $body = $c->validation->param("whatever");

=head2 openapi.valid_input

  $c = $c->openapi->valid_input;

Returns the L<Mojolicious::Controller> object if the input is valid or
automatically render an error document if not and return false. See
L</SYNOPSIS> for example usage.

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

  $route = $self->route;

The parent L<Mojolicious::Routes::Route> object for all the OpenAPI endpoints.

=head2 validator

  $jv = $self->validator;

Holds a L<JSON::Validator::OpenAPI::Mojolicious> object.

=head1 METHODS

=head2 register

  $self = $self->register($app, \%config);
  $self = $app->plugin(OpenAPI => \%config);

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

Default: 1

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
L<Mojolicious::Plugin::OpenAPI::Guides::Tutorial/"Default response schema">
for more details.

=head3 log_level

C<log_level> is used when logging invalid request/response error messages.

Default: "warn".

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

Can be used to overriden C</info/version> in the API specification, from the
return value from the C<VERSION()> method in C<version_from_class>.

This will only have an effect if "version" is "0".

Defaults to the current C<$app>.

=head1 AUTHOR

Jan Henning Thorsen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

=over 2

=item * L<Mojolicious::Plugin::OpenAPI::Guides::Tutorial>

=item * L<Mojolicious::Plugin::OpenAPI::Security>

=item * L<http://thorsen.pm/perl/programming/2015/07/05/mojolicious-swagger2.html>.

=item * L<OpenAPI specification|https://openapis.org/specification>

=back

=cut

__DATA__
@@ mojolicious/plugin/openapi/header.html.ep
<h1 id="title"><%= $spec->{info}{title} || 'No title' %></h1>
<p class="version"><span>Version</span> <span class="version"><%= $spec->{info}{version} %></span></p>

%= include "mojolicious/plugin/openapi/toc"

% if ($spec->{info}{description}) {
<h2 id="description"><a href="#title">Description</a></h2>
<div class="description">
  %== $markdown->($spec->{info}{description})
</div>
% }

% if ($spec->{info}{termsOfService}) {
<h2 id="terms-of-service"><a href="#title">Terms of service</a></h2>
<p class="terms-of-service">
  %= $spec->{info}{termsOfService}
</p>
% }
@@ mojolicious/plugin/openapi/footer.html.ep
% my $contact = $spec->{info}{contact};
% my $license = $spec->{info}{license};
<h2 id="license"><a href="#title">License</a></h2>
% if ($license->{name}) {
<p class="license"><a href="<%= $license->{url} || '' %>"><%= $license->{name} %></a></p>
% } else {
<p class="no-license">No license specified.</p>
% }
<h2 id="contact"<a href="#title">Contact information</a></h2>
% if ($contact->{email}) {
<p class="contact-email"><a href="mailto:<%= $contact->{email} %>"><%= $contact->{email} %></a></p>
% }
% if ($contact->{url}) {
<p class="contact-url"><a href="mailto:<%= $contact->{url} %>"><%= $contact->{url} %></a></p>
% }
@@ mojolicious/plugin/openapi/human.html.ep
% if ($spec->{summary}) {
<p class="spec-summary"><%= $spec->{summary} %></p>
% }
% if ($spec->{description}) {
<div class="spec-description"><%== $markdown->($spec->{description}) %></div>
% }
% if (!$spec->{description} and !$spec->{summary}) {
<p class="op-summary op-doc-missing">This resource is not documented.</p>
% }
@@ mojolicious/plugin/openapi/parameters.html.ep
% my $has_parameters = @{$op->{parameters} || []};
% my $body;
<h4 class="op-parameters">Parameters</h3>
% if ($has_parameters) {
<table class="op-parameters">
  <thead>
    <tr>
      <th>Name</th>
      <th>In</th>
      <th>Type</th>
      <th>Required</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
% }
% for my $p (@{$op->{parameters} || []}) {
  % $body = $p->{schema} if $p->{in} eq 'body';
  <tr>
    % if ($spec->{parameters}{$p->{name}}) {
      <td><a href="#ref-parameters-<%= $esc->($p->{name}) %>"><%= $p->{name} %></a></td>
    % } else {
      <td><%= $p->{name} %></td>
    % }
    <td><%= $p->{in} %></td>
    <td><%= $p->{type} %></td>
    <td><%= $p->{required} ? "Yes" : "No" %></td>
    <td><%== $p->{description} ? $markdown->($p->{description}) : "" %></td>
  </tr>
% }
% if ($has_parameters) {
  </tbody>
</table>
% } else {
<p class="op-parameters">This resource has no input parameters.</p>
% }
% if ($body) {
<h4 class="op-parameter-body">Body</h4>
<pre class="op-parameter-body"><%= $serialize->($body) %></pre>
% }
@@ mojolicious/plugin/openapi/response.html.ep
% for my $code (sort keys %{$op->{responses}}) {
  % next if $code =~ $X_RE;
  % my $res = $op->{responses}{$code};
<h4 class="op-response">Response <%= $code %></h3>
%= include "mojolicious/plugin/openapi/human", spec => $res
<pre class="op-response"><%= $serialize->($res->{schema}) %></pre>
% }
@@ mojolicious/plugin/openapi/resource.html.ep
<h3 id="op-<%= lc $method %><%= $esc->($path) %>" class="op-path <%= $op->{deprecated} ? "deprecated" : "" %>"><a href="#title"><%= uc $method %> <%= $spec->{basePath} %><%= $path %></a></h3>
% if ($op->{deprecated}) {
<p class="op-deprecated">This resource is deprecated!</p>
% }
% if ($op->{operationId}) {
<p class="op-id"><b>Operation ID:</b> <span><%= $op->{operationId} %></span></p>
% }
%= include "mojolicious/plugin/openapi/human", spec => $op
%= include "mojolicious/plugin/openapi/parameters", op => $op
%= include "mojolicious/plugin/openapi/response", op => $op
@@ mojolicious/plugin/openapi/references.html.ep
% use Mojo::ByteStream 'b';
<h2 id="references"><a href="#title">References</a></h2>
% for my $key (sort { $a cmp $b } keys %{$spec->{definitions} || {}}) {
  % next if $key =~ $X_RE;
  <h3 id="ref-definitions-<%= lc $esc->($key) %>"><a href="#title">#/definitions/<%= $key %></a></h3>
  <pre class="ref"><%= $serialize->($spec->{definitions}{$key}) %></pre>
% }
% for my $key (sort { $a cmp $b } keys %{$spec->{parameters} || {}}) {
  % next if $key =~ $X_RE;
  % my $item = $spec->{parameters}{$key};
  <h3 id="ref-parameters-<%= lc $esc->($key) %>"><a href="#title">#/parameters/<%= $key %> - "<%= $item->{name} %>"</a></h3>
  <p><%= $item->{description} || 'No description.' %></p>
  <ul>
    <li>In: <%= $item->{in} %></li>
    <li>Type: <%= $item->{type} %><%= $item->{format} ? " / $item->{format}" : "" %><%= $item->{pattern} ? " / $item->{pattern}" : ""%></li>
    % if ($item->{exclusiveMinimum} || $item->{exclusiveMaximum} || $item->{minimum} || $item->{maximum}) {
      <li>
        Min / max:
        <%= $item->{exclusiveMinimum} ? "$item->{exclusiveMinimum} <" : $item->{minimum} ? "$item->{minimum} <=" : b("&infin; <=") %>
        value
        <%= $item->{exclusiveMaximum} ? "< $item->{exclusiveMaximum}" : $item->{maximum} ? "<= $item->{maximum}" : b("<= &infin;") %>
      </li>
    % }
    % if ($item->{minLength} || $item->{maxLength}) {
      <li>
        Min / max:
        <%= $item->{minLength} ? "$item->{minLength} <=" : b("&infin; <=") %>
        length
        <%= $item->{maxLength} ? "<= $item->{maxLength}" : b("<= &infin;") %>
      </li>
    % }
    % if ($item->{minItems} || $item->{maxItems}) {
      <li>
        Min / max:
        <%= $item->{minItems} ? "$item->{minItems} <=" : b("&infin; <=") %>
        items
        <%= $item->{maxItems} ? "<= $item->{maxItems}" : b("<= &infin;") %>
      </li>
    % }
    % for my $k (qw(collectionFormat uniqueItems multipleOf enum)) {
      % next unless $item->{$k};
      <li><%= ucfirst $k %>: <%= ref $item->{$k} ? $serialize->($item->{$k}) : $item->{$k} %></li>
    % }
    <li>Required: <%= $item->{required} ? 'Yes.' : 'No.' %></li>
    <li><%= defined $item->{default} ? "Default: " . $serialize->($item->{default}) : 'No default value.' %></li>
  </ul>
  % for my $k (qw(items schema)) {
    % next unless $item->{$k};
    <pre class="ref"><%= $serialize->($item->{$k}) %></pre>
  % }
% }

@@ mojolicious/plugin/openapi/resources.html.ep
<h2 id="resources"><a href="#title">Resources</a></h2>

% my $schemes = $spec->{schemes} || ["http"];
% my $url = Mojo::URL->new("http://$spec->{host}");
<h3 id="base-url"><a href="#title">Base URL</a></h3>
<ul class="unstyled">
% for my $scheme (@$schemes) {
  % $url->scheme($scheme);
  <li><a href="<%= $url %>"><%= $url %></a></li>
% }
</ul>

% for my $path (sort { length $a <=> length $b } keys %{$spec->{paths}}) {
  % next if $path =~ $X_RE;
  % for my $http_method (sort keys %{$spec->{paths}{$path}}) {
    % next if $http_method =~ $X_RE or $http_method eq 'parameters';
    % my $op = $spec->{paths}{$path}{$http_method};
    %= include "mojolicious/plugin/openapi/resource", method => $http_method, op => $op, path => $path
  % }
% }
@@ mojolicious/plugin/openapi/toc.html.ep
<ul id="toc">
  % if ($spec->{info}{description}) {
  <li><a href="#description">Description</a></li>
  % }
  % if ($spec->{info}{termsOfService}) {
  <li><a href="#terms-of-service">Terms of service</a></li>
  % }
  <li>
    <a href="#resources">Resources</a>
    <ul>
    % for my $path (sort { length $a <=> length $b } keys %{$spec->{paths}}) {
      % next if $path =~ $X_RE;
      % for my $method (sort keys %{$spec->{paths}{$path}}) {
        % next if $method =~ $X_RE;
        <li><a href="#op-<%= lc $method %><%= $esc->($path) %>"><span class="method"><%= uc $method %></span> <%= $spec->{basePath} %><%= $path %></h3>
      % }
    % }
    </ul>
  </li>
  <li>
    <a href="#references">References</a>
    <ul>
    % for my $key (sort { $a cmp $b } keys %{$spec->{definitions} || {}}) {
      % next if $key =~ $X_RE;
      <li><a href="#ref-definitions-<%= lc $esc->($key) %>">#/definitions/<%= $key %></a></li>
    % }
    % for my $key (sort { $a cmp $b } keys %{$spec->{parameters} || {}}) {
      % next if $key =~ $X_RE;
      <li><a href="#ref-parameters-<%= lc $esc->($key) %>">#/parameters/<%= $key %></a></li>
    % }
    </ul>
  </li>
  <li><a href="#license">License</a></li>
  <li><a href="#contact">Contact</a></li>
</ul>
@@ mojolicious/plugin/openapi/layout.html.ep
<!doctype html>
<html lang="en">
<head>
  <title><%= $spec->{info}{title} || 'No title' %></title>
  <style>
    body {
      font-family: 'Gotham Narrow SSm','Helvetica Neue',Helvetica,sans-serif;
      font-size: 16px;
      margin: 3em;
      padding: 0;
      color: #222;
      line-height: 1.4em;
    }
    a {
      color: #225;
      text-decoration: underline;
    }
    h1, h2, h3, h4 { font-weight: bold; margin: 1em 0; }
    h1 a, h2 a, h3 a, h4 a { text-decoration: none; color: #222; }
    h1 { font-size: 2em; }
    h2 { font-size: 1.6em; margin-top: 2em; }
    h3 { font-size: 1.2em; }
    h4 { font-size: 1.1em; }
    table {
      margin: 0em -0.5em;
      width: 100%;
      border-collapse: collapse;
    }
    td, th {
      vertical-align: top;
      text-align: left;
      padding: 0.5em;
    }
    th {
      font-weight: bold;
      border-bottom: 1px solid #ccc;
    }
    td p, th p {
      margin: 0;
    }
    ul {
      margin: 0;
      padding: 0 1.5em;
    }
    ul.unstyled {
      list-style: none;
      padding: 0;
    }
    p {
      margin: 1em 0;
    }
    pre {
      background: #f3f3f3;
      font-size: 0.9rem;
      line-height: 1.2em;
      letter-spacing: -0.02em;
      border: 1px solid #ddd;
      padding: 0.5em;
      margin: 1em -0.5em;
      overflow: auto;
    }
    #toc a { text-decoration: none; display: block; }
    #toc .method { display: inline-block; width: 7em; }
    div.container { max-width: 50em; margin: 0 auto; }
    p.version { color: #666; margin: -0.5em 0 2em 0; }
    p.op-deprecated { color: #c00; }
    h3.op-path { margin-top: 3em; }
    .container > h3.op-path { margin-top: 1em; }
    .renderjson .disclosure { display: none; }
    .renderjson .syntax     { color: #002b36; }
    .renderjson .string     { color: #073642; }
    .renderjson .number     { color: #2aa198; }
    .renderjson .boolean    { color: #d33682; }
    .renderjson .key        { color: #0e6fb3; }
    .renderjson .keyword    { color: #b58900; }
  </style>
</head>
<body>
<div class="container">
  %= include "mojolicious/plugin/openapi/header"
  %= include "mojolicious/plugin/openapi/resources"
  %= include "mojolicious/plugin/openapi/references"
  %= include "mojolicious/plugin/openapi/footer"
</div>
<script>
var module,window,define,renderjson=function(){function n(a,u,c,p,f){var y=c?"":u,_=function(n,o,a,u,c){var _,d=l(u),h=function(){_||e(d.parentNode,_=r(c(),i(f.hide,"disclosure",function(){_.style.display="none",d.style.display="inline"}))),_.style.display="inline",d.style.display="none"};e(d,i(f.show,"disclosure",h),t(u+" syntax",n),i(o,null,h),t(u+" syntax",a));var g=e(l(),s(y.slice(0,-1)),d);return p>0&&"string"!=u&&h(),g};return null===a?t(null,y,"keyword","null"):void 0===a?t(null,y,"keyword","undefined"):"string"==typeof a&&a.length>f.max_string_length?_('"',a.substr(0,f.max_string_length)+" ...",'"',"string",function(){return e(l("string"),t(null,y,"string",JSON.stringify(a)))}):"object"!=typeof a||[Number,String,Boolean,Date].indexOf(a.constructor)>=0?t(null,y,typeof a,JSON.stringify(a)):a.constructor==Array?0==a.length?t(null,y,"array syntax","[]"):_("["," ... ","]","array",function(){for(var r=e(l("array"),t("array syntax","[",null,"\n")),o=0;o<a.length;o++)e(r,n(f.replacer.call(a,o,a[o]),u+"  ",!1,p-1,f),o!=a.length-1?t("syntax",","):[],s("\n"));return e(r,t(null,u,"array syntax","]")),r}):o(a,f.property_list)?t(null,y,"object syntax","{}"):_("{","...","}","object",function(){var r=e(l("object"),t("object syntax","{",null,"\n"));for(var o in a)var i=o;var c=f.property_list||Object.keys(a);f.sort_objects&&(c=c.sort());for(var y in c)(o=c[y])in a&&e(r,t(null,u+"  ","key",'"'+o+'"',"object syntax",": "),n(f.replacer.call(a,o,a[o]),u+"  ",!0,p-1,f),o!=i?t("syntax",","):[],s("\n"));return e(r,t(null,u,"object syntax","}")),r})}var t=function(){for(var n=[];arguments.length;)n.push(e(l(Array.prototype.shift.call(arguments)),s(Array.prototype.shift.call(arguments))));return n},e=function(){for(var n=Array.prototype.shift.call(arguments),t=0;t<arguments.length;t++)arguments[t].constructor==Array?e.apply(this,[n].concat(arguments[t])):n.appendChild(arguments[t]);return n},r=function(n,t){return n.insertBefore(t,n.firstChild),n},o=function(n,t){var e=t||Object.keys(n);for(var r in e)if(Object.hasOwnProperty.call(n,e[r]))return!1;return!0},s=function(n){return document.createTextNode(n)},l=function(n){var t=document.createElement("span");return n&&(t.className=n),t},i=function(n,t,e){var r=document.createElement("a");return t&&(r.className=t),r.appendChild(s(n)),r.href="#",r.onclick=function(n){return e(),n&&n.stopPropagation(),!1},r},a=function t(r){var o=Object.assign({},t.options);o.replacer="function"==typeof o.replacer?o.replacer:function(n,t){return t};var s=e(document.createElement("pre"),n(r,"",!1,o.show_to_level,o));return s.className="renderjson",s};return a.set_icons=function(n,t){return a.options.show=n,a.options.hide=t,a},a.set_show_to_level=function(n){return a.options.show_to_level="string"==typeof n&&"all"===n.toLowerCase()?Number.MAX_VALUE:n,a},a.set_max_string_length=function(n){return a.options.max_string_length="string"==typeof n&&"none"===n.toLowerCase()?Number.MAX_VALUE:n,a},a.set_sort_objects=function(n){return a.options.sort_objects=n,a},a.set_replacer=function(n){return a.options.replacer=n,a},a.set_property_list=function(n){return a.options.property_list=n,a},a.set_show_by_default=function(n){return a.options.show_to_level=n?Number.MAX_VALUE:0,a},a.options={},a.set_icons("⊕","⊖"),a.set_show_by_default(!1),a.set_sort_objects(!1),a.set_max_string_length("none"),a.set_replacer(void 0),a.set_property_list(void 0),a}();define?define({renderjson:renderjson}):(module||{}).exports=(window||{}).renderjson=renderjson;
(function(w, d) {
  renderjson.set_show_to_level("all");
  renderjson.set_sort_objects(true);
  renderjson.set_max_string_length(100);

  var els = d.querySelectorAll("pre");
  for (var i = 0; i < els.length; i++) {
    els[i].parentNode.replaceChild(renderjson(JSON.parse(els[i].innerText)), els[i]);
  }

  els = d.querySelectorAll(".key");
  for (var i = 0; i < els.length; i++) {
    if (els[i].textContent != '"$ref"') continue;
    var link = els[i].nextElementSibling;
    while (link = link.nextElementSibling) {
      if (!link.className || !link.className.match(/\bstring\b/)) continue;
      var a = d.createElement("a");
      var href = link.textContent.replace(/"/g, "");
      a.className = link.className;
      a.textContent = link.textContent;
      a.href = href.match(/^#/) ? "#ref-" + href.replace(/\W/g, "-").substring(2).toLowerCase() : href;
      link.parentNode.replaceChild(a, link);
    }
  }
})(window, document);
</script>
</body>
</html>
