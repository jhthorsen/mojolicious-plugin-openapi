use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

package Test::Controller::Echo;
use Mojo::Base 'Mojolicious::Controller';

sub any {
  my $c = shift->openapi->valid_input or return;

  my $name
    = $c->stash('name')
    ? {param      => $c->param('name'), stash => $c->stash('name')}
    : {controller => $c->param('name'), form  => $c->req->body_params->param('name')};

  $c->render(
    openapi => {
      days       => {controller => $c->param('days'), url => $c->req->query_params->param('days')},
      name       => $name,
      x_foo      => {header => $c->req->headers->header('X-Foo')},
      validation => $c->validation->output,
    }
  );
}

package main;
use Mojolicious::Lite;
get '/echo' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {bool => $c->param('bool')});
  },
  'echo';

get '/echo/:whatever' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {this_stack => $c->match->stack->[-1], whatever => $c->param('whatever')});
  },
  'whatever';

get '/param-has-ref' => sub {
  my $c      = shift->openapi->valid_input or return;
  my $params = $c->validation->output;
  $c->render(status => 200, openapi => $params->{pcversion});
  },
  'ParamsHasRef';

plugin OpenAPI => {url => 'data://main/def.json'};

my $t = Test::Mojo->new;
$t->get_ok('/api/echo?bool=false')->status_is(200)->json_is('/bool' => Mojo::JSON->false);
$t->get_ok('/api/echo?bool=true')->status_is(200)->json_is('/bool' => Mojo::JSON->true);
$t->get_ok('/api/echo')->status_is(200)->json_is('/bool' => Mojo::JSON->true);

$t->get_ok('/api/echo/something')->status_is(200)->json_is('/this_stack/whatever' => 'something')
  ->json_is('/whatever' => 'something');

$t->get_ok('/api/param-has-ref?x=42')->status_is(200)->content_is('"10.1.0"');

$t->post_ok('/api/echo-controller')->status_is(200)
  ->json_is('/days' => {controller => 42, url => 42})
  ->json_is('/name',  {controller => 'batman', form => 'batman'})
  ->json_is('/x_foo', {header     => 'yikes'})
  ->json_is('/validation',
  {days => 42, name => 'batman', 'X-Foo' => 'yikes', enumParam => '10.1.0'});

$t->get_ok('/api/echo-controller/batman')->status_is(200)
  ->json_is('/days' => {controller => 42, url => 42})
  ->json_is('/name', {param => 'batman', stash => 'batman'});
ok !$t->tx->res->json->{x_foo}{header}, 'x_foo header is not set';

done_testing;

__DATA__
@@ def.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Pets" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "parameters": {
    "PCVersion": {
      "name": "pcversion",
      "in": "query",
      "type": "string",
      "enum": [ "9.6.1", "10.1.0" ],
      "default": "10.1.0",
      "description": "version of commands which will run on backend"
    }
  },
  "paths": {
    "/echo/{whatever}": {
      "get": {
        "x-mojo-name": "whatever",
        "parameters": [
          { "in": "path", "name": "whatever", "type": "string", "required": true }
        ],
        "responses": {
          "200": {
            "description": "Echo response",
            "schema": { "type": "object" }
          }
        }
      }
    },
    "/echo": {
      "get": {
        "x-mojo-name": "echo",
        "parameters": [
          { "in": "query", "name": "bool", "type": "boolean", "default": true }
        ],
        "responses": {
          "200": {
            "description": "Echo response",
            "schema": { "type": "object" }
          }
        }
      }
    },
    "/echo-controller": {
      "post": {
        "x-mojo-to": ["namespace", "Test::Controller", "controller", "echo", "action", "any"],
        "parameters": [
          { "in": "query", "name": "days", "type": "number", "default": 42 },
          { "in": "formData", "name": "name", "type": "string", "default": "batman" },
          {
            "in": "query", "name": "enumParam",
            "type": "string", "default": "10.1.0",
            "enum": [ "9.6.1", "10.1.0" ]
          },
          { "in": "header", "name": "X-Foo", "type": "string", "default": "yikes" }
        ],
        "responses": {
          "200": {
            "description": "Echo response",
            "schema": { "type": "object" }
          }
        }
      }
    },
    "/echo-controller/{name}": {
      "get": {
        "x-mojo-to": ["namespace", "Test::Controller", "controller", "echo", "action", "any"],
        "parameters": [
          { "in": "path", "name": "name", "type": "string", "required": true },
          { "in": "query", "name": "days", "type": "number", "default": 42 }
        ],
        "responses": {
          "200": {
            "description": "Echo response",
            "schema": { "type": "object" }
          }
        }
      }
    },
    "/param-has-ref": {
      "get": {
        "operationId": "ParamsHasRef",
        "parameters": [
          { "$ref": "#/parameters/PCVersion" },
          { "name": "x", "in": "query", "type": "string", "description": "x" }
        ],
        "responses": {
          "200": {
            "description": "thing",
            "schema": { "type": "string" }
          }
        }
      }
    }
  }
}
