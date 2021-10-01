use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

get '/test' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(status => 200, openapi => $c->param('pcversion'));
  },
  'File';

plugin OpenAPI => {url => app->home->rel_file('spec/v3-invalid_file_refs.yaml')};

my $t = Test::Mojo->new;
$t->get_ok('/api')->status_is(200)->json_hasnt('/PCVersion/name')->json_has('/components/schemas')
  ->content_like(qr/v3-invalid_include_yaml-PCVersion/);

my $validator = JSON::Validator::Schema::OpenAPIv3->new($t->get_ok('/api')->tx->res->body);
like $validator->errors->[0], qr/Properties not allowed/, 'invalid bundled spec';

done_testing;
