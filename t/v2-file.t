use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/user' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {});
  },
  'createUser';


plugin OpenAPI => {url => 'data://main/readonly.json'};

my $t = Test::Mojo->new;

$t->post_ok('/api/user')->status_is(400)
  ->json_is('/errors/0', {message => 'Missing property.', path => '/image'});

my $image = Mojo::Asset::Memory->new->add_chunk('smileyface');
$t->post_ok('/api/user', form => {image => {file => $image}})->status_is(200);

done_testing;

__DATA__
@@ readonly.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Test readonly" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "paths": {
    "/user": {
      "post": {
        "operationId": "createUser",
        "parameters": [
          {
            "name": "image",
            "in": "formData",
            "type": "file",
            "required": true
          }
        ],
        "responses": {
          "200": { "description": "ok", "schema": { "type": "object" } }
        }
      }
    }
  }
}
