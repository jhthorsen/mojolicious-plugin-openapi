use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious;

sub VERSION {1.42}

{
  my $app = Mojolicious->new;
  my $under = $app->routes->under('/my-api' => sub {1});
  add_routes($app, 'cool_spec_path');
  $app->plugin(
    OpenAPI => {route => $under, url => 'data://main/reply.json', version_from_class => 'main'});

  my $t = Test::Mojo->new($app);
  $t->get_ok('/url')->status_is(200)->content_is('/my-api');
  $t->get_ok('/my-api')->status_is(200)->json_is('/basePath', '/my-api')
    ->json_unlike('/host', qr{api\.thorsen\.pm})->json_like('/host', qr{.:\d+$})
    ->json_is('/info/version', 1.42);
}

{
  my $app = Mojolicious->new;
  add_routes($app, 'my.cool.api');
  $app->plugin(
    OpenAPI => {
      spec_route_name    => 'my.cool.api',
      url                => 'data://main/reply.json',
      version_from_class => 'main'
    }
  );

  my $t = Test::Mojo->new($app);
  $t->get_ok('/url')->status_is(200)->content_is('/api');
  $t->get_ok('/api')->status_is(200)->json_is('/info/version', 1.42);
  $t->get_ok('/api.html')->status_is(200)->text_is('title', 'Test reply spec')
    ->text_is('h1#title', 'Test reply spec')->text_is('h3#op-post-pets a', 'POST /api/pets');

  $t->get_ok('/api/docs')->status_is(200)->json_is('/info/version', 1.42)
    ->json_is('/basePath', '/api');
  $t->get_ok('/api/docs.html')->status_is(200)->text_is('h3#op-post-pets a', 'POST /api/pets');

SKIP: {
    skip 'Text::Markdown is not installed', 2 unless eval 'require Text::Markdown;1';
    $t->text_is('div.spec-description p',    'pet response')
      ->text_is('div.spec-description code', 'markdown');
  }
}

sub add_routes {
  my ($app, $name) = @_;
  $app->routes->get('/url' => sub { $_[0]->render(text => $_[0]->url_for($name)) });
  $app->routes->get('/docs')->to(cb => sub { shift->openapi->render_spec })->name('docs');
  $app->routes->post('/pets')->to(cb => sub { shift->render(openapi => {}) })->name('addPet');
  return $app;
}

done_testing;

__DATA__
@@ reply.json
{
  "swagger": "2.0",
  "info": { "version": "0", "title": "Test reply spec" },
  "consumes": [ "application/json" ],
  "produces": [ "application/json" ],
  "x-mojo-name": "cool_spec_path",
  "schemes": [ "http" ],
  "host": "api.thorsen.pm",
  "basePath": "/api",
  "paths": {
    "/docs": {
      "get": {
        "operationId": "docs",
        "responses": {
          "200": {
            "description": "pet response\n\nwith `markdown` content",
            "schema": { "type": "object" }
          }
        }
      }
    },
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
