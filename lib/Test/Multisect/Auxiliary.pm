package Test::Multisect::Auxiliary;
use strict;
use warnings;
use v5.10.0;
our $VERSION = '0.01';
use base qw( Exporter );
our @EXPORT_OK = qw(
    clean_outputfile
    hexdigest_one_file
);
use Carp;
use Digest::MD5;
use File::Copy;
#use File::Path qw( mkpath );
#use File::Temp qw( tempdir );
#use Getopt::Long;

=head1 NAME

Test::Multisect::Auxiliary - Helper functions for Test::Multisect

=head1 SYNOPSIS

    use Test::Multisect::Auxiliary qw(
        clean_outputfile
        hexdigest_one_file
    );

=head1 DESCRIPTION

This package exports on demand only subroutines used within publicly available
methods in Test::Multisect.

=cut

sub clean_outputfile {
    my $outputfile = shift;
    my $replacement = "$outputfile.tmp";
    open my $IN, '<', $outputfile
        or croak "Could not open $outputfile for reading";
    open my $OUT, '>', $replacement
        or croak "Could not open $replacement for writing";
    while (my $l = <$IN>) {
        chomp $l;
        say $OUT $l unless $l =~ m/^Files=\d+,\sTests=\d+/;
    }
    close $OUT or croak "Could not close after writing";
    close $IN  or croak "Could not close after reading";
    move $replacement => $outputfile or croak "Could not replace";
    return $outputfile;
}

sub hexdigest_one_file {
    my $filename = shift;
    my $state = Digest::MD5->new();
    open my $FH, '<', $filename or croak "Unable to open $filename for reading";
    $state->addfile($FH);
    close $FH or croak "Unable to close $filename after reading";
    my $hexdigest = $state->hexdigest;
    return $hexdigest;
}

1;


