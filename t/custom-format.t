use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
my $what_ever;
get '/cf' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => $c->validation->output);
  },
  'custom_format';

my $oap = plugin OpenAPI => {url => 'data://main/cf.json'};

$oap->validator->formats->{need_to_be_x} = sub { $_[0] eq 'x' ? undef : 'Not x.' };

my $t = Test::Mojo->new;
$t->get_ok('/api/cf' => json => {str => 'x'})->status_is(200)->content_like(qr{"str":"x"});
$t->get_ok('/api/cf' => json => {str => 'y'})->status_is(400)->content_like(qr{"errors"});

done_testing;

__DATA__
@@ cf.json
{
  "swagger" : "2.0",
  "info" : { "version": "9.1", "title" : "Test API for custom formats" },
  "consumes" : [ "application/json" ],
  "produces" : [ "application/json" ],
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/cf" : {
      "get" : {
        "x-mojo-name": "custom_format",
        "parameters" : [
          {"in": "body", "name": "body", "schema": {"$ref": "Body"}}
        ],
        "responses" : {
          "200" : {
            "description": "this is required",
            "schema": { "type" : "object" }
          }
        }
      }
    }
  },
  "definitions": {
    "Body": {
      "required": ["str"],
      "type": "object",
      "properties": {
        "str": {
          "type": "string",
          "format": "need_to_be_x"
        }
      }
    }
  }
}
