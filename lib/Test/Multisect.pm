package Test::Multisect;
use strict;
use warnings;
use v5.10.0;
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

Test::Multisect - Study test output over a range of F<git> commits

=head1 SYNOPSIS

You will typically construct an object of a class which is a child of
F<Test::Multisect>, such as F<Test::Multisect::AllCommits> or
F<Test::Multisect::Transitions>.  All methods documented in this package may
be called from either child class.

    use Test::Multisect::AllCommits;
    $self = Test::Multisect::AllCommits->new(\%parameters);

... or

    use Test::Multisect::Transitions;
    $self = Test::Multisect::Transitions->new(\%parameters);

... and then:

    $commit_range = $self->get_commits_range();

    $full_targets = $self->set_targets(\@target_args);

    $outputs = $self->run_test_files_on_one_commit($commit_range->[0]);

... followed by methods specific to the child class.

=head1 DESCRIPTION

Given a Perl library or application kept in F<git> for version control, it is
often useful to be able to compare the output collected from running one or
several test files over a range of F<git> commits.  If that range is sufficiently
large, a test may fail in B<more than one way> over that range.

If that is the case, then simply asking, I<"When did this file start to
fail?"> is insufficient.  We may want to capture the test output for each
commit, or, more usefully, may want to capture the test output only at those
commits where the output changed.

F<Test::Multisect> provides methods to achieve that objective.  Its child
classes, F<Test::Multisect::AllCommits> and F<Test::Multisect::Transitions>,
provide different flavors of that functionality.

=head1 METHODS

=head2 C<new()>

=over 4

=item * Purpose

Constructor.

=item * Arguments

    $self = Test::Multisect::AllCommits->new(\%params);

or

    $self = Test::Multisect::Transitions->new(\%params);

Reference to a hash, typically the return value of
C<Test::Multisect::Opts::process_options()>.

The hashref passed as argument must contain key-value pairs for C<gitdir>,
C<workdir> and C<outputdir>.  C<new()> tests for the existence of each of
these directories.

=item * Return Value

Object of Test::Multisect child class.

=back

=cut

sub new {
    my ($class, $params) = @_;
    my %data;

    while (my ($k,$v) = each %{$params}) {
        $data{$k} = $v;
    }

    my @missing_dirs = ();
    for my $dir ( qw| gitdir workdir outputdir | ) {
        push @missing_dirs, $data{$dir}
            unless (-d $data{$dir});
    }
    if (@missing_dirs) {
        croak "Cannot find directory(ies): @missing_dirs";
    }

    $data{last_short} = substr($data{last}, 0, $data{short});
    $data{commits} = _get_commits(\%data);
    $data{targets} //= [];

    return bless \%data, $class;
}

sub _get_commits {
    my $dataref = shift;
    my $cwd = cwd();
    chdir $dataref->{gitdir} or croak "Unable to chdir";
    my @commits = ();
    my ($older, $cmd);
    my ($fh, $err) = File::Temp::tempfile();
    if ($dataref->{last_before}) {
        $older = '^' . $dataref->{last_before};
        $cmd = "git rev-list --reverse $older $dataref->{last} 2>$err";
    }
    else {
        $older = $dataref->{first} . '^';
        $cmd = "git rev-list --reverse ${older}..$dataref->{last} 2>$err";
    }
    chomp(@commits = `$cmd`);
    if (! -z $err) {
        open my $FH, '<', $err or croak "Unable to open $err for reading";
        my $error = <$FH>;
        chomp($error);
        close $FH or croak "Unable to close $err after reading";
        croak $error;
    }
    my @extended_commits = map { {
        sha     => $_,
        short   => substr($_, 0, $dataref->{short}),
    } } @commits;
    chdir $cwd or croak "Unable to return to original directory";
    return [ @extended_commits ];
}

=head2 C<get_commits_range()>

=over 4

=item * Purpose

Identify the SHAs of each F<git> commit identified by C<new()>.

=item * Arguments

    $commit_range = $self->get_commits_range();

None; all data needed is already in the object.

=item * Return Value

Array reference, each element of which is a SHA.

=back

=cut

sub get_commits_range {
    my $self = shift;
    return [  map { $_->{sha} } @{$self->{commits}} ];
}

=head2 C<set_targets()>

=over 4

=item * Purpose

Identify the test files which will be run at different points in the commits range.

=item * Arguments

    $target_args = [
        't/44_func_hashes_mult_unsorted.t',
        't/45_func_hashes_alt_dual_sorted.t',
    ];
    $full_targets = $self->set_targets($target_args);

Reference to an array holding the relative paths beneath the C<gitdir> to the
test files selected for examination.

=item * Return Value

Reference to an array holding hash references with these elements:

=over 4

=item * C<path>

Absolute paths to the test files selected for examination.  Test file is
tested for its existence.

=item * C<stub>

String composed by taking an element in the array ref passed as argument and substituting underscores C(<_>) for forward slash (C</>) and dot (C<.>) characters.  So,

    t/44_func_hashes_mult_unsorted.t

