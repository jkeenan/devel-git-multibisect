package Test::Multisect;
use strict;
use warnings;
use v5.10.0;
use Test::Multisect::Opts qw( process_options );
use Test::Multisect::Auxiliary qw(
    clean_outputfile
    hexdigest_one_file
);
use Carp;
use Cwd;
use File::Temp;
use List::Util qw(first);
#use Data::Dump qw( pp );

our $VERSION = '0.01';

=head1 NAME

Test::Multisect - Study test output over a range of git commits

=head1 SYNOPSIS

    use Test::Multisect;

    $self = Test::Multisect->new(\%parameters);

    $commit_range = $self->get_commits_range();

    $full_targets = $self->set_targets(\@target_args);

    $outputs = $self->run_test_files_on_one_commit($commit_range->[0]);

    $all_outputs = $self->run_test_files_on_all_commits();

    $rv = $self->get_digests_by_file_and_commit();

    $transitions = $self->examine_transitions();

=head1 DESCRIPTION

Given a Perl library or application kept in F<git> for version control, it is
often useful to be able to compare the output collected from running one or
several test files over a range of git commits.  If that range is sufficiently
large, a test may fail in B<more than one way> over that range.

If that is the case, then simply asking, I<"When did this file start to
fail?"> is insufficient.  We may want to capture the test output for each
commit, or, more usefully, may want to capture the test output only at those
commits where the output changed.

F<Test::Multisect> provides methods to achieve that objective.

=head1 METHODS

=head2 C<new()>

=over 4

=item * Purpose

Test::Multisect constructor.

=item * Arguments

    $self = Test::Multisect->new(\%params);

Reference to a hash, typically the return value of
C<Test::Multisect::Opts::process_options()>.

The hashref passed as argument must contain key-value pairs for C<gitdir>,
C<workdir> and C<outputdir>.  C<new()> tests for the existence of each of
these directories.

=item * Return Value

Test::Multisect object.

=item * Comment

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

Identify the SHAs of each git commit identified by C<new()>.

=item * Arguments

    $commit_range = $self->get_commits_range();

None; all data needed is already in the object.

=item * Return Value

Array reference, each element of which is a SHA.

=item * Comment

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

Reference to an array holding the absolute paths to the test files selected
for examination.Each such test file is tested for its existence.

=item * Comment

=back

=cut

sub set_targets {
    my ($self, $targets) = @_;

    # If set_targets() is provided with an appropriate argument, override
    # whatever may have been stored in the object by new().

    if (defined $targets and ref($targets) eq 'ARRAY') {
        $self->{targets} = $targets;
    }

    my @missing_files = ();
    my @full_targets = map { "$self->{gitdir}/$_" } @{$self->{targets}};
    for my $f (@full_targets) {
        push @missing_files, $f
            unless (-e $f);
    }
    if (@missing_files) {
        croak "Cannot find file(s) to be tested: @missing_files";
    }
    return \@full_targets;
}

=head2 C<run_test_files_on_one_commit()>

=over 4

=item * Purpose

Capture the output from running the selected test files at one specific git checkout.

=item * Arguments

    $outputs = $self->run_test_files_on_one_commit("2a2e54a");

String holding the SHA from a single commit in the repository.  This string
would typically be one of the elements in the array reference returned by
C<$self->get_commits_range()>.  If no argument is provided, the method will
default to using the first element in the array reference returned by
C<$self->get_commits_range()>.

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

String holding a rewritten version of the relative path beneath C<gitcir> of
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
    my ($self, $commit) = @_;
    $commit //= $self->{commits}->[0]->{sha};
    my $short = substr($commit,0,$self->{short});

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
    my @outputs;
    for my $test (@{$self->{targets}}) {
        my $this_test = "$self->{gitdir}/$test";
        my $no_slash = $test;
        $no_slash =~ s{[./]}{_}g;
        my $outputfile = join('/' => (
            $self->{outputdir},
            join('.' => (
                $short,
                $no_slash,
                'output',
                'txt'
            )),
        ));
        my $cmd = qq|$self->{test_command} $this_test >$outputfile 2>&1|;
        system($cmd) and croak "Unable to run test_command";
        $outputfile = clean_outputfile($outputfile);
        push @outputs, {
            commit => $commit,
            commit_short => $short,
            file => $outputfile,
            file_stub => $no_slash,
            md5_hex => hexdigest_one_file($outputfile),
        };
        say "Created $outputfile" if $self->{verbose};
    }
    system(qq|git checkout $current_branch|) and croak "Unable to 'git checkout $current_branch";
    return \@outputs;
}

