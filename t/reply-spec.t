use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious;

{
  my $app = Mojolicious->new;
  my $under = $app->routes->under('/my-api' => sub {1});
  $app->plugin(OpenAPI => {route => $under, url => 'data://main/reply.json'});
  add_url_route($app, 'cool_spec_path');

  my $t = Test::Mojo->new($app);
  $t->get_ok('/url')->status_is(200)->content_is('/my-api');
  $t->get_ok('/my-api')->status_is(200)->json_is('/basePath', '/my-api')
    ->json_unlike('/host', qr{api\.thorsen\.pm})->json_like('/host', qr{.:\d+$})
    ->json_is('/info/version', 0.8);
}

{
  my $app = Mojolicious->new;
  $app->plugin(OpenAPI => {spec_route_name => 'my.cool.api', url => 'data://main/reply.json'});
  add_url_route($app, 'my.cool.api');

  my $t = Test::Mojo->new($app);
  $t->get_ok('/url')->status_is(200)->content_is('/api');
  $t->get_ok('/api')->status_is(200)->json_is('/info/version', 0.8);
}

sub add_url_route {
  my ($app, $name) = @_;
  $app->routes->get('/url' => sub { $_[0]->render(text => $_[0]->url_for($name)) });
}

done_testing;

__DATA__
@@ reply.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Test reply spec" },
  "consumes": [ "application/json" ],
  "produces": [ "application/json" ],
  "x-mojo-name": "cool_spec_path",
  "schemes": [ "http" ],
  "host": "api.thorsen.pm",
  "basePath": "/api",
  "paths": {
    "/pets": {
      "post": {
        "operationId": "addPet",
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {
            "description": "pet response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
