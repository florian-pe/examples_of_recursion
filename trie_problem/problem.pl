#!/usr/bin/perl

use strict;
use warnings;
use v5.10;
use JSON::XS;

# ./problem.pl 
# ./problem.pl | jq

my @list = qw(dir1/file1.txt file2.txt dir1/file3.txt dir2/file4.txt); 
my $root = {};
my $ptr;

for my $path (@list) {
    $ptr=$root;
    for (split "/", $path) {
#         $ptr = $ptr->{$_} //= {};
        $ptr->{$_} //= {};
        $ptr = $ptr->{$_};
    }
}

sub make_json {
    map { { name  => $_,
            children   => [ make_json($_[0]->{$_}) ] }
    } keys $_[0]->%*
}

say encode_json([ make_json($root) ])


