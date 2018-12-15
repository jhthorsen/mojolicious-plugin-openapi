use lib '.';
use JSON::Validator::OpenAPI::Mojolicious;
use Test::More;

my $schema = {type => 'object', properties => {v => {type => 'string'}}};
my $validator = JSON::Validator::OpenAPI::Mojolicious->new;

sub E { goto &JSON::Validator::OpenAPI::Mojolicious::E; }

sub validate_ok {
  my ($data, $schema, @expected) = @_;
  my $descr = @expected ? "errors: @expected" : "valid: " . Mojo::JSON::encode_json($data);
  my @errors = $validator->schema($schema)->validate($data);
  is_deeply [map { $_->TO_JSON } sort { $a->path cmp $b->path } @errors],
    [map { $_->TO_JSON } sort { $a->path cmp $b->path } @expected], $descr
    or Test::More::diag(Mojo::JSON::encode_json(\@errors));
}

{
  $schema->{properties}{v}{format} = 'byte';
  validate_ok {v => 'amh0aG9yc2Vu'}, $schema;
  validate_ok {v => "\0"}, $schema, E('/v', 'Does not match byte format.');
}

{
  $schema->{properties}{v}{format} = 'date';
  validate_ok {v => '2014-12-09'},           $schema;
  validate_ok {v => '0000-00-00'},           $schema, E('/v', 'Month out of range.');
  validate_ok {v => '0000-01-00'},           $schema, E('/v', 'Day out of range.');
  validate_ok {v => '2014-12-09T20:49:37Z'}, $schema, E('/v', 'Does not match date format.');
  validate_ok {v => '0-0-0'},                $schema, E('/v', 'Does not match date format.');
  validate_ok {v => '09-12-2014'},           $schema, E('/v', 'Does not match date format.');
  validate_ok {v => '09-DEC-2014'},          $schema, E('/v', 'Does not match date format.');
  validate_ok {v => '09/12/2014'},           $schema, E('/v', 'Does not match date format.');
}

{
  $schema->{properties}{v}{format} = 'date-time';
  validate_ok {v => '2014-12-09T20:49:37Z'}, $schema;
  validate_ok {v => '0000-00-00T00:00:00Z'}, $schema, E('/v', 'Month out of range.');
  validate_ok {v => '0000-01-00T00:00:00Z'}, $schema, E('/v', 'Day out of range.');
  validate_ok {v => '20:46:02'},             $schema, E('/v', 'Does not match date-time format.');
}

{
  local $schema->{properties}{v}{type}   = 'number';
  local $schema->{properties}{v}{format} = 'double';
  local $TODO                            = "cannot test double, since input is already rounded";
  validate_ok {v => 1.1000000238418599085576943252817727625370025634765626}, $schema;
}

{
  local $schema->{properties}{v}{format} = 'email';
  validate_ok {v => 'jhthorsen@cpan.org'}, $schema;
  validate_ok {v => 'foo'}, $schema, E('/v', 'Does not match email format.');
}

{
  local $schema->{properties}{v}{type}   = 'number';
  local $schema->{properties}{v}{format} = 'float';
  validate_ok {v => -1.10000002384186}, $schema;
  validate_ok {v => 1.10000002384186},  $schema;

  local $TODO = 'No idea how to test floats';
  validate_ok {v => 0.10000000000000}, $schema, E('/v', 'Does not match float format.');
}

{
  local $schema->{properties}{v}{format} = 'ipv4';
  validate_ok {v => '255.100.30.1'}, $schema;
  validate_ok {v => '300.0.0.0'}, $schema, E('/v', 'Does not match ipv4 format.');
}

{
  local $schema->{properties}{v}{type}   = 'integer';
  local $schema->{properties}{v}{format} = 'int32';
  validate_ok {v => -2147483648}, $schema;
  validate_ok {v => 2147483647},  $schema;
  validate_ok {v => 2147483648},  $schema, E('/v', 'Does not match int32 format.');
}

if (JSON::Validator::OpenAPI::Mojolicious::IV_SIZE >= 8) {
  local $schema->{properties}{v}{type}   = 'integer';
  local $schema->{properties}{v}{format} = 'int64';
  validate_ok {v => -9223372036854775808}, $schema;
  validate_ok {v => 9223372036854775807},  $schema;
  validate_ok {v => 9223372036854775808},  $schema, E('/v', 'Does not match int64 format.');
}

{
  local $schema->{properties}{v}{format} = 'password';
  validate_ok {v => 'whatever'}, $schema;
}

{
  local $schema->{properties}{v}{format} = 'unknown';
  validate_ok {v => 'whatever'}, $schema;
}

done_testing;
