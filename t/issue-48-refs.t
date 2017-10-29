use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

post '/event/update' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {status => $c->req->json->[0]});
  },
  'update';

eval { plugin OpenAPI => {url => 'data://main/with-refs.json'} };
ok !$@, 'resolved refs' or diag $@;

my $t = Test::Mojo->new;
$t->post_ok('/v1/event/update')->status_is(400);
$t->post_ok('/v1/event/update', json => [undef])->status_is(400);
$t->post_ok('/v1/event/update', json => ['ok'])->status_is(200)->json_is('/status', 'ok');

done_testing;

__DATA__
@@ with-refs.json
{
  "swagger": "2.0",
  "info": {
    "description": "Services and stuff",
    "title": "test api",
    "version": "0.0.6"
  },
  "schemes": [ "http" ],
  "host": "localhost",
  "basePath": "/v1",
  "paths": {
    "/event/update": {
      "$ref": "data://main/spec/event.json#/paths/~1event~1update"
    }
  }
}
@@ spec/event.json
{
  "paths": {
    "/event/update": {
      "post": {
        "operationId": "update",
        "summary": "Trigger an update to 1 or more properties",
        "description": "Notify the API of an update that needs processing.",
        "parameters": [
          {
            "description": "Data structure of events to process",
            "in": "body",
            "required": true,
            "name": "events",
            "schema": { "$ref": "#/definitions/events" }
          }
        ],
        "responses": {
          "200": { "$ref": "#/responses/updateSuccess" }
        }
      }
    }
  },
  "responses": {
    "updateSuccess": {
      "description": "",
      "schema": {
        "type": "object",
        "required": ["status"]
      }
    }
  },
  "definitions": {
    "events": {
      "type": "array",
      "minItems": 1,
      "items": {"type": "string"}
    }
  }
}