=head2 C<run_test_files_on_all_commits()>

=over 4

=item * Purpose

Capture the output from a run of the selected test files at each specific git
checkout in the selected commit range.

=item * Arguments

    $all_outputs = $self->run_test_files_on_all_commits();

None; all data needed is already present in the object.

=item * Return Value

Array reference, each of whose elements is an array reference, each of whose elements is a hash reference with the same four keys as in the return value from C<run_test_files_on_one_commit()>:

    commit
    commit_short
    file
    md5_hex

Example:

    [
      # Array where each element corresponds to a single git checkout

      [
        # Array where each element corresponds to one of the selected test
        # files (here, 2 test files were targetd)

        {
          # Hash where each element correponds to the result of running a
          # single test file at a single commit point

          commit => "2a2e54af709f17cc6186b42840549c46478b6467",
          commit_short => "t_44_func_hashes_mult_unsorted_t",
          file => "/tmp/BrihPrp0qw/2a2e54a.t_44_func_hashes_mult_unsorted_t.output.txt",
          md5_hex => "31b7c93474e15a16d702da31989ab565",
        },
        {
          commit => "2a2e54af709f17cc6186b42840549c46478b6467",
          commit_short => "t_45_func_hashes_alt_dual_sorted_t",
          file => "/tmp/BrihPrp0qw/2a2e54a.t_45_func_hashes_alt_dual_sorted_t.output.txt",
          md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
        },
      ],
      [
        {
          commit => "a624024294a56964eca53ec4617a58a138e91568",
          commit_short => "t_44_func_hashes_mult_unsorted_t",
          file => "/tmp/BrihPrp0qw/a624024.t_44_func_hashes_mult_unsorted_t.output.txt",
          md5_hex => "31b7c93474e15a16d702da31989ab565",
        },
        {
          commit => "a624024294a56964eca53ec4617a58a138e91568",
          commit_short => "t_45_func_hashes_alt_dual_sorted_t",
          file => "/tmp/BrihPrp0qw/a624024.t_45_func_hashes_alt_dual_sorted_t.output.txt",
          md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
        },
      ],
    # ...
      [
        {
          commit => "d304a207329e6bd7e62354df4f561d9a7ce1c8c2",
          commit_short => "t_44_func_hashes_mult_unsorted_t",
          file => "/tmp/BrihPrp0qw/d304a20.t_44_func_hashes_mult_unsorted_t.output.txt",
          md5_hex => "31b7c93474e15a16d702da31989ab565",
        },
        {
          commit => "d304a207329e6bd7e62354df4f561d9a7ce1c8c2",
          commit_short => "t_45_func_hashes_alt_dual_sorted_t",
          file => "/tmp/BrihPrp0qw/d304a20.t_45_func_hashes_alt_dual_sorted_t.output.txt",
          md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
        },
      ],
    ]

=item * Comment

Note:  If the number of commits in the commits range is large, this method
will take a long time to run.  That time will be even longer if the
configuration and build times for each commit are large.  For example, to run
one test over 160 commits from the Perl 5 core distribution might take 15
hours.  YMMV.

The implementation of this method is very much subject to change.

=back

=cut

sub run_test_files_on_all_commits {
    my $self = shift;
    my $all_commits = $self->get_commits_range();
    my @all_outputs;
    for my $commit (@{$all_commits}) {
        my $outputs = $self->run_test_files_on_one_commit($commit);
        push @all_outputs, $outputs;
    }
    $self->{all_outputs} = [ @all_outputs ];
    return \@all_outputs;
}

