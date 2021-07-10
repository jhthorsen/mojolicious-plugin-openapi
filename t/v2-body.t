use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/body-string' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;
  $c->render(text => $c->req->body, status => 200);
  },
  'bodyString';

plugin OpenAPI => {url => 'data:///api.yml'};

my $t = Test::Mojo->new;

$t->post_ok('/api/body-string', {'Content-Type' => 'text/plain'} => 'invalid_json')->status_is(200)
  ->content_is('invalid_json');

done_testing;

__DATA__
@@ api.yml
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Raw data" },
  "basePath": "/api",
  "paths": {
    "/body-string": {
      "post": {
        "x-mojo-name": "bodyString",
        "parameters": [
          { "name": "echo", "in": "body", "schema": {"type": "string"} }
        ],
        "responses": {
          "200": { "description": "response", "schema": { "type": "string" } }
        }
      }
    }
  }
}