... becomes:

    t_44_func_hashes_mult_unsorted_t'

=back

=back

=cut

sub set_targets {
    my ($self, $explicit_targets) = @_;

    my @raw_targets = @{$self->{targets}};

    # If set_targets() is provided with an appropriate argument
    # ($explicit_targets), override whatever may have been stored in the
    # object by new().

    if (defined $explicit_targets) {
        croak "Explicit targets passed to set_targets() must be in array ref"
            unless ref($explicit_targets) eq 'ARRAY';
        @raw_targets = @{$explicit_targets};
    }

    my @full_targets = ();
    my @missing_files = ();
    for my $rt (@raw_targets) {
        my $ft = "$self->{gitdir}/$rt";
        if (! -e $ft) { push @missing_files, $ft; next }
        my $stub;
        ($stub = $rt) =~ s{[./]}{_}g;
        push @full_targets, {
            path    => $ft,
            stub    => $stub,
        };
    }
    if (@missing_files) {
        croak "Cannot find file(s) to be tested: @missing_files";
    }
    $self->{targets} = [ @full_targets ];
    return \@full_targets;
}

=head2 C<run_test_files_on_one_commit()>

=over 4

=item * Purpose

Capture the output from running the selected test files at one specific F<git> checkout.

=item * Arguments

    $outputs = $self->run_test_files_on_one_commit("2a2e54a");

or

    $excluded_targets = [
        't/45_func_hashes_alt_dual_sorted.t',
    ];
    $outputs = $self->run_test_files_on_one_commit("2a2e54a", $excluded_targets);

=over 4

=item 1

String holding the SHA from a single commit in the repository.  This string
would typically be one of the elements in the array reference returned by
C<$self->get_commits_range()>.  If no argument is provided, the method will
default to using the first element in the array reference returned by
C<$self->get_commits_range()>.

=item 2

Reference to array of target test files to be excluded from a particular invocation of this method.  Optional, but will die if argument is not an array reference.

=back

=item * Return Value

Reference to an array, each element of which is a hash reference with the
following elements:

=over 4

=item * C<commit>

String holding the SHA from the commit passed as argument to this method (or
the default described above).

=item * C<commit_short>

String holding the value of C<commit> (above) to the number of characters
specified in the C<short> element passed to the constructor; defaults to 7.

=item * C<file_stub>

String holding a rewritten version of the relative path beneath C<gitdir> of
the test file being run.  In this relative path forward slash (C</>) and dot
(C<.>) characters are changed to underscores C(<_>).  So,

    t/44_func_hashes_mult_unsorted.t

... becomes:

    t_44_func_hashes_mult_unsorted_t'

=item * C<file>

String holding the full path to the file holding the TAP output collected
while running one test file at the given commit.  The following example shows
how that path is calculated.  Given:

    output directory (outputdir)    => '/tmp/DQBuT_SRAY/'
    SHA (commit)                    => '2a2e54af709f17cc6186b42840549c46478b6467'
    shortened SHA (commit_short)    => '2a2e54a'
    test file (target->[$i])        => 't/44_func_hashes_mult_unsorted.t'

... the file is placed in the directory specified by C<outputdir>.  We then
join C<commit_short> (the shortened SHA), C<file_stub> (the rewritten relative
path) and the strings C<output> and C<txt> with a dot to yield this value for
the C<file> element:

    2a2e54a.t_44_func_hashes_mult_unsorted_t.output.txt

=item * C<md5_hex>

String holding the return value of
C<Test::Multisect::Auxiliary::hexdigest_one_file()> run with the file
designated by the C<file> element as an argument.  (More precisely, the file
as modified by C<Test::Multisect::Auxiliary::clean_outputfile()>.)

=back

Example:

    [
      {
        commit => "2a2e54af709f17cc6186b42840549c46478b6467",
        commit_short => "2a2e54a",
        file => "/tmp/1mVnyd59ee/2a2e54a.t_44_func_hashes_mult_unsorted_t.output.txt",
        file_stub => "t_44_func_hashes_mult_unsorted_t",
        md5_hex => "31b7c93474e15a16d702da31989ab565",
      },
      {
        commit => "2a2e54af709f17cc6186b42840549c46478b6467",
        commit_short => "2a2e54a",
        file => "/tmp/1mVnyd59ee/2a2e54a.t_45_func_hashes_alt_dual_sorted_t.output.txt",
        file_stub => "t_45_func_hashes_alt_dual_sorted_t",
        md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
      },
    ]

=item * Comment

In this method's current implementation, we start with a C<git checkout> from
the repository at the specified C<commit>.  We configure (I<e.g.,> C<perl
Makefile.PL>) and build (I<e.g.,> C<make>) the source code.  We then test each
of the test files we have targeted (I<e.g.,> C<prove -vb
relative/path/to/test_file.t>).  We redirect both STDOUT and STDERR to
C<outputfile>, clean up the outputfile to remove the line containing timings
(as that introduces unwanted variability in the C<md5_hex> values) and compute
the digest.

