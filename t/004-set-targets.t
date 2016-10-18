# -*- perl -*-
# t/004-set-targets-t
use strict;
use warnings;
use Test::Multisect;
use Test::Multisect::Opts qw( process_options );
use Test::More tests => 12;
use Cwd;

my $cwd = cwd();

# Before releasing this to cpan I'll have to figure out how to embed a real
# git repository within this repository.

my (%args, $params, $self);
my ($good_gitdir, $good_last_before, $good_last);
my ($target_args, $full_targets);
my $bad_target_args;

$good_gitdir = "$cwd/t/lib/list-compare";
$good_last_before = '2614b2c2f1e4c10fe297acbbea60cf30e457e7af';
$good_last = 'd304a207329e6bd7e62354df4f561d9a7ce1c8c2';
%args = (
    gitdir => $good_gitdir,
    #    targets => [ @good_targets ],
    last_before => $good_last_before,
    last => $good_last,
);
$params = process_options(%args);
$self = Test::Multisect->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Test::Multisect');

$target_args = [
    't/44_func_hashes_mult_unsorted.t',
    't/45_func_hashes_alt_dual_sorted.t',
];
$full_targets = $self->set_targets($target_args);
ok($full_targets, "set_targets() returned true value");
is(ref($full_targets), 'ARRAY', "set_targets() returned array ref");
is_deeply(
    $full_targets,
    [ map { "$self->{gitdir}/$_" } @{$target_args} ],
    "Got expected full paths to target files for testing",
);

{
    local $@;
    $bad_target_args = [
        't/44_func_hashes_mult_unsorted.t',
        '45_func_hashes_alt_dual_sorted.t',
    ];
    eval { $full_targets = $self->set_targets($bad_target_args); };
    like($@, qr/Cannot find file\(s\) to be tested:.*$bad_target_args->[1]/,
        "Got expected error message: bad target file: $bad_target_args->[1]");
}

my ($good_first, $bad_first);
delete $args{last_before};
$good_first = '2a2e54af709f17cc6186b42840549c46478b6467';
$args{first} = $good_first;
$params = process_options(%args);
$self = Test::Multisect->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Test::Multisect');

$full_targets = $self->set_targets($target_args);
ok($full_targets, "set_targets() returned true value");
is(ref($full_targets), 'ARRAY', "set_targets() returned array ref");
is_deeply(
    $full_targets,
    [ map { "$self->{gitdir}/$_" } @{$target_args} ],
    "Got expected full paths to target files for testing",
);

{
    local $@;
    $bad_target_args = [
        't/44_func_hashes_mult_unsorted.t',
        '45_func_hashes_alt_dual_sorted.t',
    ];
    eval { $full_targets = $self->set_targets($bad_target_args); };
    like($@, qr/Cannot find file\(s\) to be tested:.*$bad_target_args->[1]/,
        "Got expected error message: bad target file: $bad_target_args->[1]");
}

