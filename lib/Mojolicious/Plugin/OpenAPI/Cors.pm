package Mojolicious::Plugin::OpenAPI::Cors;
use Mojo::Base -base;

use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

our %SIMPLE_METHODS = map { ($_ => 1) } qw(GET HEAD POST);
our %SIMPLE_CONTENT_TYPES
  = map { ($_ => 1) } qw(application/x-www-form-urlencoded multipart/form-data text/plain);
our %SIMPLE_HEADERS = map { (lc $_ => 1) }
  qw(Accept Accept-Language Content-Language Content-Type DPR Downlink Save-Data Viewport-Width Width);

our %PREFLIGHTED_CONTENT_TYPES = %SIMPLE_CONTENT_TYPES;
our %PREFLIGHTED_METHODS       = map { ($_ => 1) } qw(CONNECT DELETE OPTIONS PATCH PUT TRACE);

my $X_RE = qr{^x-};

sub register {
  my ($self, $app, $config) = @_;
  my $openapi = $config->{openapi};

  if ($config->{add_preflighted_routes}) {
    $app->plugins->once(openapi_routes_added => sub { $self->_add_preflighted_routes($app, @_) });
  }

  my %defaults = (
    openapi_cors_allowed_origins           => [],
    openapi_cors_default_exchange_callback => \&_default_cors_exchange_callback,
    openapi_cors_default_max_age           => 1800,
  );

  $app->defaults($_ => $defaults{$_}) for grep { !$app->defaults($_) } keys %defaults;
  $app->helper('openapi.cors_exchange' => sub { $self->_exchange(@_) });

  # TODO: Remove support for openapi.cors_simple
  $app->helper(
    'openapi.cors_simple' => sub {
      $self->_exchange(shift->stash('openapi.cors_simple_deprecated' => 1), @_);
    }
  );
}

sub _add_preflighted_routes {
  my ($self, $app, $openapi, $routes) = @_;
  my $c     = $app->build_controller;
  my $match = Mojolicious::Routes::Match->new(root => $app->routes);

  for my $route (@$routes) {
    my $route_path = $route->to_string;
    next if $self->_takeover_exchange_route($route);
    next if $match->find($c, {method => 'options', path => $route_path});

    # Make a given action also handle OPTIONS
    push @{$route->via}, 'OPTIONS';
    $route->to->{'openapi.cors_preflighted'} = 1;
    warn "[OpenAPI] Add route options $route_path (@{[$route->name // '']})\n" if DEBUG;
  }
}

sub _default_cors_exchange_callback {
  my $c       = shift;
  my $allowed = $c->stash('openapi_cors_allowed_origins') || [];
  my $origin  = $c->req->headers->origin // '';

  return scalar(grep { $origin =~ $_ } @$allowed) ? undef : '/Origin';
}

sub _exchange {
  my ($self, $c) = (shift, shift);
  my $cb = shift || $c->stash('openapi_cors_default_exchange_callback');

  # Not a CORS request
  unless (defined $c->req->headers->origin) {
    my $method = $c->req->method;
    _render_bad_request($c, 'OPTIONS is only for preflighted CORS requests.')
      if $method eq 'OPTIONS' and $c->match->endpoint->to->{'openapi.cors_preflighted'};
    return $c;
  }

  my $type = $self->_is_simple_request($c) || $self->_is_preflighted_request($c) || 'real';
  $c->stash(openapi_cors_type => $type);

  my $errors = $c->$cb;

  # TODO: Remove support for openapi.cors_simple
  if ($c->stash('openapi.cors_simple_deprecated')) {
    warn "\$c->openapi->cors_simple() has been replaced by \$c->openapi->cors_exchange()";
    return _render_bad_request($c, '/Origin') unless $c->res->headers->access_control_allow_origin;
    return $c;
  }

  return _render_bad_request($c, $errors) if $errors;

  _set_default_headers($c);
  return $type eq 'preflighted' ? $c->tap('render', data => '', status => 200) : $c;
}

sub _is_preflighted_request {
  my ($self, $c) = @_;
  my $req_h = $c->req->headers;

  return undef unless $c->req->method eq 'OPTIONS';
  return 'preflighted' if $req_h->header('Access-Control-Request-Headers');
  return 'preflighted' if $req_h->header('Access-Control-Request-Method');

  my $ct = lc($req_h->content_type || '');
  return 'preflighted' if $ct and $PREFLIGHTED_CONTENT_TYPES{$ct};

  return undef;
}

sub _is_simple_request {
  my ($self, $c) = @_;
  return undef unless $SIMPLE_METHODS{$c->req->method};

  my $req_h = $c->req->headers;
  my @names = grep { !$SIMPLE_HEADERS{lc($_)} } @{$req_h->names};
  return undef if @names;

  my $ct = lc $req_h->content_type || '';
  return undef if $ct and $SIMPLE_CONTENT_TYPES{$ct};

  return 'simple';
}

