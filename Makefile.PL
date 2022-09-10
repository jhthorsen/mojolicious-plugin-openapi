use 5.016;
use strict;
use warnings;
use utf8;
use ExtUtils::MakeMaker;

my $GITHUB_URL        = 'https://github.com/jhthorsen/mojolicious-plugin-openapi';
my %WriteMakefileArgs = (
  NAME          => 'Mojolicious::Plugin::OpenAPI',
  AUTHOR        => 'Jan Henning Thorsen <jan.henning@thorsen.pm>',
  LICENSE       => 'artistic_2',
  ABSTRACT_FROM => 'lib/Mojolicious/Plugin/OpenAPI.pm',
  VERSION_FROM  => 'lib/Mojolicious/Plugin/OpenAPI.pm',
  TEST_REQUIRES => {'Test::More'      => '0.88'},
  PREREQ_PM     => {'JSON::Validator' => '5.10', 'Mojolicious' => '9.00'},
  META_MERGE    => {
    'dynamic_config' => 0,
    'meta-spec'      => {version   => 2},
    'no_index'       => {directory => [qw(examples t)]},
    'prereqs'        =>
      {runtime => {recommends => {'Text::Markdown' => 'v1.0.31'}, requires => {perl => '5.016'}}},
    'resources' => {
      bugtracker => {web => "$GITHUB_URL/issues"},
      homepage   => $GITHUB_URL,
      license    => ['http://www.opensource.org/licenses/artistic-license-2.0'],
      repository => {type => 'git', url => "$GITHUB_URL.git", web => $GITHUB_URL},
      x_IRC      => {
        url => 'irc://irc.libera.chat/#perl-openapi',
        web => 'https://web.libera.chat/#perl-openapi'
      },
    },
    'x_contributors' => [
      'Bernhard Graf <augensalat@gmail.com>',
      'Doug Bell <doug@preaction.me>',
      'Ed J <mohawk2@users.noreply.github.com>',
      'Henrik Andersen <hem@hamster.dk>',
      'Ilya Rassadin <elcamlost@gmail.com>',
      'Jan Henning Thorsen <jhthorsen@cpan.org>',
      'Ji-Hyeon Gim <potatogim@gluesys.com>',
      'Joel Berger <joel.a.berger@gmail.com>',
      'Krasimir Berov <k.berov@gmail.com>',
      'Lars Thegler <lth@fibia.dk>',
      'Lee Johnson <lee@givengain.ch>',
      'Linn-Hege Kristensen <linn-hege@stix.no>',
      'Manuel <manuel@mausz.at>',
      'Martin Renvoize <martin.renvoize@ptfs-europe.com>',
      'Mohammad S Anwar <mohammad.anwar@yahoo.com>',
      'Nick Morrott <knowledgejunkie@gmail.com>',
      'Renee <reb@perl-services.de>',
      'Roy Storey <kiwiroy@users.noreply.github.com>',
      'SebMourlhou <35918953+SebMourlhou@users.noreply.github.com>',
      'Søren Lund <sl@keycore.dk>',
      'Stephan Hradek <github@hradek.net>',
      'Stephan Hradek <stephan.hradek@eco.de>',
    ],
  },
  test => {TESTS => (-e 'META.yml' ? 't/*.t' : 't/*.t xt/*.t')},
);

unless (eval { ExtUtils::MakeMaker->VERSION('6.63_03') }) {
  my $test_requires = delete $WriteMakefileArgs{TEST_REQUIRES};
  @{$WriteMakefileArgs{PREREQ_PM}}{keys %$test_requires} = values %$test_requires;
}

WriteMakefile(%WriteMakefileArgs);
