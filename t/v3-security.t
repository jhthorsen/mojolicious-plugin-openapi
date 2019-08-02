use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

plan skip_all => $@ unless eval 'use YAML::XS 0.67;1';

use Mojolicious::Lite;

post '/global' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {ok => 1});
  },
  'global';

post('/fail_escape' => sub { shift->render(openapi => {ok => 1}) }, 'fail_escape');

post '/simple' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {ok => 1});
  },
  'simple';

options '/options' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {ok => 1});
  },
  'options';

post '/fail_or_pass' => sub {
  my $c = shift->openapi->valid_input or return;
  die 'Could not connect to dummy database error message' if $ENV{DUMMY_DB_ERROR};
  $c->render(openapi => {ok => 1});
  },
  'fail_or_pass';

post '/fail_and_pass' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {ok => 1});
  },
  'fail_and_pass';

post '/multiple_fail' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {ok => 1});
  },
  'multiple_fail';

post '/multiple_and_fail' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {ok => 1});
  },
  'multiple_and_fail';

post '/cache' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {ok => 1});
  },
  'cache';

post '/die' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {ok => 1});
  },
  'die';

our %checks;
plugin OpenAPI => {
  url      => 'data://main/sec.json',
  schema   => 'v3',
  security => {
    pass1 => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{pass1}++;
      $c->$cb;
    },
    pass2 => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{pass2}++;
      $c->$cb;
    },
    fail1 => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{fail1}++;

      # This deferment causes multiple_and_fail to report
      # out of order unless order is carefully maintained
      Mojo::IOLoop->next_tick(sub { $c->$cb('Failed fail1') });
    },
    fail2 => sub {
      my ($c, $def, $scopes, $cb) = @_;
      $checks{fail2}++;
      my %res = %$def;
      $res{message} = 'Failed fail2';
      $c->$cb(\%res);
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

my %security_definition
  = (description => 'fail2', in => 'header', name => 'Authorization', type => 'apiKey');

my $t = Test::Mojo->new;

{
  local %checks;
  $t->post_ok('/api/global' => json => {})->status_is(200)->json_is('/ok' => 1);
  is_deeply \%checks, {pass1 => 1}, 'expected checks occurred';
}

{
  # global does not define an options handler, so it gets the default
  # which is allowed through the security
  local %checks;
  $t->options_ok('/api/global')->status_is(200);
  is_deeply \%checks, {}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/simple' => json => {})->status_is(200)->json_is('/ok' => 1);
  is_deeply \%checks, {pass2 => 1}, 'expected checks occurred';
}

{
  # route defined with an options handler so it must use the defined security
  local %checks;
  $t->options_ok('/api/options' => json => {})->status_is(200)->json_is('/ok' => 1);
  is_deeply \%checks, {pass1 => 1}, 'expected checks occurred';
}

{
  local %checks;
  $t->post_ok('/api/fail_or_pass' => json => {})->status_is(200)->json_is('/ok' => 1);
  is_deeply \%checks, {fail1 => 1, pass1 => 1}, 'expected checks occurred';
}

{
  local $ENV{DUMMY_DB_ERROR} = 1;
  $t->post_ok('/api/fail_or_pass' => json => {})->status_is(500)
    ->json_is('/errors/0/message', 'Internal Server Error.')->json_is('/errors/0/path', '/');
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
        {message => 'Failed fail2', %security_definition},
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
        {message => 'Failed fail2', %security_definition}
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
  "openapi": "3.0.0",
  "info": { "version": "0.8", "title": "Pets" },
  "servers": [
    { "url": "http://petstore.swagger.io/api" }
  ],
  "components": {
    "responses": {
      "defaultResponse": {
        "description": "default response",
        "content": {
          "application/json": {
            "schema": {
              "type": "object",
              "properties": {
                "errors": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "message": {
                        "type": "string"
                      },
                      "path": {
                        "type": "string"
                      }
                    },
                    "required": ["message"]
                  }
                }
              },
              "required": ["errors"]
            }
          }
        }
      }
    },
    "securitySchemes": {
      "pass1": {
        "type": "apiKey",
        "name": "Authorization",
        "in": "header",
        "description": "pass1"
      },
      "pass2": {
        "type": "apiKey",
        "name": "Authorization",
        "in": "header",
        "description": "pass2"
      },
      "fail1": {
        "type": "apiKey",
        "name": "Authorization",
        "in": "header",
        "description": "fail1"
      },
      "fail2": {
        "type": "apiKey",
        "name": "Authorization",
        "in": "header",
        "description": "fail2"
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
        "description": "die"
      }
    }
  },
  "security": [{"pass1": []}],
  "paths": {
    "/global": {
      "post": {
        "x-mojo-name": "global",
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
        }
      }
    },
    "/simple": {
      "post": {
        "x-mojo-name": "simple",
        "security": [{"pass2": []}],
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
        }
      }
    },
    "/options": {
      "options": {
        "x-mojo-name": "options",
        "security": [{"pass1": []}],
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
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
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
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
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
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
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
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
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
        }
      }
    },
    "/fail_escape": {
      "post": {
        "x-mojo-name": "fail_escape",
        "security": [{"~fail/escape": []}],
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
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
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
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
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }
        },
        "responses": {
          "200": {"description": "Echo response", "content": {
            "application/json": {
              "schema": { "type": "object" }
            }
          }}
        }
      }
    }
  }
}
