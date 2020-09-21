use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/required' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {id => 1}, status => 201);
  },
  'with_required';

plugin OpenAPI => {url => 'data:///schema.json', schema => 'v3'};

my $t = Test::Mojo->new;
$t->post_ok('/required' => json => {app_id => 1})->status_is(201);

done_testing;

sub post_test {
}

__DATA__
@@ schema.json
{
  "openapi": "3.0.3",
  "info": { "title": "Test", "version": "0.0.0" },
  "paths": {
    "/required": {
      "post": {
        "operationId": "with_required",
        "requestBody": {
          "content": {
            "application/json": { "schema": { "$ref": "#/components/schemas/Required" } }
          }
        },
        "responses": {
          "201": {
            "description": "ok",
            "content": {
              "application/json": { "schema": { "$ref": "#/components/schemas/Required" } }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Required": {
        "required": ["app_id", "id"],
        "properties": {
          "app_id": { "type": "integer", "writeOnly": true },
          "id": { "type": "integer", "readOnly": true }
        }
      }
    }
  }
}
