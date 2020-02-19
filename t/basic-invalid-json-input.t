use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/invalid' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {x => 42});
  },
  'invalid';

plugin OpenAPI => {url => 'data://main/spec.json', default_response => undef};

my $t = Test::Mojo->new;
$t->post_ok('/api/invalid')->status_is(400)->content_like(qr{got null});

done_testing;

__DATA__
@@ spec.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.1", "title" : "Test response codes" },
  "basePath" : "/api",
  "paths" : {
    "/invalid": {
      "post" : {
        "operationId" : "invalid",
        "parameters": [
          {"in": "body", "name": "body", "required": true, "schema": {"type": "object"}}
        ],
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
