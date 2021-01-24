use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

our $cors_callback = 'main::cors_exchange';

use Mojolicious::Lite;
get '/user' => sub {
  my $c = shift->openapi->cors_exchange($cors_callback)->openapi->valid_input or return;
  $c->render(json => {cors => 'cors_exchange', origin => $c->stash('origin')});
  },
  'getUser';

put '/user' => sub {
  my $c = shift->openapi->cors_exchange->openapi->valid_input or return;
  $c->render(json => {created => time});
  },
  'addUser';

put '/headers' => sub {
  my $c = shift->openapi->valid_input or return;

  $c->res->headers->access_control_allow_origin($c->req->headers->origin)
    if $c->req->headers->origin;

  $c->render(json => {h => 42});
  },
  'headerValidation';

plugin OpenAPI => {url => 'data://main/cors.json', add_preflighted_routes => 1};

my $t = Test::Mojo->new;

note 'Simple';
$t->get_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://bar.example'})
  ->status_is(400)->json_is('/errors/0/message', 'Invalid Origin header.');

$t->get_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://foo.example'})
  ->status_is(200)->header_is('Access-Control-Allow-Origin' => 'http://foo.example')
  ->json_is('/cors', 'cors_exchange')->json_is('/origin', 'http://foo.example');

$t->get_ok('/api/user', {Origin => 'http://foo.example'})->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => 'http://foo.example');

note 'Preflighted';
$t->options_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://bar.example'})
  ->status_is(400)->json_is('/errors/0/message', 'Invalid Origin header.');

$t->options_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://foo.example'})
  ->status_is(200)->header_is('Access-Control-Allow-Origin' => 'http://foo.example')
  ->header_is('Access-Control-Allow-Headers' => 'X-Whatever, X-Something')
  ->header_is('Access-Control-Allow-Methods' => 'POST, GET, OPTIONS')
  ->header_is('Access-Control-Max-Age'       => 86400)->content_is('');

$t->options_ok(
  '/api/user',
  {
    'Access-Control-Request-Headers' => 'X-Foo, X-Bar',
    'Access-Control-Request-Method'  => 'GET',
    'Content-Type'                   => 'text/plain',
    'Origin'                         => 'http://foo.example'
  }
)->status_is(200)->header_is('Access-Control-Allow-Origin' => 'http://foo.example')
  ->header_is('Access-Control-Allow-Headers' => 'X-Foo, X-Bar')
  ->header_is('Access-Control-Allow-Methods' => 'GET, PUT')
  ->header_is('Access-Control-Max-Age'       => 1800)->content_is('');

note 'Default cors exchange';
$cors_callback = undef;
$t->app->defaults(openapi_cors_allowed_origins => [qr{bar\.example}]);
$t->app->defaults(openapi_cors_default_max_age => 42);
$t->options_ok('/api/user',
  {'Origin' => 'http://bar.example', 'Access-Control-Request-Method' => 'GET'})->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => 'http://bar.example')
  ->header_is('Access-Control-Max-Age'      => 42)->content_is('');

note 'Actual request';
$t->options_ok('/api/user')->status_is(400)
  ->json_is('/errors/0/message', 'OPTIONS is only for preflighted CORS requests.');

$t->put_ok('/api/user', {'Origin' => 'http://bar.example'})->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => 'http://bar.example')->json_has('/created');

$t->get_ok('/api/user')->status_is(200)->header_is('Access-Control-Allow-Origin' => undef)
  ->json_is('/origin', undef);

$t->put_ok('/api/user')->status_is(200)->header_is('Access-Control-Allow-Origin' => undef)
  ->json_has('/created');

$t->put_ok('/api/headers')->status_is(200)->header_is('Access-Control-Allow-Origin' => undef)
  ->json_is('/h' => 42);

note 'Using the spec';
$t->options_ok('/api/headers')->status_is(400)->json_is('/errors/0/path' => '/Origin');
$t->put_ok('/api/headers', {'Origin' => 'https://foo.example'})->status_is(400)
  ->json_is('/errors/0/path' => '/Origin');

$t->options_ok('/api/headers', {'Origin' => 'http://foo.example'})->status_is(400)
  ->json_is('/errors/0/path' => '/Origin');

$t->options_ok('/api/headers', {'Origin' => 'http://bar.example'})->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => 'http://bar.example')
  ->header_is('Access-Control-Max-Age'      => 42)->content_is('');

$t->put_ok('/api/headers', {'Origin' => 'https://bar.example'})->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => 'https://bar.example')->json_is('/h' => 42);

done_testing;

sub cors_exchange {
  my $c       = shift;
  my $req_h   = $c->req->headers;
  my $headers = $req_h->header('Access-Control-Request-Headers');
  my $method  = $req_h->header('Access-Control-Request-Methods');
  my $origin  = $req_h->header('Origin');

  return '/Origin' unless $origin eq 'http://foo.example';
  return '/X-No-Can-Do'                   if $headers and $headers =~ /X-No-Can-Do/;
  return '/Access-Control-Request-Method' if $method  and $method eq 'DELETE';

  $c->stash(origin => $origin);

  # Set required Preflighted response header
  $c->res->headers->header('Access-Control-Allow-Origin' => $origin);

  # Set Preflighted response headers, instead of using the default
  $c->res->headers->header('Access-Control-Allow-Headers' => 'X-Whatever, X-Something')
    unless $c->req->headers->header('Access-Control-Request-Headers');
  $c->res->headers->header('Access-Control-Allow-Methods' => 'POST, GET, OPTIONS')
    unless $c->req->headers->header('Access-Control-Request-Method');
  $c->res->headers->header('Access-Control-Max-Age' => 86400)
    unless $c->req->headers->header('Access-Control-Request-Method');

  return undef;
}

__DATA__
@@ cors.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Test cors response" },
  "basePath": "/api",
  "paths": {
    "/user": {
      "get": {
        "operationId": "getUser",
        "responses": {
          "200": { "description": "Get user", "schema": { "type": "object" } }
        }
      },
      "put": {
        "operationId": "addUser",
        "responses": {
          "200": { "description": "Create user", "schema": { "type": "object" } }
        }
      }
    },
    "/headers": {
      "parameters": [
        { "in": "header", "name": "Origin", "type": "string", "pattern": "https?://bar.example" }
      ],
      "options": {
        "x-mojo-to": "#openapi_plugin_cors_exchange",
        "responses": {
          "200": { "description": "Cors exchange", "schema": { "type": "object" } }
        }
      },
      "put": {
        "operationId": "headerValidation",
        "responses": {
          "200": { "description": "Cors put", "schema": { "type": "object" } }
        }
      }
    }
  }
}
