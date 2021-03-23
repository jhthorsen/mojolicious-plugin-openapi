use Mojo::Base -strict;
use Mojo::File 'path';
use Mojolicious;
use Test::Mojo;
use Test::More;

sub VERSION {1.42}

my $petstore = path(__FILE__)->dirname->child(qw(spec v2-petstore.json));
my $app      = Mojolicious->new;

# All options are ignored when loaded as standalone plugin
$app->plugin('Mojolicious::Plugin::OpenAPI::SpecRenderer' =>
    {url => $petstore->to_string, spec_route_name => 'my.cool.api', version_from_class => 'main'});

my $custom_spec = JSON::Validator->new->schema($petstore->to_string)->bundle;
$app->routes->get('/my-unknown-doc' => sub { shift->openapi->render_spec });
$app->routes->get(
  '/my-cool-doc' => [format => [qw(html json)]],
  {format => undef}, sub { $_[0]->openapi->render_spec($_[0]->param('path'), $custom_spec) }
);

my $t = Test::Mojo->new($app);
$t->get_ok('/my-cool-doc.json')->status_is(200)->json_is('/basePath', '/v1')
  ->json_is('/host', 'petstore.swagger.io')->json_is('/info/version', '1.0.0');

$t->get_ok('/my-cool-doc.json?path=/pets/{petId}')->status_is(200)
  ->json_is('/$schema',                       'http://json-schema.org/draft-04/schema#')
  ->json_is('/title',                         'Swagger Petstore')->json_is('/description', '')
  ->json_is('/get/operationId',               'showPetById')
  ->json_is('/get/responses/200/schema/$ref', '#/definitions/Pets')
  ->json_is('/definitions/Pets/type',         'array');

$t->get_ok('/my-cool-doc.json?method=get&path=/pets/{petId}')->status_is(200)
  ->json_is('/$schema', 'http://json-schema.org/draft-04/schema#')
  ->json_is('/title',   'Swagger Petstore')->json_is('/operationId', 'showPetById');

$t->get_ok('/my-unknown-doc')->status_is(500)
  ->json_is('/errors/0/message', 'No specification to render.');

$t->get_ok('/my-cool-doc.html')->status_is(200)->text_is('h3#op-post--pets a', 'createPets');

SKIP: {
  skip 'Text::Markdown is not installed', 2 unless eval 'require Text::Markdown;1';
  $t->text_is('div.spec-description p', 'Null response');
}

done_testing;
