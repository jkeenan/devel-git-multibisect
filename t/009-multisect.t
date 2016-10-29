# -*- perl -*-
# t/009-multisect.t
use strict;
use warnings;
use Test::Multisect::AllCommits;
use Test::Multisect::Transitions;
use Test::Multisect::Opts qw( process_options );
use Test::Multisect::Auxiliary qw(
    validate_list_sequence
);
use Test::More qw(no_plan); # tests => 47;
use Data::Dump qw(pp);
use List::Util qw( first );
use Cwd;

my $cwd = cwd();

my (%args, $params, $self);
my ($good_gitdir, $good_first, $good_last);
my ($target_args, $full_targets);
my ($rv, $transitions, $all_outputs, $all_outputs_count, $expected_count, $first_element);

# In this test file we'll use a different (newer) range of commits in the
# 'dummyrepo' repository.  In this range there will exist 2 test files for
# targeting.

# So that we have a basis for comparison, we'll first run already tested
# methods over the 'dummyrepo'.

$good_gitdir = "$cwd/t/lib/dummyrepo";
$good_first = 'd2bd2c75a2fd9afd3ac65a808eea2886d0e41d01';
$good_last = '199494ee204dd78ed69490f9e54115b0e83e7d39';
%args = (
    gitdir => $good_gitdir,
    first => $good_first,
    last => $good_last,
    verbose => 0,
);
$params = process_options(%args);
$target_args = [
    't/001_load.t',
    't/002_add.t',
];

note("First object");

$self = Test::Multisect::AllCommits->new($params);
ok($self, "new() returned true value");
isa_ok($self, 'Test::Multisect::AllCommits');

$full_targets = $self->set_targets($target_args);
ok($full_targets, "set_targets() returned true value");
is(ref($full_targets), 'ARRAY', "set_targets() returned array ref");
is_deeply(
    [ map { $_->{path} } @{$full_targets} ],
    [ map { "$self->{gitdir}/$_" } @{$target_args} ],
    "Got expected full paths to target files for testing",
);

$all_outputs = $self->run_test_files_on_all_commits();
ok($all_outputs, "run_test_files_on_all_commits() returned true value");
is(ref($all_outputs), 'ARRAY', "run_test_files_on_all_commits() returned array ref");
$all_outputs_count = 0;
for my $c (@{$all_outputs}) {
    for my $t (@{$c}) {
        $all_outputs_count++;
    }
}
is(
    $all_outputs_count,
    scalar(@{$self->get_commits_range}) * scalar(@{$target_args}),
    "Got expected number of output files"
);

$rv = $self->get_digests_by_file_and_commit();
ok($rv, "get_digests_by_file_and_commit() returned true value");
is(ref($rv), 'HASH', "get_digests_by_file_and_commit() returned hash ref");
cmp_ok(scalar(keys %{$rv}), '==', scalar(@{$target_args}),
    "Got expected number of elements: one for each of " . scalar(@{$target_args}) . " test files targeted");
$first_element = first { $_ } keys %{$rv};
is(ref($rv->{$first_element}), 'ARRAY', "Records are array references");
is(
    scalar(@{$rv->{$first_element}}),
    scalar(@{$self->get_commits_range}),
    "Got 1 element for each of " . scalar(@{$self->get_commits_range}) . " commits"
);
is(ref($rv->{$first_element}->[0]), 'HASH', "Records are hash references");
for my $k ( qw| commit file md5_hex | ) {
    ok(exists $rv->{$first_element}->[0]->{$k}, "Record has '$k' element");
}

$transitions = $self->examine_transitions($rv);
ok($transitions, "examine_transitions() returned true value");
is(ref($transitions), 'HASH', "examine_transitions() returned hash ref");
cmp_ok(scalar(keys %{$transitions}), '==', scalar(@{$target_args}),
    "Got expected number of elements: one for each of " . scalar(@{$target_args}) . " test files targeted");
