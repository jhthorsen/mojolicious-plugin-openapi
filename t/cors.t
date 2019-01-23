use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
my $cors_method = '';
get '/user' => sub {
  my $c = shift->openapi->$cors_method("main::$cors_method")->openapi->valid_input or return;
  $c->render(json => {cors => $cors_method, origin => $c->stash('origin')});
  },
  'User';

plugin OpenAPI => {url => 'data://main/cors.json', add_preflighted_routes => 1};

my $t = Test::Mojo->new;

note $cors_method = 'cors_simple';
$t->get_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://bar.example'})
  ->status_is(400)->json_is('/errors/0/message', 'Invalid CORS request.');
$t->get_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://foo.example'})
  ->status_is(200)->header_is('Access-Control-Allow-Origin' => 'http://foo.example')
  ->json_is('/cors', 'cors_simple')->json_is('/origin', 'http://foo.example');
$t->get_ok('/api/user', {Origin => 'http://foo.example'})->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => 'http://foo.example');

note $cors_method = 'cors_preflighted';
$t->options_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://bar.example'})
  ->status_is(400)->json_is('/errors/0/message', 'Invalid CORS request.');
$t->options_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://foo.example'})
  ->header_is('Access-Control-Allow-Origin'  => 'http://foo.example')
  ->header_is('Access-Control-Allow-Headers' => 'X-Whatever, X-Something')
  ->header_is('Access-Control-Allow-Methods' => 'POST, GET, OPTIONS')
  ->header_is('Access-Control-Max-Age'       => 86400)->content_is('');

note $cors_method = 'cors_exchange';
$t->options_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://bar.example'})
  ->status_is(400)->json_is('/errors/0/message', 'Invalid CORS request.');
$t->options_ok(
  '/api/user',
  {
    'Access-Control-Request-Headers' => 'X-Foo, X-Bar',
    'Access-Control-Request-Method'  => 'POST',
    'Content-Type'                   => 'text/plain',
    'Origin'                         => 'http://foo.example'
  }
)->header_is('Access-Control-Allow-Origin' => 'http://foo.example')
  ->header_is('Access-Control-Allow-Headers' => 'X-Foo, X-Bar')
  ->header_is('Access-Control-Allow-Methods' => 'POST')
  ->header_is('Access-Control-Max-Age'       => 3600)->content_is('');

$t->get_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://bar.example'})
  ->status_is(400)->json_is('/errors/0/message', 'Invalid CORS request.');
$t->get_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://foo.example'})
  ->status_is(200)->header_is('Access-Control-Allow-Origin' => 'http://foo.example')
  ->json_is('/cors', 'cors_exchange')->json_is('/origin', 'http://foo.example');

done_testing;

sub cors_exchange {
  return cors_simple(@_);
}

sub cors_preflighted {
  my ($c, $args) = @_;

  # Need to do the following to allow regular OPTIONS request
  # Note that $args->{type} will be "preflighted" or "simple" in case of a
  # CORS request.
  return $c->stash(openapi_allow_options_request => 1) unless $args->{type};

  # Check the "Origin" header
  return unless $args->{origin} eq 'http://foo.example';

  # Check the Access-Control-Request-Headers header
  return if $args->{headers} =~ /X-No-Can-Do/;

  # Check the Access-Control-Request-Method header
  return if $args->{method} eq 'delete';

  # Set required Preflighted response header
  $c->res->headers->header('Access-Control-Allow-Origin' => $args->{origin});

  # Set Preflighted response headers, instead of using the default
  $c->res->headers->header('Access-Control-Allow-Headers' => 'X-Whatever, X-Something');
  $c->res->headers->header('Access-Control-Allow-Methods' => 'POST, GET, OPTIONS');
  $c->res->headers->header('Access-Control-Max-Age'       => 86400);
}

sub cors_simple {
  my ($c, $args) = @_;

  if ($args->{origin} eq 'http://foo.example') {
    $c->stash(origin => $args->{origin});
    $c->res->headers->header('Access-Control-Allow-Origin' => $args->{origin});
  }
}

__DATA__
@@ cors.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test cors response" },
  "basePath" : "/api",
  "paths" : {
    "/user" : {
      "get" : {
        "operationId" : "User",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": {
            "description": "Cors response.",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
