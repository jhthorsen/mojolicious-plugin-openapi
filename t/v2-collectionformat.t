use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/header' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getHeader';

get '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPets';

post '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'postPets';

get '/pets/:id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPetsById';

plugin OpenAPI => {url => 'data://main/discriminator.json'};

my $t = Test::Mojo->new;

subtest 'Expected array - got null' => sub {
  $t->get_ok('/api/pets')->status_is(400)->json_is('/errors/0/path', '/ri');
};

subtest 'Expected integer - got number.' => sub {
  $t->get_ok('/api/pets?ri=1.3')->status_is(400)->json_is('/errors/0/path', '/ri/0');
};

subtest 'Not enough items: 1\/2' => sub {
  $t->get_ok('/api/pets?ri=3&ml=5')->status_is(400)->json_is('/errors/0/path', '/ml');
};

subtest 'Valid' => sub {
  $t->get_ok('/api/pets?ri=3&ml=4&ml=2')->status_is(200)->json_is('/ml', [4, 2])
    ->json_is('/ri', [3]);
};

subtest 'In path' => sub {
  $t->get_ok('/api/pets/ilm,a,r,i')->status_is(200)->json_is('/id', [qw(ilm a r i)]);
};

subtest 'In query' => sub {
  $t->post_ok('/api/pets?idq=ilm,a,r,i')->status_is(200)->json_is('/idq', [qw(ilm a r i)]);
  $t->post_ok("/api/pets?idq-tsv=ilm\ta\tr\ti")->status_is(200)
    ->json_is('/idq-tsv', [qw(ilm a r i)]);
  $t->post_ok('/api/pets?idq-ssv=ilm a r i')->status_is(200)->json_is('/idq-ssv', [qw(ilm a r i)]);
  $t->post_ok('/api/pets?idq-pipes=ilm|a|r|i')->status_is(200)
    ->json_is('/idq-pipes', [qw(ilm a r i)]);
};

subtest 'In formData' => sub {
  $t->post_ok('/api/pets' => form => {idf => 'ilm,a,r,i'})->status_is(200)
    ->json_is('/idf', [qw(ilm a r i)]);
  $t->post_ok('/api/pets' => form => {'idf-tsv' => "ilm\ta\tr\ti"})->status_is(200)
    ->json_is('/idf-tsv', [qw(ilm a r i)]);
  $t->post_ok('/api/pets' => form => {'idf-ssv' => 'ilm a r i'})->status_is(200)
    ->json_is('/idf-ssv', [qw(ilm a r i)]);
  $t->post_ok('/api/pets' => form => {'idf-pipes' => 'ilm|a|r|i', 'a' => 'b'})->status_is(200)
    ->json_is('/idf-pipes', [qw(ilm a r i)]);
  $t->post_ok('/api/pets' => {'Content-Type' => 'application/x-www-form-urlencoded'} =>
      'idf-multi=ilm&idf-multi=a')->status_is(200)->json_is('/idf-multi', [qw(ilm a)]);
};

subtest 'In header' => sub {
  $t->get_ok('/api/header')->status_is(200)->content_is('{}');
  $t->get_ok('/api/header', {'X-Collection' => ''})->status_is(200)->json_is('/X-Collection' => []);
  $t->get_ok('/api/header', {'X-Collection' => 'a,b'})->status_is(200)
    ->json_is('/X-Collection' => [qw(a b)]);
};

done_testing;

__DATA__
@@ discriminator.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test collectionFormat" },
  "basePath": "/api",
  "paths" : {
    "/header" : {
      "get" : {
        "operationId" : "getHeader",
        "parameters" : [
          {
            "name":"X-Collection",
            "in":"header",
            "type":"array",
            "collectionFormat":"csv",
            "items":{"type":"string"},
            "minItems":0
          }
        ],
        "responses" : {
          "200": {
            "description": "response",
            "schema": { "type": "object" }
          }
        }
      }
     },
    "/pets/{id}" : {
      "get" : {
        "operationId" : "getPetsById",
        "parameters" : [
          {
            "name":"id",
            "in":"path",
            "type":"array",
            "collectionFormat":"csv",
            "items":{"type":"string"},
            "minItems":0,
            "required":true
          }
        ],
        "responses" : {
          "200": {
            "description": "pet response",
            "schema": { "type": "object" }
          }
        }
      }
    },
    "/pets" : {
      "get" : {
        "operationId" : "getPets",
        "parameters" : [
          {
            "name":"no",
            "in":"query",
            "type":"array",
            "collectionFormat":"multi",
            "items":{"type":"integer"},
            "minItems":0
          },
          {
            "name":"ml",
            "in":"query",
            "type":"array",
            "collectionFormat":"multi",
            "items":{"type":"integer"},
            "minItems":2
          },
          {
            "name":"ri",
            "in":"query",
            "type":"array",
            "collectionFormat":"multi",
            "required":true,
            "items":{"type":"integer"},
            "minItems":1
          }
        ],
        "responses" : {
          "200": {
            "description": "pet response",
            "schema": { "type": "object" }
          }
        }
      },
      "post" : {
        "operationId" : "postPets",
        "parameters" : [
          {
            "name":"idq",
            "in":"query",
            "type":"array",
            "collectionFormat":"csv",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          },
          {
            "name":"idq-tsv",
            "in":"query",
            "type":"array",
            "collectionFormat":"tsv",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          },
          {
            "name":"idq-ssv",
            "in":"query",
            "type":"array",
            "collectionFormat":"ssv",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          },
          {
            "name":"idq-pipes",
            "in":"query",
            "type":"array",
            "collectionFormat":"pipes",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          },
          {
            "name":"idf",
            "in":"formData",
            "type":"array",
            "collectionFormat":"csv",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          },
          {
            "name":"idf-tsv",
            "in":"formData",
            "type":"array",
            "collectionFormat":"tsv",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          },
          {
            "name":"idf-ssv",
            "in":"formData",
            "type":"array",
            "collectionFormat":"ssv",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          },
          {
            "name":"idf-pipes",
            "in":"formData",
            "type":"array",
            "collectionFormat":"pipes",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          },
          {
            "name":"idf-multi",
            "in":"formData",
            "type":"array",
            "collectionFormat":"multi",
            "items":{"type":"string"},
            "minItems":0,
            "required":false
          }
        ],
        "responses" : {
          "200": {
            "description": "pet response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
