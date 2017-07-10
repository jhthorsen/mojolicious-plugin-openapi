use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/global' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 'checks disabled'});
  },
  'global';

plugin OpenAPI => {url => 'data://main/sec.json'};

my $t = Test::Mojo->new;
$t->post_ok('/api/global' => json => {})->status_is(200)->json_is('/ok' => 'checks disabled');

done_testing;

__DATA__
@@ sec.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Pets" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "securityDefinitions": {
    "fail1": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "fail1"
    }
  },
  "security": [{"fail1": []}],
  "paths": {
    "/global": {
      "post": {
        "x-mojo-name": "global",
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    }
  },
  "definitions": {
    "Error": {
      "type": "object",
      "properties": {
        "errors": {
          "type": "array",
          "items": {
            "required": ["message"],
            "properties": {
              "message": { "type": "string", "description": "Human readable description of the error" },
              "path": { "type": "string", "description": "JSON pointer to the input data where the error occur" }
            }
          }
        }
      }
    }
  }
}
