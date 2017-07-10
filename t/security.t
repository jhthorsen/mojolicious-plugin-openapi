use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/global' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'global';

post '/simple' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'simple';

post '/fail_or_pass' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'fail_or_pass';

post '/fail_and_pass' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'fail_and_pass';

post '/multiple_fail' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'multiple_fail';

post '/multiple_and_fail' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'multiple_and_fail';

post '/cache' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'cache';

post '/die' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->reply->openapi(200 => {ok => 1});
  },
  'die';

our %checks;
plugin OpenAPI => {
  url      => 'data://main/sec.json',
  security => {
    pass1 => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{pass1}++;
      $c->$cb();
    },
    pass2 => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{pass2}++;
      $c->$cb();
    },
    fail1 => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{fail1}++;

      # this deferrment causes multiple_and_fail to report
      # out of order unless order is carefully maintained
      Mojo::IOLoop->next_tick(sub { $c->$cb('Failed fail1') });
    },
    fail2 => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{fail2}++;
      $c->$cb('Failed fail2');
    },
    '~fail/escape' => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{'~fail/escape'}++;
      $c->$cb('Failed ~fail/escape');
    },
    die => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{die}++;
      die 'Argh!';
    },
  },
};

my $t = Test::Mojo->new;
{
  local %checks;
  $t->post_ok('/api/global' => json => {})->status_is(200)->json_is('/ok' => 1);
  is_deeply \%checks, {pass1 => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/simple' => json => {})->status_is(200)->json_is('/ok' => 1);
  is_deeply \%checks, {pass2 => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/fail_or_pass' => json => {})->status_is(200)->json_is('/ok' => 1);
  is_deeply \%checks, {fail1 => 1, pass1 => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/fail_and_pass' => json => {})->status_is(401)
    ->json_is({errors => [{message => 'Failed fail1', path => '/security/0/fail1'}]});
  is_deeply \%checks, {fail1 => 1, pass1 => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/multiple_fail' => json => {})->status_is(401)->json_is(
    {
      errors => [
        {message => 'Failed fail1', path => '/security/0/fail1'},
        {message => 'Failed fail2', path => '/security/1/fail2'}
      ]
    }
  );
  is_deeply \%checks, {fail1 => 1, fail2 => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/multiple_and_fail' => json => {})->status_is(401)->json_is(
    {
      errors => [
        {message => 'Failed fail1', path => '/security/0/fail1'},
        {message => 'Failed fail2', path => '/security/0/fail2'}
      ]
    }
  );
  is_deeply \%checks, {fail1 => 1, fail2 => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/fail_escape' => json => {})->status_is(401)
    ->json_is(
    {errors => [{message => 'Failed ~fail/escape', path => '/security/0/~0fail~1escape'}]});
  is_deeply \%checks, {'~fail/escape' => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/cache' => json => {})->status_is(200)->json_is('/ok' => 1);
  is_deeply \%checks, {fail1 => 1, pass1 => 1, pass2 => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/die' => json => {})->status_is(500)->json_has('/errors/0/message');
  is_deeply \%checks, {die => 1}, 'expected checks occurred';
}

done_testing;

__DATA__
@@ sec.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Pets" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "securityDefinitions": {
    "pass1": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "dummy"
    },
    "pass2": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "dummy"
    },
    "fail1": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "dummy"
    },
    "fail2": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "dummy"
    },
    "~fail/escape": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "dummy"
    },
    "die": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header",
      "description": "dummy"
    }
  },
  "security": [{"pass1": []}],
  "paths": {
    "/global": {
      "post": {
        "x-mojo-name": "global",
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    },
    "/simple": {
      "post": {
        "x-mojo-name": "simple",
        "security": [{"pass2": []}],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    },
    "/fail_or_pass": {
      "post": {
        "x-mojo-name": "fail_or_pass",
        "security": [
          {"fail1": []},
          {"pass1": []}
        ],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    },
    "/fail_and_pass": {
      "post": {
        "x-mojo-name": "fail_and_pass",
        "security": [
          {
            "fail1": [],
            "pass1": []
          }
        ],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    },
    "/multiple_fail": {
      "post": {
        "x-mojo-name": "multiple_fail",
        "security": [
          { "fail1": [] },
          { "fail2": [] }
        ],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    },
    "/multiple_and_fail": {
      "post": {
        "x-mojo-name": "multiple_and_fail",
        "security": [
          {
            "fail1": [],
            "fail2": [] 
          }
        ],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    },
    "/fail_escape": {
      "post": {
        "x-mojo-name": "fail_escape",
        "security": [{"~fail/escape": []}],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    },
    "/cache": {
      "post": {
        "x-mojo-name": "cache",
        "security": [
          {
            "fail1": [],
            "pass1": []
          },
          {
            "pass1": [],
            "pass2": []
          }
        ],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    },
    "/die": {
      "post": {
        "x-mojo-name": "die",
        "security": [
          {"die": []},
          {"pass1": []}
        ],
        "parameters": [
          { "in": "body", "name": "body", "schema": { "type": "object" } }
        ],
        "responses": {
          "200": {"description": "Echo response", "schema": { "type": "object" }},
          "401": {"description": "Sorry mate", "schema": { "$ref": "#/definitions/Error" }}
        }
      }
    }
  },
  "definitions": {
    "Error": {
      "type": "object",
      "properties": {
        "errors": {
          "type": "array",
          "items": {
            "required": ["message"],
            "properties": {
              "message": { "type": "string", "description": "Human readable description of the error" },
              "path": { "type": "string", "description": "JSON pointer to the input data where the error occur" }
            }
          }
        }
      }
    }
  }
}
