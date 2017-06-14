use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

plan skip_all => 'TEST_MIXIN=1' unless $ENV{TEST_MIXIN};

use Mojolicious::Lite;
get '/mixin' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => $c->openapi->spec);
  },
  'mixin';

plugin OpenAPI => {allow_invalid_ref => 1, url => 'data://main/main.json'};

my $t = Test::Mojo->new;
$t->get_ok('/api/mixin?age=34')->status_is(200)->json_is('/parameters/0/name', 'age');

done_testing;

__DATA__
@@ main.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Array" },
  "basePath" : "/api",
  "paths" : {
    "/mixin" : {
      "get" : {
        "x-mojo-name" : "mixin",
        "parameters" : [
          {
            "name": "age",
            "$ref": "data://main/mixins.json#/definitions/p1"
          }
        ],
        "responses" : {
          "200": { "description": "Response", "schema": {"type":"object"} }
        }
      }
    }
  }
}

@@ mixins.json
{
  "definitions": {
    "p1": {"in": "query", "name": "x", "type": "integer"}
  }
}
