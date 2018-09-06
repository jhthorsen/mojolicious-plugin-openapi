use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

#============================================================================
package MyApp;
use Mojo::Base 'Mojolicious';

sub startup {
  my $app = shift;
  $app->plugin(OpenAPI => {url => "data://main/dummy.json"});
}

#============================================================================
package MyApp::Controller::Dummy;
use Mojo::Base 'Mojolicious::Controller';

sub dummy {
  my $c = shift->openapi->valid_input or return;

  $c->render(
    openapi => { dummy => 'ok' }
  );
}

#============================================================================
package main;
my $t = Test::Mojo->new('MyApp');

$t->post_ok('/api/dummy')->status_is(404);

$t->post_ok('/api/dummy', {'X-Secret' => 'Foo'})
    ->status_is(200)
    ->json_is('/dummy', 'ok');

done_testing;

__DATA__
@@ dummy.json
{
  "swagger": "2.0",
  "info": { "version": "0.1", "title": "x-mojo-over test" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "paths": {
    "/dummy": {
      "post": {
        "x-mojo-to": "dummy#dummy",
        "x-mojo-over": [ "headers", { "X-Secret": "Foo" } ],
        "responses": {
          "200": {
            "description": "Dummy response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
