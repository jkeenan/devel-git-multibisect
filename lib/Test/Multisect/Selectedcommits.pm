package Test::Multisect::Selectedcommits;
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
use Data::Dump qw( pp );

our $VERSION = '0.01';

=head1 NAME

Test::Multisect::Selectedcommits - Study test output over a range of git commits

=head1 SYNOPSIS

    use Test::Multisect;

    $self = Test::Multisect->new(\%parameters);

    $commit_range = $self->get_commits_range();

    $full_targets = $self->set_targets(\@target_args);

    $outputs = $self->run_test_files_on_one_commit($commit_range->[0]);

    TK

=head1 DESCRIPTION

    TK

=head1 METHODS

    TK

=cut

sub prepare_multisect_hash {
    my $self = shift;
    my $all_commits = $self->get_commits_range();
    $self->{xall_outputs} = [ (undef) x scalar(@{$all_commits}) ];
    my %bisected_outputs;
    for my $idx (0, $#{$all_commits}) {
        my $outputs = $self->run_test_files_on_one_commit($all_commits->[$idx]);
        $self->{xall_outputs}->[$idx] = $outputs;
        for my $target (@{$outputs}) {
            my @other_keys = grep { $_ ne 'file_stub' } keys %{$target};
            $bisected_outputs{$target->{file_stub}}[$idx] =
                { map { $_ => $target->{$_} } @other_keys };
        }
    }
    $self->{bisected_outputs} = { %bisected_outputs };
    return \%bisected_outputs;
}

=pod

This is a first pass at multisection.  Here, we'll only try to identify the
very first transition for each test file targeted.

To establish that, for each target, we have to find the commit whose md5_hex
first differs from that of the very first commit in the range.  How will we
know when we've found it?  Its md5_hex will be different from the very first's,
but the immediately preceding commit will have the same md5_hex as the very first.

Hence, we have to do *two* instances of run_test_files_on_one_commit() at each
bisection point.  For each of them we will stash the result in a cache.  That way,
before calling run_test_files_on_one_commit(), we can check the cache to see
whether we can skip the configure-build-test cycle for that particular commit.
As a matter of fact, that cache will be nothing other than the 'bisected_outputs'
array created in prepare_multisect().

We have to account for the fact that the first transition is quite likely to be
different for each of the test files targeted.  We are likely to have to keep on
bisecting for one file after we've completed another.  Hence, we'll need a hash
keyed on file_stub in which to record the Boolean status of our progress for each
target and before embarking on a given round of run_test_files_on_one_commit()
we should check the status.

=cut

sub identify_transitions {
    my ($self) = @_;
    croak "You must run prepare_multisect_hash() before identify_transitions()"
        unless exists $self->{bisected_outputs};

    my $target_count = scalar(@{$self->{targets}});
    my $max_target_idx = $#{$self->{targets}};

    # 1 element per test target file, keyed on stub, value 0 or 1
    my %overall_status = map { $self->{targets}->[$_]->{stub} => 0 } (0 .. $max_target_idx);

    # Overall success criterion:  We must have completed multisection for each
    # targeted test file and recorded that completion with a '1' in its
    # element in %overall_status.  If we have achieved that, then each element
    # in %overall_status will have the value '1' and they will sum up to the
    # total number of test files being targeted.

    until (sum(values(%overall_status)) == $target_count) {
        if ($self->{verbose}) {
            say "target count|sum of status values: ",
                join('|' => $target_count, sum(values(%overall_status)));
        }

        # Target and process one file at a time.

        for my $target_idx (0 .. $max_target_idx) {
            my $target = $self->{targets}->[$target_idx];
            if ($self->{verbose}) {
                say "Targeting file: $target->{path}";
            }
            my $rv = $self->multisect_one_target($target_idx);
            if ($rv) {
                $overall_status{$target->{stub}}++;
            }
        }
    } # END until loop
}

