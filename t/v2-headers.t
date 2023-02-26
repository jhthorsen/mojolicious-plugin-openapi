use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
my $what_ever;
get '/headers' => sub {
  my $c              = shift;
  my $x_array_before = $c->req->headers->header('x-array');
  return unless $c->openapi->valid_input;

  my $args = $c->validation->output;
  $c->res->headers->header('what-ever' => ref $what_ever ? @$what_ever : $what_ever);
  $c->res->headers->header('x-bool'    => $args->{'x-bool'}) if exists $args->{'x-bool'};
  $c->render(
    openapi => {args => $args, x_array => [$x_array_before, $c->req->headers->header('x-array')]});
  },
  'dummy';

plugin OpenAPI => {url => 'data://main/headers.json'};

my $t = Test::Mojo->new;
$t->get_ok('/api/headers' => {'x-number' => 'x', 'x-string' => '123'})->status_is(400)
  ->json_is('/errors/0', {'path' => '/x-number', 'message' => 'Expected number - got string.'});

$what_ever = '123';
$t->get_ok('/api/headers' => {'x-number' => 42.3, 'x-string' => '123'})->status_is(200)
  ->header_is('what-ever', '123')
  ->json_is('', {args => {'x-number' => 42.3, 'x-string' => 123}, x_array => [undef, undef]});

# header() returns join(', ', @$headers), resulting in "42, 24" instead of "42,24",
# since Mojolicious::Plugin::OpenAPI turns 42,24 into an array. every_header() on the
# other hand will return [42, 24]. See perldoc -m Mojo::Headers
$what_ever = [qw(1 2 3)];
$t->get_ok('/api/headers' => {'x-array' => '42,24'})->status_is(200)
  ->header_is('what-ever', '1, 2, 3')
  ->json_is('', {args => {'x-array' => [42, 24]}, x_array => ['42,24', '42, 24']});

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
    }
  }
}
