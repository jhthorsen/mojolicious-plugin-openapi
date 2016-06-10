use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
get '/die' => sub { die 'Oh noes!' }, 'Die';
plugin OpenAPI => {url => 'data://main/exception.json'};
my $t = Test::Mojo->new;
$t->get_ok('/api/die')->status_is(500)->json_is('/errors/0/message', 'Internal server error.');

done_testing;

__DATA__
@@ exception.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test exception response" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/die" : {
      "get" : {
        "operationId" : "Die",
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
