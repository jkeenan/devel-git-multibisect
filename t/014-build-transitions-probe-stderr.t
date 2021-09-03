# -*- perl -*-
# t/014-build-transitions-probe-stderr.t
use 5.14.0;
use warnings;
use Devel::Git::MultiBisect::BuildTransitions;
use Devel::Git::MultiBisect::Opts qw( process_options );
use Devel::Git::MultiBisect::Auxiliary qw( write_transitions_report );
use Test::More;
unless (
    $ENV{PERL_GIT_CHECKOUT_DIR}
        and
    (-d $ENV{PERL_GIT_CHECKOUT_DIR})
) {
    plan skip_all => "No git checkout of perl found";
}
else {
    plan tests => 42;
}
use Carp;
use Cwd;
use File::Spec;
use File::Temp qw( tempdir );
use Tie::File;
use lib qw( t/lib );
use Helpers qw( test_report );
use Getopt::Long;

my $startdir = cwd();

chdir $ENV{PERL_GIT_CHECKOUT_DIR}
    or croak "Unable to change to perl checkout directory";

my (%args, $params, $self);
my ($first, $last, $branch, $configure_command, $test_command);
my ($git_checkout_dir, $outputdir, $rv, $this_commit_range);
my ($multisected_outputs, @invalids);

my $compiler = 'clang';

$git_checkout_dir = cwd();
#$outputdir = tempdir( CLEANUP => 1 );
$outputdir = tempdir(); # Permit CLEANUP only when we're set

$branch = 'blead';
$first = 'd4bf6b07402c770d61a5f8692f24fe944655d99f';
$last  = '9be343bf32d0921e5c792cbaa2b0038f43c6e463';

$configure_command =  q|sh ./Configure -des -Dusedevel|;
$configure_command   .= qq| -Dcc=$compiler |;
$configure_command   .=  q| 1>/dev/null 2>&1|;
$test_command = '';

%args = (
    gitdir  => $git_checkout_dir,
    outputdir => $outputdir,
    first   => $first,
    last    => $last,
    branch  => $branch,
    configure_command => $configure_command,
    test_command => $test_command,
    verbose => 1,
);
$params = process_options(%args);
is($params->{gitdir}, $git_checkout_dir, "Got expected gitdir");
is($params->{outputdir}, $outputdir, "Got expected outputdir");
is($params->{first}, $first, "Got expected first commit to be studied");
is($params->{last}, $last, "Got expected last commit to be studied");
is($params->{branch}, $branch, "Got expected branch");
is($params->{configure_command}, $configure_command, "Got expected configure_command");
ok(! $params->{test_command}, "test_command empty as expected");
ok($params->{verbose}, "verbose requested");

$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Devel::Git::MultiBisect::BuildTransitions');
isa_ok($self, 'Devel::Git::MultiBisect');

ok(! exists $self->{targets},
    "BuildTransitions has no need of 'targets' attribute");
ok(! exists $self->{test_command},
    "BuildTransitions has no need of 'test_command' attribute");

$this_commit_range = $self->get_commits_range();
ok($this_commit_range, "get_commits_range() returned true value");
is(ref($this_commit_range), 'ARRAY', "get_commits_range() returned array ref");
is($this_commit_range->[0], $first, "Got expected first commit in range");
is($this_commit_range->[-1], $last, "Got expected last commit in range");
note("Observed " . scalar(@{$this_commit_range}) . " commits in range");

$rv = $self->multisect_builds( { probe => 'stderr' } );
ok($rv, "multisect_builds() returned true value");

note("get_multisected_outputs()");

$multisected_outputs = $self->get_multisected_outputs();

is(ref($multisected_outputs), 'ARRAY',
    "get_multisected_outputs() returned array reference");
is(scalar(@{$multisected_outputs}), scalar(@{$self->{commits}}),
    "get_multisected_outputs() has one element for each commit");

note("inspect_transitions()");

my $transitions = $self->inspect_transitions();

my $transitions_report = write_transitions_report(
    $outputdir,
    "transitions.$compiler.pl",
    $transitions
);
note("Report: $transitions_report");

is(ref($transitions), 'HASH',
    "inspect_transitions() returned hash reference");
is(scalar(keys %{$transitions}), 3,
    "inspect_transitions() has 3 elements");
for my $k ( qw| newest oldest | ) {
    is(ref($transitions->{$k}), 'HASH',
        "Got hashref as value for '$k'");
    for my $l ( qw| idx md5_hex file | ) {
        ok(exists $transitions->{$k}->{$l},
            "Got key '$l' for '$k'");
    }
}
is(ref($transitions->{transitions}), 'ARRAY',
    "Got arrayref as value for 'transitions'");
my @arr = @{$transitions->{transitions}};
for my $t (@arr) {
    is(ref($t), 'HASH',
        "Got hashref as value for element in 'transitions' array");
    for my $m ( qw| newer older | ) {
        ok(exists $t->{$m}, "Got key '$m'");
        is(ref($t->{$m}), 'HASH', "Got hashref");
        for my $n ( qw| idx md5_hex file | ) {
            ok(exists $t->{$m}->{$n},
                "Got key '$n'");
        }
    }
}

#if (defined $pattern_sought) {
#    my $first_commit_with_warning = '';
#    LOOP: for my $t (@arr) {
#        my $newer = $t->{newer}->{file};
#        say "Examining $newer";
#        my @lines;
#        tie @lines, 'Tie::File', $newer or croak "Unable to Tie::File to $newer";
#        for my $l (@lines) {
#            if ($l =~ m/$quoted_pattern/) {
#                $first_commit_with_warning =
#                    $multisected_outputs->[$t->{newer}->{idx}]->{commit};
#                untie @lines;
#                last LOOP;
#            }
#        }
#        untie @lines;
#    }
#    say "Likely commit with first instance of warning is $first_commit_with_warning";
#}
#
#say STDERR "See results in:\n$transitions_report";
#say "\nFinished";

#done_testing();
__END__
