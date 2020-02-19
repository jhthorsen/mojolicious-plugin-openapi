use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

get '/test' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(status => 200, openapi => $c->param('pcversion'));
  },
  'File';

plugin OpenAPI => {schema => 'v3', url => 'data://main/file.yaml'};

my $t = Test::Mojo->new;

$t->get_ok('/api/test')->status_is(200)->content_is('"10.1.0"');

done_testing;

package main;
__DATA__
@@ file.yaml
openapi: 3.0.0
info:
  title: Test defaults
  version: "1"
servers:
  - url: /api
paths:
  /test:
    get:
      operationId: File
      parameters:
        - $ref: "#/components/parameters/PCVersion"
      responses:
        "200":
          description: thing
          content:
            "*/*":
              schema:
                type: string
components:
  parameters:
    PCVersion:
      name: pcversion
      in: query
      description: version of commands which will run on backend
      schema:
        type: string
        enum:
          - 9.6.1
          - 10.1.0
        default: 10.1.0
