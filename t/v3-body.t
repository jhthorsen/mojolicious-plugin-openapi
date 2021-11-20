use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/test' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;
  $c->render(json => undef, status => 200);
  },
  'test';

post '/test/string' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;
  $c->render(text => $c->req->body, status => 200);
  },
  'string';

post '/test/optional/explicitly' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;
  $c->render(openapi => undef, status => 200);
  },
  'test2';

post '/test/optional/implicitly' => sub {
  my $c = shift;
  $c->openapi->valid_input or return;
  $c->render(openapi => undef, status => 200);
  },
  'test3';

plugin OpenAPI => {url => 'data:///api.yml'};

my $t = Test::Mojo->new();

note 'Valid request should be ok';
$t->post_ok('/test', json => {foo => 'bar'})->status_is(200);

note 'Missing property should fail';
$t->post_ok('/test', json => {})->status_is(400)->json_is('/errors/0/message', 'Missing property.');

note 'Array should fail';
$t->post_ok('/test', json => [])->status_is(400)
  ->json_is('/errors/0/message', 'Expected object - got array.');

note 'Null should fail';
$t->post_ok('/test', json => undef)->status_is(400)
  ->json_is('/errors/0/message', 'Expected object - got null.');

note 'Invalid JSON should fail';
$t->post_ok('/test', {'Content-Type' => 'application/json'} => 'invalid_json')->status_is(400)
  ->json_is('/errors/0/message', 'Expected object - got string.');

note 'Invalid Content-Type should fail';
$t->post_ok('/test', {'Content-Type' => 'application/xml'} => '<?xml version = "1.0"?>')
  ->status_is(400)
  ->json_is('/errors/0/message', 'Expected application/json - got application/xml.');

note 'empty requestBody with "required: false"';
$t->post_ok('/test/optional/explicitly')->status_is(200);

note 'requestBody with "required: false"';
$t->post_ok('/test/optional/explicitly', json => {foo => 'bar'})->status_is(200);

note 'empty requestBody without "required: false"';
$t->post_ok('/test/optional/implicitly')->status_is(200);

note 'requestBody without "required: false"';
$t->post_ok('/test/optional/implicitly', json => {foo => 'bar'})->status_is(200);

note 'requestBody as plain string';
$t->post_ok('/test/string', {'Content-Type' => 'text/plain'}, 'cool beans')->status_is(200)
  ->content_is('cool beans');

note 'not really the first, since "content" is an object, but predictable when there is only one';
$t->post_ok('/test/string', 'first content-type')->status_is(200)->content_is('first content-type');

done_testing;

__DATA__
@@ api.yml
openapi: 3.0.0
info:
  title: Test
  version: 0.0.0
paths:
  /test:
    post:
      x-mojo-name: test
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                foo:
                  type: string
              required:
                - foo
      responses:
        '200':
          description: ok

  /test/string:
    post:
      x-mojo-name: string
      requestBody:
        required: true
        content:
          text/plain:
            schema:
              type: string
      responses:
        '200':
          description: ok

  /test/optional/explicitly:
    post:
      x-mojo-name: test2
      requestBody:
        required: false
        content:
          application/json:
            schema:
              type: object
              properties:
                foo:
                  type: string
              required:
                - foo
      responses:
        '200':
          description: ok

  /test/optional/implicitly:
    post:
      x-mojo-name: test3
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                foo:
                  type: string
              required:
                - foo
      responses:
        '200':
          description: ok
