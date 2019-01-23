package Mojolicious::Plugin::OpenAPI::Cors;
use Mojo::Base -base;

use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

# https://developer.mozilla.org/en-US/docs/Web/HTTP/Access_control_CORS#Simple_requests
our @CORS_SIMPLE_METHODS = qw(GET HEAD POST);
our @CORS_SIMPLE_CONTENT_TYPES
  = qw(application/x-www-form-urlencoded multipart/form-data text/plain);
our $SKIP_RENDER;

my $X_RE = qr{^x-};

sub register {
  my ($self, $app, $openapi, $config) = @_;

  if ($config->{add_preflighted_routes}) {
    $app->plugins->once(openapi_routes_added => sub { $self->_add_preflighted_route($app, @_) });
  }

  $app->helper('openapi.cors_exchange'    => \&_helper_cors_exchange);
  $app->helper('openapi.cors_preflighted' => \&_helper_cors_preflighted);
  $app->helper('openapi.cors_simple'      => \&_helper_cors_simple);
}

sub _add_preflighted_route {
  my ($self, $app, $openapi, $routes) = @_;
  my $c = $app->build_controller;
  my $match = Mojolicious::Routes::Match->new(root => $app->routes);

  for my $route (@$routes) {
    my $route_path = $route->to_string;
    next if $match->find($c, {method => 'options', path => $route_path});

    # Make a given action also handle OPTIONS
    push @{$route->via}, 'OPTIONS';
    warn "[OpenAPI] Add route options $route_path (@{[$route->name // '']})\n" if DEBUG;
  }
}

sub _helper_cors_exchange {
  my ($c, $cb) = @_;

  local $SKIP_RENDER = 1;

  # Check simple first
  $c->openapi->cors_simple($cb);
  return $c if $c->res->headers->header('Access-Control-Allow-Origin');

  # Then go on to preflight
  $c->openapi->cors_preflighted($cb);
  return $c if $c->res->headers->header('Access-Control-Allow-Origin');

  # Invalid request
  return _render_bad_request($c);
}

sub _helper_cors_preflighted {
  my ($c, $cb) = @_;

  # Run default simple CORS checks
  my $method = uc $c->req->method;
  return $c unless $method eq 'OPTIONS';

  my $req_headers = $c->req->headers;
  my $req         = {
    headers => $req_headers->header('Access-Control-Request-Headers') // '',
    method  => $req_headers->header('Access-Control-Request-Method') // $method,
    origin  => $req_headers->header('Origin') // '',
  };

  $req->{type} = $req->{origin} ? 'preflighted' : '';

  # Allow the callback to make up the decision if this is a valid CORS request
  $c->$cb($req);

  # Valid CORS request if the callback set the Access-Control-Allow-Origin header
  return _render_preflighted_response($c, $req)
    if $c->res->headers->header('Access-Control-Allow-Origin');

  # Regular OPTIONS request
  return $c if $c->stash('openapi_allow_options_request');

  # Invalid if no header is set
  return $SKIP_RENDER ? $c : _render_bad_request($c);
}

sub _helper_cors_simple {
  my ($c, $cb) = @_;
  my $req = {type => 'simple'};

  # Run default simple CORS checks
  my $method = uc $c->req->method;
  return $c unless grep { $method eq $_ } @CORS_SIMPLE_METHODS;

  my $req_headers = $c->req->headers;
  my $ct = $req_headers->content_type || '';
  return $c if $ct and !grep { $ct eq $_ } @CORS_SIMPLE_CONTENT_TYPES;
  return $c unless $req->{origin} = $req_headers->header('Origin');

  # Allow the callback to make up the decision if this is a valid CORS request
  $c->$cb($req);

  # Valid CORS request if the callback set the Access-Control-Allow-Origin header
  return $c if $c->res->headers->header('Access-Control-Allow-Origin');

  # Invalid if no header is set
  return $SKIP_RENDER ? $c : _render_bad_request($c);
}

sub _render_bad_request {
  my $c      = shift;
  my $self   = $c->stash('openapi.object') or return;
  my @errors = ({message => 'Invalid CORS request.'});
  $self->_log($c, '<<<', \@errors);
  $c->render(data => $self->_renderer->($c, {errors => \@errors, status => 400}), status => 400);
  return $c;
}

