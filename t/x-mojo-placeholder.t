use Mojo::Base -strict;
use Mojo::Util 'monkey_patch';
use Test::Mojo;
use Test::More;

my $t = Test::Mojo->new(make_app());

monkey_patch 'Myapp::Controller::Pet' => one => sub {
  my $c = shift->openapi->valid_input or return;
  return $c->render(openapi => {email => $c->param('email')});
};

$t->app->plugin(OpenAPI => {url => 'data://main/echo.json'});

$t->get_ok('/api/jhthorsen@cpan.org')->status_is(200)->json_is('/email' => 'jhthorsen@cpan.org');

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
    "/{email}" : {
      "get" : {
        "x-mojo-to" : "pet#one",
        "parameters" : [
          {
            "x-mojo-placeholder": "#",
            "in": "path",
            "name": "email",
            "required": true,
            "type": "string"
          }
        ],
        "responses" : {
          "200": { "description": "Echo response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
