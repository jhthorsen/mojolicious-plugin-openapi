use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojo::Util 'encode';

use Mojolicious::Lite;

post '/decode' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {decode => 1});
  },
  'decode';

post '/:id' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {id => $c->param('id')});
  },
  'id';


plugin OpenAPI => {url => "data://main/correct-order.json"};

my $t = Test::Mojo->new;

$t->post_ok('/api/foo')->status_is(200)->json_is('/id', 'foo')->content_like(qr{id});
$t->post_ok('/api/decode')->status_is(200)->json_is('/decode', 1)->content_like(qr{decode});

done_testing;

__DATA__
@@ correct-order.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "File" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/decode": {
      "post": {
        "x-mojo-name": "decode",
        "responses": {
          "200": { "description": "Success" }
        }
      }
    },
    "/{id}": {
      "post": {
        "x-mojo-name": "id",
        "parameters": [
          { "name": "id", "in": "path", "required": true, "type": "string" }
        ],
        "responses": {
          "200": { "description": "Success" }
        }
      }
    }
  }
}
