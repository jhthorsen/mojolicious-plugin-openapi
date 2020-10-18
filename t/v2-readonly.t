use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/user' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'createUser';


plugin OpenAPI => {url => 'data://main/readonly.json'};

my $t = Test::Mojo->new;

$t->post_ok('/api/user', json => {age => 42})->status_is(400)
  ->json_is('/errors/0', {message => 'Read-only.', path => '/body/age'});

$t->post_ok('/api/user', json => {something => 'else'})->status_is(500)
  ->json_is('/errors/0', {message => 'Missing property.', path => '/body/age'});

done_testing;

__DATA__
@@ readonly.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test readonly" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/user" : {
      "post" : {
        "operationId" : "createUser",
        "parameters" : [
          {
            "name":"body",
            "in":"body",
            "schema": { "$ref": "#/definitions/User" }
          }
        ],
        "responses" : {
          "200": { "description": "ok", "schema": { "$ref": "#/definitions/User" } }
        }
      }
    }
  },
  "definitions": {
    "User": {
      "type" : "object",
      "required": ["age"],
      "properties": {
        "age": {
          "type": "integer",
          "readOnly": true
        }
      }
    }
  }
}
