use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

post '/auto' => sub {
  my $c = shift->openapi->valid_input or return;
  return $c->reply->openapi(200 => [42]) if $c->req->json->{invalid_output};
  return $c->render(text => 'make sure openapi.errors is part of output');
  },
  'Auto';

plugin OpenAPI => {url => 'data://main/auto.json'};

my $t = Test::Mojo->new;
$t->post_ok('/api/auto' => json => ['invalid'])->status_is(400)
  ->json_like('/errors/0/message', qr{Expected}i)->json_is('/errors/0/path', '/body');

$t->post_ok('/api/auto' => json => {})->status_is(200)
  ->content_is('make sure openapi.errors is part of output');

$t->post_ok('/api/auto' => json => {invalid_output => 1})->status_is(500)
  ->json_like('/errors/0/message', qr{Expected}i)->json_is('/errors/0/path', '/');

done_testing;

__DATA__
@@ auto.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test auto response" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/auto" : {
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
