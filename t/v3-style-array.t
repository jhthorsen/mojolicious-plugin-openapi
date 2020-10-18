use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPets';

get '/pets/:id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPetsById';

get '/petsByLabelId#id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPetsByLabelId';

get '/petsByExplodedLabelId#id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPetsByExplodedLabelId';

get '/petsByMatrixId#id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPetsByMatrixId';

get '/petsByExplodedMatrixId#id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPetsByExplodedMatrixId';


plugin OpenAPI => {url => 'data:///parameters.json'};

my $t = Test::Mojo->new;

# Expected array - got null
$t->get_ok('/api/pets')->status_is(400)->json_is('/errors/0/path', '/ri');

# Expected integer - got number.
$t->get_ok('/api/pets?ri=1.3')->status_is(400)->json_is('/errors/0/path', '/ri/0');

# Not enough items: 1\/2
$t->get_ok('/api/pets?ri=3&ml=5')->status_is(400)->json_is('/errors/0/path', '/ml');

# Valid, in path
$t->get_ok('/api/pets/10,11,12')->status_is(200)->json_is('/id', [qw(10 11 12)]);
$t->get_ok('/api/pets/10')->status_is(200)->content_like(qr{"id":\[10\]});
$t->get_ok('/api/petsByLabelId.3,4,5')->status_is(200)->json_is('/id',         [qw(3 4 5)]);
$t->get_ok('/api/petsByLabelId.5')->status_is(200)->json_is('/id',             [5]);
$t->get_ok('/api/petsByExplodedLabelId.3.4.5')->status_is(200)->json_is('/id', [qw(3 4 5)]);
$t->get_ok('/api/petsByExplodedLabelId.5')->status_is(200)->json_is('/id',     [5]);
$t->get_ok('/api/petsByMatrixId;id=3,4,5')->status_is(200)->json_is('/id',     [qw(3 4 5)]);
$t->get_ok('/api/petsByMatrixId;id=5')->status_is(200)->json_is('/id',         [5]);
$t->get_ok('/api/petsByExplodedMatrixId;id=3;id=4;id=5')->status_is(200)
  ->json_is('/id', [qw(3 4 5)]);
$t->get_ok('/api/petsByExplodedMatrixId;id=5')->status_is(200)->json_is('/id', [5]);

# Valid, in query
$t->get_ok('/api/pets?ri=3&ml=4&ml=2&no=5')->status_is(200)->json_is('/ri', [3])
  ->content_like(qr{"ml":\["4","2"\]})->content_like(qr{"no":\[5\]});
$t->get_ok('/api/pets?ri=3&no=5,6&sp=7 8 9&pi=10|11')->status_is(200)->json_is('/no', [5, 6])
  ->json_is('/sp', [7, 8, 9])->json_is('/pi', [10, 11]);

done_testing;

__DATA__
@@ parameters.json
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
    {
      "url": "/api"
    }
  ],
  "paths": {
    "/pets/{id}": {
      "get": {
        "operationId": "getPetsById",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "style": "simple",
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              },
              "minItems": 1
            }
          }
        ],
        "responses": {
          "200": {
            "description": "pet response",
            "content": {
              "*/*": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    },
    "/petsByLabelId{id}": {
      "get": {
        "operationId": "getPetsByLabelId",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "style": "label",
            "explode": false,
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              },
              "minItems": 1
            }
          }
        ],
        "responses": {
          "200": {
            "description": "pet response",
            "content": {
              "*/*": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    },
    "/petsByExplodedLabelId{id}": {
      "get": {
        "operationId": "getPetsByExplodedLabelId",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "style": "label",
            "explode": true,
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              },
              "minItems": 1
            }
          }
        ],
        "responses": {
          "200": {
            "description": "pet response",
            "content": {
              "*/*": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    },
    "/petsByMatrixId{id}": {
      "get": {
        "operationId": "getPetsByMatrixId",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "style": "matrix",
            "explode": false,
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              },
              "minItems": 1
            }
          }
        ],
        "responses": {
          "200": {
            "description": "pet response",
            "content": {
              "*/*": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    },
    "/petsByExplodedMatrixId{id}": {
      "get": {
        "operationId": "getPetsByExplodedMatrixId",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "style": "matrix",
            "explode": true,
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              },
              "minItems": 1
            }
          }
        ],
        "responses": {
          "200": {
            "description": "pet response",
            "content": {
              "*/*": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    },
    "/pets": {
      "get": {
        "operationId": "getPets",
        "parameters": [
          {
            "name": "no",
            "in": "query",
            "style": "form",
            "explode": false,
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              },
              "minItems": 1
            }
          },
          {
            "name": "ml",
            "in": "query",
            "style": "form",
            "explode": true,
            "schema": {
              "type": "array",
              "items": {
                "type": "string"
              },
              "minItems": 2
            }
          },
          {
            "name": "ri",
            "in": "query",
            "required": true,
            "style": "form",
            "explode": true,
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              },
              "minItems": 1
            }
          },
          {
            "name": "sp",
            "in": "query",
            "style": "spaceDelimited",
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              }
            }
          },
          {
            "name": "pi",
            "in": "query",
            "style": "pipeDelimited",
            "schema": {
              "type": "array",
              "items": {
                "type": "integer"
              }
            }
          }
        ],
        "responses": {
          "200": {
            "description": "pet response",
            "content": {
              "*/*": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    }
  }
}
