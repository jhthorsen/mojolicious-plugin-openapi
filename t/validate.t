use Mojo::Base -strict;
use Test::More;
use Mojolicious::Lite;

eval { plugin OpenAPI => {url => 'data://main/invalid.json'} };
like $@, qr{Invalid schema.*Missing}si, 'missing spec elements';

eval { plugin OpenAPI => {url => 'data://main/swagger2/issues/89.json'} };
like $@, qr{/definitions/\$ref}si, 'ref in the wrong place';

eval { plugin OpenAPI => {allow_invalid_ref => 1, url => 'data://main/swagger2/issues/89.json'} };
ok !$@, 'allow_invalid_ref=1' or diag $@;

done_testing;

__DATA__
@@ invalid.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test auto response" }
}
@@ swagger2/issues/89.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test auto response" },
  "paths" : { "$ref": "#/x-def/paths" },
  "definitions": { "$ref": "#/x-def/defs" },
  "x-def": {
    "defs": {
      "foo": { "properties": {} }
    },
    "paths": {
      "/auto" : {
        "post" : {
          "responses" : {
            "200": { "description": "response", "schema": { "type": "object" } }
          }
        }
      }
    }
  }
}
