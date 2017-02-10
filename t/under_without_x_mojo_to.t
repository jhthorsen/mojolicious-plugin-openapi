use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

my $underRouteInvoked=0; #How many times the under-route is invoked?

make_app();
make_under_controller();
make_controller();

my $t = Test::Mojo->new('Myapp');

$t->get_ok('/api/pets')->status_is(200)->json_is('/0', 'cat1');
is($underRouteInvoked, 1, 'Under-route invoked only once');


done_testing;

sub make_app {
  eval <<'HERE' or die $@;
  package Myapp;
  use Mojo::Base "Mojolicious";

  sub startup {
    my $app = shift;
    $app->plugin("OpenAPI" => {
      url => "data://main/myapi.json",
      route => $app->routes->under("/api")->to('auth#under'),
    });
  }

  $ENV{"Myapp.pm"} = 1;
HERE
}

sub make_under_controller {
  eval <<'HERE' or die $@;
  package Myapp::Controller::Auth;
  use Mojo::Base "Mojolicious::Controller";

  sub under {
    my $c = shift;
    $underRouteInvoked++;
    $c->render(text => 'Hello under-route!');
  }

  $ENV{"Myapp/Controller/Auth.pm"} = 1;
HERE
}

sub make_controller {
  eval <<'HERE' or die $@;
  package Myapp::Controller::Pet;
  use Mojo::Base "Mojolicious::Controller";

  sub list {
    my $c = shift->openapi->valid_input or return;

    $c->render(openapi => ['cat1', 'cat2']);
  }

  $ENV{"Myapp/Controller/Pet.pm"} = 1;
HERE
}

__DATA__
@@ myapi.json
{
  "swagger": "2.0",
  "info": { "version": "1.0", "title": "Some awesome API" },
  "basePath": "/api",
  "paths": {
    "/pets": {
      "get": {
        "summary": "Finds pets in the system",
        "responses": {
          "200": {
            "description": "Pet response"
          },
          "default": {
            "description": "Unexpected error",
            "schema": { "$ref": "http://git.io/vcKD4#" }
          }
        }
      }
    }
  }
}
