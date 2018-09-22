use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

make_app();
my $t = Test::Mojo->new(MyApp->new);
$t->get_ok('/api/user')->status_is(200)->json_is('/age', 42);

$t->get_ok('/api/user?code=201')->status_is(501)
  ->json_is('/errors/0/message', 'No response rule for "201".');

$t->get_ok('/api/user/foo')->status_is(404)->json_is('/errors/0/message', 'Not Found.');

$t->delete_ok('/api/user?code=201')->status_is(501)
  ->json_is('/errors/0/message', 'Not Implemented.');

done_testing;

sub make_app {
  eval <<'HERE' or die $@;
package MyApp;
use Mojo::Base 'Mojolicious';
sub startup {
  my $app = shift;
  $app->plugin(OpenAPI => {url => 'data://main/user.json'});
}

package MyApp::Controller::User;
use Mojo::Base 'Mojolicious::Controller';
sub find {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {age => 42}, status => $c->param('code') || 200);
}

1;
HERE
}

__DATA__
@@ user.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Pets" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "paths": {
    "/user": {
      "delete": {
        "x-mojo-to": "user#delete",
        "responses": {
          "200": { "description": "TODO", "schema": { "type": "object" } }
        }
      },
      "get": {
        "x-mojo-to": "user#find",
        "responses": {
          "200": {
            "description": "User",
            "schema": {
              "type": "object",
              "properties": { "age": { "type": "integer"} }
            }
          }
        }
      },
      "post": {
        "x-mojo-to": "user#create",
        "parameters": [
          { "in": "formData", "name": "age", "type": "integer" }
        ],
        "responses": {
          "400": { "description": "Error", "schema": { "type": "object" } }
        }
      }
    }
  }
}
