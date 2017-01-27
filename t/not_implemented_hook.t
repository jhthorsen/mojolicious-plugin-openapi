use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

plugin OpenAPI => {url => 'data://main/emulation.json',};

my $t = Test::Mojo->new;

$t->app->helper(
  'openapi.not_implemented' => sub {
    my ($c) = @_;

    my $spec = $c->openapi->spec;
    is($spec->{operationId}, 'dig', 'not_implemented got spec');

    return {json => [{status => "passed"}], status => 201};
  }
);

$t->post_ok('/api/emulate')->status_is(201)->json_is([{status => "passed"}]);

done_testing;

__DATA__
@@ emulation.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test emulation" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/emulate" : {
      "post" : {
        "operationId" : "dig",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": {
            "description": "response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
