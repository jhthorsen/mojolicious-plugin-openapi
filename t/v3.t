use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/pets/:petId' => sub {
  my $c = shift->openapi->valid_input or return;
  my $input = $c->validation->output;
  my $output = {id => $input->{petId}, name => 'Cow'};
  $output->{age} = 6 if $input->{wantAge};
  $c->render(openapi => $output);
  },
  'showPetById';

get '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->param('limit') ? [] : {});
  },
  'listPets';

post '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => '', status => 201);
  },
  'createPets';

plugin OpenAPI => {
  url      => 'data:///petstore.json',
  schema   => 'v3',
  renderer => sub {
    my ($c, $data) = @_;
    my $ct = $c->stash('openapi_negotiated_content_type') || 'application/json';
    return '' if $c->stash('status') == 201;
    $c->res->headers->content_type($ct);
    return '<xml></xml>' if $ct =~ m!^application/xml!;
    return Mojo::JSON::encode_json($data);
  }
};

my $t = Test::Mojo->new;
$t->get_ok('/v1/pets?limit=invalid', {Accept => 'application/json'})->status_is(400)
  ->json_is('/errors/0/message', 'Expected integer - got string.');

# TODO: Should probably be 400
$t->get_ok('/v1/pets?limit=10', {Accept => 'not/supported'})->status_is(500)
  ->json_is('/errors/0/message', 'No responses rules defined for Accept not/supported.');

$t->get_ok('/v1/pets?limit=0', {Accept => 'application/json'})->status_is(500)
  ->json_is('/errors/0/message', 'Expected array - got object.');

$t->get_ok('/v1/pets?limit=10', {Accept => 'application/json'})->status_is(200)
  ->header_like('Content-Type' => qr{^application/json})->content_is('[]');
$t->get_ok('/v1/pets?limit=10', {Accept => 'application/*'})->status_is(200)
  ->header_like('Content-Type' => qr{^application/json})->content_is('[]');
$t->get_ok('/v1/pets?limit=10', {Accept => 'text/html,application/xml;q=0.9,*/*;q=0.8'})
  ->status_is(200)->header_like('Content-Type' => qr{^application/xml})->content_is('<xml></xml>');
$t->get_ok('/v1/pets?limit=10', {Accept => 'text/html,*/*;q=0.8'})->status_is(200)
  ->header_like('Content-Type' => qr{^application/json})->content_is('[]');

$t->get_ok('/v1/pets?limit=10', {Accept => 'application/json'})->status_is(200)->content_is('[]');

$t->post_ok('/v1/pets', {Accept => 'application/json', Cookie => 'debug=foo'})->status_is(400)
  ->json_is('/errors/0/message', 'Invalid Content-Type.')
  ->json_is('/errors/1/message', 'Expected integer - got string.');

$t->post_ok('/v1/pets', {Cookie => 'debug=1'}, json => {id => 1, name => 'Supercow'})
  ->status_is(201)->content_is('');

$t->post_ok('/v1/pets', form => {id => 1, name => 'Supercow'})->status_is(201)->content_is('');

$t->get_ok('/v1/pets/23?wantAge=yes', {Accept => 'application/json'})->status_is(400)
  ->json_is('/errors/0/message', 'Expected boolean - got string.');

$t->get_ok('/v1/pets/23?wantAge=true', {Accept => 'application/json'})->status_is(200)
  ->json_is('/id', 23)
  ->json_is('/age', 6);

$t->get_ok('/v1/pets/23?wantAge=false', {Accept => 'application/json'})->status_is(200)
  ->json_is('/id', 23)
  ->json_is('/age', undef);

done_testing;

__DATA__
@@ petstore.json
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
          "default": {
            "description": "unexpected error",
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/Error" }
              },
              "application/xml": {
                "schema": { "$ref": "#/components/schemas/Error" }
              }
            }
          },
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
          },
          "default": {
            "description": "unexpected error",
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/Error" }
              },
              "application/xml": {
                "schema": { "$ref": "#/components/schemas/Error" }
              }
            }
          }
        }
      },
      "post": {
        "operationId": "createPets",
        "summary": "Create a pet",
        "tags": [ "pets" ],
        "parameters": [
          {
            "description": "Turn on/off debug",
            "in": "cookie",
            "name": "debug",
            "schema": {
              "type": "integer",
              "enum": [0, 1]
            }
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": { "$ref": "#/components/schemas/Pet" }
            },
            "application/x-www-form-urlencoded": {
              "schema": { "$ref": "#/components/schemas/Pet" }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Null response",
            "content": {
              "*/*": {
                "schema": { "type": "string" }
              }
            }
          },
          "default": {
            "description": "unexpected error",
            "content": {
              "*/*": {
                "schema": { "$ref": "#/components/schemas/Error" }
              }
            }
          }
        }
      }
    }
  },
  "components": {
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
      },
      "Error": {
        "required": [ "code", "message" ],
        "properties": {
          "code": { "format": "int32", "type": "integer" },
          "message": { "type": "string" }
        }
      }
    }
  }
}
