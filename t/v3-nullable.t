use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

my %data = (id => 42);
get '/nullable-data' => \&action_null, 'withNullable';
get '/nullable-ref'  => \&action_null, 'withNullableRef';
plugin OpenAPI       => {url => 'data:///nullable.json', schema => 'v3'};

my $t = Test::Mojo->new;
$t->get_ok('/v1/nullable-data')->status_is(500);

$data{name} = undef;
$t->get_ok('/v1/nullable-data')->status_is(200);

$data{name} = 'batgirl';
$t->get_ok('/v1/nullable-data')->status_is(200);

$t->get_ok('/v1/nullable-ref')->status_is(200);

done_testing;

sub action_null {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => \%data);
}

__DATA__
@@ nullable.json
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
    "/nullable-data": {
      "get": {
        "operationId": "withNullable",
        "summary": "Dummy",
        "responses": {
          "200": {
            "description": "type:[null, string, ...] does the same",
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/WithNullable" }
              }
            }
          }
        }
      }
    },
    "/nullable-ref": {
      "get": {
        "operationId": "withNullableRef",
        "summary": "Dummy",
        "responses": {
          "200": {
            "description": "type:[null, string, ...] does the same",
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/WithNullableRef" }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "WithNullable": {
        "required": [ "id", "name" ],
        "properties": {
          "id": { "type": "integer", "format": "int64" },
          "name": { "type": "string", "nullable": true }
        }
      },
      "WithNullableRef": {
        "properties": {
          "name": { "$ref": "#/components/schemas/WithNullable/properties/name" }
        }
      }
    }
  }
}
