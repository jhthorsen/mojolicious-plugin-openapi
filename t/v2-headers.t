use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
my $what_ever;
get '/headers' => sub {
  my $c    = shift->openapi->valid_input or return;
  my $args = $c->validation->output;

  $c->res->headers->header('what-ever' => ref $what_ever ? @$what_ever : $what_ever);
  $c->res->headers->header('x-bool'    => $args->{'x-bool'}) if exists $args->{'x-bool'};
  $c->render(openapi => $args);
  },
  'dummy';

get '/validate_twice' => sub {

  my $c = shift;

  my $res = {before => $c->req->headers->header('x-array')};

  $c->openapi->valid_input or return;

  $res->{first} = $c->req->headers->header('x-array');

  $c->openapi->valid_input;
  $res->{second} = $c->req->headers->header('x-array');

  $c->render(openapi => $res);
  },
  'twice';

plugin OpenAPI => {url => 'data://main/headers.json'};

my $t = Test::Mojo->new;
$t->get_ok('/api/headers' => {'x-number' => 'x', 'x-string' => '123'})->status_is(400)
  ->json_is('/errors/0', {'path' => '/x-number', 'message' => 'Expected number - got string.'});

$what_ever = '123';
$t->get_ok('/api/headers' => {'x-number' => 42.3, 'x-string' => '123'})->status_is(200)
  ->json_is('/x-number', 42.3)->header_is('what-ever', '123');

$what_ever = [qw(1 2 3)];
$t->get_ok('/api/headers' => {'x-array' => '42,24'})->status_is(200)->json_is('/x-array', [42, 24])
  ->header_is('what-ever', '1, 2, 3');

my $header_value = '42,24, 44';

$t->get_ok('/api/validate_twice' => {'x-array' => $header_value })->status_is(200)
  ->json_is( '/before'  => $header_value )
  ->json_is( '/first'   => $header_value )
  ->json_is( '/second'  => $header_value );

for my $bool (qw(true false 1 0)) {
  my $s = $bool =~ /true|1/ ? 'true' : 'false';
  $what_ever = '123';
  $t->get_ok('/api/headers' => {'x-bool' => $bool})->status_is(200)->content_like(qr{"x-bool":$s})
    ->header_is('x-bool', $s);
}

done_testing;

__DATA__
@@ headers.json
{
  "swagger" : "2.0",
  "info" : { "version": "9.1", "title" : "Test API for body parameters" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/headers" : {
      "get" : {
        "x-mojo-name": "dummy",
        "parameters" : [
          { "in": "header", "name": "x-bool", "type": "boolean", "description": "desc..." },
          { "in": "header", "name": "x-number", "type": "number", "description": "desc..." },
          { "in": "header", "name": "x-string", "type": "string", "description": "desc..." },
          { "in": "header", "name": "x-array", "items": { "type": "string" }, "type": "array", "description": "desc..." }
        ],
        "responses" : {
          "200" : {
            "description": "this is required",
            "headers": {
              "x-bool": { "type": "boolean" },
              "what-ever": {
                "type": "array",
                "items": { "type": "string" },
                "minItems": 1
              }
            },
            "schema": { "type" : "object" }
          }
        }
      }
    },
    "/twice" : {
      "get" : {
        "x-mojo-name": "twice",
        "parameters" : [
          { "in": "header", "name": "x-array", "items": { "type": "string" }, "type": "array", "description": "desc..." }
        ],
        "responses" : {
          "200" : {
            "description": "this is required",
            "schema": { "type" : "object" }
          }
        }
      }
    }
  }
}