=head2 C<get_digests_by_file_and_commit()>

=over 4

=item * Purpose

Present the same outcomes as C<run_test_files_on_all_commits()>, but formatted by target file, then commit.

=item * Arguments

    $rv = $self->get_digests_by_file_and_commit();

None; all data needed is already present in the object.

=item * Return Value

Reference to a hash keyed on the basename of the target file, modified to substitute underscores for forward slashes and dots.  The value of each element in the hash is a reference to an array which, in turn, holds a list of hash references, one per git commit.  Each such hash has the following keys:

    commit
    file
    md5_hex

Example:

    {
      t_44_func_hashes_mult_unsorted_t   => [
          {
            commit  => "2a2e54af709f17cc6186b42840549c46478b6467",
            file    => "/tmp/Xhilc8ZSgS/2a2e54a.t_44_func_hashes_mult_unsorted_t.output.txt",
            md5_hex => "31b7c93474e15a16d702da31989ab565",
          },
          {
            commit  => "a624024294a56964eca53ec4617a58a138e91568",
            file    => "/tmp/Xhilc8ZSgS/a624024.t_44_func_hashes_mult_unsorted_t.output.txt",
            md5_hex => "31b7c93474e15a16d702da31989ab565",
          },
          # ...
          {
            commit  => "d304a207329e6bd7e62354df4f561d9a7ce1c8c2",
            file    => "/tmp/Xhilc8ZSgS/d304a20.t_44_func_hashes_mult_unsorted_t.output.txt",
            md5_hex => "31b7c93474e15a16d702da31989ab565",
          },
      ],
      t_45_func_hashes_alt_dual_sorted_t => [
          {
            commit  => "2a2e54af709f17cc6186b42840549c46478b6467",
            file    => "/tmp/Xhilc8ZSgS/2a2e54a.t_45_func_hashes_alt_dual_sorted_t.output.txt",
            md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
          },
          {
            commit  => "a624024294a56964eca53ec4617a58a138e91568",
            file    => "/tmp/Xhilc8ZSgS/a624024.t_45_func_hashes_alt_dual_sorted_t.output.txt",
            md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
          },
          # ...
          {
            commit  => "d304a207329e6bd7e62354df4f561d9a7ce1c8c2",
            file    => "/tmp/Xhilc8ZSgS/d304a20.t_45_func_hashes_alt_dual_sorted_t.output.txt",
            md5_hex => "6ee767b9d2838e4bbe83be0749b841c1",
          },
      ],
    }


=item * Comment

This method currently may be called only after calling
C<run_test_files_on_all_commits()> and will die otherwise.

=back

=cut

sub get_digests_by_file_and_commit {
    my $self = shift;
    unless (exists $self->{all_outputs}) {
        croak "You must call run_test_files_on_all_commits() before calling get_digests_by_file_and_commit()";
    }
    my $rv = {};
    for my $commit (@{$self->{all_outputs}}) {
        for my $target (@{$commit}) {
            push @{$rv->{$target->{file_stub}}},
                {
                    commit  => $target->{commit},
                    file    => $target->{file},
                    md5_hex => $target->{md5_hex},
                };
        }
    }
    return $rv;
}

=head2 C<examine_transitions()>

=over 4

=item * Purpose

