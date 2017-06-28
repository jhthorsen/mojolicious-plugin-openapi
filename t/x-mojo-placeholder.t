use Mojo::Base -strict;
use Mojo::Util 'monkey_patch';
use Test::Mojo;
use Test::More;

my $t = Test::Mojo->new(make_app());

monkey_patch 'Myapp::Controller::Pet' => one => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {username => $c->stash('username')});
};

$t->app->plugin(OpenAPI => {url => 'data://main/echo.json'});

$t->get_ok('/api/jhthorsen@cpan.org')->status_is(200)->json_is('/username' => 'jhthorsen@cpan.org');
$t->options_ok('/api/jhthorsen@cpan.org?method=get')->status_is(200)
  ->json_is('/parameters/0/x-mojo-placeholder' => '#')->json_is('/parameters/0/in' => 'path')
  ->json_is('/parameters/0/name' => 'username')->json_is('/parameters/1/in' => 'query')
  ->json_is('/parameters/1/name' => 'fields')->json_hasnt('/x-all-parameters');

# make sure rendering doesn't croak when "parameters" are under a path
# Not a HASH reference at template mojolicious/plugin/openapi/resource.html.ep
$t->get_ok('/api.html')->status_is(200);

done_testing;

sub make_app {
  eval <<"HERE";
package Myapp;
use Mojo::Base 'Mojolicious';
sub startup { }
1;
package Myapp::Controller::Pet;
use Mojo::Base 'Mojolicious::Controller';
1;
HERE
  return Myapp->new;
}

__DATA__
@@ echo.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Pets" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/{username}" : {
      "parameters": [
        { "x-mojo-placeholder": "#", "in": "path", "name": "username", "required": true, "type": "string" }
      ],
      "get" : {
        "x-mojo-to" : "pet#one",
        "parameters" : [
          { "in": "query", "name": "fields", "type": "string" }
        ],
        "responses" : {
          "200": { "description": "Echo response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
