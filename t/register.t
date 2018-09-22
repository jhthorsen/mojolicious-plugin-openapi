use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post('/user' => sub { shift->render(openapi => {}) }, 'User');
my $obj = plugin OpenAPI => {route => app->routes->any('/one'), url => 'data://main/one.json'};
plugin OpenAPI => {route => app->routes->any('/two'), url => 'data://main/two.json'};

plugin OpenAPI => {
  default_response => undef,
  spec             => {
    swagger  => '2.0',
    info     => {version => '0.8', title => 'Test schema in perl'},
    schemes  => ['http'],
    basePath => '/perl',
    paths    => {
      '/user' => {
        post => {
          operationId => 'User',
          responses   => {200 => {description => 'response', schema => {type => 'object'}}}
        }
      }
    }
  }
};

ok $obj->route->find('cool_api'), 'found api endpoint';
isa_ok($obj->route,     'Mojolicious::Routes::Route');
isa_ok($obj->validator, 'JSON::Validator::OpenAPI::Mojolicious');

my $t = Test::Mojo->new;
$t->get_ok('/one')->status_is(200)->json_is('/info/title', 'Test schema one');
$t->get_ok('/two')->status_is(200)->json_is('/info/title', 'Test schema two');
$t->get_ok('/perl')->status_is(200)->json_is('/info/title', 'Test schema in perl');

$t->options_ok('/one/user?method=post')->status_is(200)
  ->json_is('/responses/default/description', 'Default response.');

$t->options_ok('/two/user?method=post')->status_is(200)
  ->json_is('/responses/default/description', 'whatever');

$t->options_ok('/perl/user?method=post')->status_is(200)
  ->json_is('/responses/default/description', undef);

done_testing;

__DATA__
@@ one.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test schema one" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "x-mojo-name": "cool_api",
  "paths" : {
    "/user" : {
      "post" : {
        "operationId" : "User",
        "responses" : {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    }
  }
}
@@ two.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test schema two" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/user" : {
      "post" : {
        "operationId" : "User",
        "responses" : {
          "200": { "description": "response", "schema": { "type": "object" } },
          "default": { "description": "whatever", "schema": { "type": "array" } }
        }
      }
    }
  }
}
