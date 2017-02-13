use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

my $t = Test::Mojo->new;
my ($res, $status);

get '/string' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $res, status => $status);
  },
  'File';

plugin OpenAPI => {url => 'data://main/file.json'};

($res, $status) = ('', 200);
$t->get_ok('/api/string')->status_is(200)->content_is('""');

($res, $status) = (undef, 200);
$t->get_ok('/api/string')->status_is(200)->content_is('null');

($res, $status) = ('', 204);
$t->get_ok('/api/string')->status_is(204)->content_is('');

done_testing;

package main;
__DATA__
@@ file.json
{
  "swagger": "2.0",
  "info": {"version": "0.8", "title": "Test empty response"},
  "schemes": ["http"],
  "basePath": "/api",
  "paths": {
    "/string": {
      "get": {
        "operationId": "File",
        "responses": {
          "200": {
            "description": "response",
            "schema": {"type": ["null", "string"]}
          },
          "204": {
            "description": "empty",
            "schema": {"type": ["string"]}
          }
        }
      }
    }
  }
}
