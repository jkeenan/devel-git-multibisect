

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Test::Multisect',
    VERSION_FROM => 'lib/Test/Multisect.pm', # finds \$VERSION
    AUTHOR       => 'James E Keenan (jkeenan@cpan.org)',
    ABSTRACT     => 'Run test file(s) at consecutive git commits',
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
                    },
);
