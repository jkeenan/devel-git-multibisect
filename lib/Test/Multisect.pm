package Test::Multisect;
use strict;
use warnings;
use Test::Multisect::Opts qw( process_options );
use Carp;
use Cwd;
use Data::Dumper;
use File::Temp;
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
    # existence of each file in @{$data{targets}}

    my @missing_dirs = ();
    for my $dir ( qw| gitdir workdir outputdir | ) {
        push @missing_dirs, $data{$dir}
            unless (-d $data{$dir});
    }
    if (@missing_dirs) {
        croak "Cannot find directory(ies): @missing_dirs";
    }

    my @missing_files = ();
    for my $f (@{$data{targets}}) {
        my $ff = "$data{gitdir}/$f";
        push @missing_files, $ff
            unless (-e $ff);
    }
    if (@missing_files) {
        croak "Cannot find files to be tested: @missing_files";
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
        $data{last_before_short} = substr($data{last_before}, 0, $data{short});
        $older = '^' . $data{last_before_short};
        $cmd = "git rev-list --reverse $older $data{last} 2>$err";
        #print STDERR "AAA: last_before: <$cmd>\n";
    }
    else {
        $data{first_short} = substr($data{first}, 0, $data{short});
        $older = $data{first_short} . '^';
        $cmd = "git rev-list --reverse ${older}..$data{last} 2>$err";
        #print STDERR "BBB: first:       <$cmd>\n";
    }
    chomp(@commits = `$cmd`);
    if (! -z $err) {
        open my $FH, '<', $err or croak "Unable to open $err for reading";
        my $error = <$FH>;
        chomp($error);
        close $FH or croak "Unable to close $err after reading";
        croak $error;
    }
    $data{commits} = [ @commits ];

    return bless \%data, $class;
}

sub get_commits_range {
    my $self = shift;
    return $self->{commits};
}

sub run_one_file_on_one_commit {
    my ($self, $commit) = @_;

    chdir $self->{gitdir} or croak "Unable to change to $self->{gitdir}";
    system(qq|git clean -dfx|) and croak "Unable to 'git clean -dfx'";
    system(qq|git checkout $commit|) and croak "Unable to 'git checkout $commit";
    system($self->{configure_command}) and croak "Unable to run '$self->{configure_command})'";
    system($self->{make_command}) and croak "Unable to run '$self->{make_command})'";
    my $this_test = "$self->{gitdir}/$self->{targets}->[0]";
    my $outputfile = join('/' => (
        $self->{outputdir},
        join('.' => (
            $self->{targets}->[0],
            'output',
            'txt'
        )),
    ));
    system(qq|$self->{test_command} $this_test >$outputfile 2>&1| )
        and croak "Unable to run '$self->{test_command})'";
    print "Creating $outputfile\n" if $self->{verbose};
    return $outputfile;
}

1;
# The preceding line will help the module return a true value

