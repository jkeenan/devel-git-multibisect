package Test::Multisect::Transitions;
use strict;
use warnings;
use v5.10.0;
use parent ( qw| Test::Multisect | );
use Test::Multisect::Opts qw( process_options );
use Test::Multisect::Auxiliary qw(
    clean_outputfile
    hexdigest_one_file
    validate_list_sequence
);
use Carp;
use Cwd;
use File::Temp;
use List::Util qw(first sum);
#use Data::Dump qw( pp );

our $VERSION = '0.01';

=head1 NAME

Test::Multisect::Transitions - Gather test output where it changes over a range of F<git> commits

=head1 SYNOPSIS

    use Test::Multisect::Transitions;

    $self = Test::Multisect::Transitions->new(\%parameters);

    $commit_range = $self->get_commits_range();

    $full_targets = $self->set_targets(\@target_args);

    $self->multisect_all_targets()

=head1 DESCRIPTION

Given a Perl library or application kept in F<git> for version control, it is
often useful to be able to compare the output collected from running one or
several test files over a range of F<git> commits.  If that range is sufficiently
large, a test may fail in B<more than one way> over that range.

If that is the case, then simply asking, I<"When did this file start to
fail?"> is insufficient.  We may want to capture the test output for each
commit, or, more usefully, may want to capture the test output only at those
commits where the output changed.

F<Test::Multisect> provides methods to achieve that objective.  More specifically:

=over 4

=item *

When the number of commits in the specified range is large and you only need
the test output at those commits where the output materially changed, you can
use this package, F<Test::Multisect::Transitions>.

=item *

When you want to capture the test output for each commit in a specified range,
you can use another package in this library, F<Test::Multisect::AllCommits>.

=back

=head1 METHODS

=head2 C<multisect_all_targets()>

=over 4

=item * Purpose

For selected files within an application's test suite, determine the points
within a specified range of F<git> commits where the output of a run of each
test materially changes.  Store the test output at those transition points for
human inspection.

=item * Glossary

=over 4

=item * B<commit>

An individual commit to a F<git> repository, which takes the form of a SHA.

=item * B<commit range>

The range of commits requested for analysis in the sequence determined by F<git log>.

=item * B<target>

A target is a test file from the test suite of the application or library under study.

=item * B<test output>

What is sent to STDOUT or STDERR as a result of calling a test program such as
F<prove> or F<t/harness> on an individual target file.

=item * B<transitional commit>

A commit at which the test output for a given target changes from that of the
commit immediately preceding.

=item * B<digest>

A string holding the output of a cryptographic process run on test output
which uniquely identifies that output.  (Currently, we use the
C<Digest::SHA::md5_hex> algorithm.)  We assume that if the test output does
not change between one or more commits, then that commit is not a transitional
commit.

Note:  Before taking a digest on a particular test output, we exclude text
such as timings which are highly likely to change from one run to the next and
which would introduce spurious variability into the digest calculations.

=item * B<multisection>

A series of configure-build-test sequences at commits within the commit range
which are selected by a bisection algorithm.

Normally, when we bisect (via F<git bisect>, F<Porting/bisect.pl> or
otherwise), we are seeking a single point where a Boolean result -- yes/no,
true/false, pass/fail -- is returned.  What the test run outputs to STDOUT or
STDERR is a lesser concern.

In multisection we bisect repeatedly to determine all points where the output
of the test command changes -- regardless of whether that change is a C<PASS>,
C<FAIL> or whatever.  We capture the output for later human examination.

=back

=item * Arguments

    $self->multisect_all_targets();

None; all data needed is already present in the object.

=item * Return Value

Implicitly returns true value upon success.

=item * Comment

As C<multisect_all_targets()> runs it does two kinds of things:

=over 4

=item *

It stores results data within the object which you can subsequently access through method calls.

=item *

It captures each test output and writes it to a file on disk for later human inspection.

=back

=back

=cut

sub multisect_all_targets {
    my ($self) = @_;

    # Prepare data structures in the object to hold results of test runs on a
    # per target, per commit basis.
    # Also, "prime" the data structure by performing test runs for each target
    # on the first and last commits in the commit range, storing that test
    # output on disk as well.

    $self->_prepare_for_multisection();

    my $target_count = scalar(@{$self->{targets}});
    my $max_target_idx = $#{$self->{targets}};

    # 1 element per test target file, keyed on stub, value 0 or 1
    my %overall_status = map { $self->{targets}->[$_]->{stub} => 0 } (0 .. $max_target_idx);

    # Overall success criterion:  We must have completed multisection --
    # identified all transitional commits -- for each target and recorded that
    # completion with a '1' in its element in %overall_status.  If we have
    # achieved that, then each element in %overall_status will have the value
    # '1' and they will sum up to the total number of test files being
    # targeted.

    until (sum(values(%overall_status)) == $target_count) {
        if ($self->{verbose}) {
            say "target count|sum of status values: ",
                join('|' => $target_count, sum(values(%overall_status)));
        }

        # Target and process one file at a time.  To multisect a target is to
        # identify all its transitional commits over the commit range.

        for my $target_idx (0 .. $max_target_idx) {
            my $target = $self->{targets}->[$target_idx];
            if ($self->{verbose}) {
                say "Targeting file: $target->{path}";
            }

            my $rv = $self->_multisect_one_target($target_idx);
            if ($rv) {
                $overall_status{$target->{stub}}++;
            }
        }
    } # END until loop
}

