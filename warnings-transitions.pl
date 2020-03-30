# -*- perl -*-
# warnings-transitions.pl
# Adapted from Devel::Git::MultiBisect's xt/104-gcc-build-transitions-warnings.t
use 5.14.0;
use warnings;
use Devel::Git::MultiBisect::Opts qw( process_options );
use Devel::Git::MultiBisect::BuildTransitions;
use Test::More;
use Carp;
use File::Spec;
use Data::Dump qw(dd pp);
use Tie::File;

=head1 NAME

warnings-transitions.pl

=head1 ABSTRACT

Identify Perl 5 commit at which a given build-time warning first appeared

=head1 DESCRIPTION

This program uses methods from L<Devel::Git::MultiBisect::BuildTransitions> to identify the first commit in Perl 5 blead

=cut

# TODO:  Use Getopt::Long to de-hard-code these settings

my $pattern_sought = qr/\QOpcode.xs:_:_: warning: overflow in implicit constant conversion [Woverflow]\E/;
my ($compiler, %args, $params, $self, $good_gitdir, $workdir, $first, $last, $branch, $configure_command, 
$make_command);
$compiler = 'gcc';
$good_gitdir = "$ENV{GIT_WORKDIR}/perl2";
$workdir = "$ENV{HOMEDIR}/learn/perl/multisect/testing/$compiler";
$first = 'd7fb2be259ba2ec08e8fa0e88ad0ee860d59dab9';
$last  = '043ae7481cd3d05b453e0830b34573b7eef2aade';

$branch = 'blead';
$configure_command =  q|sh ./Configure -des -Dusedevel|;
$configure_command   .= qq| -Dcc=$compiler|;
$configure_command   .=  q| 1>/dev/null 2>&1|;
$make_command = qq|make -j$ENV{TEST_JOBS} 1>/dev/null|;

%args = (
    gitdir  => $good_gitdir,
    workdir => $workdir,
    first => $first,
    last    => $last,
    branch  => $branch,
    configure_command => $configure_command,
    make_command => $make_command,
    verbose => 1,
);
say '\%args';
pp(\%args);
$params = process_options(%args);
say '$params';
pp($params);

is($params->{gitdir}, $good_gitdir, "Got expected gitdir");
is($params->{workdir}, $workdir, "Got expected workdir");
is($params->{first}, $first, "Got expected first commit to be studied");
is($params->{last}, $last, "Got expected last commit to be studied");
is($params->{branch}, $branch, "Got expected branch");
is($params->{configure_command}, $configure_command, "Got expected configure_command");
ok($params->{verbose}, "verbose requested");

$self = Devel::Git::MultiBisect::BuildTransitions->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Devel::Git::MultiBisect::BuildTransitions');
isa_ok($self, 'Devel::Git::MultiBisect');

pp($self);
ok(! exists $self->{targets},
    "BuildTransitions has no need of 'targets' attribute");
ok(! exists $self->{test_command},
    "BuildTransitions has no need of 'test_command' attribute");

my $this_commit_range = $self->get_commits_range();
ok($this_commit_range, "get_commits_range() returned true value");
is(ref($this_commit_range), 'ARRAY', "get_commits_range() returned array ref");
is($this_commit_range->[0], $first, "Got expected first commit in range");
is($this_commit_range->[-1], $last, "Got expected last commit in range");
say scalar @{$this_commit_range}, " commits found in range";

my $rv = $self->multisect_builds( { probe => 'warning' } );
ok($rv, "multisect_builds() returned true value");

note("get_multisected_outputs()");

my $multisected_outputs = $self->get_multisected_outputs();
pp($multisected_outputs);

is(ref($multisected_outputs), 'ARRAY',
    "get_multisected_outputs() returned array reference");
is(scalar(@{$multisected_outputs}), scalar(@{$self->{commits}}),
    "get_multisected_outputs() has one element for each commit");

note("inspect_transitions()");

my $transitions = $self->inspect_transitions();

my $transitions_report = File::Spec->catfile($workdir, "transitions.$compiler.pl");
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
my $first_commit_with_warning = '';
LOOP: for my $t (@arr) {
    my $newer = $t->{newer}->{file};
    say "Examining $newer";
    my @lines;
    tie @lines, 'Tie::File', $newer or croak "Unable to Tie::File to $newer";
    for my $l (@lines) {
        if ($l =~ m/$pattern_sought/) {
            $first_commit_with_warning =
                $multisected_outputs->[$t->{newer}->{idx}]->{commit};
            untie @lines;
            last LOOP;
        }
    }
    untie @lines;
}

say "See results in:\n$transitions_report";
say "Likely commit with first instance of warning is $first_commit_with_warning";
say "\nFinished";

done_testing();
