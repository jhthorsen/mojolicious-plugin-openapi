use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/spec' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(json => {info => $c->openapi->spec('/info'), op_spec => $c->openapi->spec});
  },
  'Spec';

get('/user/:id' => sub { shift->render(openapi => {}) }, 'user');

plugin OpenAPI => {url => 'data://main/spec.json'};

my $t = Test::Mojo->new;

$t->get_ok('/api')->status_is(200)->json_is('/swagger', '2.0')
  ->json_is('/definitions/DefaultResponse/properties/errors/items/properties/message/type',
  'string')->json_is('/definitions/SpecResponse/type', 'object')
  ->json_is('/paths/~1spec/get/operationId', 'Spec');

$t->get_ok('/api/spec')->status_is(200)
  ->json_is('/op_spec/responses/200/description', 'Spec response.')
  ->json_is('/info/version',                      '0.8');

$t->get_ok('/api/user/1')->status_is(200)->content_is('{}');

$t->options_ok('/api/spec')->status_is(200)
  ->json_is('/$schema',                       'http://json-schema.org/draft-04/schema#')
  ->json_is('/title',                         'Test spec response')->json_is('/description', '')
  ->json_is('/get/operationId',               'Spec')
  ->json_is('/get/responses/200/schema/$ref', '#/definitions/SpecResponse')
  ->json_is('/definitions/DefaultResponse/properties/errors/items/properties/message/type',
  'string')->json_is('/definitions/SpecResponse/type', 'object');

$t->options_ok('/api/spec?method=get')->status_is(200)
  ->json_is('/$schema',     'http://json-schema.org/draft-04/schema#')
  ->json_is('/title',       'Test spec response')->json_is('/description', '')
  ->json_is('/operationId', 'Spec')->json_is('/definitions/SpecResponse/type', 'object');

$t->options_ok('/api/spec?method=post')->status_is(404)
  ->json_is('/errors/0/message', 'No spec defined.');

$t->options_ok('/api/user/1')->status_is(200)
  ->json_is('/$schema', 'http://json-schema.org/draft-04/schema#')
  ->json_is('/title',   'Test spec response')->json_is('/get/operationId', 'user')
  ->json_is('/definitions/DefaultResponse/properties/errors/items/properties/message/type',
  'string');

$t->get_ok('/api')->status_is(200)->json_is('/basePath', '/api');

$t->head_ok('/api')->status_is(200);
$t->head_ok('/api/user/1')->status_is(200)->content_is('');

hook before_dispatch => sub {
  my $c = shift;
  $c->req->url->base->path('/whatever');
};

$t->get_ok('/api')->status_is(200)->json_is('/basePath', '/whatever/api');

done_testing;

__DATA__
@@ spec.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test spec response" },
  "basePath" : "/api",
  "paths" : {
    "/spec" : {
      "get" : {
        "operationId" : "Spec",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": { "description": "Spec response.", "schema": { "$ref": "#/definitions/SpecResponse" } }
        }
      }
    },
    "/user/{id}" : {
      "parameters" : [
        { "in": "path", "name": "id", "type": "integer", "required": true }
      ],
      "get" : {
        "operationId" : "user",
        "responses" : {
          "200": {
            "description": "User response.",
            "schema": { "type": "object" }
          }
        }
      }
    }
  },
  "definitions": {
    "Object": {
      "type": "object"
    },
    "SpecResponse": {
      "type": "object",
      "properties": {
        "get": { "$ref": "#/definitions/Object" }
      }
    }
  }
}
