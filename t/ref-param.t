use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

get '/test' => sub {
  my $c = shift->openapi->valid_input or return;
  my $params = $c->validation->output;
  $c->render(status => 200, openapi => $params->{pcversion});
  },
  'File';

plugin OpenAPI => {url => 'data://main/file.yaml'};

my $t = Test::Mojo->new;

$t->get_ok('/api/test?x=42')->status_is(200)->content_is('"10.1.0"');

done_testing;

__DATA__
@@ file.yaml
{
  "swagger": "2.0",
  "info": { "title": "Test defaults", "version": "1" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "parameters": {
    "PCVersion": {
      "name": "pcversion",
      "in": "query",
      "type": "string",
      "enum": [ "9.6.1", "10.1.0" ],
      "default": "10.1.0",
      "description": "version of commands which will run on backend"
    }
  },
  "paths": {
    "/test": {
      "get": {
        "parameters": [
          { "$ref": "#/parameters/PCVersion" },
          { "name": "x", "in": "query", "type": "string", "description": "x" }
        ],
        "operationId": "File",
        "responses": {
          "200": {
            "description": "thing",
            "schema": { "type": "string" }
          }
        }
      }
    }
  }
}
