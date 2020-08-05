use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/securitytest' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => {message => "ok"}, status => 200);
  },
  'securitytest';

plugin OpenAPI => {
  url      => 'data://main/sec.yaml',
  schema   => 'v3',
  security => {
    api_key => sub {
      my ($self, $definition, $scopes, $cb) = @_;
      my $apikey  = $self->req->headers->header('apikey');
      my $apiuser = $self->req->headers->header('apiuser');
      return $self->$cb("apikey/apiuser missing") unless $apikey and $apiuser;
      if ($apikey eq "authenticated" and $apiuser eq "authenticated") {
        $self->stash(status => 403);
        return $self->$cb("Permission denied");
      }
      if ($apikey eq "authorized" and $apiuser eq "authorized") {
        return $self->$cb();
      }
      return $self->$cb("Unauthorized");
    },
  },
};

my $t = Test::Mojo->new;

$t->get_ok('/api/securitytest' => {apikey => 'authorized', apiuser => 'authorized'})->status_is(200);

$t->get_ok('/api/securitytest' => {apikey => 'authenticated', apiuser => 'authenticated'})->status_is(403);

$t->get_ok('/api/securitytest' => {apikey => 'unknown', apiuser => 'unknown'})->status_is(401);

$t->get_ok('/api/securitytest')->status_is(401);


done_testing;

__DATA__
@@ sec.yaml
openapi: 3.0.2
info:
  title: CSApi
  version: "1.0"
  description: API test
servers:
- url: /api
security:
  - api_key: []
    api_user: []
paths:
  /securitytest:
    get:
      x-mojo-name: securitytest
      summary: test security
      description: >
        Will grant authenticated and authorized apikeys access
      responses:
        200:
          $ref: "#/components/responses/200_OK_message"
        403:
          $ref: "#/components/responses/403_Forbidden"
components:
  securitySchemes:
    api_key:
      type: apiKey
      description: API key to authorize requests.
      name: apikey
      in: header
    api_user:
      type: apiKey
      description: Username going with that key.
      name: apiuser
      in: header
  schemas:
    Error:
      type: object
      required:
        - errors
      properties:
        errors:
          type: array
          items:
            type: object
            required:
              - message
            properties:
              message:
                type: string
              path:
                type: string
  responses:
    200_OK_message:
      description: OK
      content:
        application/json:
          schema:
            type: object
            required:
              - message
            properties:
              message:
                type: string
              path:
                type: string
    403_Forbidden:
      description: Insufficient priviliges
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/Error"
    DefaultResponse:
      description: Default Response
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/Error"
