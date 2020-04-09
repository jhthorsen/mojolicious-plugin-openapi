use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/upload' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {size => $c->req->upload('image')->size});
  },
  'upload';

plugin OpenAPI => {url => 'data://main/openapi.yaml'};

my $t = Test::Mojo->new;

$t->post_ok('/api/upload', form => {})->status_is(400)
  ->json_is('/errors/0', {message => 'Missing property.', path => '/body/image'});

my $image = Mojo::Asset::Memory->new->add_chunk('smileyface');
$t->post_ok(
  '/api/upload',
  {Accept => 'application/json'},
  form => {id => 1, image => {file => $image}}
)->status_is(200);

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
  /upload:
    post:
      operationId: upload
      requestBody:
        required: true
        content:
          application/x-www-form-urlencoded:
            schema:
              required: [ image ]
              properties:
                id:
                  type: string
                image:
                  type: string
                  format: binary
          multipart/form-data:
            schema:
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
