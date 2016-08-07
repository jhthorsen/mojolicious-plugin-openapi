package Mojolicious::Plugin::OpenAPI;
use Mojo::Base 'Mojolicious::Plugin';

use JSON::Validator::OpenAPI;
use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

our $VERSION = '0.09';

sub EXCEPTION { +{errors => [{message => 'Internal server error.', path => '/'}], status => 500} }
sub NOT_FOUND { +{errors => [{message => 'Not found.',             path => '/'}], status => 404} }
sub NOT_IMPLEMENTED { +{errors => [{message => 'Not implemented.', path => '/'}], status => 501} }

my $X_RE = qr{^x-};

has _validator => sub { JSON::Validator::OpenAPI->new; };

sub register {
  my ($self, $app, $config) = @_;
  my $api_spec = $self->_load_spec($app, $config);

  unless ($app->defaults->{'openapi.base_paths'}) {
    $app->helper('openapi.invalid_input' => \&_invalid_input);
    $app->helper('openapi.valid_input'   => \&_valid_input);
    $app->helper('openapi.spec'          => sub { shift->stash('openapi.op_spec') });
    $app->helper('reply.openapi'         => \&_reply);
    $app->hook(before_render => \&_before_render);
    push @{$app->renderer->classes}, __PACKAGE__;
  }

  $self->{log_level} = $ENV{MOJO_OPENAPI_LOG_LEVEL} || $config->{log_level} || 'warn';
  $self->_validator->schema($api_spec->data)->coerce($config->{coerce} // 1);
  $self->_add_routes($app, $api_spec, $config);
}

sub _add_routes {
  my ($self, $app, $api_spec, $config) = @_;
  my $base_path    = $api_spec->get('/basePath') || '/';
  my $paths        = $api_spec->get('/paths');
  my $route        = $config->{route};
  my $route_prefix = "";
  my %uniq;

  $route = $route->any($base_path) if $route and !$route->pattern->unparsed;
  $route = $app->routes->any($base_path) unless $route;
  $base_path = $api_spec->data->{basePath} = $route->to_string;
  $base_path =~ s!/$!!;

  push @{$app->defaults->{'openapi.base_paths'}}, $base_path;
  $route->to({'openapi.api_spec' => $api_spec, 'openapi.object' => $self});

  my $spec_route = $route->get->to(cb => \&_reply_spec);
  if (my $spec_route_name = $config->{spec_route_name} || $api_spec->get('/x-mojo-name')) {
    $spec_route->name($spec_route_name);
    $route_prefix = "$spec_route_name.";
  }

  for my $path (sort { length $a <=> length $b } keys %$paths) {
    next if $path =~ $X_RE;

    for my $http_method (keys %{$paths->{$path}}) {
      next if $http_method =~ $X_RE;
      my $op_spec = $paths->{$path}{$http_method};
      my $name    = $op_spec->{'x-mojo-name'} || $op_spec->{operationId};
      my $to      = $op_spec->{'x-mojo-to'};
      my $endpoint;

      die qq([OpenAPI] operationId "$op_spec->{operationId}" is not unique)
        if $op_spec->{operationId} and $uniq{o}{$op_spec->{operationId}}++;
      die qq([OpenAPI] Route name "$name" is not unique.) if $name and $uniq{r}{$name}++;

      if ($name and $endpoint = $route->root->find($name)) {
        $route->add_child($endpoint);
      }
      if (!$endpoint) {
        $endpoint = $route->$http_method(_route_path($path, $op_spec));
        $endpoint->name("$route_prefix$name") if $name;
      }

      $endpoint->to(ref $to eq 'ARRAY' ? @$to : $to) if $to;
      $endpoint->to({'openapi.op_spec' => $op_spec});
      warn "[OpenAPI] Add route $http_method @{[$endpoint->render]}\n" if DEBUG;
    }
  }
}

sub _before_render {
  my ($c, $args) = @_;
  my $template = $args->{template} || '';
  return unless $args->{exception} or $template =~ /^not_found\b/;

  my $path     = $c->req->url->path->to_string;
  my $has_spec = $c->stash('openapi.op_spec');
  return unless $has_spec or grep { $path =~ /^$_/ } @{$c->stash('openapi.base_paths')};

  my $format = $c->stash('format') || 'json';
  my $res = $args->{exception} ? EXCEPTION() : !$has_spec ? NOT_FOUND() : NOT_IMPLEMENTED();
  $args->{status} = $res->{status};
  $args->{$format} = $res;
}

sub _invalid_input {
  my ($c, $args) = @_;
  my $self    = $c->stash('openapi.object');
  my $op_spec = $c->openapi->spec;
  my @errors  = $self->_validator->validate_request($c, $op_spec, $c->validation->output);

  if (@errors) {
    $self->_log($c, '<<<', \@errors);
    $c->render(json => {errors => \@errors, status => 400}, status => 400)
      if $args->{auto_render} // 1;
  }

  return @errors;
}

sub _load_spec {
  my ($self, $app, $config) = @_;
  my $openapi = JSON::Validator->new->schema(JSON::Validator::OpenAPI::SPECIFICATION_URL());
  my ($api_spec, @errors);

  # first check if $ref is in the right place,
  # and then check if the spec is correct
  for my $r (sub { }, undef) {
    next if $r and $config->{allow_invalid_ref};
    my $jv = JSON::Validator->new;
    $jv->resolver($r) if $r;
    $api_spec = $jv->schema($config->{url})->schema;
    $openapi->coerce('booleans' => $jv->coerce()->{'booleans'});
    @errors   = $openapi->validate($api_spec->data);
    die join "\n", "[OpenAPI] Invalid spec:", @errors if @errors;
  }

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
  my ($c, $status, $output) = @_;
  my $self = $c->stash('openapi.object');
  my $format = $c->stash('format') || 'json';

  if (UNIVERSAL::isa($output, 'Mojo::Asset')) {
    my $h = $c->res->headers;
    if (!$h->content_type and $output->isa('Mojo::Asset::File')) {
      my $types = $c->app->types;
      my $type = $output->path =~ /\.(\w+)$/ ? $types->type($1) : undef;
      $h->content_type($type || $types->type('bin'));
    }
    return $c->reply->asset($output);
  }

  my @errors = $self->_validator->validate_response($c, $c->openapi->spec, $status, $output);
  return $c->render($format => $output, status => $status) unless @errors;

  $self->_log($c, '>>>', \@errors);
  $c->render($format => {errors => \@errors, status => 500}, status => 500);
}


sub _reply_spec {
  my $c      = shift;
  my $spec   = $c->stash('openapi.api_spec')->data;
  my $format = $c->stash('format') || 'json';

  local $spec->{id};
  delete $spec->{id};
  local $spec->{host} = $c->req->url->to_abs->host_port;

  return $c->render(json => $spec) unless $format eq 'html';
  return $c->render(
    template  => 'mojolicious/plugin/openapi/layout',
    esc       => sub { local $_ = shift; s/\W/-/g; $_ },
    serialize => \&_serialize,
    spec      => $spec,
    X_RE      => $X_RE
  );
}

sub _route_path {
  my ($path, $op_spec) = @_;
  my %parameters = map { ($_->{name}, $_) } @{$op_spec->{parameters} || []};
  $path =~ s/{([^}]+)}/{
    my $pname = $1;
    my $type = $parameters{$pname}{'x-mojo-placeholder'} || ':';
    "($type$pname)";
  }/ge;
  return $path;
}

