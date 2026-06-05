use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

post '/formdata' => sub {
    my $c = shift;
    $c->openapi->valid_input or return;

    my $name = $c->param('name');

    $c->render(json => {name => $name}, status => 200);
  },
  'formdata';

post '/formdata_array' => sub {
    my $c = shift;
    $c->openapi->valid_input or return;

    my $names = $c->req->body_params->every_param('name');

    $c->render(json => {name => $names, count => scalar @$names}, status => 200);
  },
  'formdata_array';

post '/upload' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;

  $c->render(openapi => {size => $c->req->upload('image')->size});
  },
  'upload';

post '/upload_array' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;

  my $sizes = [map { $_->size } @{$c->req->every_upload('image')}];

  $c->render(openapi => {size => $sizes, count => scalar @$sizes});
  },
  'upload_array';

plugin OpenAPI => {url => 'data://main/openapi.yaml'};

my $t = Test::Mojo->new;

# Basic data validation

$t->post_ok('/api/formdata', {'Content-Type' => 'application/json'}, json => {foo => 42})
  ->status_is(400)
  ->json_is('/errors/0', {message => 'Expected multipart/form-data - got application/json.', path => '/body'});

$t->post_ok('/api/formdata', {'Content-Type' => 'multipart/form-data'}, form => {foo => 42})
  ->status_is(400)
  ->json_is('/errors/0', {message => 'Missing property.', path => '/body/name'});

$t->post_ok('/api/formdata', {'Content-Type' => 'multipart/form-data'}, form => {name => 'John'})
  ->status_is(200)
  ->json_is('/name', 'John');

$t->post_ok('/api/formdata', {'Content-Type' => 'multipart/form-data'}, form => {name => ['John', 'Jane']})
  ->status_is(400)
  ->json_is('/errors/0', {message => 'Expected string - got array.', path => '/body/name'});

$t->post_ok('/api/formdata_array', {'Content-Type' => 'multipart/form-data'}, form => {name => 'John'})
  ->status_is(200)
  ->json_is('/name', ['John'])
  ->json_is('/count', 1);

$t->post_ok('/api/formdata_array', {'Content-Type' => 'multipart/form-data'}, form => {name => ['John', 'Jane']})
  ->status_is(200)
  ->json_is('/name', ['John', 'Jane'])
  ->json_is('/count', 2);

# File upload

my $image = Mojo::Asset::Memory->new->add_chunk('smileyface');

$t->post_ok('/api/upload', {'Content-Type' => 'multipart/form-data'}, form => {image => {file => $image}})
  ->status_is(200)
  ->json_has('/size');

$t->post_ok('/api/upload', {'Content-Type' => 'multipart/form-data'}, form => {picture => {file => $image}})
  ->status_is(400)
  ->json_is('/errors/0', {message => 'Missing property.', path => '/body/image'});

$t->post_ok('/api/upload', {'Content-Type' => 'multipart/form-data'}, form => {image => [{file => $image}, {file => $image}]})
  ->status_is(400)
  ->json_is('/errors/0', {message => 'Expected string - got array.', path => '/body/image'});

$t->post_ok('/api/upload_array', {'Content-Type' => 'multipart/form-data'}, form => {image => {file => $image}})
  ->status_is(200)
  ->json_has('/size')
  ->json_is('/count', 1);

$t->post_ok('/api/upload_array', {'Content-Type' => 'multipart/form-data'}, form => {image => [{file => $image}, {file => $image}]})
  ->status_is(200)
  ->json_has('/size')
  ->json_is('/count', 2);

done_testing;

__DATA__
@@ openapi.yaml
---
openapi: 3.0.0
info:
  title: Upload test
  version: 1.0.0
servers:
- url: http://example.com/api
paths:
  /formdata:
    post:
      x-mojo-name: formdata
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                name:
                  type: string
              required:
                - name
      responses:
        200:
          description: Accepted
          content:
            application/json:
              schema:
                required: [ name ]
                properties:
                  name:
                    type: string
  /formdata_array:
    post:
      x-mojo-name: formdata_array
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                name:
                  type: array
                  items:
                    type: string
              required:
                - name
      responses:
        200:
          description: Accepted
          content:
            application/json:
              schema:
                required: [ name ]
                properties:
                  name:
                    type: array
                    items:
                      type: string
                  count:
                    type: integer
  /upload:
    post:
      operationId: upload
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              required: [ image ]
              properties:
                image:
                  type: string
                  format: binary
      responses:
        200:
          description: Accepted
          content:
            application/json:
              schema:
                required: [ size ]
                properties:
                  size:
                    type: integer
  /upload_array:
    post:
      operationId: upload_array
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              required: [ image ]
              properties:
                image:
                  type: array
                  items:
                    type: string
                    format: binary
      responses:
        200:
          description: Accepted
          content:
            application/json:
              schema:
                required: [ size ]
                properties:
                  size:
                    type: array
                    items:
                      type: integer
                  count:
                    type: integer