sub _prepare_for_multisection {
    my $self = shift;

    # get_commits_range is inherited from parent

    my $all_commits = $self->get_commits_range();
    $self->{all_outputs} = [ (undef) x scalar(@{$all_commits}) ];

    my %multisected_outputs_table;
    for my $idx (0, $#{$all_commits}) {

        # run_test_files_on_one_commit is inherited from parent

        my $outputs = $self->run_test_files_on_one_commit($all_commits->[$idx]);
        $self->{all_outputs}->[$idx] = $outputs;
        for my $target (@{$outputs}) {
            my @other_keys = grep { $_ ne 'file_stub' } keys %{$target};
            $multisected_outputs_table{$target->{file_stub}}[$idx] =
                { map { $_ => $target->{$_} } @other_keys };
        }
    }
    $self->{multisected_outputs} = { %multisected_outputs_table };
    return \%multisected_outputs_table;
}

sub _multisect_one_target {
    my ($self, $target_idx) = @_;
    croak "Must supply index of test file within targets list"
        unless(defined $target_idx and $target_idx =~ m/^\d+$/);
    croak "You must run _prepare_for_multisection() before any stand-alone run of _multisect_one_target()"
        unless exists $self->{multisected_outputs};
    my $target  = $self->{targets}->[$target_idx];
    my $stub    = $target->{stub};

    # The condition for successful multisection of one particular test file
    # target is that the list of md5_hex values for files holding the output of TAP
    # run over the commit range exhibit the following behavior:

    # The list is composed of sub-sequences (a) whose elements are either (i)
    # the md5_hex value for the TAP outputfiles at a given commit or (ii)
    # undefined; (b) if defined, the md5_values are all identical; (c) the
    # first and last elements of the sub-sequence are both defined; and (d)
    # the sub-sequence's unique defined value never reoccurs in any subsequent
    # sub-sequence.

    # For each run of _multisect_one_target() over a given target, it will
    # return a true value (1) if the above condition(s) are met and 0
    # otherwise.  The caller (multisect_all_targets()) will handle that return
    # value appropriately.  The caller will then call _multisect_one_target()
    # on the next target, if any.

    # The objective of multisection is to identify the git commits at which
    # the test output targeted materially changed.  We are using
    # an md5_hex value for that test file as a presumably valid unique
    # identifier for that file's content.  A transition point is a commit at
    # which the output file's md5_hex differs from that of the immediately
    # preceding commit.  So, to identify the first transition point for a
    # given target, we need to locate the commit at which the md5_hex changed
    # from that found in the very first commit in the designated commit range.
    # Once we've identified the first transition point, we'll look for the
    # second transition point, i.e., that where the md5_hex changed from that
    # observed at the first transition point.  We'll continue that process
    # until we get to a transition point where the md5_hex is identical to
    # that of the very last commit in the commit range.

    # This entails checking out the source code at each commit calculated by
    # the bisection algorithm, configuring and building the code, running the
    # test targets at that commit, computing their md5_hex values and storing
    # them in the 'multisected_outputs' structure.  The _prepare_for_multisection()
    # method will pre-populate that structure with md5_hexes for each test
    # file for each of the first and last commits in the commit range.

    # Since the configuration and build at a particular commit may be
    # time-consuming, once we have completed those steps we will run all the
    # test files at once and store their results in 'multisected_outputs'
    # immediately.  We will make our bisection decision based only on analysis
    # of the current target.  But when we come to the second target file we
    # will be able to skip configuration, build and test-running at commits
    # visited during the pass over the first target file.

    my ($min_idx, $max_idx)     = (0, $#{$self->{commits}});
    my $this_target_status      = 0;
    my $current_start_idx       = $min_idx;
    my $current_end_idx         = $max_idx;
    my $overall_start_md5_hex   =
            $self->{multisected_outputs}->{$stub}->[$min_idx]->{md5_hex};
    my $overall_end_md5_hex     =
            $self->{multisected_outputs}->{$stub}->[$max_idx]->{md5_hex};
    my $excluded_targets = {};
    my $n = 0;

    while (! $this_target_status) {

        # Start multisecting on this test target file: one transition point at
        # a time until we've got them all for this test file.

        # What gets (or may get) updated or assigned to in the course of one rep of this loop:
        # $current_start_idx
        # $current_end_idx
        # $n
        # $excluded_targets
        # $self->{all_outputs}
        # $self->{multisected_outputs}

        my $h = sprintf("%d" => (($current_start_idx + $current_end_idx) / 2));
        $self->_run_one_commit_and_assign($h);

        my $current_start_md5_hex =
            $self->{multisected_outputs}->{$stub}->[$current_start_idx]->{md5_hex};
        my $target_h_md5_hex  =
            $self->{multisected_outputs}->{$stub}->[$h]->{md5_hex};

        # Decision criteria:
        # If $target_h_md5_hex eq $current_start_md5_hex, then the first
        # transition is *after* index $h.  Hence bisection should go upwards.

        # If $target_h_md5_hex ne $current_start_md5_hex, then the first
        # transition has come *before* index $h.  Hence bisection should go
        # downwards.  However, since the test of where the first transition is
        # is that index j-1 has the same md5_hex as $current_start_md5_hex but
        #         index j   has a different md5_hex, we have to do a run on
        #         j-1 as well.

        if ($target_h_md5_hex ne $current_start_md5_hex) {
            my $g = $h - 1;
            $self->_run_one_commit_and_assign($g);
            my $target_g_md5_hex  = $self->{multisected_outputs}->{$stub}->[$g]->{md5_hex};
            if ($target_g_md5_hex eq $current_start_md5_hex) {
                if ($target_h_md5_hex eq $overall_end_md5_hex) {
                }
                else {
                    $current_start_idx  = $h;
                    $current_end_idx    = $max_idx;
                }
                $n++;
            }
            else {
                # Bisection should continue downwards
                $current_end_idx = $h;
                $n++;
            }
        }
        else {
            # Bisection should continue upwards
            $current_start_idx = $h;
            $n++;
        }
        $this_target_status = $self->_evaluate_status_one_target_run($target_idx);
    }
    return 1;
}

sub _evaluate_status_one_target_run {
    my ($self, $target_idx) = @_;
    my $stub = $self->{targets}->[$target_idx]->{stub};
    my @trans = ();
    for my $o (@{$self->{all_outputs}}) {
        push @trans,
            defined $o ? $o->[$target_idx]->{md5_hex} : undef;
    }
    my $vls = validate_list_sequence(\@trans);
    return ( (scalar(@{$vls}) == 1 ) and ($vls->[0])) ? 1 : 0;
}

sub _run_one_commit_and_assign {

    # If we've already stashed a particular commit's outputs in
    # all_outputs (and, simultaneously) in multisected_outputs,
    # then we don't need to actually perform a run.

    # This internal method assigns to all_outputs and multisected_outputs in
    # place.

    my ($self, $idx) = @_;
    my $this_commit = $self->{commits}->[$idx]->{sha};
    unless (defined $self->{all_outputs}->[$idx]) {
        my $these_outputs = $self->run_test_files_on_one_commit($this_commit);
        $self->{all_outputs}->[$idx] = $these_outputs;

        for my $target (@{$these_outputs}) {
            my @other_keys = grep { $_ ne 'file_stub' } keys %{$target};
            $self->{multisected_outputs}->{$target->{file_stub}}->[$idx] =
                { map { $_ => $target->{$_} } @other_keys };
        }
    }
}

=head2 C<get_multisected_outputs()>

=over 4

=item * Purpose

=item * Arguments

=item * Return Value

=item * Comment

=back

=cut

sub get_multisected_outputs {
    my $self = shift;
    return $self->{multisected_outputs};
}

=head2 C<inspect_transitions()>

=over 4

=item * Purpose

=item * Arguments

=item * Return Value

=item * Comment

=back

=cut

sub inspect_transitions {
    my ($self) = @_;
    my $multisected_outputs = $self->get_multisected_outputs();
    my %transitions;
    for my $k (sort keys %{$multisected_outputs}) {
        my $arr = $multisected_outputs->{$k};
        my $max_index = $#{$arr};
        $transitions{$k}{oldest} = {
            idx     => 0,
            md5_hex => $arr->[0]->{md5_hex},
        };
        $transitions{$k}{newest} = {
            idx     => $max_index,
            md5_hex => $arr->[$max_index]->{md5_hex},
        };
        for (my $j = 1; $j <= $max_index; $j++) {
            my $i = $j - 1;
            next unless ((defined $arr->[$i]) and (defined $arr->[$j]));
            my $older = $arr->[$i]->{md5_hex};
            my $newer = $arr->[$j]->{md5_hex};
            unless ($older eq $newer) {
                push @{$transitions{$k}{transitions}}, {
                    older => { idx => $i, md5_hex => $older },
                    newer => { idx => $j, md5_hex => $newer },
                }
            }
        }
    }
    return \%transitions;
}

1;

__END__
