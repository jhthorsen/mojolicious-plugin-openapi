use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
app->routes->namespaces(['MyApp::Controller']);
get '/whatever' => sub { die 'Oh noes!' }, 'Whatever';
plugin OpenAPI => {url => 'data://main/lite.json'};
my $t = Test::Mojo->new;
my $r;
ok $t->app->routes->find('Whatever'), 'Whatever is defined';

$t = Test::Mojo->new(Mojolicious->new);
$r = $t->app->routes->namespaces(['MyApp::Controller']);
$t->app->plugin(OpenAPI => {spec_route_name => 'my_api', url => 'data://main/full.json'});
ok $r->lookup('my_api'), 'my_api is defined';
$r = $r->lookup('my_api')->parent;
ok $r->find('my_api.Whatever'), 'my_api.Whatever is defined';

{
  local $TODO = 'This default route name might change in the future';
  ok $r->find('my_api.whatever_options'), 'my_api.whatever_options is defined';
}

eval { plugin OpenAPI => {url => 'data://main/unique-route.json'} };
like $@, qr{Route name "xyz" is not unique}, 'unique route names';

eval { plugin OpenAPI => {url => 'data://main/unique-op.json'} };
like $@, qr{operationId "xyz" is not unique}, 'unique operationId';

done_testing;

sub define_controller {
  eval <<'HERE' or die;
  package MyApp::Controller::Dummy;
  use Mojo::Base 'Mojolicious::Controller';
  sub todo {}
  1;
HERE
}

package main;
__DATA__
@@ full.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test route names" },
  "basePath" : "/api",
  "paths" : {
    "/whatever" : {
      "get" : {
        "operationId" : "Whatever",
        "responses" : { "200": { "description": "response", "schema": { "type": "object" } } }
      }
    }
  }
}
@@ lite.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test route names" },
  "basePath" : "/api",
  "paths" : {
    "/whatever" : {
      "get" : {
        "operationId" : "Whatever",
        "responses" : { "200": { "description": "response", "schema": { "type": "object" } } }
      }
    }
  }
}
@@ unique-op.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test unique operationId" },
  "basePath" : "/api",
  "paths" : {
    "/r" : {
      "get" : {
        "operationId": "xyz",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      },
      "post" : {
        "operationId": "xyz",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
@@ unique-route.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test unique route names" },
  "basePath" : "/api",
  "paths" : {
    "/r" : {
      "get" : {
        "x-mojo-name": "xyz",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      },
      "post" : {
        "x-mojo-name": "xyz",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
