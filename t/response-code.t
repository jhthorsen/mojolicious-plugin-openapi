use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
get '/info' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {x => 42}, status => $c->param('status'));
  },
  'info';

plugin OpenAPI => {url => 'data://main/spec.json', default_response => undef};

my $t = Test::Mojo->new;
$t->get_ok('/api/info')->status_is(200)->json_is('/x', 42);
$t->get_ok('/api/info?status=302')->status_is(500)
  ->json_is('/errors/0/message', 'No responses rules defined for status 302.');

done_testing;

__DATA__
@@ spec.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.1", "title" : "Test response codes" },
  "basePath" : "/api",
  "paths" : {
    "/info": {
      "get" : {
        "operationId" : "info",
        "responses" : {
          "200": {
            "description": "Info",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