sub _render_preflighted_response {
  my ($c, $req) = @_;
  my $h = $c->res->headers;

  $h->header('Access-Control-Allow-Headers' => $req->{headers})
    unless $h->header('Access-Control-Allow-Headers');
  $h->header('Access-Control-Allow-Methods' => $req->{method})
    unless $h->header('Access-Control-Allow-Methods');
  $h->header('Access-Control-Max-Age' => $req->{age} || '3600')
    unless $h->header('Access-Control-Max-Age');

  return $c->tap(render => data => '', status => 200);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI::Cors - OpenAPI plugin for Cross-Origin Resource Sharing

=head1 SYNOPSIS

=head2 Application

  # Set "add_preflighted_routes" to 1, if you want "Preflighted" CORS requests
  # to be sent to your action.
  $app->plugin("OpenAPI" => {add_preflighted_routes => 1});

=head2 Controller

  package MyApplication::Controller::User;

  sub get_user {
    my $c = shift;

    # Choose from one of the methods below:

    # 1. Validate incoming Simple CORS request with _validate_cors()
    $c->openapi->cors_simple("_validate_cors_simple")->openapi->valid_input or return;

    # 2. Validate incoming Preflighted CORS request with _validate_cors()
    $c->openapi->cors_preflighted("_validate_cors_preflighted")->openapi->valid_input or return;

    # 3. Validate any CORS request with _validate_cors()
    $c->openapi->cors_exchange("_validate_cors_exchange")->openapi->valid_input or return;

    $c->render(openapi => {user => {}});
  }

  sub _validate_cors_exchange {
    my ($c, $args) = @_;

    # $args->{type} is set to "simple" or "preflighted"
    $c->app->log->debug("Got CORS $args->{type} request");

    # Re-use Simple CORS logic and use default values for the rest of
    # Preflighted response.
    return $self->_validate_cors_simple($args);
  }

  sub _validate_cors_preflighted {
    my ($c, $args) = @_;

    # Need to do the following to allow regular OPTIONS request
    # Note that $args->{type} will be "preflighted" or "simple" in case of a
    # CORS request.
    return $c->stash(openapi_allow_options_request => 1) unless $args->{type};

    # Check the "Origin" header
    return unless $args->{origin} =~ m!^https?://whatever.example.com!;

    # Check the Access-Control-Request-Headers header
    return if $args->{headers} =~ /X-No-Can-Do/;

    # Check the Access-Control-Request-Method header
    return if $args->{method} eq "delete";

    # Set required Preflighted response header
    $c->res->headers->header("Access-Control-Allow-Origin" => $args->{origin});

    # Set Preflighted response headers, instead of using the default
    $c->res->headers->header("Access-Control-Allow-Headers" => "X-Whatever, X-Something");
    $c->res->headers->header("Access-Control-Allow-Methods" => "POST, GET, OPTIONS");
    $c->res->headers->header("Access-Control-Max-Age" => 86400);
  }

  sub _validate_cors_simple {
    my ($c, $args) = @_;

    # Check the "Origin" header
    if ($args->{origin} =~ m!^https?://whatever.example.com!) {

      # Setting the "Access-Control-Allow-Origin" will mark this request as valid
      $c->res->headers->header("Access-Control-Allow-Origin" => $args->{origin});
    }
  }

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI::Cors> is a plugin for accepting Preflighted or
Simple Cross-Origin Resource Sharing requests, by looking at the "Origin"
header. See L<https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS> for more
details.

This plugin is loaded by default by L<Mojolicious::Plugin::OpenAPI>.

Note that this plugin currently EXPERIMENTAL! Please let me know if you have
any feedback.

=head1 HELPERS

=head2 openapi.cors_exchange

  $c = $c->openapi->cors_exchange($method);
  $c = $c->openapi->cors_exchange("MyApp::cors_simple");
  $c = $c->openapi->cors_exchange("_some_controller_method");
  $c = $c->openapi->cors_exchange(sub { ... });

Used to validate either a simple or preflighted CORS request. This is the same
as doing:

  $c->openapi->cors_simple($method)->openapi->cors_preflighted($method);

=head2 openapi.cors_preflighted

  $c = $c->openapi->cors_preflighted($preflight_callback);
  $c = $c->openapi->cors_preflighted("MyApp::cors_simple");
  $c = $c->openapi->cors_preflighted("_some_controller_method");
  $c = $c->openapi->cors_preflighted(sub { ... });

Will validate a Preflighted CORS request using the C<$preflight_callback>, if
the incoming request...

=over 2

=item * has HTTP method set to OPTIONS

=item * has the "Access-Control-Request-Headers" header set

=item * has the "Access-Control-Request-Method" header set

=item * has the "Origin" header set

=back

C<openapi.cors_preflighted> will automatically generate a "400 Bad Request"
response if the "Access-Control-Allow-Origin" response header is not set by
C<$preflight_callback>. On success, the following headers will be set, unless
already set by C<$preflight_callback>:

C<Access-Control-Max-Age> will have the following default values if not set by
C<$preflight_callback>:

=over 2

=item * Access-Control-Allow-Headers

Set to the value of the incoming "Access-Control-Request-Headers" header.

=item * Access-Control-Allow-Methods

Set to the value of the incoming "Access-Control-Request-Method" header.

=item * Access-Control-Max-Age

Set to "3600".

=back

The C<$preflight_callback> can be a simple method name in the current
controller, a sub ref or a FQN function name, such as
C<MyApp::validate_simple_cors>. See L</SYNOPSIS> for example usage.

=head2 openapi.cors_simple

  $c = $c->openapi->cors_simple($simple_callback);
  $c = $c->openapi->cors_simple("MyApp::cors_simple");
  $c = $c->openapi->cors_simple("_some_controller_method");
  $c = $c->openapi->cors_simple(sub { ... });

Will validate a Simple CORS request using the C<$simple_callback>, if the
incoming request...

=over 2

=item * has HTTP method set to GET, HEAD or POST.

=item * has the "Content-Type" header set to application/x-www-form-urlencoded, multipart/form-data or text/plain.

=item * has the "Origin" header set

=back

C<openapi.cors_simple> will automatically generate a "400 Bad Request" response
if the "Access-Control-Allow-Origin" response header is not set by the
C<$simple_callback>.

The C<$simple_callback> can be a simple method name in the current controller,
a sub ref or a FQN function name, such as C<MyApp::validate_simple_cors>. See
L</SYNOPSIS> for example usage.

=head1 METHODS

=head2 register

Called by L<Mojolicious::Plugin::OpenAPI>.

=head1 SEE ALSO

L<Mojolicious::Plugin::OpenAPI>.

=cut
