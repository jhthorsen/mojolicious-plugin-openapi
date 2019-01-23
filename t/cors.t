use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

our $cors_callback = 'main::cors_exchange';
our $cors_method   = 'cors_exchange';

use Mojolicious::Lite;
get '/user' => sub {
  my $c = shift->openapi->$cors_method($cors_callback)->openapi->valid_input or return;
  $c->render(json => {cors => $cors_method, origin => $c->stash('origin')});
  },
  'GetUser';

put '/user' => sub {
  my $c = shift->openapi->cors_exchange->openapi->valid_input or return;
  $c->render(json => {created => time});
  },
  'AddUser';

plugin OpenAPI => {url => 'data://main/cors.json', add_preflighted_routes => 1};

my $t = Test::Mojo->new;

for (qw(cors_simple cors_exchange)) {
  note 'Simple';
  local $cors_method = $_;
  $t->get_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://bar.example'})
    ->status_is(400)->json_is('/errors/0/message', 'Invalid Origin header.');

  $t->get_ok('/api/user', {'Content-Type' => 'text/plain', Origin => 'http://foo.example'})
    ->status_is(200)->header_is('Access-Control-Allow-Origin' => 'http://foo.example')
    ->json_is('/cors', $cors_method)->json_is('/origin', 'http://foo.example');

  $t->get_ok('/api/user', {Origin => 'http://foo.example'})->status_is(200)
    ->header_is('Access-Control-Allow-Origin' => 'http://foo.example');
}

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
$t->app->defaults(openapi_cors_allow_origins   => [qr{bar\.example}]);
$t->app->defaults(openapi_cors_default_max_age => 42);
$t->options_ok('/api/user', {'Origin' => 'http://bar.example'})->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => 'http://bar.example')
  ->header_is('Access-Control-Max-Age'      => 42)->content_is('');

note 'Actual request';
$t->options_ok('/api/user')->status_is(400)
  ->json_is('/errors/0/message', 'OPTIONS is only for preflighted CORS requests.');

$t->put_ok('/api/user', {'Origin' => 'http://bar.example'})->status_is(200)
  ->header_is('Access-Control-Allow-Origin' => 'http://bar.example')->json_has('/created');

done_testing;

sub cors_exchange {
  my ($c, $params) = @_;

  return '/Origin' unless $params->{origin} eq 'http://foo.example';
  return '/X-No-Can-Do' if $params->{headers} and $params->{headers} =~ /X-No-Can-Do/;
  return '/Access-Control-Request-Method' if $params->{method} and $params->{method} eq 'DELETE';

  $c->stash(origin => $params->{origin});

  # Set required Preflighted response header
  $c->res->headers->header('Access-Control-Allow-Origin' => $params->{origin});

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
        "operationId": "GetUser",
        "responses": {
          "200": { "description": "Whatever", "schema": { "type": "object" } }
        }
      },
      "put": {
        "operationId": "AddUser",
        "responses": {
          "200": { "description": "Whatever", "schema": { "type": "object" } }
        }
      }
    }
  }
}
