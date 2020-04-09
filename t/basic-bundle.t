use Mojo::Base -strict;
use Mojo::File 'path';
use Test::More;
use JSON::Validator::Schema::OpenAPIv2;

# This test mimics what Mojolicious::Plugin::OpenAPI does when loading
# a spec from a file that Mojolicious locates with a '..'
# It checks that a $ref to something that's under /responses doesn't
# get picked as remote, or if so that it doesn't make an invalid spec!
my $validator = JSON::Validator::Schema::OpenAPIv2->new;
my $bundlecheck_path
  = path(path(__FILE__)->dirname, 'spec', File::Spec->updir, 'spec', 'bundlecheck.json');
my $bundled = $validator->schema($bundlecheck_path)->bundle;
eval { $validator->load_and_validate_schema($bundled) };
is $@, '', 'bundled schema is valid';

done_testing;
