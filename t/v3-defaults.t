use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

plan skip_all => $@ unless eval 'use YAML::XS 0.67;1';

post '/test' => sub {
  my $c = shift->openapi->valid_input or return;

  my $return_obj = {query  => $c->validation->param('querydefault'),
                    body   => $c->validation->param('body'),
                    header => $c->req->headers->header('headerdefault')};

  $c->render(status => 200, openapi => $return_obj);
  },
  'File';

plugin OpenAPI => {schema => 'v3', url => 'data://main/file.yaml'};

my $t = Test::Mojo->new;

$t->post_ok('/api/test', json => {})->status_is(200)
  ->json_is('/query'  => '2')
  ->json_is('/body/bodydefault'  => '7')
  ->json_is('/body/subobject/bodydefault'  => Mojo::JSON->true)
  ->json_is('/body/subobject/subsubobject/bodydefault'  => 'astring')
  ->json_is('/header' => 'a');

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
    post:
      operationId: File
      parameters:
        - $ref: "#/components/parameters/querydefault"
        - $ref: "#/components/parameters/headerdefault"
      requestBody:
        content:
          'application/json':
            schema:
              $ref: "#/components/schemas/bodydefault"
      responses:
        "200":
          description: description
          content:
            "*/*":
              schema:
                type: object
                required:
                  - query
                  - header
                  - body
                properties:
                  query:
                    type: string
                  header:
                    type: string
                  body:
                    type: object
components:
  schemas:
    DefaultResponse:
      description: description
      type: object
      properties:
        message:
          type: string
    bodydefault:
      description: description
      type: object
      required:
        - bodydefault
        - subobject
      properties:
        bodydefault:
          type: integer
          default: 7
        subobject:
          type: object
          required:
            - bodydefault
            - subsubobject
          properties:
            bodydefault:
              type: boolean
              default: true
            subsubobject:
              type: object
              required:
                - bodydefault
              properties:
                bodydefault:
                  type: string
                  default: astring
  parameters:
    querydefault:
      name: querydefault
      in: query
      schema:
        type: string
        enum:
          - 1
          - 2
        default: 2
    headerdefault:
      name: headerdefault
      in: header
      schema:
        type: string
        enum:
          - a
          - b
        default: a
  responses:
    DefaultResponse:
      description: description
      content:
        "*/*":
          schema:
            $ref: "#/components/schemas/DefaultResponse"