Determine whether a run of the same targeted test file run at two consecutive
commits produced the same or different output (as measured by string equality
or inequality of each commit's md5_hex value.

=item * Arguments

    $transitions = $self->examine_transitions();

None; all data needed is already present in the object.

=item * Return Value

Reference to a hash keyed on the basename of the target file, modified to
substitute underscores for forward slashes and dots.  The value of each
element in the hash is a reference to an array which, in turn, holds a list of
hash references, one per each pair of consecutive git commits.  Each such hash
has the following keys:

    older
    newer
    compare

The value for each of the C<older> and C<newer> elements is a reference to a
hash with two elements:

    md5_hex
    idx

... where C<md5_hex> is the digest of the test output file and C<idx> is the
position (count starting at C<0>) of that element in the list of commits in
the commit range.

Example:

    {
      t_44_func_hashes_mult_unsorted_t   => [
          {
            compare => "same",
            newer   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 1 },
            older   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 0 },
          },
          {
            compare => "same",
            newer   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 2 },
            older   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 1 },
          },
          # ...
          {
            compare => "same",
            newer   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 9 },
            older   => { md5_hex => "31b7c93474e15a16d702da31989ab565", idx => 8 },
          },
      ],
      t_45_func_hashes_alt_dual_sorted_t => [
          {
            compare => "same",
            newer   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 1 },
            older   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 0 },
          },
          {
            compare => "same",
            newer   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 2 },
            older   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 1 },
          },
          {
            compare => "same",
            newer   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 3 },
            older   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 2 },
          },
          # ...
          {
            compare => "same",
            newer   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 9 },
            older   => { md5_hex => "6ee767b9d2838e4bbe83be0749b841c1", idx => 8 },
          },
      ],
    }

=item * Comment

This method currently may be called only after calling
C<run_test_files_on_all_commits()> and will die otherwise.

Since in this method we are concerned with the B<transition> in the test
output between a pair of commits, the second-level arrays returned by this
method will have one fewer element than the second-level arrays returned by
C<get_digests_by_file_and_commit()>.

=back

=cut

sub examine_transitions {
    my $self = shift;
    my $rv = $self->get_digests_by_file_and_commit();
    my %transitions;
    for my $k (sort keys %{$rv}) {
        my @arr = @{$rv->{$k}};
        for (my $i = 1; $i <= $#arr; $i++) {
            my $older = $arr[$i-1]->{md5_hex};
            my $newer = $arr[$i]->{md5_hex};
            if ($older eq $newer) {
                push @{$transitions{$k}}, {
                    older => { idx => $i-1, md5_hex => $older },
                    newer => { idx => $i,   md5_hex => $newer },
                    compare => 'same',
                }
            }
            else {
                push @{$transitions{$k}}, {
                    older => { idx => $i-1, md5_hex => $older },
                    newer => { idx => $i,   md5_hex => $newer },
                    compare => 'different',
                }
            }
        }
    }
    return \%transitions;
}

=head2 C<prepare_multisect()>

=over 4

=item * Purpose

Set up data structures within object needed before multisection can start.

=item * Arguments

    $bisected_outputs = $dself->prepare_multisect();

None; all data needed is already present in the object.

=item * Return Value

Reference to an array holding a list of array references, one for each commit
in the range.  Only the first and last elements of the array will be
populated, as the other, internal elements will be populated in the course of
the multisection process.  The first and last elements will hold one element
for each of the test files targeted.  Each such element will be a hash keyed
on the same keys as C<run_test_files_on_one_commit()>:

    commit
    commit_short
    file
    file_stub
    md5_hex

Example:

   [
     [
       {
         commit => "630a7804a7849e0075351ef72b0cbf5a44985fb1",
         commit_short => "630a780",
         file => "/tmp/T8oUInphoW/630a780.t_001_load_t.output.txt",
         file_stub => "t_001_load_t",
         md5_hex => "59c9d8f4cee1c31bcc3d85ab79a158e7",
       },
     ],
     [],
     [],
     # ...
     [],
     [
       {
         commit => "efdd091cf3690010913b849dcf4fee290f399009",
         commit_short => "efdd091",
         file => "/tmp/T8oUInphoW/efdd091.t_001_load_t.output.txt",
         file_stub => "t_001_load_t",
         md5_hex => "318ce8b2ccb3e92a6e516e18d1481066",
       },
     ],
   ];


=item * Comment

=back

=cut

sub prepare_multisect {
    my $self = shift;
    my $all_commits = $self->get_commits_range();
    my @bisected_outputs = ([]) x scalar(@{$all_commits});
    for my $idx (0, $#{$all_commits}) {
        my $outputs = $self->run_test_files_on_one_commit($all_commits->[$idx]);
        $bisected_outputs[$idx] = $outputs;
    }
    $self->{bisected_outputs} = [ @bisected_outputs ];
    return \@bisected_outputs;
}

1;

__END__
