package Test::Multisect::Auxiliary;
use strict;
use warnings;
use v5.10.0;
our $VERSION = '0.01';
use base qw( Exporter );
our @EXPORT_OK = qw(
    clean_outputfile
    hexdigest_one_file
    validate_list_sequence
);
use Carp;
use Digest::MD5;
use File::Copy;

=head1 NAME

Test::Multisect::Auxiliary - Helper functions for Test::Multisect

=head1 SYNOPSIS

    use Test::Multisect::Auxiliary qw(
        clean_outputfile
        hexdigest_one_file
    );

=head1 DESCRIPTION

This package exports, on demand only, subroutines used within publicly available
methods in Test::Multisect.

=head1 SUBROUTINES

=head2 C<clean_outputfile()>

=over 4

=item * Purpose

When we redirect the output of a test harness program such as F<prove> to a
file, we typically get at the end a line matching this pattern:

    m/^Files=\d+,\sTests=\d+/

This line also contains measurements of the time it took for a particular file
to be run.  These timings vary from one run to the next, which makes the
content of otherwise identical files different, which in turn makes their
md5_hex digests different.  So we simply rewrite the test output file to
remove this line.

=item * Arguments

    $outputfile = clean_outputfile($outputfile);

A string holding the path to a file holding TAP output.

=item * Return Value

A string holding the path to a file holding TAP output.

=item * Comment

The return value is provided for the purpose of chaining function calls; the
file itself is changed in place.

=back

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

=head2 C<hexdigest_one_file()>

=over 4

=item * Purpose

To compare multiple files for same or different content, we need a convenient,
short datum.  We will use the C<md5_hex> value provided by the F<Digest::MD5>
module which is part of the Perl 5 core distribution.

=item * Arguments

    $md5_hex = hexdigest_one_file($outputfile);

A string holding the path to a file holding TAP output.

=item * Return Value

A string holding the C<md5_hex> digest for that file.

=item * Comment

The file provided as argument should be run through C<clean_outputfile()>
before being passed to this function.

=back

=cut

sub hexdigest_one_file {
    my $filename = shift;
    my $state = Digest::MD5->new();
    open my $FH, '<', $filename or croak "Unable to open $filename for reading";
    $state->addfile($FH);
    close $FH or croak "Unable to close $filename after reading";
    my $hexdigest = $state->hexdigest;
    return $hexdigest;
}

sub validate_list_sequence {
    my $list = shift;
    croak "Must provide array ref to validate_list_sequence()"
        unless ref($list) eq 'ARRAY';;
    my $rv = [];
    my $status = 1;
    if (! defined $list->[0]) {
        $rv = [0, 0, 'first element undefined'];
        return $rv;
    }
    if (! defined $list->[$#{$list}]) {
        $rv = [0, $#{$list}, 'last element undefined'];
        return $rv;
    }
    # lpd => 'last previously defined'
    my $lpd = $list->[0];
    my %previous = ();
    for (my $j = 1; $j <= $#{$list}; $j++) {
        if (! defined $list->[$j]) {
            next;
        }
        else {
            if ($list->[$j] eq $lpd) {
                next;
            }
            else {
                # value differs from last previously observed
                # Was it ever previously observed?  If so, bad.
                if (exists $previous{$list->[$j]}) {
                    $status = 0;
                    $rv = [$status, $j, "$list->[$j] previously observed"];
                    return $rv;
                }
                else {
                    $previous{$lpd}++;
                    $lpd = $list->[$j];
                    next;
                }
            }
        }
    }
    return [$status];
}

1;