sub _serialize {
  Data::Dumper->new([@_])->Indent(1)->Pair(': ')->Sortkeys(1)->Terse(1)->Useqq(1)->Dump;
}

sub _valid_input { _invalid_input($_[0], {}) ? undef : $_[0]; }

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI - OpenAPI / Swagger plugin for Mojolicious

=head1 SYNOPSIS

  use Mojolicious::Lite;

  # Will be moved under "basePath", resulting in "POST /api/echo"
  post "/echo" => sub {
    my $c = shift->openapi->valid_input or return;
    $c->reply->openapi(200 => $c->validation->param("body"));
  }, "echo";

  # Load specification and start web server
  plugin OpenAPI => {url => "data://main/api.json"};
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

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI> is L<Mojolicious::Plugin> that add routes and
input/output validation to your L<Mojolicious> application based on a OpenAPI
(Swagger) specification.

Have a look at the L</SEE ALSO> for references to more documentation, or jump
right to the L<tutorial|Mojolicious::Plugin::OpenAPI::Guides::Tutorial>.

L<Mojolicious::Plugin::OpenAPI> will replace L<Mojolicious::Plugin::Swagger2>.

This plugin is currently EXPERIMENTAL.

=head1 HELPERS

=head2 openapi.invalid_input

  @errors = $c->openapi->invalid_input;
  @errors = $c->openapi->invalid_input({auto_render => 0});

