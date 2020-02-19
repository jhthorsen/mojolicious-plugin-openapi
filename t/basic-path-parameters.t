use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

post '/user/:id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {id => $c->param('id')});
  },
  'user';

plugin OpenAPI => {url => "data://main/path-parameters.json"};

my $t = Test::Mojo->new;

$t->post_ok('/api/user/foo' => json => {})->status_is(400);
$t->post_ok('/api/user/42a' => json => {})->status_is(400);
$t->post_ok('/api/user/42'  => json => {})->status_is(200)->json_is('/id', 42);

done_testing;

__DATA__
@@ path-parameters.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Path parameters" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/user/{id}" : {
      "parameters" : [
        { "in": "path", "name": "id", "type": "integer", "required": true }
      ],
      "post" : {
        "x-mojo-name" : "user",
        "responses" : {
          "200": { "description": "User response", "schema": { "type": "object" } },
          "400": { "description": "Invalid input", "schema": { "type": "object" } }
        }
      }
    }
  }
}
