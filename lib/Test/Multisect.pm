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
    my $older;
    my ($fh, $err) = File::Temp::tempfile();
    if ($data{last_before}) {
        $data{last_before_short} = substr($data{last_before}, 0, $data{short});
        $older = '^' . $data{last_before_short};
        @commits = `git rev-list --reverse $older $data{last} 2>$err`;
    }
    else {
        $data{first_short} = substr($data{first}, 0, $data{short});
        $older = $data{first_short} . '^';
        @commits = `git rev-list --reverse $older $data{last} 2>$err`;
    }
    if (! -z $err) {
        open my $FH, '<', $err or croak "Unable to open";
        my $error = <$FH>;
        chomp($error);
        close $FH or croak "Unable to close";
        croak $error;
    }
    $data{commits} = [ @commits ];

    return bless \%data, $class;
}

1;
# The preceding line will help the module return a true value

