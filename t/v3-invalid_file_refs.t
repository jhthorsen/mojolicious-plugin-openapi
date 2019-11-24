use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use JSON::Validator::OpenAPI::Mojolicious;

get '/test' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(status => 200, openapi => $c->param('pcversion'));
  },
  'File';

plugin OpenAPI => {schema => 'v3', url => app->home->rel_file("spec/v3-invalid_file_refs.yaml")};

my $t = Test::Mojo->new;

$t->get_ok('/api')->status_is(200)->json_hasnt('/PCVersion/name')->json_has('/definitions')
  ->content_like(qr/v3-invalid_include_yaml-PCVersion-/);

my $json      = $t->get_ok('/api')->tx->res->body;
my $validator = JSON::Validator::OpenAPI::Mojolicious->new(version => 3);
eval { $validator->load_and_validate_schema($json, {schema => 'v3'}) };
like $@, qr/Properties not allowed: definitions/,
  'load_and_validate_schema fails, wrong placement of data';

done_testing;
