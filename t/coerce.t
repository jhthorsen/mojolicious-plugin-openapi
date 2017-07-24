use Mojo::Base -strict;
use Mojolicious;
use Test::Mojo;
use Test::More;

my $coerced = Test::Mojo->new(Mojolicious->new);
$coerced->app->routes->get('/user' => \&action_user)->name('user');
$coerced->app->plugin(OpenAPI => {url => 'data://main/user.json'});
$coerced->get_ok('/api/user')->status_is(200)->json_is('/age', 34);

my $strict = Test::Mojo->new(Mojolicious->new);
$strict->app->routes->get('/user' => \&action_user)->name('user');
$strict->app->plugin(OpenAPI => {url => 'data://main/user.json', coerce => {}});
$strict->get_ok('/api/user')->status_is(500)->json_has('/errors');

sub action_user {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {age => '34'});    # '34' is not an integer
}

done_testing;

__DATA__
@@ user.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Pets" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/user" : {
      "get" : {
        "x-mojo-name" : "user",
        "responses" : {
          "200": {
            "description": "User",
            "schema": {
              "type": "object",
              "properties": {
                "age": { "type": "integer"}
              }
            }
          }
        }
      }
    }
  }
}
