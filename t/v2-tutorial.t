use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

make_app();
make_controller();

my $t = Test::Mojo->new('Myapp');

$t->get_ok('/api')->status_is(200)->json_is('/info/title', 'Some awesome API');
$t->get_ok('/api/pets')->status_is(200)->json_is('/pets/0/name', 'kit-e-cat');

done_testing;

sub make_app {
  eval <<'HERE' or die $@;
  package Myapp;
  use Mojo::Base "Mojolicious";

  sub startup {
    my $app = shift;
    $app->plugin("OpenAPI" => {url => "data://main/myapi.json"});
  }

  $ENV{"Myapp.pm"} = 1;
HERE
}

sub make_controller {
  eval <<'HERE' or die $@;
  package Myapp::Controller::Pet;
  use Mojo::Base "Mojolicious::Controller";

  sub list {

    # Do not continue on invalid input and render a default 400
    # error document.
    my $c = shift->openapi->valid_input or return;

    # $c->openapi->valid_input copies valid data to validation object,
    # and the normal Mojolicious api works as well.
    my $input = $c->validation->output;
    my $age   = $c->param("age"); # same as $input->{age}
    my $body  = $c->req->json;    # same as $input->{body}

    # $output will be validated by the OpenAPI spec before rendered
    my $output = {pets => [{name => "kit-e-cat"}]};
    $c->render(openapi => $output);
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
        "operationId": "getPets",
        "x-mojo-name": "get_pets",
        "x-mojo-to": "pet#list",
        "summary": "Finds pets in the system",
        "parameters": [
          {"in": "body", "name": "body", "schema": {"type": "object"}},
          {"in": "query", "name": "age", "type": "integer"}
        ],
        "responses": {
          "200": {
            "description": "Pet response",
            "schema": {
              "type": "object",
              "properties": {
                "pets": {
                  "type": "array",
                  "items": { "type": "object" }
                }
              }
            }
          }
        }
      }
    }
  }
}
