use Mojo::Base -strict;
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
post '/echo' => sub {
  my ($c, $data, $cb) = @_;
  $c->$cb({body => $data->{body}}, 200);
  },
  'echo';

get '/' => {text => 'test123'};

plugin OpenAPI => {url => 'data://main/echo.json'};

my $t = Test::Mojo->new;

hook around_action => sub {
  my ($next, $c, $action, $last) = @_;

  return $next->() unless $last;
  return $next->() unless $c->openapi->spec;
  return           unless $c->openapi->valid_input;

  my $cb = sub {
    my ($c, $data, $code) = @_;
    $c->reply->openapi($code => $data);
  };

  return $c->$action($c->validation->output, $cb);
};

$t->get_ok('/')->status_is(200)->content_is('test123');
$t->post_ok('/api/echo' => json => {foo => 123})->status_is(200)->json_is('/body/foo' => 123);

done_testing;

__DATA__
@@ echo.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Pets" },
  "schemes" : [ "http" ],
  "basePath" : "/api",
  "paths" : {
    "/echo" : {
      "post" : {
        "x-mojo-name" : "echo",
        "parameters" : [
          { "in": "body", "name": "body", "schema": { "type" : "object" } }
        ],
        "responses" : {
          "200": {
            "description": "Echo response",
            "schema": { "type": "object" }
          }
        }
      }
    }
  }
}
