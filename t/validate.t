use Mojo::Base -strict;
use Test::More;
use Mojolicious::Lite;

eval { plugin OpenAPI => {url => 'data://main/invalid.json'} };
like $@, qr{Invalid Open API spec}, 'invalid';
done_testing;

__DATA__
@@ invalid.json
{
  "swagger" : "2.0",
  "info" : { "version": "0.8", "title" : "Test auto response" }
}
