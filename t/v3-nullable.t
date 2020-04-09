use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

my %data = (id => 42);
get '/nullable-data' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => \%data);
  },
  'withNullable';

plugin OpenAPI => {url => 'data:///nullable.json'};

my $t = Test::Mojo->new;
$t->get_ok('/v1/nullable-data')->status_is(500);

$data{name} = undef;
$t->get_ok('/v1/nullable-data')->status_is(200);

$data{name} = 'batgirl';
$t->get_ok('/v1/nullable-data')->status_is(200);

done_testing;

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
      }
    }
  }
}
