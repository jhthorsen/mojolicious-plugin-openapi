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
