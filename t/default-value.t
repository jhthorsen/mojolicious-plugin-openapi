use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post "/echo" => sub {
  my $c = shift;
  return if $c->openapi->invalid_input;
  return $c->reply->openapi(
    200 => {
      days => {controller => $c->param('days'), url  => $c->req->query_params->param('days')},
      name => {controller => $c->param('name'), form => $c->req->body_params->param('name')},
      x_foo      => {header => $c->req->headers->header('X-Foo')},
      validation => $c->validation->output,
    }
  );
  },
  "echo";

plugin OpenAPI => {url => "data://main/echo.json"};

my $t = Test::Mojo->new;
$t->post_ok('/api/echo')->status_is(200)->json_is('/days' => {controller => 42, url => 42})
  ->json_is('/name', {controller => 'batman', form => 'batman'})
  ->json_is('/x_foo', {header => 'yikes'})
  ->json_is('/validation', {days => 42, name => 'batman', 'X-Foo' => 'yikes'});

done_testing;

__DATA__
@@ echo.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Pets" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "paths": {
    "/echo/{something}": {
      "post": {
        "x-mojo-name": "echo",
        "parameters": [
          { "in": "query", "name": "days", "type": "number", "default": 42 },
          { "in": "formData", "name": "name", "type": "string", "default": "batman" },
          { "in": "header", "name": "X-Foo", "type": "string", "default": "yikes" }
        ],
        "responses": {
          "200": {
            "description": "Echo response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
