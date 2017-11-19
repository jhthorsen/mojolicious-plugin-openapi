use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'getPets';

plugin OpenAPI => {url => 'data://main/discriminator.json'};

my $t = Test::Mojo->new;

# Expected array - got null
$t->get_ok('/api/pets')->status_is(400)->json_is('/errors/0/path', '/ri');

# Expected integer - got number.
$t->get_ok('/api/pets?ri=1.3')->status_is(400)->json_is('/errors/0/path', '/ri/0');

# Not enough items: 1\/2
$t->get_ok('/api/pets?ri=3&ml=5')->status_is(400)->json_is('/errors/0/path', '/ml');

# Valid
$t->get_ok('/api/pets?ri=3&ml=4&ml=2')->status_is(200)->json_is('/ml', [4, 2])->json_is('/ri', [3]);

done_testing;

__DATA__
@@ discriminator.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test collectionFormat" },
  "basePath": "/api",
  "paths" : {
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
      }
    }
  }
}