Used to validate a request. C<@errors> holds a list of
L<JSON::Validator::Error> objects or empty list on valid input. Setting
C<auto_render> to a false value will disable the internal auto rendering. This
is useful if you want to craft a custom resonse.

Validated input parameters will be copied to
C<Mojolicious::Controller/validation>, which again can be extracted by the
"name" in the parameters list from the spec. Example:

  # specification:
  "parameters": [{"in": "body", "name": "whatever", "schema": {"type": "object"}}],

  # controller
  my $body = $c->validation->param("whatever");

=head2 openapi.spec

  $hash = $c->openapi->spec;

Returns the OpenAPI specification for the current route. Example:

  {
    "paths": {
      "/pets": {
        "get": {
          // This datastructure is returned
        }
      }
    }
  }

=head2 openapi.valid_input

  $c = $c->openapi->valid_input;

Returns the L<Mojolicious::Controller> object if the input is valid. This
helper will also auto render a response. Use L</openapi.invalid_input> if this
is not the desired behavior.

See L</SYNOPSIS> for example usage.

=head2 reply.openapi

  $c->reply->openapi($status => $output);

Will L<validate|/openapi.validate> C<$output> before passing it on to
L<Mojolicious::Controller/render>. Note that C<$output> will be passed on using
the L<format|Mojolicious::Guides::Rendering/Content type> key in stash, which
defaults to "json". This also goes for L<auto-rendering|/Controller>. Example:

  my $format = $c->stash("format") || "json";
  $c->render($format => \%output);

C<$status> is a HTTP status code.

=head1 METHODS

=head2 register

  $self->register($app, \%config);

Loads the OpenAPI specification, validates it and add routes to
L<$app|Mojolicious>. It will also set up L</HELPERS> and adds a
L<before_render|Mojolicious/before_render> hook for auto-rendering of error
documents.

C<%config> can have:

=over 2

=item * allow_invalid_ref

The OpenAPI specification does not allow "$ref" at every level, but setting
this flag to a true value will ignore the $ref check.

Note that setting this attribute is discourage.

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

=item * spec_route_name

Name of the route that handles the "basePath" part of the specification and
serves the specification. Defaults to "x-mojo-name" in the specification at
the top level.

=item * url

See L<JSON::Validator/schema> for the different C<url> formats that is
accepted.

=back

=head1 TODO

This plugin is still a big rough on the edges, but I decided to release it on
CPAN so people can start playing around with it.

=over 2

=item * Add L<WebSockets support|https://github.com/jhthorsen/mojolicious-plugin-openapi/compare/websocket>.

=item * Add support for /api.html (human readable documentation)

=item * Never add support for "x-mojo-around-action", but possibly "before action".

=back

=head1 AUTHOR

Jan Henning Thorsen

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

=over 2

=item * L<Mojolicious::Plugin::OpenAPI::Guides::Tutorial>

=item * L<http://thorsen.pm/perl/programming/2015/07/05/mojolicious-swagger2.html>.

=item * L<OpenAPI specification|https://openapis.org/specification>

=item * L<Mojolicious::Plugin::Swagger2>.

=back

=cut

__DATA__
@@ mojolicious/plugin/openapi/header.html.ep
<h1 id="title"><%= $spec->{info}{title} || 'No title' %></h1>
<p class="version"><span>Version</span> <span class="version"><%= $spec->{info}{version} %></span></p>

% if ($spec->{info}{description}) {
<h2 id="description">Description</h2>
<p class="description">
  %= $spec->{info}{description}
</p>
% }

% if ($spec->{info}{termsOfService}) {
<h2 id="terms-of-service">Terms of service</h2>
<p class="terms-of-service">
  %= $spec->{info}{termsOfService}
</p>
% }

