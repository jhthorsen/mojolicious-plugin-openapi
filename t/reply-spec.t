use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
my $under = under '/whatever' => sub {1};
plugin OpenAPI => {route => $under, url => 'data://main/reply.json'};
my $t = Test::Mojo->new;
$t->get_ok('/whatever')->status_is(200)->json_is('/basePath', '/whatever')
  ->json_unlike('/host', qr{api\.thorsen\.pm})->json_like('/host', qr{.:\d+$})
  ->json_is('/info/version', 0.8);

done_testing;

__DATA__
@@ reply.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test reply spec" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "host": "api.thorsen.pm",
  "basePath" : "/api",
  "paths" : {
    "/pets" : {
      "post" : {
        "operationId" : "addPet",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": {
            "description": "pet response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
