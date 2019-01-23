package Mojolicious::Plugin::OpenAPI::Cors;
use Mojo::Base -base;

use constant DEBUG => $ENV{MOJO_OPENAPI_DEBUG} || 0;

our %SIMPLE_METHODS = map { ($_ => 1) } qw(GET HEAD POST);
our %SIMPLE_CONTENT_TYPES
  = map { ($_ => 1) } qw(application/x-www-form-urlencoded multipart/form-data text/plain);
our %SIMPLE_HEADERS = map { (lc $_ => 1) }
  qw(Accept Accept-Language Content-Language Content-Type DPR Downlink Save-Data Viewport-Width Width);

our %PREFLIGHTED_CONTENT_TYPES = %SIMPLE_CONTENT_TYPES;
our %PREFLIGHTED_METHODS = map { ($_ => 1) } qw(CONNECT DELETE OPTIONS PATCH PUT TRACE);

my $X_RE = qr{^x-};

sub register {
  my ($self, $app, $openapi, $config) = @_;

  if ($config->{add_preflighted_routes}) {
    $app->plugins->once(openapi_routes_added => sub { $self->_add_preflighted_routes($app, @_) });
  }

  $app->defaults(openapi_cors_default_exchange_callback => \&_default_cors_exchange_callback);
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
  my $c = $app->build_controller;
  my $match = Mojolicious::Routes::Match->new(root => $app->routes);

  for my $route (@$routes) {
    my $route_path = $route->to_string;
    next if $match->find($c, {method => 'options', path => $route_path});

    # Make a given action also handle OPTIONS
    push @{$route->via}, 'OPTIONS';
    $route->to->{'openapi.cors_preflighted'} = 1;
    warn "[OpenAPI] Add route options $route_path (@{[$route->name // '']})\n" if DEBUG;
  }
}

sub _default_cors_exchange_callback {
  my ($c, $req) = @_;
  my $allow_origins = $c->stash('openapi_cors_allow_origins') || [];
  return scalar(grep { $req->{origin} =~ $_ } @$allow_origins) ? undef : '/Origin';
}

sub _exchange {
  my ($self, $c) = (shift, shift);
  my $cb = shift || $c->stash('openapi_cors_default_exchange_callback');

  my $h   = $c->req->headers;
  my $req = {
    headers => $h->header('Access-Control-Request-Headers') // '',
    method  => $h->header('Access-Control-Request-Method') // $c->req->method,
    origin  => $h->header('Origin'),
  };

  # Not a CORS request
  unless (defined $req->{origin}) {
    $self->_render_bad_request($c, 'OPTIONS is only for preflighted CORS requests.')
      if $c->match->endpoint->to->{'openapi.cors_preflighted'};
    return $c;
  }

  $req->{type}
    = $self->_is_simple_request($c, $req) || $self->_is_preflighted_request($c, $req) || 'real';

  my $errors = $c->$cb($req);

  # TODO: Remove support for openapi.cors_simple
  if ($c->stash('openapi.cors_simple_deprecated')) {
    warn "\$c->openapi->cors_simple() has been replaced by \$c->openapi->cors_exchange()";
    return $self->_render_bad_request($c, '/Origin')
      unless $c->res->headers->header("Access-Control-Allow-Origin");
    return $c;
  }

  return $self->_render_bad_request($c, $errors) if $errors;

  $self->_set_default_headers($c, $req);
  return $req->{type} eq 'preflighted' ? $c->tap(render => data => '', status => 200) : $c;
}

sub _is_preflighted_request {
  my ($self, $c, $req) = @_;

  return undef unless $c->req->method eq 'OPTIONS';
  return 'preflighted' if $req->{headers};
  return 'preflighted' if $PREFLIGHTED_METHODS{$req->{method}};

  my $ct = lc $c->req->headers->content_type || '';
  return 'preflighted' if $ct and $PREFLIGHTED_CONTENT_TYPES{$ct};

  return undef;
}

sub _is_simple_request {
  my ($self, $c, $req) = @_;

  my $method = $c->req->method;
  return undef unless $SIMPLE_METHODS{$method};

  my $h = $c->req->headers;
  my @names = grep { !$SIMPLE_HEADERS{lc($_)} } @{$h->names};
  return undef if @names;

  my $ct = lc $h->content_type || '';
  return undef if $ct and $SIMPLE_CONTENT_TYPES{$ct};

  return 'simple';
}

sub _render_bad_request {
  my ($self, $c, $errors) = @_;

  unless (ref $errors) {
    if ($errors =~ m!^/([\w-]+)!) {
      $errors = [{message => "Invalid $1 header.", path => $errors}];
    }
    else {
      $errors = [{message => $errors, path => '/'}];
    }
  }

  return $c->tap(render => openapi => {errors => $errors, status => 400}, status => 400);
}

