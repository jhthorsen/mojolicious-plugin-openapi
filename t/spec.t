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

$t->get_ok('/api/spec')->status_is(200)
  ->json_is('/op_spec/responses/200/description', 'Spec response.')
  ->json_is('/info/version',                      '0.8');

$t->options_ok('/api/spec')->status_is(200)->json_is('/get/operationId', 'Spec');
$t->options_ok('/api/spec?method=get')->status_is(200)->json_is('/operationId', 'Spec');
$t->options_ok('/api/spec?method=post')->status_is(404);

$t->options_ok('/api/user/1')->status_is(200)->json_is('/get/operationId', 'user');

$t->get_ok('/api')->status_is(200)->json_is('/basePath', '/api');

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
          "200": {
            "description": "Spec response.",
            "schema": { "type": "object" }
          }
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
            "description": "Spec response.",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
