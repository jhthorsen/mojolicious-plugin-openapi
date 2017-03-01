use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojo::Util 'encode';

use Mojolicious::Lite;

post '/echo' => sub {
  my $c = shift->openapi->valid_input or return;
  my $data = $c->req->body;
  note "body=($data)";
  $c->res->headers->content_type('text/echo');
  $c->render(openapi => Mojo::Asset::Memory->new->add_chunk($data));
  },
  'echo';

plugin OpenAPI => {url => "data://main/echo.json"};

my $t = Test::Mojo->new;

$t->post_ok('/api/echo' => encode('UTF-8', 'utf табак'))->status_is(200)
  ->content_is('utf табак')->content_type_is('text/echo');

done_testing;

__DATA__
@@ echo.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "File" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/echo" : {
      "post" : {
        "x-mojo-name" : "echo",
        "parameters" : [
          { "name": "body", "in": "formData", "type": "file" }
        ],
        "responses" : {
          "200": { "description": "Echo response", "schema": { "type": "file" } }
        }
      }
    }
  }
}
