use Mojo::Base -strict;
use Mojo::File 'path';
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

subtest 'check that we can load swagger.yaml' => sub {
  eval {
    plugin OpenAPI => {url => path(__FILE__)->dirname->child(qw(spec swagger swagger.yaml))};
    ok 1, 'spec loaded';
  } or do {
    diag $@;
    ok 0, 'spec loaded';
  };
};

my $t = Test::Mojo->new;
subtest 'check that we can add DefaultResponse to paths/ref.yaml' => sub {
  $t->get_ok('/swagger.json')->status_is(200)
    ->json_is('/paths/~1external~1ref/get/responses/200/description', 'Ref response')
    ->json_is('/paths/~1external~1ref/get/responses/500/description', 'Default response.');
};

done_testing;
