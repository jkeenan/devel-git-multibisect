package Test::Multisect;
use strict;
use warnings;
use Test::Multisect::Opts qw( process_options );
use Carp;
use Cwd;
use Data::Dumper;
use Data::Dump qw( pp );

our $VERSION = '0.01';

sub new {
    my ($class, $params) = @_;
    my %data;

    while (my ($k,$v) = each %{$params}) {
        $data{params}{$k} = $v;
    }

}

1;
# The preceding line will help the module return a true value

