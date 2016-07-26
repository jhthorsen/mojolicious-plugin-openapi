use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

{
  use Mojolicious::Lite;
  app->routes->namespaces(['MyApp::Controller']);
  get '/die' => sub { die 'Oh noes!' }, 'Die';
  plugin OpenAPI => {url => 'data://main/hook.json'};
}

my $t = Test::Mojo->new;

# Exception
$t->get_ok('/api/die')->status_is(500)->json_is('/errors/0/message', 'Internal server error.');

# Not implemented
$t->get_ok('/api/todo' => json => {})->status_is(404)->json_is('/errors/0/message', 'Not found.');
$t->post_ok('/api/todo' => json => ['invalid'])->status_is(501)
  ->json_is('/errors/0/message', 'Not implemented.');

# Implemented, but still Not found
define_controller();
$t->get_ok('/api/todo' => json => {})->status_is(404)->json_is('/errors/0/message', 'Not found.');
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
@@ hook.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test before_render hook" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/die" : {
      "get" : {
        "operationId" : "Die",
        "responses" : {
          "200": {
            "description": "response",
            "schema": { "type": "object" }
          }
        }
      }
    },
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
