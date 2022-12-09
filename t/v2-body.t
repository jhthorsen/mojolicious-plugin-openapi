use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
for ('string', 'array') {
  my ($path, $name) = ("/body-$_", 'body' . ucfirst);
  post $path => sub {
    warn $_[0]->req->body;
    my $c = shift->openapi->valid_input or return;
    $c->render(text => $c->req->body, status => 200);
  }, $name;
}

plugin OpenAPI => {url => 'data:///api.yml'};

my $t = Test::Mojo->new;

$t->post_ok('/api/body-string', {'Content-Type' => 'text/plain'} => 'invalid_json')->status_is(200)
  ->content_is('invalid_json');

$t->post_ok('/api/body-array', json => [{cool => 'beans'}])->status_is(200)
  ->json_is('/0/cool', 'beans');

$t->post_ok('/api/body-array', json => ['str'])->status_is(400)
  ->json_is('/errors/0', {path => '/body/0', message => 'Expected object - got string.'});

done_testing;

__DATA__
@@ api.yml
{
  "swagger": "2.0",
  "info": {"version": "0.8", "title": "Raw data"},
  "basePath": "/api",
  "paths": {
    "/body-string": {
      "post": {
        "x-mojo-name": "bodyString",
        "parameters": [
          {"name": "echo", "in": "body", "schema": {"type": "string"}}
        ],
        "responses": {
          "200": {"description": "response", "schema": {"type": "string"}}
        }
      }
    },
    "/body-array": {
      "post": {
        "x-mojo-name": "bodyArray",
        "parameters": [
          {"name": "body", "in": "body", "schema": {"type": "array", "items": {"type": "object"}}}
        ],
        "responses": {
          "200": {"description": "response", "schema": {"type": "array"}}
        }
      }
    }
  }
}
