use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
get '/cors/simple' => sub {
  my $c = shift->openapi->cors_simple('main::cors_simple')->openapi->valid_input or return;
  $c->render(json => {cors => 'simple', origin => $c->stash('origin')});
  },
  'CorsSimple';

plugin OpenAPI => {url => 'data://main/cors.json'};

my $t = Test::Mojo->new;

$t->get_ok('/api/cors/simple', {'Content-Type' => 'text/plain', Origin => 'http://bar.example'})
  ->status_is(400)->json_is('/errors/0/message', 'Invalid CORS request.');

$t->get_ok('/api/cors/simple', {'Content-Type' => 'text/plain', Origin => 'http://foo.example'})
  ->status_is(200)->json_is('/cors', 'simple')->json_is('/origin', 'http://foo.example');

done_testing;

sub cors_simple {
  my ($c, $args) = @_;

  if ($args->{origin} eq 'http://foo.example') {
    $c->stash(origin => $args->{origin});
    $c->res->headers->header('Access-Control-Allow-Origin' => $args->{origin});
  }
}

__DATA__
@@ cors.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test cors response" },
  "basePath" : "/api",
  "paths" : {
    "/cors/simple" : {
      "get" : {
        "operationId" : "CorsSimple",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": {
            "description": "Cors simple response.",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
