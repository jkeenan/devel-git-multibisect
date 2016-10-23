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
#use Data::Dumper;
#use Digest::MD5;
#use File::Copy;
use File::Temp;
use List::Util qw(first);
#use Data::Dump qw( pp );

our $VERSION = '0.01';

sub new {
    my ($class, $params) = @_;
    my %data;

    while (my ($k,$v) = each %{$params}) {
        $data{$k} = $v;
    }
    # What do we have to test for before proceeding?
    # existence of directories workdir, outputdir, gitdir

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

sub get_commits_range {
    my $self = shift;
    return [  map { $_->{sha} } @{$self->{commits}} ];
}

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
        clean_outputfile($outputfile);
        push @outputs, {
            commit => $commit,
            file => $outputfile,
            md5_hex => hexdigest_one_file($outputfile),
            file_short => $no_slash,
        };
        print "Created $outputfile\n" if $self->{verbose};
    }
    system(qq|git checkout $current_branch|) and croak "Unable to 'git checkout $current_branch";
    return \@outputs;
}

#sub _clean_outputfile {
#    my $outputfile = shift;
#    my $replacement = "$outputfile.tmp";
#    open my $IN, '<', $outputfile
#        or croak "Could not open $outputfile for reading";
#    open my $OUT, '>', $replacement
#        or croak "Could not open $replacement for writing";
#    while (my $l = <$IN>) {
#        chomp $l;
#        say $OUT $l unless $l =~ m/^Files=\d+,\sTests=\d+/;
#    }
#    close $OUT or croak "Could not close after writing";
#    close $IN  or croak "Could not close after reading";
#    move $replacement => $outputfile or croak "Could not replace";
#    return $outputfile;
#}
#
#sub _hexdigest_one_file {
#    my $filename = shift;
#    my $state = Digest::MD5->new();
#    open my $FH, '<', $filename or croak "Unable to open $filename for reading";
#    $state->addfile($FH);
#    close $FH or croak "Unable to close $filename after reading";
#    my $hexdigest = $state->hexdigest;
#    return $hexdigest;
#}

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

sub get_digests_by_file_and_commit {
    my $self = shift;
    unless (exists $self->{all_outputs}) {
        croak "You must call run_test_files_on_all_commits() before calling get_digests_by_file_and_commit()";
    }
    my $rv = {};
    for my $commit (@{$self->{all_outputs}}) {
        for my $target (@{$commit}) {
            push @{$rv->{$target->{file_short}}},
                {
                    commit  => $target->{commit},
                    file    => $target->{file},
                    md5_hex => $target->{md5_hex},
                };
        }
    }
    return $rv;
}

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
                    older => { idx => $i-1, file => $older },
                    newer => { idx => $i,   file => $newer },
                    compare => 'same',
                }
            }
            else {
                push @{$transitions{$k}}, {
                    older => { idx => $i-1, file => $older },
                    newer => { idx => $i,   file => $newer },
                    compare => 'different',
                }
            }
        }
    }
    return \%transitions;
}

1;

__END__
