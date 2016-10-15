# -*- perl -*-
# t/002-new.t
use strict;
use warnings;
use Test::Multisect;
use Test::Multisect::Opts qw( process_options );
use Test::More qw(no_plan); # tests => 18;

my %args = (
    gitdir => '/home/jkeenan/gitwork/list-compare',
    targets => [
        't/44_func_hashes_mult_unsorted.t',
        't/45_func_hashes_alt_dual_sorted.t',
    ],
    last_before => '2614b2c2f1e4c10fe297acbbea60cf30e457e7af',
    last => 'd304a207329e6bd7e62354df4f561d9a7ce1c8c2',
);
my $params = process_options(%args);
my $self = Test::Multisect->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Test::Multisect');
