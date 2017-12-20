use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

#============================================================================
package MyApp;
use Mojo::Base 'Mojolicious';

sub startup {
  my $app = shift;
  $app->plugin(OpenAPI => {url => "data://main/echo.json"});
}

#============================================================================
package MyApp::Controller::Dummy;
use Mojo::Base 'Mojolicious::Controller';

sub echo {
  my $c = shift->openapi->valid_input or return;

  my $name
    = $c->stash('name')
    ? {param => $c->param('name'), stash => $c->stash('name')}
    : {controller => $c->param('name'), form => $c->req->body_params->param('name')};

  $c->render(
    openapi => {
      days => {controller => $c->param('days'), url => $c->req->query_params->param('days')},
      name => $name,
      x_foo      => {header => $c->req->headers->header('X-Foo')},
      validation => $c->validation->output,
    }
  );
}

#============================================================================
package main;
my $t = Test::Mojo->new('MyApp');

$t->get_ok('/api/echo/batman')->status_is(200)->json_is('/days' => {controller => 42, url => 42})
  ->json_is('/name', {param => 'batman', stash => 'batman'});
ok !$t->tx->res->json->{x_foo}{header}, 'x_foo header is not set';

$t->post_ok('/api/echo')->status_is(200)->json_is('/days' => {controller => 42, url => 42})
  ->json_is('/name', {controller => 'batman', form => 'batman'})
  ->json_is('/x_foo', {header => 'yikes'})
  ->json_is('/validation', {days => 42, name => 'batman', 'X-Foo' => 'yikes', enumParam => '10.1.0'});

done_testing;

__DATA__
@@ echo.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Pets" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "paths": {
    "/echo": {
      "post": {
        "x-mojo-to": "dummy#echo",
        "parameters": [
          { "in": "query", "name": "days", "type": "number", "default": 42 },
          { "in": "formData", "name": "name", "type": "string", "default": "batman" },
          {
            "in": "query", "name": "enumParam",
            "type": "string", "default": "10.1.0",
            "enum": [ "9.6.1", "10.1.0" ]
          },
          { "in": "header", "name": "X-Foo", "type": "string", "default": "yikes" }
        ],
        "responses": {
          "200": {
            "description": "Echo response",
            "schema": { "type": "object" }
          }
        }
      }
    },
    "/echo/{name}": {
      "get": {
        "x-mojo-to": "dummy#echo",
        "parameters": [
          { "in": "path", "name": "name", "type": "string", "required": true },
          { "in": "query", "name": "days", "type": "number", "default": 42 }
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
