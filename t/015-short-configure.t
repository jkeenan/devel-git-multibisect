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
else {
    plan tests => 40;
}
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
my ($multisected_outputs, @invalids);
my ($change_file, $rv, $expect);
my ($stdout, @result);


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
    verbose => 0,
);
$params = process_options(%args);
#Data::Dump::pp($params);
is($params->{gitdir}, $git_checkout_dir, "Got expected gitdir");
is($params->{outputdir}, $outputdir, "Got expected outputdir");
is($params->{first}, $first, "Got expected first commit to be studied");
is($params->{last}, $last, "Got expected last commit to be studied");
is($params->{branch}, $branch, "Got expected branch");
is($params->{configure_command}, $configure_command, "Got expected configure_command");
ok(! $params->{test_command}, "test_command empty as expected");
ok(! $params->{verbose}, "verbose not requested");

$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
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

$this_commit_range = $self->get_commits_range();

ok($this_commit_range, "get_commits_range() returned true value");
is(ref($this_commit_range), 'ARRAY', "get_commits_range() returned array ref");
is($this_commit_range->[0], $first, "Got expected first commit in range");
is($this_commit_range->[-1], $last, "Got expected last commit in range");
note("Observed " . scalar(@{$this_commit_range}) . " commits in range");

$change_file = "Configure";
$expect = 0;
$rv = $self->did_file_change_over_commits_range($change_file);
is($rv, $expect, "$change_file did not change over commit range");

#pp($this_commit_range);
#pass(changes($this_commit_range, $git_checkout_dir));


# f1258252af9029c93a503f5e45bf6ae88977c4dd

$branch = 'blead';
$first = 'f1258252af9029c93a503f5e45bf6ae88977c4dd';
$last  = '9be343bf32d0921e5c792cbaa2b0038f43c6e463';

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
($stdout, @result) = capture_stdout { process_options(%args); };
$params = $result[0];
ok($params->{verbose}, "verbose requested");
like($stdout, qr/Arguments provided to process_options\(\):/s,
    "Got expected verbose output with 'verbose' in arguments to process_options()");

$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Devel::Git::MultiBisect::BuildTransitions');
isa_ok($self, 'Devel::Git::MultiBisect');

$this_commit_range = $self->get_commits_range();
ok($this_commit_range, "get_commits_range() returned true value");
is(ref($this_commit_range), 'ARRAY', "get_commits_range() returned array ref");
is($this_commit_range->[0], $first, "Got expected first commit in range");
is($this_commit_range->[-1], $last, "Got expected last commit in range");
note("Observed " . scalar(@{$this_commit_range}) . " commits in range");

$change_file = "Configure";
$expect = 1;
#$rv = $self->did_file_change_over_commits_range($change_file);
#is($rv, $expect, "$change_file changed over commit range");
($stdout, @result) = capture_stdout { $self->did_file_change_over_commits_range($change_file); };
like($stdout, qr/Calling/s,
    "did_file_change_over_commits_range(): Got expected verbose output");
like($stdout, qr/$change_file did change/s,
    "did_file_change_over_commits_range(): Got expected verbose output");
$rv = $result[0];
is($rv, $expect, "$change_file changed over commit range");


# 78f044cf3c081ec5840ad6e07cf2e3d33f2c227e

$branch = 'blead';
$first = '78f044cf3c081ec5840ad6e07cf2e3d33f2c227e';
$last  = '9be343bf32d0921e5c792cbaa2b0038f43c6e463';

%args = (
    gitdir  => $git_checkout_dir,
    outputdir => $outputdir,
    first   => $first,
    last    => $last,
    branch  => $branch,
    configure_command => $configure_command,
    test_command => $test_command,
    verbose => 0,
);
$params = process_options(%args);
ok(! $params->{verbose}, "verbose not requested");
$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Devel::Git::MultiBisect::BuildTransitions');
isa_ok($self, 'Devel::Git::MultiBisect');

$this_commit_range = $self->get_commits_range();
ok($this_commit_range, "get_commits_range() returned true value");
is(ref($this_commit_range), 'ARRAY', "get_commits_range() returned array ref");
is($this_commit_range->[0], $first, "Got expected first commit in range");
is($this_commit_range->[-1], $last, "Got expected last commit in range");
note("Observed " . scalar(@{$this_commit_range}) . " commits in range");

#pp($this_commit_range);
#pass(changes($this_commit_range, $git_checkout_dir));

$change_file = "Configure";
$expect = 1;
$rv = $self->did_file_change_over_commits_range($change_file);
is($rv, $expect, "$change_file changed over commit range");

#sub changes {
#    my ($this_commit_range, $git_checkout_dir) = @_;
#    my $last_before = $this_commit_range->[0] . '^';
#    my $file = File::Spec->catfile($git_checkout_dir, "Configure");
#    my $cmd = qq|git diff -w ${last_before}..$this_commit_range->[-1] -- $file|;
#    say STDERR "Calling: ", $cmd;
#    my @lines = `$cmd`;
#    #pp(\@lines);
#    my $msg = "From $this_commit_range->[0] to $this_commit_range->[-1] (inclusive), there were ";
#    $msg .= (@lines ? '' : 0) . " change(s) in $file";
#    return $msg;
#}


__END__
$rv = $self->multisect_builds( { probe => 'stderr' } );
ok($rv, "multisect_builds() returned true value");

note("get_multisected_outputs()");

$multisected_outputs = $self->get_multisected_outputs();
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

#if (defined $pattern_sought) {
#    dd($quoted_pattern);
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
