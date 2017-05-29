use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/protected' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'protected';

plugin OpenAPI => {
  url      => 'data://main/sec.json',
  security => {
    dummy => sub {
      my ($c, $config, $next) = @_;
      return $c->$next if $c->req->headers->authorization;
      return $c->render(openapi => $config, status => 401);
    },
  },
};

my $t = Test::Mojo->new;
$t->post_ok('/api/protected' => {Authorization => 42}, json => {})->status_is(200)
  ->json_is('/ok' => 1);

$t->post_ok('/api/protected' => json => {})->status_is(401)->json_is('' => []);

done_testing;

__DATA__
@@ sec.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Pets" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "securityDefinitions": {
    "dummy": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "dummy"
    }
  },
  "paths": {
    "/protected": {
      "post": {
        "x-mojo-name": "protected",
        "security": [{"dummy": []}],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "type": "array" }}
        }
      }
    }
  }
}
