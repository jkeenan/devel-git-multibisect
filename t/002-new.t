# -*- perl -*-
# t/002-new.t
use strict;
use warnings;
use Test::Multisect;
use Test::Multisect::Opts qw( process_options );
use Test::More qw(no_plan); # tests => 18;

# Before releasing this to cpan I'll have to figure out how to embed a real
# git repository within this repository.

my (%args, $params, $self);

my ($good_gitdir, @good_targets, $good_last_before, $good_last);
$good_gitdir = '/home/jkeenan/gitwork/list-compare';
@good_targets = (
    't/44_func_hashes_mult_unsorted.t',
    't/45_func_hashes_alt_dual_sorted.t',
);
$good_last_before = '2614b2c2f1e4c10fe297acbbea60cf30e457e7af';
$good_last = 'd304a207329e6bd7e62354df4f561d9a7ce1c8c2';
%args = (
    gitdir => $good_gitdir,
    targets => [ @good_targets ],
    last_before => $good_last_before,
    last => $good_last,
);
$params = process_options(%args);
$self = Test::Multisect->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Test::Multisect');

my ($bad_gitdir, @bad_targets, $bad_last_before, $bad_last);
{
    local $@;
    $bad_gitdir = '/home/jkeenan/gitwork/mist-compare';
    $args{gitdir} = $bad_gitdir;
    $params = process_options(%args);
    eval { $self = Test::Multisect->new($params); };
    like($@, qr/Cannot find directory\(ies\): $bad_gitdir/,
        "Got expected error: missing directory $bad_gitdir"
    );
    $args{gitdir} = $good_gitdir;
}

{
    local $@;
    @bad_targets = (
        't/44_func_hashes_mult_unsorted.t',
        '45_func_hashes_alt_dual_sorted.t',
    );
    $args{targets} = \@bad_targets;
    $params = process_options(%args);
    eval { $self = Test::Multisect->new($params); };
    like($@, qr/Cannot find files to be tested: $params->{gitdir}\/$bad_targets[1]/,
        "Got expected error: Cannot find test file: $bad_targets[1]"
    );
    $args{targets} = \@good_targets;
}

{
    local $@;
    $bad_last_before = 'xxxxx';
    $args{last_before} = $bad_last_before;
    $params = process_options(%args);
    eval { $self = Test::Multisect->new($params); };
#    like($@, qr/Cannot find files to be tested: $params->{gitdir}\/$bad_last_before[1]/,
#        "Got expected error: Cannot find test file: $bad_last_before[1]"
#    );
    $args{last_before} = $good_last_before;
}

{
    local $@;
    $bad_last = 'xxxxx';
    $args{last} = $bad_last;
    $params = process_options(%args);
    eval { $self = Test::Multisect->new($params); };
#    like($@, qr/Cannot find files to be tested: $params->{gitdir}\/$bad_last[1]/,
#        "Got expected error: Cannot find test file: $bad_last[1]"
#    );
    $args{last} = $good_last;
}

