use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

my %inline;

{
  use Mojolicious::Lite;
  app->routes->namespaces(['MyApp::Controller']);
  get('/die'    => sub { die 'Oh noes!' },         'Die');
  get('/inline' => sub { shift->render(%inline) }, 'Inline');
  get
    '/not-found' => sub { shift->render(openapi => {this_is_fine => 1}, status => 404) },
    'NotFound';
  plugin OpenAPI => {url => 'data://main/hook.json'};
}

my $t = Test::Mojo->new;
$t->app->mode('development');

# Exception
$t->get_ok('/api/die')->status_is(500)->json_is('/errors/0/message', 'Internal Server Error.');

# Not implemented
$t->get_ok('/api/todo')->status_is(404)->json_is('/errors/0/message', 'Not Found.');

# Implemented, but Not Found
define_controller();
$t->get_ok('/api/todo')->status_is(404)->json_is('/errors/0/message', 'Not Found.');
$t->post_ok('/api/todo')->status_is(200)->json_is('/todo', 42);

# Custom Not Found response
$t->get_ok('/api/not-found')->status_is(404)->json_is('/this_is_fine', 1);

# Custom Not Found template (mode)
$t->get_ok('/THIS_IS_NOT_FOUND')->status_is(404)->content_like(qr{Not found development});

# Fallback to default renderer
$inline{template} = 'inline';
$t->get_ok('/api/inline')->status_is(200);    #->content_like(qr{Too cool});
$inline{openapi} = 'openapi is cool';
$t->get_ok('/api/inline')->status_is(200)->content_like(qr{openapi is cool});

done_testing;

sub define_controller {
  eval <<'HERE' or die;
  package MyApp::Controller::Dummy;
  use Mojo::Base 'Mojolicious::Controller';
  sub todo {
    my $c = shift->openapi->valid_input or return;
    $c->render(openapi => {todo => 42});
  }
  1;
HERE
}

package main;
__DATA__
@@ hook.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test before_render hook" },
  "basePath" : "/api",
  "paths" : {
    "/die" : {
      "get" : {
        "operationId" : "Die",
        "responses" : {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    },
    "/inline" : {
      "get" : {
        "operationId" : "Inline",
        "responses" : {
          "200": { "description": "response", "schema": { "type": "string" } }
        }
      }
    },
    "/not-found" : {
      "get" : {
        "operationId" : "NotFound",
        "responses" : {
          "404": { "description": "response", "schema": { "type": "object" } }
        }
      }
    },
    "/todo" : {
      "post" : {
        "x-mojo-to": "dummy#todo",
        "operationId" : "Auto",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
@@ inline.html.ep
Too cool
@@ not_found.html.ep
Not found
@@ not_found.development.html.ep
Not found development