% my $schemes = $spec->{schemes} || ["http"];
% my $url = Mojo::URL->new("http://$spec->{host}");
<h3 id="base-url">Base URL</h3>
<ul>
% for my $scheme (@$schemes) {
  % $url->scheme($scheme);
  <li><a href="<%= $url %>"><%= $url %></a></li>
% }
</ul>
@@ mojolicious/plugin/openapi/footer.html.ep
% my $contact = $spec->{info}{contact};
% my $license = $spec->{info}{license};
<h2 class="license">License</h2>
% if ($license->{name}) {
<p class="license"><a href="<%= $license->{url} || '' %>"><%= $license->{name} %></a></p>
% } else {
<p class="no-license">No license specified.</p>
% }
<h2 class="contact">Contact information</h2>
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
<p class="spec-description"><%= $spec->{description} %></p>
% }
% if (!$spec->{description} and !$spec->{summary}) {
<p class="op-summary op-doc-missing">This resource is not documented.</p>
% }
@@ mojolicious/plugin/openapi/parameters.html.ep
% my $has_parameters = @{$op->{parameters} || []};
% my $body;
<h3 class="op-parameters">Parameters</h3>
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
      <td><%= $p->{name} %></td>
      <td><%= $p->{in} %></td>
      <td><%= $p->{type} %></td>
      <td><%= $p->{required} ? "Yes" : "No" %></td>
      <td><%= $p->{description} || "" %></td>
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
<h3 class="op-response">Response <%= $code %></h3>
%= include "mojolicious/plugin/openapi/human", spec => $res
<pre class="op-response"><%= $serialize->($res->{schema}) %></pre>
% }
@@ mojolicious/plugin/openapi/resource.html.ep
<h3 id="op-<%= lc $method %><%= $esc->($path) %>" class="op-path <%= $op->{deprecated} ? "deprecated" : "" %>"><%= uc $method %> <%= $spec->{basePath} %><%= $path %></h3>
% if ($op->{deprecated}) {
<p class="op-deprecated">This resource is deprecated!</p>
% }
% if ($op->{operationId}) {
<p class="op-id"><b>Operation ID:</b> <span><%= $op->{operationId} %></span></p>
% }
%= include "mojolicious/plugin/openapi/human", spec => $op
%= include "mojolicious/plugin/openapi/parameters", op => $op
%= include "mojolicious/plugin/openapi/response", op => $op
@@ mojolicious/plugin/openapi/resources.html.ep
<h2 id="resources">Resources</h2>
% for my $path (sort { length $a <=> length $b } keys %{$spec->{paths}}) {
  % next if $path =~ $X_RE;
  % for my $http_method (sort keys %{$spec->{paths}{$path}}) {
    % next if $http_method =~ $X_RE;
    % my $op = $spec->{paths}{$path}{$http_method};
    %= include "mojolicious/plugin/openapi/resource", method => $http_method, op => $op, path => $path
  % }
% }
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
    }
    a {
      color: #225;
      text-decoration: underline;
    }
    h1, h2, h3, h4 { font-weight: bold; margin: 1em 0; }
    h1 { font-size: 2em; }
    h2 { font-size: 1.6em; margin-top: 2em; }
    h3 { font-size: 1.2em; }
    h4 { font-size: 1.1em; }
    pre {
      background: #eee;
      border: 1px solid #ddd;
      padding: 0.5em;
      margin: 1em -0.5em;
      overflow: auto;
    }
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
    ul {
      list-style: none;
      margin: 0;
      padding: 0;
    }
    div.container { max-width: 50em; margin: 0 auto; }
    p.version { color: #666; margin: -0.5em 0 2em 0; }
    p.op-deprecated { color: #c00; }
    h3.op-path { margin-top: 3em; }
    .container > h3.op-path { margin-top: 1em; }
  </style>
</head>
<body>
<div class="container">
  %= include "mojolicious/plugin/openapi/header"
  %= include "mojolicious/plugin/openapi/endpoint"
  %= include "mojolicious/plugin/openapi/resources"
  %= include "mojolicious/plugin/openapi/footer"
</div>
</body>
</html>
