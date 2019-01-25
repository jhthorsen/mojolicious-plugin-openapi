use Mojo::Base -strict;
use Mojo::JSON 'true';
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
get(
  '/no-default-options/:id' => sub { $_[0]->render(openapi => {id => $_[0]->stash('id')}) },
  'Dummy'
);
options(
  '/perl/no-default-options/:id' => sub { $_[0]->render(json => {options => $_[0]->stash('id')}) });
post('/user' => sub { shift->render(openapi => {}) }, 'User');
my $obj = plugin OpenAPI => {route => app->routes->any('/one'), url => 'data://main/one.json'};
plugin OpenAPI => {default_response_name => 'DefErr', url => 'data://main/two.json'};

plugin OpenAPI => {
  default_response_codes => [],
  spec                   => {
    swagger  => '2.0',
    info     => {version => '0.8', title => 'Test schema in perl'},
    schemes  => ['http'],
    basePath => '/perl',
    paths    => {
      '/no-default-options/{id}' => {
        get => {
          operationId => 'Dummy',
          parameters  => [{in => 'path', name => 'id', type => 'string', required => true}],
          responses   => {200 => {description => 'response', schema => {type => 'object'}}}
        }
      },
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
$t->get_ok('/one')->status_is(200)
  ->json_is('/definitions/DefaultResponse/properties/errors/type', 'array')
  ->json_is('/info/title',                                         'Test schema one');

$t->options_ok('/one/user?method=post')->status_is(200)
  ->json_is('/responses/200/description', 'ok')
  ->json_is('/responses/400/description', 'Default response.')
  ->json_is('/responses/400/schema/$ref', '#/definitions/DefaultResponse')
  ->json_is('/responses/500/description', 'err');

$t->get_ok('/two')->status_is(200)->json_is('/definitions/DefaultResponse', undef)
  ->json_is('/definitions/DefErr/required', [qw(errors something_else)])
  ->json_is('/info/title', 'Test schema two');
$t->options_ok('/two/user?method=post')->status_is(200)
  ->json_is('/responses/400/schema/$ref',     '#/definitions/DefErr')
  ->json_is('/responses/default/description', 'whatever');

$t->get_ok('/perl')->status_is(200)->json_is('/info/title', 'Test schema in perl');
$t->options_ok('/perl/user?method=post')->status_is(200)
  ->json_is('/responses/500/description', undef);

note 'Override options';
$t->get_ok('/perl/no-default-options/42')->status_is(200)->json_is('/id', 42);
$t->options_ok('/perl/no-default-options/42')->status_is(200)->json_is('/options', 42);

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
          "200": { "description": "ok", "schema": { "type": "object" } },
          "500": { "description": "err", "schema": { "type": "object" } }
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
  "basePath" : "/two",
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
  },
  "definitions": {
    "DefErr": {
      "type": "object",
      "required": ["errors", "something_else"]
    }
  }
}