sub _set_default_headers {
  my ($self, $c, $req) = @_;
  my $h = $c->res->headers;

  $h->header('Access-Control-Allow-Origin' => $req->{origin})
    unless $h->header('Access-Control-Allow-Origin');

  return unless $req->{type} eq 'preflighted';

  $h->header('Access-Control-Allow-Headers' => $req->{headers})
    unless $h->header('Access-Control-Allow-Headers');

  unless ($h->header('Access-Control-Allow-Methods')) {
    my $op_spec = $c->openapi->spec('for_path');
    my @methods = sort grep { !/$X_RE/ } keys %{$op_spec || {}};
    $h->header('Access-Control-Allow-Methods' => uc join ', ', @methods);
  }

  unless ($h->header('Access-Control-Max-Age')) {
    my $default_max_age = $c->stash('openapi_cors_default_max_age') || 1800;
    $h->header('Access-Control-Max-Age' => $req->{age} || $default_max_age);
  }
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI::Cors - OpenAPI plugin for Cross-Origin Resource Sharing

=head1 SYNOPSIS

=head2 Application

Set L</add_preflighted_routes> to 1, if you want "Preflighted" CORS requests to
be sent to your already existing actions.

  $app->plugin("OpenAPI" => {add_preflighted_routes => 1});

=head2 Simple exchange

The following example will automatically set default CORS response headers
after validating the request against L</openapi_cors_allow_origins>:

  package MyApp::Controller::User;

  sub get_user {
    my $c = shift->openapi->cors_exchange->openapi->valid_input or return;

    # Will only run this part if both the cors_exchange and valid_input was
    # successful.
    $c->render(openapi => {user => {}});
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

  # This method must return undef on success. Any true value will be used as
  # an error.
  sub _validate_cors {
    my ($c, $params) = @_;

    # $params->{type} is set to "preflighted", "real" or "simple"
    $c->app->log->debug("Got CORS $params->{type} request");

    # The following "Origin" header check is the same for both simple and
    # preflighted.
    return "/Origin" unless $params->{origin} =~ m!^https?://whatever.example.com!;

    # The following checks are only valid if preflighted...

    # Check the Access-Control-Request-Headers header
    return "Bad stuff." if $params->{headers} and $params->{headers} =~ /X-No-Can-Do/;

    # Check the Access-Control-Request-Method header
    return "Not cool." if $params->{method} and $params->{method} eq "delete";

    # Set the following header for both simple and preflighted on success
    # or just let the auto-renderer handle it.
    $c->res->headers->header("Access-Control-Allow-Origin" => $params->{origin});

    # Set Preflighted response headers, instead of using the default
    if ($params->{type} eq "preflighted") {
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

=head2 openapi_cors_allow_origins

This variable should hold an array-ref of regexes that will be matched against
the "Origin" header in case the default
L</openapi_cors_default_exchange_callback> is used. Examples:

  $app->defaults(openapi_cors_allow_origins => [qr{^https?://whatever.example.com}]);
  $c->stash(openapi_cors_allow_origins => [qr{^https?://whatever.example.com}]);

=head2 openapi_cors_default_exchange_callback

Instead of using the default C<$callback> provided by this module for
L</openapi.cors_exchange>, you can set a global value.

=head2 openapi_cors_default_max_age

Holds the default value for the "Access-Control-Max-Age" response header
set by L</openapi.cors_preflighted>. Examples:

  $app->defaults(openapi_cors_default_max_age => 3600);
  $c->stash(openapi_cors_default_max_age => 3600);

=head1 HELPERS

=head2 openapi.cors_exchange

  $c = $c->openapi->cors_exchange($callback);
  $c = $c->openapi->cors_exchange("MyApp::cors_validator");
  $c = $c->openapi->cors_exchange("_some_controller_method");
  $c = $c->openapi->cors_exchange(sub { ... });
  $c = $c->openapi->cors_exchange;

Used to validate either a simple CORS request, preflighted CORS request or a
real request. It will be called as soon as the "Origin" request header is seen.

The C<$callback> will be called with the following arguments:

  my $error = $callback->($c, {
    headers => "X-Foo", # Value of Access-Control-Request-Headers or empty string
    method  => "DELETE", # Value of Access-Control-Request-Method or empty string
    origin  => "https://example.com", # Value of "Origin" header
    type    => "simple", # either "preflighted", "real" or "simple"
  });

The return value C<$error> must be in one of the following formats:

=over 2

=item * A string starting with "/"

Shortcut for generating a 400 Bad Request response with a header name. Example:

  return "/Origin"                         if $params->{origin} !~ /example.com$/;
  return "/Access-Control-Request-Headers" if $params->{headers} =~ /^X-Foo/;

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

Set to L</openapi_cors_default_max_age> or 1800.

=back

=head1 METHODS

=head2 register

Called by L<Mojolicious::Plugin::OpenAPI>.

=head1 SEE ALSO

L<Mojolicious::Plugin::OpenAPI>.

=cut