This implementation is very much subject to change.

If a true value for C<verbose> has been passed to the constructor, the method
prints C<Created [outputfile]> to STDOUT before returning.

=back

=cut

sub run_test_files_on_one_commit {
    my ($self, $commit, $excluded_targets) = @_;
    if (defined $excluded_targets) {
        if (ref($excluded_targets) ne 'ARRAY') {
            croak "excluded_targets, if defined, must be in array reference";
        }
    }
    else {
        $excluded_targets = [];
    }
    my %excluded_targets;
    for my $t (@{$excluded_targets}) {
        $excluded_targets{"$self->{gitdir}/$t"}++;
    }

    my $current_targets = [
        grep { ! exists $excluded_targets{$_->{path}} }
        @{$self->{targets}}
    ];
    $commit //= $self->{commits}->[0]->{sha};

    my $current_branch = $self->_configure_build_one_commit($commit);

    my $outputsref = $self->_test_one_commit($commit, $current_targets);

    system(qq|git checkout --quiet $current_branch|)
        and croak "Unable to 'git checkout --quiet $current_branch";

    return $outputsref;
}

sub _configure_build_one_commit {
    my ($self, $commit) = @_;
    chdir $self->{gitdir} or croak "Unable to change to $self->{gitdir}";
    system(qq|git clean --quiet -dfx|) and croak "Unable to 'git clean --quiet -dfx'";
    my @branches = qx{git branch};
    chomp(@branches);
    my ($cb, $current_branch);
    $cb = first { m/^\*\s+?/ } @branches;
    ($current_branch) = $cb =~ m{^\*\s+?(.*)};

    system(qq|git checkout --quiet $commit|) and croak "Unable to 'git checkout --quiet $commit'";
    system($self->{configure_command}) and croak "Unable to run '$self->{configure_command})'";
    system($self->{make_command}) and croak "Unable to run '$self->{make_command})'";
    return $current_branch;
}

sub _test_one_commit {
    my ($self, $commit, $current_targets) = @_; 
    my $short = substr($commit,0,$self->{short});
    my @outputs;
    for my $target (@{$current_targets}) {
        my $outputfile = join('/' => (
            $self->{outputdir},
            join('.' => (
                $short,
                $target->{stub},
                'output',
                'txt'
            )),
        ));
        my $cmd = qq|$self->{test_command} $target->{path} >$outputfile 2>&1|;
        system($cmd) and croak "Unable to run test_command";
        $outputfile = clean_outputfile($outputfile);
        push @outputs, {
            commit => $commit,
            commit_short => $short,
            file => $outputfile,
            file_stub => $target->{stub},
            md5_hex => hexdigest_one_file($outputfile),
        };
        say "Created $outputfile" if $self->{verbose};
    }
    return \@outputs;
}

1;

__END__
#
#            # Our process has to set the value of each element (file_stub) in
#            # %this_round_status to 1 to terminate.
#
#            # For each test file, we know we've identified *one* transition point
#            # when (a) the md5_hex of the commit currently under consideration is
#            # *different* from $current_start_md5_hex and (b) the md5_hex of the
#            # immediately preceding commit is defined and is the *same* as
#            # $current_start_md5_hex.
#
#            # For each test file, we know we've identified *all* transition points
#            # when, after repeating the procedure in the preceding paragraph
#            # enough times, (a) the md5_hex of the current commit is the same as that
#            # of the very last commit and (b) the md5_hex of the immediately
#            # preceding commit is defined and is *different* from the current
#            # md5_hex.
#
#    #        return 1 if sum(values %this_round_status) ==
#    #            scalar(@{$self->{targets}});
#
#            my $h = sprintf("%d" => (($current_start_idx + $current_end_idx) / 2));
#            $self->_run_one_commit_and_assign($h);
#
#
#            # Decision criteria:
#            # We'll handle 1 target test file at a time; too confusing otherwise.
#            my $first_target_stub = $self->{targets}->[0]->{stub};
#            my $current_start_md5_hex = $self->{bisected_outputs}->{$first_target_stub}->[0]->{md5_hex};
#            my $first_target_md5_hex  = $self->{bisected_outputs}->{$first_target_stub}->[$h]->{md5_hex};
#    say STDERR "GGG: ", join('|' => $first_target_stub, $current_start_md5_hex, $first_target_md5_hex);
#
#            # If $first_target_stub eq $current_start_md5_hex, then the first
#            # transition is *after* index $h.  Hence bisection should go upwards.
#            #
#            # If $first_target_stub ne $current_start_md5_hex, then the first
#            # transition has come *before* index $h.  Hence bisection should go
#            # downwards.  However, since the test of where the first transition is
#            # is that index j-1 has the same md5_hex as $current_start_md5_hex but
#            #         index j   has a different md5_hex, we have to do a run on
#            #         j-1 as well.
#
