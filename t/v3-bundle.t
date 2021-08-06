use Mojo::Base -strict;
use Mojo::File 'path';
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->res->headers->header('x-next' => $c->param('limit') // 0);
  $c->render(openapi => $c->param('limit') ? [] : {});
  },
  'listPets';

plugin OpenAPI => {url => 'data:///spec.json'};

my $t = Test::Mojo->new;

$t->get_ok('/v1.json')->status_is(200)->json_is('/openapi' => '3.0.0')
  ->json_is('/info/title' => 'Swagger Petstore')->json_like('/servers/0/url' => qr{^http://.*/v1$})
  ->json_is('/security/0/pass1', [])->json_is('/components/securitySchemes/apiKey/type' => 'http')
  ->json_is('/components/schemas/DefaultResponse/properties/errors/items/properties/message/type',
  'string')->json_is('/components/schemas/Pet/required/0', 'id')
  ->json_is('/components/schemas/Pets/type',                       'array')
  ->json_is('/paths/~1pets~1{petId}/get/parameters/0/schema/type', 'string')
  ->json_is('/paths/~1pets~1{petId}/get/responses/500/content/application~1json/schema/$ref',
  '#/components/schemas/DefaultResponse')
  ->json_hasnt('/paths/~1pets~1{petId}/get/parameters/0/type')->json_hasnt('/basePath');

done_testing;

__DATA__
@@ spec.json
{
  "openapi": "3.0.0",
  "info": {
    "license": {
      "name": "MIT"
    },
    "title": "Swagger Petstore",
    "version": "1.0.0"
  },
  "servers": [
    { "url": "http://petstore.swagger.io/v1" }
  ],
  "security": [{"pass1": []}],
  "paths": {
    "/pets/{petId}": {
      "get": {
        "operationId": "showPetById",
        "tags": [ "pets" ],
        "summary": "Info for a specific pet",
        "parameters": [
          {
            "description": "The id of the pet to retrieve",
            "in": "path",
            "name": "petId",
            "required": true,
            "schema": { "type": "string" }
          },
          {
            "description": "Indicates if the age is wanted in the response object",
            "in": "query",
            "name": "wantAge",
            "schema": {
              "type": "boolean"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Expected response to a valid request",
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/Pet" }
              },
              "application/xml": {
                "schema": { "$ref": "#/components/schemas/Pet" }
              }
            }
          }
        }
      }
    },
    "/pets": {
      "get": {
        "operationId": "listPets",
        "summary": "List all pets",
        "tags": [ "pets" ],
        "parameters": [
          {
            "description": "How many items to return at one time (max 100)",
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": { "type": "integer", "format": "int32" }
          }
        ],
        "responses": {
          "200": {
            "description": "An paged array of pets",
            "headers": {
              "x-next": {
                "schema": { "type": "string" },
                "description": "A link to the next page of responses"
              }
            },
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/Pets" }
              },
              "application/xml": {
                "schema": { "$ref": "#/components/schemas/Pets" }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "securitySchemes": {
      "apiKey": {
        "type": "http",
        "scheme": "basic"
      }
    },
    "schemas": {
      "Pets": {
        "type": "array",
        "items": { "$ref": "#/components/schemas/Pet" }
      },
      "Pet": {
        "required": [ "id", "name" ],
        "properties": {
          "tag": { "type": "string" },
          "id": { "type": "integer", "format": "int64" },
          "name": { "type": "string" },
          "age": { "type": "integer" }
        }
      }
    }
  }
}
