use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

get '/test' => sub {
  my $c = shift->openapi->valid_input or return;
  $c->render(status => 200, openapi => $c->param('pcversion'));
  },
  'File';

plugin OpenAPI => {url => app->home->rel_file('spec/v3-valid_file_refs.yaml')};

my $t = Test::Mojo->new;

$t->get_ok('/api')->status_is(200)->json_is('/components/parameters/PCVersion/name', 'pcversion');

my $validator = JSON::Validator::Schema::OpenAPIv3->new($t->get_ok('/api')->tx->res->body);
is $validator->errors->[0], undef, 'load_and_validate_schema; prove we get a valid spec';

done_testing;
