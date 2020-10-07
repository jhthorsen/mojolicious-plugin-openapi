use Mojo::Base -strict;
use Mojolicious;
use Test::Mojo;
use Test::More;

my $coerced = t();
$coerced->post_ok('/api/user')->status_is(200)->json_is('/age', 34);
$coerced->post_ok('/api/user', json => [{}])->status_is(400)
  ->json_is('/errors/0/message', 'Expected object - got array.');

my $strict = t(coerce => {});
$strict->post_ok('/api/user')->status_is(500)->json_has('/errors');

sub t {
  my $t = Test::Mojo->new(Mojolicious->new);
  $t->app->routes->post(
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
      "post" : {
        "x-mojo-name" : "user",
        "parameters": [
          {"in": "body", "name": "body", "schema": {"type": "object"}}
        ],
        "responses" : {
          "200": {
            "description": "User",
            "schema": { "properties": { "age": { "type": "integer"} } }
          }
        }
      }
    }
  }
}
