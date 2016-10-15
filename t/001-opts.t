# -*- perl -*-
# t/001-opts.t
use strict;
use warnings;
use Test::Multisect::Opts qw( process_options );
use Test::More tests => 18;

{
    local $@;
    eval { process_options('verbose'); };
    like($@, qr/Must provide even list of key-value pairs to process_options\(\)/,
        "Got expected error message: odd number of arguments to proces_options()"
    );
}

{
    local $@;
    eval { process_options('targets' => 't/phony.t'); };
    like($@, qr/Value of 'targets' must be an array reference/,
        "Got expected error message: 'targets' takes array ref"
    );
}

{
    local $@;
    eval {
        process_options(
            last_before => '12345ab',
            first => '67890ab',
        );
    };
    like($@, qr/Must define only one of 'last_before' and 'first'/,
        "Got expected error message: Provide only one of 'last_before' and 'first'"
    );
}

{
    local $@;
    eval { process_options(); };
    like($@, qr/Must define one of 'last_before' and 'first'/,
        "Got expected error message: Provide one of 'last_before' and 'first'"
    );
}

#        gitdir
#        targets
#        last

{
    local $@;
    eval {
        process_options(
            last_before => '12345ab',
            # gitdir => '/path/to/gitdir',
            targets => [ '/path/to/test/file' ],
            last => '67890ab',
        );
    };
    like($@, qr/Undefined parameter: gitdir/,
        "Got expected error message: Lack 'gitdir'"
    );
}

{
    local $@;
    eval {
        process_options(
            last_before => '12345ab',
            gitdir => '/path/to/gitdir',
            # targets => [ '/path/to/test/file' ],
            last => '67890ab',
        );
    };
    like($@, qr/Undefined parameter: targets/,
        "Got expected error message: Lack 'targets'"
    );
}

{
    local $@;
    eval {
        process_options(
            last_before => '12345ab',
            gitdir => '/path/to/gitdir',
            targets => [ '/path/to/test/file' ],
            # last => '67890ab',
        );
    };
    like($@, qr/Undefined parameter: last/,
        "Got expected error message: Lack 'last'"
    );
}

my $params = process_options(
    last_before => '12345ab',
    gitdir => '/path/to/gitdir',
    targets => [ '/path/to/test/file' ],
    last => '67890ab',
);
ok($params, "process_options() returned true value");
ok(ref($params) eq 'HASH', "process_options() returned hash reference");
for my $k ( qw|
    configure_command
    last_before
    make_command
    outputdir
    repository
    short
    test_command
    verbose
    workdir
| ) {
    ok(defined($params->{$k}), "A default value was assigned for $k: $params->{$k}");
}


