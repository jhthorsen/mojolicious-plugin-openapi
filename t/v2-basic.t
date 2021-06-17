use Mojo::Base -strict;
use Mojo::File 'path';
use Test::Mojo;
use Test::More;

use Mojolicious::Lite;

get '/pets/:petId' => sub {
  my $c      = shift->openapi->valid_input or return;
  my $input  = $c->validation->output;
  my $output = {id => $input->{petId}, name => 'Cow'};
  $output->{age} = 6 if $input->{wantAge};
  $c->render(openapi => $output);
  },
  'showPetById';

get '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->res->headers->header('x-next' => $c->param('limit') // 0);
  $c->render(openapi => $c->param('limit') ? [] : {});
  },
  'listPets';

plugin OpenAPI => {url => path(__FILE__)->dirname->child(qw(spec v2-petstore.json))};

my $t = Test::Mojo->new;
$t->get_ok('/v1.json')->status_is(200)->json_has('/basePath');

$t->get_ok('/v1/pets?limit=invalid', {Accept => 'application/json'})->status_is(400)
  ->json_is('/errors/0/path',    '/limit')
  ->json_is('/errors/0/message', 'Expected integer - got string.');

$t->get_ok('/v1/pets?limit=5', {Accept => 'application/json'})->status_is(200)
  ->header_is('x-next', 5)->content_is('[]');

done_testing;
