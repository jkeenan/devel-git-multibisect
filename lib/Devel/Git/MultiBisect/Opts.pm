package Devel::Git::MultiBisect::Opts;
use strict;
use warnings;
use v5.10.0;
our $VERSION = '0.02';
use base qw( Exporter );
our @EXPORT_OK = qw(
    process_options
);
use Carp;
use Cwd;
use Data::Dumper;
use File::Path qw( mkpath );
use File::Temp qw( tempdir );
use Getopt::Long;

=head1 NAME

Devel::Git::MultiBisect::Opts - Prepare parameters for Devel::Git::MultiBisect

=head1 SYNOPSIS

    use Devel::Git::MultiBisect::Opts qw( process_options );

    my $params = process_options();

=head1 DESCRIPTION

This package exports on demand only one subroutine, C<process_options()>, used
to prepare parameters for Devel::Git::MultiBisect.

C<process_options()> takes as arguments an optional list of key-value pairs.
This approach is useful in testing the subroutine but is not expected to be
used otherwise.  C<process_options()> is a wrapper around
Getopt::Long::GetOptions(), so is devoted to processing command-line arguments
provided, for example, to the command-line utility F<multisect> (not yet
created, but to be included in a future version of this CPAN distribution).

The subroutine returns a reference to a hash populated with values in the
following order:

=over 4

=item 1 Default values hard-coded within the subroutine.

=item 2 Command-line options.

=item 3 Key-value pairs provided as arguments to the function.

=back

=cut

sub process_options {
    croak "Must provide even list of key-value pairs to process_options()"
        unless (@_ % 2 == 0);
    my %args = @_;
    if (defined $args{targets}) {
        croak "Value of 'targets' must be an array reference"
            unless ref($args{targets}) eq 'ARRAY';
    }
    if ($args{verbose}) {
        print "Arguments provided to process_options():\n";
        print Dumper \%args;
    }

    my %defaults = (
       'workdir' => cwd(),
       'short' => 7,
       'repository' => 'origin',
       'branch' => 'master',
       'verbose' => 0,
       'configure_command' => 'perl Makefile.PL 1>/dev/null',
       'make_command' => 'make 1>/dev/null',
       'test_command' => 'prove -vb',
   );

    my %opts;
    GetOptions(
        "gitdir=s" => \$opts{gitdir},
        "target=s@" => \$opts{targets},
        "last_before=s" => \$opts{last_before},
        "last-before=s" => \$opts{last_before},
        "first=s" => \$opts{first},
        "last=s" => \$opts{last},
        "configure_command=s" => \$opts{configure_command},
        "make_command=s" => \$opts{make_command},
        "test_command=s" => \$opts{test_command},
        "workdir=s" => \$opts{workdir},
        "outputdir=s" => \$opts{outputdir},
        "short=i" => \$opts{short},
        "repository=s" => \$opts{repository},
        "branch=s" => \$opts{branch},
        "verbose"  => \$opts{verbose}, # flag
    ) or croak("Error in command line arguments\n");

    if ($opts{verbose}) {
        print "Command-line arguments:\n";
        my %defined_opts;
        for my $k (keys %opts) {
            $defined_opts{$k} = $opts{$k} if defined $opts{$k};
        }
        print Dumper \%defined_opts;
    }

    # Final selection of params starts with defaults.
    my %params = map { $_ => $defaults{$_} } keys %defaults;

    # Override with command-line arguments.
    for my $o (keys %opts) {
        if (defined $opts{$o}) {
            $params{$o} = $opts{$o};
        }
    }
    # Arguments provided directly to process_options() supersede command-line
    # arguments.  (Mainly used in testing of this module.)
    for my $o (keys %args) {
        $params{$o} = $args{$o};
    }

    # If user has not supplied a value for 'outputdir' by this point, then we
    # have to use a tempdir.

    if (! exists $params{outputdir}) {
        $params{outputdir} = tempdir
            or croak "Unable to create tempdir";
    }

    croak "Must define only one of 'last_before' and 'first'"
        if (defined $params{last_before} and defined $params{first});

    croak "Must define one of 'last_before' and 'first'"
        unless (defined $params{last_before} or defined $params{first});

    for my $p ( qw|
        workdir
        short
        repository
        branch
        configure_command
        make_command
        test_command
        outputdir

        gitdir
        last
    | ) {
        croak "Undefined parameter: $p" unless defined $params{$p};
    }

    return \%params;
}

1;

