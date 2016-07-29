use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
app->routes->namespaces(['MyApp::Controller']);
get '/whatever' => sub { die 'Oh noes!' }, 'Whatever';
plugin OpenAPI => {url => 'data://main/lite.json'};
my $t = Test::Mojo->new;
ok $t->app->routes->find('Whatever'), 'Whatever is defined';

$t = Test::Mojo->new(Mojolicious->new);
$t->app->routes->namespaces(['MyApp::Controller']);
$t->app->plugin(OpenAPI => {spec_route_name => 'my_api', url => 'data://main/full.json'});
ok $t->app->routes->find('my_api'),          'my_api is defined';
ok $t->app->routes->find('my_api.Whatever'), 'my_api.Whatever is defined';

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
