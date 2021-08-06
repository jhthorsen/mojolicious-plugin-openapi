use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use JSON::Validator::Schema::OpenAPIv2;

TODO: {
  todo_skip
    'At this moment in spacetime, I do not know how to suppport both a recursive schema and a recusrive data structure',
    2;

  my ($data, @errors) = ({});
  $data->{rec} = $data;

  eval {
    local $SIG{ALRM} = sub { die 'Recursion!' };
    alarm 2;
    @errors
      = JSON::Validator::Schema::Draft4->new('data://main/spec.json')->validate({top => $data});
  };
  is $@, '', 'no error';
  is_deeply(\@errors, [], 'avoided recursion');
}

note 'This part of the test checks that we don\'t go into an infite loop';
eval {
  my $validator = JSON::Validator::Schema::OpenAPIv2->new;
  $validator->data('data://main/user.json')->errors;
  $validator->data($validator->data)->errors;
};
ok !$@, 'handle $schema with recursion';

done_testing;
__DATA__
@@ spec.json
{
  "properties": {
    "top": { "$ref": "#/definitions/again" }
  },
  "definitions": {
    "again": {
      "anyOf": [
        {"type": "string"},
        {
          "type": "object",
          "properties": {
            "rec": {"$ref": "#/definitions/again"}
          }
        }
      ]
    }
  }
}
@@ user.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "User schema" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/user" : {
      "post" : {
        "operationId" : "User",
        "parameters": [{
          "name": "data",
          "in": "body",
          "required": true,
          "schema": {
            "$ref": "#/definitions/user"
            }
        }],
        "responses" : {
          "200": { "description": "response", "schema": { "type": "object" } }
        }
      }
    }
  },
  "definitions": {
    "user": {
      "type": "object",
      "properties": {
        "name": {
          "type": "string"
        },
        "siblings": {
          "type": "array",
          "items": {
            "$ref": "#/definitions/user"
          }
        }
      }
    }
  }
}
