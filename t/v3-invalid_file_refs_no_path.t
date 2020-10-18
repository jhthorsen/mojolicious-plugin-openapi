use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

get '/test' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(status => 200, openapi => $c->param('pcversion'));
  },
  'File';

plugin OpenAPI => {url => app->home->rel_file('spec/v3-invalid_file_refs_no_path.yaml')};

my $t = Test::Mojo->new;

$t->get_ok('/api')->status_is(200)->json_hasnt('/PCVersion/name')->json_has('/definitions')
  ->content_like(qr!\\/definitions\\/v3-valid_include_yaml-!);

eval { die JSON::Validator::Schema::OpenAPIv3->new($t->get_ok('/api')->tx->res->body)->errors->[0] };
like $@, qr/Properties not allowed: definitions/,
  'load_and_validate_schema fails, wrong placement of data';

done_testing;
