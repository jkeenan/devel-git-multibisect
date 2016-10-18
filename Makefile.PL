use v5.10.0;
use Devel::CheckBin;
check_bin('git');

use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
    NAME         => 'Test::Multisect',
    VERSION_FROM => 'lib/Test/Multisect.pm', # finds \$VERSION
    AUTHOR       => 'James E Keenan (jkeenan@cpan.org)',
    ABSTRACT     => 'Run test file(s) at consecutive git commits',
    CONFIGURE_REQUIRES => {
        'Devel::CheckBin' => 0,
        'ExtUtils::MakeMaker' => 0,
    },
    PREREQ_PM    => {
        'Carp' => 0,
        'Cwd' => 0,
        'Data::Dumper' => 0,
        'Digest::MD5' => 0,
        'File::Compare' => 0,
        'File::Copy' => 0,
        'File::Temp' => 0,
        'Getopt::Long' => 0,
        'List::Util' => 0,
        'strict' => 0,
        'warnings' => 0,
    },
    TEST_REQUIRES => {
        'Test::Simple' => 0.44,
        'Capture::Tiny' => 0,
    },
);

my %FallbackPrereqs = (
    %{$WriteMakefileArgs{PREREQ_PM}},
    %{$WriteMakefileArgs{TEST_REQUIRES}},
);

unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);
