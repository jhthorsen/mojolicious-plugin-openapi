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
  $c->render(openapi => $c->param('limit') ? [] : {});
  },
  'listPets';

post '/pets' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(openapi => '', status => 201);
  },
  'createPets';

plugin OpenAPI => {
  url      => path(__FILE__)->dirname->child(qw(spec v3-petstore.json)),
  renderer => sub {
    my ($c, $data) = @_;
    my $ct = $c->stash('openapi_negotiated_content_type') || 'application/json';
    return '' if $c->stash('status') == 201;
    $c->res->headers->content_type($ct);
    return '<xml></xml>' if $ct =~ m!^application/xml!;
    return Mojo::JSON::encode_json($data);
  }
};

my $t = Test::Mojo->new;
$t->get_ok('/v1.json')->status_is(200)->json_like('/servers/0/url', qr{^http://[^/]+/v1$});

$t->get_ok('/v1/pets?limit=invalid', {Accept => 'application/json'})->status_is(400)
  ->json_is('/errors/0/message', 'Expected integer - got string.');

# TODO: Should probably be 400
$t->get_ok('/v1/pets?limit=10', {Accept => 'not/supported'})->status_is(500)
  ->json_is('/errors/0/message', 'No responses rules defined for not/supported.');

$t->get_ok('/v1/pets?limit=0', {Accept => 'application/json'})->status_is(500)
  ->json_is('/errors/0/message', 'Expected array - got object.');

$t->get_ok('/v1/pets?limit=10', {Accept => 'application/json'})->status_is(200)
  ->header_like('Content-Type' => qr{^application/json})->content_is('[]');
$t->get_ok('/v1/pets?limit=10', {Accept => 'application/*'})->status_is(200)
  ->header_like('Content-Type' => qr{^application/json})->content_is('[]');
$t->get_ok('/v1/pets?limit=10', {Accept => 'text/html,application/xml;q=0.9,*/*;q=0.8'})
  ->status_is(200)->header_like('Content-Type' => qr{^application/xml})->content_is('<xml></xml>');
$t->get_ok('/v1/pets?limit=10', {Accept => 'text/html,*/*;q=0.8'})->status_is(200)
  ->header_like('Content-Type' => qr{^application/json})->content_is('[]');

$t->get_ok('/v1/pets?limit=10', {Accept => 'application/json'})->status_is(200)->content_is('[]');

$t->post_ok('/v1/pets', {Accept => 'application/json', Cookie => 'debug=foo'})->status_is(400)
  ->json_is('/errors/0/message', 'Invalid Content-Type.')
  ->json_is('/errors/1/message', 'Expected integer - got string.');

$t->post_ok('/v1/pets', {Cookie => 'debug=1'}, json => {id => 1, name => 'Supercow'})
  ->status_is(201)->content_is('');

$t->post_ok('/v1/pets', form => {id => 1, name => 'Supercow'})->status_is(201)->content_is('');

$t->get_ok('/v1/pets/23?wantAge=yes', {Accept => 'application/json'})->status_is(400)
  ->json_is('/errors/0/message', 'Expected boolean - got string.');

$t->get_ok('/v1/pets/23?wantAge=true', {Accept => 'application/json'})->status_is(200)
  ->json_is('/id', 23)->json_is('/age', 6);

$t->get_ok('/v1/pets/23?wantAge=false', {Accept => 'application/json'})->status_is(200)
  ->json_is('/id', 23)->json_is('/age', undef);

done_testing;
