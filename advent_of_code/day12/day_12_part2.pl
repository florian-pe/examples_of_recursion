#!/usr/bin/perl

use strict;
use warnings;
use v5.10;

# https://adventofcode.com/2021/day/12

# ./day_12_part2.pl input12.txt
# implementation a Depth-First Search algorithm
# this is the fast version for this problem, it is less verbose than previous ones
# the backtracking is done by mimicking the behavior of dynamical scoping on the hash %nodes

my (%nodes, $count);

while (<>) {
    chomp;
    my ($a,$b) = split "-", $_;
    push $nodes{ $a }->@*, $b;
    push $nodes{ $b }->@*, $a;
}

sub dfs {
    my ($node, $visited, $two) = @_;
    my $saved = $visited->{$node};

    if ($node eq "start") {
        return if $visited->{start}++ > 0
    }
    elsif ($node eq "end") {
        $count++;
        return;
    }
    elsif ($node eq lc $node) {
        if ($two) {
            return if $visited->{$node}++
        }
        else {
            $two = 1 if $visited->{$node}++
        }
    }

    dfs($_, $visited, $two) for $nodes{$node}->@*;
    $visited->{$node} = $saved;
}

dfs("start", {}, 0);
say $count;

