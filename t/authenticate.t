use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
my $auth = app->routes->under('/api')->to(
  cb => sub {
    my $c    = shift;
    my $spec = $c->openapi->spec;

    # skip authentication
    return 1 if $spec->{'x-no-auth'};

    # really bad authentication
    return 1 if $c->param('unsafe_token');

    # not authenticated
    $c->render(openapi => {errors => [{message => 'not logged in'}]}, status => 401);
    return;
  }
);

get
  '/login' => sub { shift->render(openapi => {id => 123}, status => 200) },
  'login';

get
  '/protected' => sub { shift->render(openapi => {protected => 'secret'}, status => 200) },
  'protected';

plugin OpenAPI => {route => $auth, url => 'data://main/api.json'};

my $t = Test::Mojo->new;

$t->get_ok('/api/login')->status_is(200)->json_is('/id', 123);
$t->get_ok('/api')->status_is(401)->json_is('/errors/0/message', 'not logged in');
$t->get_ok('/api/protected')->status_is(401)->json_is('/errors/0/message', 'not logged in');
$t->get_ok('/api/protected?unsafe_token=1')->status_is(200)->json_is('/protected', 'secret');

done_testing;

__DATA__
@@ api.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Test protected api" },
  "basePath": "/api",
  "paths": {
    "/login": {
      "get": {
        "x-no-auth": true,
        "x-mojo-name": "login",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    },
    "/protected": {
      "get": {
        "x-mojo-name": "protected",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
