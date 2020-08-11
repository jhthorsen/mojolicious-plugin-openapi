use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

my $age = 43;
get '/custom' => sub {
  my $c      = shift;
  my @errors = $c->openapi->validate;
  return $c->render(text => sprintf '%s errors', int @errors) if @errors;
  return $c->render(text => 'cool beans');
  },
  'get_custom';

plugin OpenAPI => {url => 'data://main/custom.json'};

my $t = Test::Mojo->new;
$t->get_ok('/api/custom?i=42')->content_is('cool beans');
$t->get_ok('/api/custom?i=nok')->content_is('1 errors');

done_testing;

__DATA__
@@ custom.json
---
swagger: 2.0
info:
  version: 1.0
  title: Custom validation
basePath: /api
paths:
  /custom:
    get:
      operationId: get_custom
      parameters:
      - name: i
        in: query
        type: integer
      responses:
        200:
          description: ok
          schema:
            type: file
