# -*- perl -*-
# t/015-short-configure.t
use 5.14.0;
use warnings;
use Devel::Git::MultiBisect::BuildTransitions;
use Devel::Git::MultiBisect::Opts qw( process_options );
use Test::More;
unless (
    $ENV{PERL_GIT_CHECKOUT_DIR}
        and
    (-d $ENV{PERL_GIT_CHECKOUT_DIR})
) {
    plan skip_all => "No git checkout of perl found";
}
#else {
#    plan tests => 77;
#}
use Carp;
use Capture::Tiny qw( :all );
use Cwd;
use File::Spec;
use File::Temp qw( tempdir );
use Tie::File;
use Data::Dump qw(dd pp);
use lib qw( t/lib );
use Helpers qw( test_report );
use Getopt::Long;

my $startdir = cwd();

chdir $ENV{PERL_GIT_CHECKOUT_DIR}
    or croak "Unable to change to perl checkout directory";

my (%args, $params, $self);
my ($first, $last, $branch, $configure_command, $test_command);
my ($git_checkout_dir, $outputdir, $this_commit_range);
my ($change_file, $rv, $expect);
my ($stdout, @result);


my $compiler = 'clang';

$git_checkout_dir = cwd();
#$outputdir = tempdir( CLEANUP => 1 );
$outputdir = tempdir(); # Permit CLEANUP only when we're set

note("Case 1: 7 commits | Configure did not change | 2 transitions | verbose | request_short_configure");

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
    request_short_configure => 1,
);
$params = process_options(%args);
test_params($params, $git_checkout_dir, $outputdir, $first, $last, $branch, $configure_command);
ok($params->{verbose}, "verbose requested");
ok($params->{request_short_configure}, "Short configuration requested");

$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
test_object($self);

$change_file = "Configure";
$expect = 0;
$rv = $self->did_file_change_over_commits_range($change_file);
is($rv, $expect, "$change_file DID NOT CHANGE over commit range");

say STDERR "START multisect_builds(): ", `date`;
$rv = $self->multisect_builds( { probe => 'stderr' } );
say STDERR "END   multisect_builds(): ", `date`;
ok($rv, "multisect_builds() returned true value");

balance($self, $outputdir, $compiler);

#######################################

note("Case 2: 7 commits | Configure did not change | 2 transitions | verbose | NO request_short_configure");

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
    request_short_configure => 0,
);
$params = process_options(%args);
test_params($params, $git_checkout_dir, $outputdir, $first, $last, $branch, $configure_command);
ok($params->{verbose}, "verbose requested");
ok(! $params->{request_short_configure}, "Short configuration NOT requested");

$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
test_object($self);

$change_file = "Configure";
$expect = 0;
$rv = $self->did_file_change_over_commits_range($change_file);
is($rv, $expect, "$change_file DID NOT CHANGE over commit range");

say STDERR "START multisect_builds(): ", `date`;
$rv = $self->multisect_builds( { probe => 'stderr' } );
say STDERR "END   multisect_builds(): ", `date`;
ok($rv, "multisect_builds() returned true value");

balance($self, $outputdir, $compiler);

#######################################

sub test_params {
    my ($params, $git_checkout_dir, $outputdir, $first, $last, $branch, $configure_command) = @_;
    is($params->{gitdir}, $git_checkout_dir, "Got expected gitdir");
    is($params->{outputdir}, $outputdir, "Got expected outputdir");
    is($params->{first}, $first, "Got expected first commit to be studied");
    is($params->{last}, $last, "Got expected last commit to be studied");
    is($params->{branch}, $branch, "Got expected branch");
    is($params->{configure_command}, $configure_command, "Got expected configure_command");
    ok(! $params->{test_command}, "test_command empty as expected");
}

sub test_object {
    my ($self) = @_;
    ok($self, "new() returned true value");
    isa_ok($self, 'Devel::Git::MultiBisect::BuildTransitions');
    isa_ok($self, 'Devel::Git::MultiBisect');

    ok(! exists $self->{targets},
        "BuildTransitions has no need of 'targets' attribute");
    ok(! exists $self->{test_command},
        "BuildTransitions has no need of 'test_command' attribute");

    {
        local $@;
        my ($change_file, $ffile, $rv);
        $change_file = "foobar";
        $ffile = File::Spec->catfile($self->{gitdir}, $change_file);
        eval { $rv = $self->did_file_change_over_commits_range($change_file); };
        like($@, qr/Could not locate $ffile/,
            "did_file_change_over_commits_range: Got expected exception for missing file");
    }

    my $this_commit_range = $self->get_commits_range();

    ok($this_commit_range, "get_commits_range() returned true value");
    is(ref($this_commit_range), 'ARRAY', "get_commits_range() returned array ref");
    is($this_commit_range->[0], $first, "Got expected first commit in range");
    is($this_commit_range->[-1], $last, "Got expected last commit in range");
    note("Observed " . scalar(@{$this_commit_range}) . " commits in range");
}

sub balance {
    my ($self, $outputdir, $compiler) = @_;

    note("get_multisected_outputs()");

    my $multisected_outputs = $self->get_multisected_outputs();
    pp($multisected_outputs);

    is(ref($multisected_outputs), 'ARRAY',
        "get_multisected_outputs() returned array reference");
    is(scalar(@{$multisected_outputs}), scalar(@{$self->{commits}}),
        "get_multisected_outputs() has one element for each commit");

    note("inspect_transitions()");

    my $transitions = $self->inspect_transitions();
    pp($transitions);

    my $transitions_report = File::Spec->catfile($outputdir, "transitions.$compiler.pl");
    open my $TR, '>', $transitions_report
        or croak "Unable to open $transitions_report for writing";
    my $old_fh = select($TR);
    dd($transitions);
    select($old_fh);
    close $TR or croak "Unable to close $transitions_report after writing";

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
}

done_testing();

__END__

