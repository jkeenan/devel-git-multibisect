# -*- perl -*-
# t/007-auxiliary.t
use strict;
use warnings;
use Carp;
use Test::Multisect::Auxiliary qw(
    clean_outputfile
    hexdigest_one_file
);
use Test::More qw(no_plan); # tests => 19;
use File::Temp qw(tempfile);

##### clean_outputfile() #####



##### hexdigest_one_file() #####

{
    my $basic       = 'x' x 10**2;
    my $minus       = 'x' x (10**2 - 1);
    my $end_a       = 'x' x (10**2 - 1) . 'a';
    my $end_b       = 'x' x (10**2 - 1) . 'b';
    my $plus        = 'x' x 10**2 . 'y';
    #say STDERR $_ for ('', $basic, $minus, $end_a, $end_b, $plus);

    my @digests;

    my ($fh1, $t1) = tempfile();
    for (1..100) { say $fh1 $basic }
    close $fh1 or croak "Unable to close $t1 after writing";
    push @digests, hexdigest_one_file($t1);

    my ($fh2, $t2) = tempfile();
    for (1..100) { say $fh2 $basic }
    close $fh2 or croak "Unable to close $t2 after writing";
    push @digests, hexdigest_one_file($t2);

    my ($fh3, $t3) = tempfile();
    for (1.. 99) { say $fh3 $basic }
    say $fh3 $minus;
    close $fh3 or croak "Unable to close $t3 after writing";
    push @digests, hexdigest_one_file($t3);

    my ($fh4, $t4) = tempfile();
    for (1.. 99) { say $fh4 $basic }
    say $fh4 $end_a;
    close $fh4 or croak "Unable to close $t4 after writing";
    push @digests, hexdigest_one_file($t4);

    my ($fh5, $t5) = tempfile();
    for (1.. 99) { say $fh5 $basic }
    say $fh5 $end_b;
    close $fh5 or croak "Unable to close $t5 after writing";
    push @digests, hexdigest_one_file($t5);

    my ($fh6, $t6) = tempfile();
    for (1.. 99) { say $fh6 $basic }
    say $fh6 $plus;
    close $fh6 or croak "Unable to close $t6 after writing";
    push @digests, hexdigest_one_file($t6);

    cmp_ok($digests[0], 'eq', $digests[1],
        "Same md5_hex for identically written files");

    my %digests;
    $digests{$_}++ for @digests;

    my $expect = {
        $digests[0] => 2,
        $digests[2] => 1,
        $digests[3] => 1,
        $digests[4] => 1,
        $digests[5] => 1,
    };
    is_deeply(\%digests, $expect,
        "Got expected count of different digests");
}


