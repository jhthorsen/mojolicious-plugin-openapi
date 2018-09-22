use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use Mojolicious::Lite;
eval { plugin OpenAPI => {url => 'data://main/api.json', log_level => 'debug'} };
like $@, qr{Could not find route by name}, 'invalidTrailingComma, was detetect';

done_testing;

__DATA__
@@ api.json
{
  "info": { "version": "0.8", "title": "PetCORS" },
  "basePath": "/api/v1",
  "swagger": "2.0",
  "paths": {
    "/echo": {
      "get": {
        "x-mojo-name": "invalidTrailingComma,",
        "responses": {
          "204": {
            "description": "Echo response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
