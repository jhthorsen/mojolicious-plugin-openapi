use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
plugin OpenAPI => {url => 'data://main/not-implemented.json'};
my $t = Test::Mojo->new;
$t->post_ok('/api/not-implemented' => json => ['invalid'])->status_is(501)
  ->json_is('/errors/0/message', 'Not implemented.');

done_testing;

__DATA__
@@ not-implemented.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test not-implemented response" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/not-implemented" : {
      "post" : {
        "operationId" : "Auto",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": {
            "description": "response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
