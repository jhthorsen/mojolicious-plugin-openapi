package Mojolicious::Plugin::OpenAPI::Cors;
use Mojo::Base -base;

# https://developer.mozilla.org/en-US/docs/Web/HTTP/Access_control_CORS#Simple_requests
our @CORS_SIMPLE_METHODS = qw(GET HEAD POST);
our @CORS_SIMPLE_CONTENT_TYPES
  = qw(application/x-www-form-urlencoded multipart/form-data text/plain);

sub register {
  my ($self, $app, $openapi, $config) = @_;
  $app->helper('openapi.cors_simple' => \&_helper_cors_simple);
}

sub _helper_cors_simple {
  my ($c, $cb) = @_;
  my $req = {};

  # Run default simple CORS checks
  my $method = uc $c->req->method;
  return $c unless grep { $method eq $_ } @CORS_SIMPLE_METHODS;

  my $req_headers = $c->req->headers;
  my $ct = $req_headers->content_type || '';
  return $c unless grep { $ct eq $_ } @CORS_SIMPLE_CONTENT_TYPES;
  return $c unless $req->{origin} = $req_headers->header('Origin');

  # Allow the callback to make up the decision if this is a valid CORS request
  $c->tap($cb, $req);

  # Valid CORS request if the callback set the Access-Control-Allow-Origin header
  return $c if $c->res->headers->header('Access-Control-Allow-Origin');

  # Invalid if no header is set
  my $self = $c->stash('openapi.object') or return;
  my @errors = ({message => 'Invalid CORS request.'});
  $self->_log($c, '<<<', \@errors);
  $c->render(data => $self->_renderer->($c, {errors => \@errors, status => 400}), status => 400);
  return $c;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::OpenAPI::Cors - OpenAPI plugin for Cross-Origin Resource Sharing

=head1 SYNOPSIS

  package MyApplication::Controller::User;

  sub get_user {

    # Validate incoming CORS request with _validate_cors()
    my $c = shift->openapi->cors_simple("_validate_cors")->openapi->valid_input or return;

    $c->render(openapi => {user => {}});
  }

  sub _validate_cors {
    my ($c, $args) = @_;

    # Check the origin of the request
    if ($args->{origin} =~ m!^https?://whatever.example.com!) {

      # Setting the "Access-Control-Allow-Origin" will mark this request as valid
      $c->res->headers->header("Access-Control-Allow-Origin" => $args->{origin});
    }
  }

=head1 DESCRIPTION

L<Mojolicious::Plugin::OpenAPI::Cors> is a plugin for accepting Simple
Cross-Origin Resource Sharing requests, by looking at the "Origin" header. See
L<https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS> for more details.

This plugin is loaded by default by L<Mojolicious::Plugin::OpenAPI>.

Note that this plugin currently EXPERIMENTAL! Please let me know if you have
any feedback.

=head1 HELPERS

=head2 openapi.cors_simple

  $c = $c->openapi->cors_simple($method);

Will validate the incoming request using the C<$method>, if the incoming
request HTTP method is

=over 2

=item * The HTTP method is GET, HEAD or POST.

=item * The "Content-Type" header is application/x-www-form-urlencoded, multipart/form-data or text/plain.

=item * The "Origin" header set

=back

C<openapi.cors_simple> will automatically generate a "400 Bad Request" response
if the "Access-Control-Allow-Origin" response header is not set.

The C<$method> can be a simple method name in the current controller, a sub ref
or a FQN function name, such as C<MyApp::validate_simple_cors>. See L</SYNOPSIS>
for example usage.

=head1 METHODS

=head2 register

Called by L<Mojolicious::Plugin::OpenAPI>.

=head1 SEE ALSO

L<Mojolicious::Plugin::OpenAPI>.

=cut
