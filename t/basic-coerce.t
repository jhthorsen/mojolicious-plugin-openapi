use Mojo::Base -strict;
use Mojolicious;
use Test::Mojo;
use Test::More;

my $coerced = t();
$coerced->get_ok('/api/user')->status_is(200)->json_is('/age', 34);

my $strict = t(coerce => {});
$strict->get_ok('/api/user')->status_is(500)->json_has('/errors');

sub t {
  my $t = Test::Mojo->new(Mojolicious->new);
  $t->app->routes->get(
    '/user' => sub {
      my $c = shift->openapi->valid_input or return;
      $c->render(openapi => {age => '34'});    # '34' is not an integer
    }
  )->name('user');
  $t->app->plugin(OpenAPI => {url => 'data://main/user.json', @_});
  $t;
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
