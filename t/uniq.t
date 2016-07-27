use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
eval { plugin OpenAPI => {url => 'data://main/route.json'} };
like $@, qr{Route name "xyz" is not unique}, 'unique route names';

eval { plugin OpenAPI => {url => 'data://main/op.json'} };
like $@, qr{operationId "xyz" is not unique}, 'unique operationId';

done_testing;

__DATA__
@@ op.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test unique operationId" },
  "basePath" : "/api",
  "paths" : {
    "/r" : {
      "get" : {
        "operationId": "xyz",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      },
      "post" : {
        "operationId": "xyz",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
@@ route.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test unique route names" },
  "basePath" : "/api",
  "paths" : {
    "/r" : {
      "get" : {
        "x-mojo-name": "xyz",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      },
      "post" : {
        "x-mojo-name": "xyz",
        "responses": {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