sub multisect_one_target {
    my ($self, $target_idx) = @_;
    croak "Must supply index of test file within targets list"
        unless(defined $target_idx and $target_idx =~ m/^\d+$/);
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

    # For each run of multisect_one_target() over a given target, it will
    # return a true value (1) if the above condition(s) are met and 0
    # otherwise.  The caller (identify_transitions()) will handle that return
    # value appropriately.  The caller will then call multisect_one_target()
    # on the next target, if any.

    # The objective of multisection is to identify the git commits at which
    # the output of the test file targeted materially changed.  We are using
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
    # them in the 'bisected_outputs' structure.  The prepare_multisect_hash()
    # method will pre-populate that structure with md5_hexes for each test
    # file for each of the first and last commits in the commit range.

    # Since the configuration and build at a particular commit may be
    # time-consuming, once we have completed those steps we will run all the
    # test files at once and store their results in 'bisected_outputs'
    # immediately.  We will make our bisection decision based only on analysis
    # of the current target.  But when we come to the second target file we
    # will be able to skip configuration, build and test-running at commits
    # visited during the pass over the first target file.

    my ($min_idx, $max_idx)     = (0, $#{$self->{commits}});
    my $this_target_status      = 0;
    my $current_start_idx       = $min_idx;
    my $current_end_idx         = $max_idx;
    my $overall_start_md5_hex   =
            $self->{bisected_outputs}->{$stub}->[$min_idx]->{md5_hex};
    my $overall_end_md5_hex     =
            $self->{bisected_outputs}->{$stub}->[$max_idx]->{md5_hex};
    my $excluded_targets = {};
    my $n = 0;

    #ABC: while ((! $this_target_status) or ($n <= scalar(@{$self->{targets}}))) {
    while (! $this_target_status) {

        # Start multisecting on this test target file: one transition point at
        # a time until we've got them all for this test file.

        # What gets (or may get) updated or assigned to in the course of one rep of this loop:
        # $current_start_idx
        # $current_end_idx
        # $n
        # $excluded_targets
        # $self->{xall_outputs}
        # $self->{bisected_outputs}

        my $h = sprintf("%d" => (($current_start_idx + $current_end_idx) / 2));
        $self->_run_one_commit_and_assign($h);

        my $current_start_md5_hex =
            $self->{bisected_outputs}->{$stub}->[$current_start_idx]->{md5_hex};
        my $target_h_md5_hex  =
            $self->{bisected_outputs}->{$stub}->[$h]->{md5_hex};

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
            my $target_g_md5_hex  = $self->{bisected_outputs}->{$stub}->[$g]->{md5_hex};
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
    for my $o (@{$self->{xall_outputs}}) {
        push @trans,
            defined $o ? $o->[$target_idx]->{md5_hex} : undef;
    }
    my $vls = validate_list_sequence(\@trans);
    (
        (ref($vls) eq 'ARRAY') and
        (scalar(@{$vls}) == 1 ) and
        ($vls->[0])
    ) ? 1 : 0;
}

sub _run_one_commit_and_assign {

    # If we've already stashed a particular commit's outputs in
    # xall_outputs (and, simultaneously) in bisected_outputs,
    # then we don't need to actually perform a run.

    # This internal method assigns to xall_outputs and bisected_outputs in
    # place.

    my ($self, $idx) = @_;
    my $this_commit = $self->{commits}->[$idx]->{sha};
    unless (defined $self->{xall_outputs}->[$idx]) {
        my $these_outputs = $self->run_test_files_on_one_commit($this_commit);
        $self->{xall_outputs}->[$idx] = $these_outputs;

        for my $target (@{$these_outputs}) {
            my @other_keys = grep { $_ ne 'file_stub' } keys %{$target};
            $self->{bisected_outputs}->{$target->{file_stub}}->[$idx] =
                { map { $_ => $target->{$_} } @other_keys };
        }
    }
}

1;

__END__
