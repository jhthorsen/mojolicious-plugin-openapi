use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
get '/spec' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(json => {info => $c->openapi->spec('/info'), op_spec => $c->openapi->spec});
  },
  'Spec';

plugin OpenAPI => {url => 'data://main/spec.json'};

my $t = Test::Mojo->new;

$t->get_ok('/api/spec')->status_is(200)
  ->json_is('/op_spec/responses/200/description', 'Spec response.')
  ->json_is('/info/version',                      '0.8');

done_testing;

__DATA__
@@ spec.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test spec response" },
  "basePath" : "/api",
  "paths" : {
    "/spec" : {
      "get" : {
        "operationId" : "Spec",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": {
            "description": "Spec response.",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
