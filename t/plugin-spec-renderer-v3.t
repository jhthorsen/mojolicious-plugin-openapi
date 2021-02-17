use Mojo::Base -strict;
use Mojo::File 'path';
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;
plugin OpenAPI => {url => path(__FILE__)->dirname->child(qw(spec v3-petstore.json))};

my $t = Test::Mojo->new;
$t->get_ok('/v1')->status_is(200)->json_like('/servers/0/url', qr{:\d+/v1$});
$t->get_ok('/v1.json')->status_is(200)->json_like('/servers/0/url', qr{:\d+/v1$});
$t->get_ok('/v1.html')->status_is(200)->element_exists('ul.unstyled li a[href$="/v1"]');

done_testing;
