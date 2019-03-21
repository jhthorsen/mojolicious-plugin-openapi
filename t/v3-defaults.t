use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

plan skip_all => $@ unless eval 'use YAML::XS 0.67;1';

post '/test' => sub {
  my $c = shift->openapi->valid_input or return;

  my $return_obj = {
    querydefault    => $c->validation->param('querydefault'),
    querynodefault  => $c->validation->param('querynodefault'),
    headerdefault   => $c->req->headers->header('headerdefault'),
    headernodefault => $c->req->headers->header('headernodefault'),
    body            => $c->validation->param('body')
  };

  $c->render(status => 200, openapi => $return_obj);
  },
  'File';

plugin OpenAPI => {schema => 'v3', url => 'data://main/file.yaml'};

my $t = Test::Mojo->new;

$t->post_ok(
  '/api/test?querynodefault=1' => {headernodefault => 'b'},
  json                         => {
    bodynodefault => 9,
    subobject => {subsubobject => {subarray => [{arraynodefault => 'z'}, {arraynodefault => 'x'}]}}
  }
)->status_is(200)->json_is('/querydefault' => '2')->json_is('/querynodefault' => '1')
  ->json_is('/body/bodydefault'           => '7')->json_is('/body/bodynodefault' => '9')
  ->json_is('/body/subobject/bodydefault' => Mojo::JSON->true)
  ->json_is('/body/subobject/subsubobject/bodydefault'               => 'astring')
  ->json_is('/body/subobject/subsubobject/subarray/0/arraynodefault' => 'z')
  ->json_is('/body/subobject/subsubobject/subarray/1/arraynodefault' => 'x')
  ->json_is('/body/subobject/subsubobject/subarray/0/arraydefault'   => 'arraystring')
  ->json_is('/body/subobject/subsubobject/subarray/1/arraydefault'   => 'arraystring')
  ->json_is('/headerdefault' => 'a')->json_is('/headernodefault' => 'b');

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
        - $ref: "#/components/parameters/querynodefault"
        - $ref: "#/components/parameters/querydefault"
        - $ref: "#/components/parameters/headernodefault"
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
                  - querydefault
                  - headerdefault
                  - querynodefault
                  - headernodefault
                  - body
                properties:
                  querydefault:
                    type: integer
                  querynodefault:
                    type: integer
                  headerdefault:
                    type: string
                  headernodefault:
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
    arrayelem:
      description: description
      type: object
      required:
        - arraydefault
        - arraynodefault
      properties:
        arraydefault:
          type: string
          default: arraystring
        arraynodefault:
          type: string
    bodydefault:
      description: description
      type: object
      required:
        - bodydefault
        - bodynodefault
        - subobject
      properties:
        bodydefault:
          type: integer
          default: 7
        bodynodefault:
          type: integer
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
                - subarray
              properties:
                bodydefault:
                  type: string
                  default: astring
                subarray:
                  type: array
                  items:
                    $ref: "#/components/schemas/arrayelem"
  parameters:
    querynodefault:
      name: querynodefault
      in: query
      schema:
        type: string
        enum:
          - 1
          - 2
    querydefault:
      name: querydefault
      in: query
      schema:
        type: string
        enum:
          - 1
          - 2
        default: 2
    headernodefault:
      name: headernodefault
      in: header
      schema:
        type: string
        enum:
          - a
          - b
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
