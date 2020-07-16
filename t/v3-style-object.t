use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPets';

get '/petsBySimpleId/:id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPetsBySimpleId';

get '/petsByExplodedSimpleId/:id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPetsByExplodedSimpleId';

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

plugin OpenAPI => {
  url => 'data:///parameters.json',
  schema => 'v3',
};

my $t = Test::Mojo->new;

# style: deepObject
$t->get_ok('/api/pets')->status_is(200)
  ->json_is('/do', undef);
$t->get_ok('/api/pets?do[name]=birdy&do[birth-date][gte]=1970-01-01&do[numbers][0]=5')->status_is(200)
  ->json_is('/do', {name => 'birdy', 'birth-date' => {gte => '1970-01-01'}, numbers => [5]});
$t->get_ok('/api/pets?do[numbers][0]=5&do[numbers][1]=10')->status_is(200)
  ->json_is('/do', {numbers => [5, 10]});
$t->get_ok('/api/pets?do[numbers][]=5&do[numbers][]=10')->status_is(200)
  ->json_is('/do', {numbers => [5, 10]});
$t->get_ok('/api/pets?do[numbers]=5&do[numbers]=10')->status_is(200)
  ->json_is('/do', {numbers => [5, 10]});

# style: form, explode: false
$t->get_ok('/api/pets')->status_is(200)
  ->json_is('/ff', undef);
$t->get_ok('/api/pets?ff=')->status_is(200)
  ->json_is('/ff', {});
$t->get_ok('/api/pets?ff=name,birdy,age,3')->status_is(200)
  ->json_is('/ff', {name => 'birdy', age => 3});

# style: form, explode: true
$t->get_ok('/api/pets')->status_is(200)
  ->json_is('/ft', {});
$t->get_ok('/api/pets?name=birdy&age=3')->status_is(200)
  ->json_is('/ft', {name => 'birdy', age => 3});

# style: spaceDelimited
$t->get_ok('/api/pets')->status_is(200)
  ->json_is('/sf', undef);
$t->get_ok('/api/pets?sf=')->status_is(200)
  ->json_is('/sf', {});
$t->get_ok('/api/pets?sf=name%20birdy%20age%203')->status_is(200)
  ->json_is('/sf', {name => 'birdy', age => 3});

# style: pipeDelimited
$t->get_ok('/api/pets')->status_is(200)
  ->json_is('/pf', undef);
$t->get_ok('/api/pets?pf=')->status_is(200)
  ->json_is('/pf', {});
$t->get_ok('/api/pets?pf=name|birdy|age|3')->status_is(200)
  ->json_is('/pf', {name => 'birdy', age => 3});

# style: simple, explode: false
$t->get_ok('/api/petsBySimpleId/category,bird,name,birdy')->status_is(200)
  ->json_is('/id', {category => 'bird', name => 'birdy'});

# style: simple, explode: true
$t->get_ok('/api/petsByExplodedSimpleId/category=bird,name=birdy')->status_is(200)
  ->json_is('/id', {category => 'bird', name => 'birdy'});

# style: matrix, explode: false
$t->get_ok('/api/petsByMatrixId;id=category,bird,name,birdy')->status_is(200)
  ->json_is('/id', {category => 'bird', name => 'birdy'});

# style: matrix, explode: true
$t->get_ok('/api/petsByExplodedMatrixId;category=bird;name=birdy')->status_is(200)
  ->json_is('/id', {category => 'bird', name => 'birdy'});

# style: label, explode: false
$t->get_ok('/api/petsByLabelId.category.bird.name.birdy')->status_is(200)
  ->json_is('/id', {category => 'bird', name => 'birdy'});

# style: label, explode: true
$t->get_ok('/api/petsByExplodedLabelId.category=bird.name=birdy')->status_is(200)
  ->json_is('/id', {category => 'bird', name => 'birdy'});
 
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
    "/pets": {
      "get": {
        "operationId": "getPets",
        "parameters": [
          {
            "name": "do",
            "in": "query",
            "style": "deepObject",
            "explode": true,
            "schema": {
              "type": "object"
            }
          },
          {
            "name": "ff",
            "in": "query",
            "style": "form",
            "explode": false,
            "schema": {
              "type": "object"
            }
          },
          {
            "name": "ft",
            "in": "query",
            "style": "form",
            "explode": true,
            "schema": {
              "type": "object"
            }
          },
          {
            "name": "sf",
            "in": "query",
            "style": "spaceDelimited",
            "explode": false,
            "schema": {
              "type": "object"
            }
          },
          {
            "name": "pf",
            "in": "query",
            "style": "pipeDelimited",
            "explode": false,
            "schema": {
              "type": "object"
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
    "/petsBySimpleId/{id}": {
      "get": {
        "operationId": "getPetsBySimpleId",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "style": "simple",
            "explode": false,
            "schema": {
              "type": "object"
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
    "/petsByExplodedSimpleId/{id}": {
      "get": {
        "operationId": "getPetsByExplodedSimpleId",
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "style": "simple",
            "explode": true,
            "schema": {
              "type": "object"
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
    "/petsByMatrixId/{id}": {
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
              "type": "object"
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
    "/petsByExplodedMatrixId/{id}": {
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
              "type": "object"
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
    "/petsByLabelId/{id}": {
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
              "type": "object"
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
    "/petsByExplodedLabelId/{id}": {
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
              "type": "object"
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
