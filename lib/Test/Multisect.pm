package Test::Multisect;
use strict;
use warnings;
use v5.10.0;
use Test::Multisect::Opts qw( process_options );
use Carp;
use Cwd;
use Data::Dumper;
use File::Temp;
use List::Util qw(first);
use Data::Dump qw( pp );

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

    # What will we eventually have to test for (or croak otherwise)?
    # that we can say: git checkout one of last_before or first
    #                  git checkout last
    #                  git clean -dfx
    # that we can call each of configure_command, make_command, test_command

    chdir $data{gitdir} or croak "Unable to chdir";

    $data{last_short} = substr($data{last}, 0, $data{short});
    my @commits = ();
    my ($older, $cmd);
    my ($fh, $err) = File::Temp::tempfile();
    if ($data{last_before}) {
        $older = '^' . $data{last_before};
        $cmd = "git rev-list --reverse $older $data{last} 2>$err";
    }
    else {
        $older = $data{first} . '^';
        $cmd = "git rev-list --reverse ${older}..$data{last} 2>$err";
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
        short   => substr($_, 0, $data{short}),
    } } @commits;
    $data{commits} = [ @extended_commits ];

    return bless \%data, $class;
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
    system(qq|git clean -dfx|) and croak "Unable to 'git clean -dfx'";
    my @branches = qx{git branch};
    chomp(@branches);
    #pp(\@branches);
    my ($cb, $current_branch);
    $cb = first { m/^\*\s+?/ } @branches;
    ($current_branch) = $cb =~ m{^\*\s+?(.*)};
    #say STDERR "RRR: <$current_branch>";

    system(qq|git checkout $commit|) and croak "Unable to 'git checkout $commit";
    system($self->{configure_command}) and croak "Unable to run '$self->{configure_command})'";
    system($self->{make_command}) and croak "Unable to run '$self->{make_command})'";
    my @outputs;
    for my $test (@{$self->{targets}}) {
        my $this_test = "$self->{gitdir}/$test";
        my $no_slash = $test;
        $no_slash =~ s{/}{_}g;
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
        #say STDERR "SSS: <$cmd>";;
        system($cmd) and croak "Unable to run test_command";
        push @outputs, $outputfile;
        print "Created $outputfile\n" if $self->{verbose};
    }
    #say STDERR "TTT: got this far";
    system(qq|git checkout $current_branch|) and croak "Unable to 'git checkout $current_branch";
    return \@outputs;
}

sub run_test_files_on_all_commits {
    my $self = shift;
    my $all_commits = $self->get_commits_range();
    my @all_outputs;
    for my $commit (@{$all_commits}) {
        my $outputs = $self->run_test_files_on_one_commit($commit);
        push @all_outputs, $outputs;
    }
    return \@all_outputs;
}

1;