$first_element = first { $_ } keys %{$transitions};
is(ref($transitions->{$first_element}), 'ARRAY', "Records are array references");
$expected_count = scalar(@{$self->get_commits_range}) - 1;
is(
    scalar(@{$transitions->{$first_element}}),
    $expected_count,
    "Got 1 element for each of $expected_count transitions between commits"
);
is(ref($transitions->{$first_element}->[0]), 'HASH', "Records are hash references");
for my $k ( qw| older newer compare | ) {
    ok(exists $transitions->{$first_element}->[0]->{$k}, "Record has '$k' element");
}

#######################################

note("Second object");

my ($self2, $commit_range, $idx, $initial_multisected_outputs, $initial_multisected_outputs_undef_count);

$self2 = Test::Multisect::Transitions->new({ %{$params}, verbose => 1 });
ok($self2, "new() returned true value");
isa_ok($self2, 'Test::Multisect::Transitions');

$commit_range = $self2->get_commits_range;

$full_targets = $self2->set_targets($target_args);
ok($full_targets, "set_targets() returned true value");
is(ref($full_targets), 'ARRAY', "set_targets() returned array ref");
is_deeply(
    [ map { $_->{path} } @{$full_targets} ],
    [ map { "$self2->{gitdir}/$_" } @{$target_args} ],
    "Got expected full paths to target files for testing",
);

note("_prepare_for_multisection()");

# This method, while publicly available and therefore warranting testing, is
# now called within multisect_all_targets() and only needs to be explicitly
# called if, for some reason (e.g., testing), you wish to call
# _multisect_one_target() by itself.

{
    # error case: premature run of _multisect_one_target()
    local $@;
    eval { $rv = $self2->_multisect_one_target(0); };
    like($@,
        qr/You must run _prepare_for_multisection\(\) before any stand-alone run of _multisect_one_target\(\)/,
        "Got expected error message for premature _multisect_one_target()"
    );
}

$initial_multisected_outputs = $self2->_prepare_for_multisection();
ok($initial_multisected_outputs, "_prepare_for_multisection() returned true value");
is(ref($initial_multisected_outputs), 'HASH', "_prepare_for_multisection() returned hash ref");
for my $target (keys %{$initial_multisected_outputs}) {
    ok(defined $initial_multisected_outputs->{$target}->[0], "first element for $target is defined");
    ok(defined $initial_multisected_outputs->{$target}->[-1], "last element for $target is defined");
    is(ref($initial_multisected_outputs->{$target}->[0]), 'HASH', "first element for $target is a hash ref");
    is(ref($initial_multisected_outputs->{$target}->[-1]), 'HASH', "last element for $target is a hash ref");
    $initial_multisected_outputs_undef_count = 0;
    for my $idx (1 .. ($#{$initial_multisected_outputs->{$target}} - 1)) {
        $initial_multisected_outputs_undef_count++
            if defined $initial_multisected_outputs->{$target}->[$idx];
    }
    ok(! $initial_multisected_outputs_undef_count,
        "After _prepare_for_multisection(), internal elements for $target are all as yet undefined");
}

{
    {
        local $@;
        eval { my $rv = $self2->_multisect_one_target(); };
        like($@, qr/Must supply index of test file within targets list/,
            "_multisect_one_target: got expected failure message for lack of argument");
    }
    {
        local $@;
        eval { my $rv = $self2->_multisect_one_target('not a number'); };
        like($@, qr/Must supply index of test file within targets list/,
            "_multisect_one_target: got expected failure message for lack of argument");
    }
}

$rv = $self2->multisect_all_targets();
ok($rv, "multisect_all_targets() returned true value");
say STDERR "AA: multisect_all_targets";
pp($self2);
say STDERR "AA1: ", scalar(@{$self2->{all_outputs}}), " elements";

$rv = $self2->get_multisected_outputs();
say STDERR "BB: get_multisected_outputs";
pp($rv);

my $v = $self2->inspect_transitions($rv);
say STDERR "CC: inspect_transitions";
pp($v);

__END__
