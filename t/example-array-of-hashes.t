use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/echo' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => $c->req->json);
  },
  'echo';

plugin OpenAPI => {url => 'data://main/echo.json'};

my $t = Test::Mojo->new;
$t->post_ok('/api/echo' => json => [{foo => 'f'}, {bar => 'b'}])->status_is(200)
  ->json_is('/0' => {foo => 'f'})->json_is('/1' => {bar => 'b'});

done_testing;

__DATA__
@@ echo.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Array" },
  "basePath" : "/api",
  "paths" : {
    "/echo" : {
      "post" : {
        "x-mojo-name" : "echo",
        "parameters" : [
          {"in": "body", "name": "body", "schema": {"$ref": "#/definitions/s1"}}
        ],
        "responses" : {
          "200": {
            "description": "Echo response",
            "schema": {"$ref": "#/definitions/s1"}
          }
        }
      }
    }
  },
  "definitions": {
    "s1": {"type" : "array", "items": {"type": "object"}}
  }
}
