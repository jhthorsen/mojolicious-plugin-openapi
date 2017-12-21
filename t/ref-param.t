use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

get '/test' => sub {
  my $c = shift->openapi->valid_input or return;
  my $params = $c->validation->output;
use Data::Dumper; $Data::Dumper::Sortkeys = $Data::Dumper::Indent = $Data::Dumper::Terse = 1; diag Dumper $c->openapi->spec('');
  $c->render(status => 200, openapi => $params->{pcversion});
  },
  'File';

plugin OpenAPI => {url => 'data://main/file.yaml'};

my $t = Test::Mojo->new;

$t->get_ok('/api/test')->status_is(200)->content_is('"10.1.0"');

done_testing;

__DATA__
@@ file.yaml
swagger: '2.0'
info:
  title: Test defaults
  version: 1
schemes:
  - http
basePath: /api
paths:
  /test:
    get:
      operationId: "File"
      parameters:
        - $ref: '#/parameters/PCVersion'
      responses:
        200:
          description: thing
          schema:
            type: string
parameters:
  PCVersion:
    name: pcversion
    type: string
    in: query
    description: version of commands which will run on backend
    default: 10.1.0
    enum:
      - 9.6.1
      - 10.1.0