sub _render_bad_request {
  my ($c, $errors) = @_;

  $errors = [{message => "Invalid $1 header.", path => $errors}]
    if !ref $errors and $errors =~ m!^/([\w-]+)!;
  $errors = [{message => $errors, path => '/'}] unless ref $errors;

  return $c->tap('render', openapi => {errors => $errors, status => 400}, status => 400);
}

sub _set_default_headers {
  my $c     = shift;
  my $req_h = $c->req->headers;
  my $res_h = $c->res->headers;

  unless ($res_h->access_control_allow_origin) {
    $res_h->access_control_allow_origin($req_h->origin);
  }

  return unless $c->stash('openapi_cors_type') eq 'preflighted';

  unless ($res_h->header('Access-Control-Allow-Headers')) {
    $res_h->header(
      'Access-Control-Allow-Headers' => $req_h->header('Access-Control-Request-Headers') // '');
  }

  unless ($res_h->header('Access-Control-Allow-Methods')) {
    my $op_spec = $c->openapi->spec('for_path');
    my @methods = sort grep { !/$X_RE/ } keys %{$op_spec || {}};
    $res_h->header('Access-Control-Allow-Methods' => uc join ', ', @methods);
  }

  unless ($res_h->header('Access-Control-Max-Age')) {
    $res_h->header('Access-Control-Max-Age' => $c->stash('openapi_cors_default_max_age'));
  }
}

sub _takeover_exchange_route {
  my ($self, $route) = @_;
  my $defaults = $route->to;

  return 0 if $defaults->{controller};
  return 0 unless $defaults->{action} and $defaults->{action} eq 'openapi_plugin_cors_exchange';
  return 0 unless grep { $_ eq 'OPTIONS' } @{$route->via};

  $defaults->{cb} = sub {
    my $c = shift;
    $c->openapi->valid_input or return;
    $c->req->headers->origin or return _render_bad_request($c, '/Origin');
    $c->stash(openapi_cors_type => 'preflighted');
    _set_default_headers($c);
    $c->render(data => '', status => 200);
  };

  return 1;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI::Cors - OpenAPI plugin for Cross-Origin Resource Sharing

=head1 SYNOPSIS

=head2 Application

Set L</add_preflighted_routes> to 1, if you want "Preflighted" CORS requests to
be sent to your already existing actions.

  $app->plugin(OpenAPI => {add_preflighted_routes => 1, %openapi_parameters});

See L<Mojolicious::Plugin::OpenAPI/register> for what
C<%openapi_parameters> might contain.

=head2 Simple exchange

The following example will automatically set default CORS response headers
after validating the request against L</openapi_cors_allowed_origins>:

  package MyApp::Controller::User;

  sub get_user {
    my $c = shift->openapi->cors_exchange->openapi->valid_input or return;

    # Will only run this part if both the cors_exchange and valid_input was successful.
    $c->render(openapi => {user => {}});
  }

=head2 Using the specification

It's possible to enable preflight and simple CORS support directly in the
specification. Here is one example:

  "/user/{id}/posts": {
    "parameters": [
      { "in": "header", "name": "Origin", "type": "string", "pattern": "https?://example.com" }
    ],
    "options": {
      "x-mojo-to": "#openapi_plugin_cors_exchange",
      "responses": {
        "200": { "description": "Cors exchange", "schema": { "type": "string" } }
      }
    },
    "put": {
      "x-mojo-to": "user#add_post",
      "responses": {
        "200": { "description": "Add a new post.", "schema": { "type": "object" } }
      }
    }
  }

The special part can be found in the "OPTIONS" request It has the C<x-mojo-to>
key set to "#openapi_plugin_cors_exchange". This will enable
L<Mojolicious::Plugin::OpenAPI::Cors> to take over the route and add a custom
callback to validate the input headers using regular OpenAPI rules and respond
with a "200 OK" and the default headers as listed under
L</openapi.cors_exchange> if the input is valid. The only extra part that needs
to be done in the C<add_post()> action is this:

  sub add_post {
    my $c = shift->openapi->valid_input or return;

    # Need to respond with a "Access-Control-Allow-Origin" header if
    # the input "Origin" header was validated
    $c->res->headers->access_control_allow_origin($c->req->headers->origin)
      if $c->req->headers->origin;

    # Do the rest of your custom logic
    $c->respond(openapi => {});
  }

=head2 Custom exchange

If you need full control, you must pass a callback to
L</openapi.cors_exchange>:

  package MyApp::Controller::User;

  sub get_user {
    # Validate incoming CORS request with _validate_cors()
    my $c = shift->openapi->cors_exchange("_validate_cors")->openapi->valid_input or return;

    # Will only run this part if both the cors_exchange and valid_input was
    # successful.
    $c->render(openapi => {user => {}});
  }

  # This method must return undef on success. Any true value will be used as an error.
  sub _validate_cors {
    my $c     = shift;
    my $req_h = $c->req->headers;
    my $res_h = $c->res->headers;

    # The following "Origin" header check is the same for both simple and
    # preflighted.
    return "/Origin" unless $req_h->origin =~ m!^https?://whatever.example.com!;

    # The following checks are only valid if preflighted...

    # Check the Access-Control-Request-Headers header
    my $headers = $req_h->header('Access-Control-Request-Headers');
    return "Bad stuff." if $headers and $headers =~ /X-No-Can-Do/;

    # Check the Access-Control-Request-Method header
    my $method = $req_h->header('Access-Control-Request-Methods');
    return "Not cool." if $method and $method eq "DELETE";

    # Set the following header for both simple and preflighted on success
    # or just let the auto-renderer handle it.
    $c->res->headers->access_control_allow_origin($req_h->origin);

    # Set Preflighted response headers, instead of using the default
    if ($c->stash("openapi_cors_type") eq "preflighted") {
      $c->res->headers->header("Access-Control-Allow-Headers" => "X-Whatever, X-Something");
      $c->res->headers->header("Access-Control-Allow-Methods" => "POST, GET, OPTIONS");
      $c->res->headers->header("Access-Control-Max-Age" => 86400);
    }

    # Return undef on success.
    return undef;
  }

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI::Cors> is a plugin for accepting Preflighted or
Simple Cross-Origin Resource Sharing requests. See
L<https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS> for more details.

This plugin is loaded by default by L<Mojolicious::Plugin::OpenAPI>.

Note that this plugin currently EXPERIMENTAL! Please comment on
L<https://github.com/jhthorsen/mojolicious-plugin-openapi/pull/102> if
you have any feedback or create a new issue.

=head1 STASH VARIABLES

The following "stash variables" can be set in L<Mojolicious/defaults>,
L<Mojolicious::Routes::Route/to> or L<Mojolicious::Controller/stash>.

=head2 openapi_cors_allowed_origins

This variable should hold an array-ref of regexes that will be matched against
the "Origin" header in case the default
L</openapi_cors_default_exchange_callback> is used. Examples:

  $app->defaults(openapi_cors_allowed_origins => [qr{^https?://whatever.example.com}]);
  $c->stash(openapi_cors_allowed_origins => [qr{^https?://whatever.example.com}]);

=head2 openapi_cors_default_exchange_callback

This value holds a default callback that will be used by
L</openapi.cors_exchange>, unless you pass on a C<$callback>. The default
provided by this plugin will simply validate the C<Origin> header against
L</openapi_cors_allowed_origins>.

Here is an example to allow every "Origin"

  $app->defaults(openapi_cors_default_exchange_callback => sub {
    my $c = shift;
    $c->res->headers->header("Access-Control-Allow-Origin" => "*");
    return undef;
  });

=head2 openapi_cors_default_max_age

Holds the default value for the "Access-Control-Max-Age" response header
set by L</openapi.cors_preflighted>. Examples:

  $app->defaults(openapi_cors_default_max_age => 86400);
  $c->stash(openapi_cors_default_max_age => 86400);

Default value is 1800.

=head2 openapi_cors_type

This stash variable is available inside the callback passed on to
L</openapi.cors_exchange>. It will be either "preflighted", "real" or "simple".
"real" is the type that comes after "preflighted" when the actual request
is sent to the server, but with "Origin" header set.

=head1 HELPERS

=head2 openapi.cors_exchange

  $c = $c->openapi->cors_exchange($callback);
  $c = $c->openapi->cors_exchange("MyApp::cors_validator");
  $c = $c->openapi->cors_exchange("_some_controller_method");
  $c = $c->openapi->cors_exchange(sub { ... });
  $c = $c->openapi->cors_exchange;

Used to validate either a simple CORS request, preflighted CORS request or a
real request. It will be called as soon as the "Origin" request header is seen.

The C<$callback> will be called with the current L<Mojolicious::Controller>
object and must return an error or C<undef()> on success:

  my $error = $callback->($c);

The C<$error> must be in one of the following formats:

=over 2

=item * C<undef()>

Returning C<undef()> means that the CORS request is valid.

=item * A string starting with "/"

Shortcut for generating a 400 Bad Request response with a header name. Example:

  return "/Access-Control-Request-Headers";

=item * Any other string

Used to generate a 400 Bad Request response with a completely custom message.

=item * An array-ref

Used to generate a completely custom 400 Bad Request response. Example:

  return [{message => "Some error!", path => "/Whatever"}];
  return [{message => "Some error!"}];
  return [JSON::Validator::Error->new];

=back

On success, the following headers will be set, unless already set by
C<$callback>:

=over 2

=item * Access-Control-Allow-Headers

Set to the header of the incoming "Access-Control-Request-Headers" header.

=item * Access-Control-Allow-Methods

Set to the list of HTTP methods defined in the OpenAPI spec for this path.

=item * Access-Control-Allow-Origin

Set to the "Origin" header in the request.

=item * Access-Control-Max-Age

Set to L</openapi_cors_default_max_age>.

=back

=head1 METHODS

=head2 register

Called by L<Mojolicious::Plugin::OpenAPI>.

=head1 SEE ALSO

L<Mojolicious::Plugin::OpenAPI>.

=cut
