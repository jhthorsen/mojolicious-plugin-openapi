use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojolicious;

#
# This test checks that "require: false" is indeed false
# https://github.com/jhthorsen/swagger2/issues/39
#

my $n = 0;
for my $module (qw(YAML::XS YAML::Syck)) {
  unless (eval "require $module;1") {
    diag "Skipping test when $module is not installed";
    next;
  }

  no warnings qw(once redefine);
  use JSON::Validator;
  local *JSON::Validator::_load_yaml = eval "\\\&$module\::Load";
  $n++;
  diag join ' ', $module, $module->VERSION || 0;
  my $app = Mojolicious->new;
  eval { $app->plugin(OpenAPI => {url => 'data://main/coercion.yaml'}); 1 };
  ok !$@, "Could not load Swagger2 plugin using $module" or diag $@;
}

ok 1, 'no yaml modules available' unless $n;

done_testing;

__DATA__
@@ coercion.yaml
---
swagger: 2.0
info:
  version: "0.8"
  title: Pets
basePath: /api
paths:
  /echo:
    post:
      x-mojo-to: dummy#echo
      parameters:
        - { in: query, name: days, type: number, default: 42 }
        - { in: formData, name: name, type: string, default: batman }
        - { in: header, name: X-Foo, type: string, default: yikes }
      responses:
        200:
          description: Echo response
          schema:
            type: object
