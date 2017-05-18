use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

my $code;
my $age = 43;
get '/user' => sub {
  my $c = shift->openapi->valid_input or return;
  die 'no age!' unless defined $age;
  $c->render(openapi => {age => $age});
  },
  'get_user';

post '/user' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {age => $c->param('age')});
  },
  'create_user';

plugin OpenAPI => {renderer => \&renderer, url => 'data://main/user.json'};

my $t = Test::Mojo->new;
$t->get_ok('/api/user')->status_is(200)->json_is('/age', 43)->json_is('/t', $^T);

$age = 'invalid output!';
$t->get_ok('/api/user')->status_is(500)->json_is('/messages/0/path', '/age')->json_is('/t', $^T);

$t->get_ok('/api/user')->status_is(500)->json_is('/messages/0/path', '/age')->json_is('/t', $^T);

$t->post_ok('/api/user', form => {age => 'invalid input'})->status_is(400)
  ->json_is('/messages/0/path', '/age')->json_is('/t', $^T);

undef $age;
$t->get_ok('/api/user')->status_is(500)->json_is('/messages/0/message', 'Internal server error.')
  ->json_is('/t', $^T);

$t->delete_ok('/api/user')->status_is(501)->json_is('/messages/0/message', 'Not implemented.')
  ->json_is('/t', $^T);

$t->get_ok('/api/nope')->status_is(404)->json_is('/messages/0/message', 'Not found.')
  ->json_is('/t', $^T);

$code = 200;
$t->delete_ok('/api/user')->status_is(200)->json_is('/messages/0/message', 'Not implemented.')
  ->json_is('/t', $^T);

done_testing;

sub renderer {
  my ($c, $data) = @_;

  $data->{messages} = delete $data->{errors} if $data->{errors};
  $data->{t} = $^T if ref $data eq 'HASH';

  $c->stash(status => $code) if $code;

  return Mojo::JSON::encode_json($data);
}

__DATA__
@@ user.json
{
  "swagger": "2.0",
  "info": { "version": "0.8", "title": "Pets" },
  "schemes": [ "http" ],
  "basePath": "/api",
  "paths": {
    "/user": {
      "delete": {
        "operationId": "todo",
        "responses": {
          "200": { "description": "TODO", "schema": { "type": "object" } }
        }
      },
      "get": {
        "x-mojo-name": "get_user",
        "responses": {
          "200": {
            "description": "User",
            "schema": {
              "type": "object",
              "properties": { "age": { "type": "integer"} }
            }
          },
          "500": { "description": "Error", "schema": { "type": "object" } }
        }
      },
      "post": {
        "x-mojo-name": "create_user",
        "parameters": [
          { "in": "formData", "name": "age", "type": "integer" }
        ],
        "responses": {
          "400": { "description": "Error", "schema": { "type": "object" } }
        }
      }
    }
  }
}
