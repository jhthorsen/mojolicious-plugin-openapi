use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
plugin OpenAPI => {url => 'data://main/todo.json'};
app->routes->namespaces(['MyApp::Controller']);
my $t = Test::Mojo->new;
$t->get_ok('/api/todo' => json => {})->status_is(404);
$t->post_ok('/api/todo' => json => ['invalid'])->status_is(501)
  ->json_is('/errors/0/message', 'Not implemented.');

define_controller();
$t->get_ok('/api/todo' => json => {})->status_is(404);
$t->post_ok('/api/todo' => json => {})->status_is(200)->json_is('/todo', 42);

done_testing;

sub define_controller {
  eval <<'HERE' or die;
  package MyApp::Controller::Dummy;
  use Mojo::Base 'Mojolicious::Controller';
  sub todo {
    my $c = shift;
    return if $c->openapi->invalid_input;
    return $c->reply->openapi(200, {todo => 42});
  }
  1;
HERE
}

package main;
__DATA__
@@ todo.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test todo response" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/todo" : {
      "post" : {
        "x-mojo-to": "dummy#todo",
        "operationId" : "Auto",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": {
            "description": "response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
