#!/usr/bin/perl

use strict;
use warnings;
use v5.10;
use Scalar::Util qw(refaddr);
use GraphViz2;
use LWP::UserAgent;
use B;
# use Carp;
# use File::Temp;
# config file ??

# package viz;    # or pic


# TO DO
# add FORMAT slot

# rewrite the script/module withtout making a deep copy of a data structure

# split the recursion subroutines (traverse() and add_edges() into several) so that special packages or data types can be handled differently. Use a hashref of coderef ???

# check the logic of
#   : [$_, { port => "<$_>", text => ref $tree->{value}->[$_]->{value} } ]

# make one (vertical ?) GLOB table / STASH


sub is_string {
    # check if the flag SVf_POK or the flag SVp_POK is set (perl5/sv.h)
    B::svref_2object(\$_[0])->FLAGS & (0x400 | 0x4000) ? 1 : 0
}


our %reference;

sub traverse {
    return unless @_;
    my $refaddr;

    if (@_ > 1) {
        return { type  => "LIST", value => [ map { traverse($_) } @_ ], }
    }

    if (ref($_[0]) eq "") {

        if (ref(\$_[0]) eq "GLOB") {
            return traverse(\$_[0])
        }
        else {
            if (defined $_[0]) {
                return is_string($_[0])
                       ? "\"$_[0]\"" : $_[0]
            }
            else {
                return "undef"
            }
        }
    }

    $refaddr = refaddr($_[0]);
        
    if (exists $reference{$refaddr}) {
        return {
            type => ref $_[0],
            refaddr => $refaddr,
        }
    }

    $reference{ $refaddr } =  1;

    if (ref($_[0]) eq "REF") {
        return {
            type => "REF",
            value => traverse($_[0]->$*),
            refaddr => $refaddr,
        }
    }
    elsif (ref($_[0]) eq "SCALAR") {
        return {
            type => "SCALAR",
            value => traverse($_[0]->$*),
            refaddr => $refaddr,
        }
    }
    elsif (ref($_[0]) eq "ARRAY") {
        return {
            type => "ARRAY",
            value => [ map { traverse($_) } $_[0]->@* ],
            refaddr => $refaddr,
        }
    }
    elsif (ref($_[0]) eq "HASH") {
        return {
            type => "HASH",
            value => { map { $_ => traverse($_[0]->{$_}) } sort keys $_[0]->%* },
            refaddr => $refaddr,
        }
    }
    elsif (ref($_[0]) eq "CODE") {
        return {
            type => "CODE",
            value => "sub { ... }",
            refaddr => $refaddr,
        }
    }
    elsif (ref($_[0]) eq "GLOB") {
        my $glob;
        $glob->{GLOB} = *{$_[0]} . "";

        if (defined *{$_[0]}{SCALAR}) {

            $reference{ refaddr(*{$_[0]}{SCALAR}) } = 1;
            if (ref $_[0] eq "REF") {
                $reference{ refaddr(*{$_[0]}->$*) } = 1;
            }
            $glob->{SCALAR} = traverse($_[0]->$*);
        }
        if (defined *{$_[0]}{CODE}) {
            $reference{ refaddr(*{$_[0]}{CODE}) } = 1;
            $glob->{CODE} = "sub { ... }";
        }
        if (defined *{$_[0]}{IO}) {
            $reference{ refaddr(*{$_[0]}{IO}) } = 1;
            $glob->{IO} = *{$_[0]}{IO} . "";
        }
        if (defined *{$_[0]}{ARRAY}) {
            $reference{ refaddr(*{$_[0]}{ARRAY}) } = 1;
            $glob->{ARRAY} = [ map { traverse($_) } $_[0]->@* ]
        }
        if (defined *{$_[0]}{HASH}) {
            $reference{ refaddr(*{$_[0]}{HASH}) } = 1;
            $glob->{HASH} = { map { $_ => traverse($_[0]->{$_}) } sort keys $_[0]->%* }
        }

        return {
            type => "GLOB",
            value => $glob,
            refaddr => $refaddr,
        }
    }
    else {  # blessed object
        my ($value, $isa);
        if (UNIVERSAL::isa($_[0], "SCALAR")) {
            $value = traverse($_[0]->$*);
            $isa = "SCALAR";
        }
        elsif (UNIVERSAL::isa($_[0], "ARRAY")) {
#             $value = traverse([ $_[0]->@* ])->{value};
            $value = [ map { traverse($_) } $_[0]->@* ];
            # WILL CAUSE PROBLEMS WITH CIRCULAR REFERENCES ???
            $isa = "ARRAY";
        }
        elsif (UNIVERSAL::isa($_[0], "HASH")) {
#             $value = traverse({ $_[0]->%* })->{value};
            $value = { map { $_ => traverse($_[0]->{$_}) } sort keys $_[0]->%* };
            # WILL CAUSE PROBLEMS WITH CIRCULAR REFERENCES ???
            $isa = "HASH";
        }
        else {
            die "unknown base class"
        }

        return {
            type    => ref $_[0],
            value   => $value,
            refaddr => $refaddr,
            isa     => $isa,
        }
    }
}

our $lastname = 0;

sub genname {
    my $addr = shift;
    while (exists $reference{$addr}) {
        $addr++;
    }
    $reference{$addr} = 1;
    $addr;
}

sub add_edges {
    my ($graph, $tree, $parent) = @_;
    my $name;

    if (ref $tree eq "") {
        $name = genname($lastname);
        $graph->add_node(name => $name, label => $tree);
        $graph->add_edge(from => $parent, to => $name);
        return;
    }

    if (! exists $tree->{value}) {
        $graph->add_edge(from => $parent, to => $tree->{refaddr});
        return;
    }

    if ($tree->{type} eq "LIST") {
        $name = genname($lastname);
        $graph->add_node(name => $name, label => "LIST");
        $graph->add_edge(from => $parent, to => $name);
        $parent = $name;
        
        for my $val ($tree->{value}->@*) {
            add_edges($graph, $val, $parent);
        }
    }
    elsif ($tree->{type} eq "REF") {
        $graph->add_node(name => $tree->{refaddr}, label => "REF");
        $graph->add_edge(from => $parent, to => $tree->{refaddr});
        add_edges($graph, $tree->{value}, $tree->{refaddr});
    }
    elsif ($tree->{type} eq "SCALAR") {
        $graph->add_node(name => $tree->{refaddr}, label => "SCALAR");
        $graph->add_edge(from => $parent, to => $tree->{refaddr});
        $name = genname($lastname);
        $graph->add_node(name => $name, label => $tree->{value});
        $graph->add_edge(from => $tree->{refaddr}, to => $name);

    }
    elsif ($tree->{type} eq "ARRAY") {

        $graph->add_node(
            name => $tree->{refaddr},
            shape => "Mrecord",
            label => [
                map {
                    ref $tree->{value}->[$_] eq ""
                    ? [$_, $tree->{value}->[$_] ]
                    : [$_, { port => "<$_>", text => ref $tree->{value}->[$_]->{value} } ]
                } 0 .. $tree->{value}->$#*
            ],
        );

        $graph->add_edge(from => $parent, to => $tree->{refaddr});

        $parent = $tree->{refaddr};

        for (my $i=0; $i < $tree->{value}->@*; $i++) {

            next if ref $tree->{value}->[$i] eq "";

            add_edges($graph, $tree->{value}->[$i], "$parent:$i");
        }


    }
    elsif ($tree->{type} eq "HASH") {

        $graph->add_node(
            name => $tree->{refaddr},
            shape => "record",
            label => [
                map {
                    ref $tree->{value}->{$_} eq ""
                    ? [$_, $tree->{value}->{$_} ]
                    : [$_, { port => "<$_>", text => ref $tree->{value}->{$_}->{value} } ]
                } sort keys $tree->{value}->%*
            ],
        );

        $graph->add_edge(from => $parent, to => $tree->{refaddr});

        $parent = $tree->{refaddr};

        for my $key (sort keys $tree->{value}->%*) {

            next if ref $tree->{value}->{$key} eq "";

            add_edges($graph, $tree->{value}->{$key}, "$parent:$key");
        }
    }
    elsif ($tree->{type} eq "CODE") {
        $name = genname($lastname);
        $graph->add_node(name => $name, label => "CODE");
        $graph->add_edge(from => $parent, to => $name);
        my $code = genname($lastname);
        $graph->add_node(name => $code, label => "sub { ... }");
        $graph->add_edge(from => $name, to => $code);

    }
    elsif ($tree->{type} eq "GLOB") {
        $graph->add_node(name => $tree->{refaddr}, label => "GLOB");
        $graph->add_edge(from => $parent, to => $tree->{refaddr});
        $parent = $tree->{refaddr};

        for my $slot (sort keys $tree->{value}->%*) {
            $name = exists $tree->{value}->{refaddr}
                    ?      $tree->{value}->{refaddr} : genname($lastname);

            $graph->add_node(name => $name, label => $slot);
            $graph->add_edge(from => $parent, to => $name);
            add_edges($graph, $tree->{value}->{$slot}, $name);
        }
    }
    else {

        if ($tree->{isa} eq "SCALAR") {

            $graph->add_node(name => $tree->{refaddr},
                            label => "$tree->{type}, isa SCALAR");
            $graph->add_edge(from => $parent, to => $tree->{refaddr});
            $name = genname($lastname);
            $graph->add_node(name => $name, label => $tree->{value});
            $graph->add_edge(from => $tree->{refaddr}, to => $name);
        }
        elsif ($tree->{isa} eq "ARRAY") {

            $graph->add_node(
                name => $tree->{refaddr},
                shape => "Mrecord",
                label => [
                    [
#                         "$tree->{type}, isa ARRAY",
                        $tree->{type},
                        [ map {
                            ref $tree->{value}->[$_] eq ""
                            ? [$_, $tree->{value}->[$_] ]
    #                         : [$_, { port => "<$_>" } ]
#                             : [$_, { port => "<$_>", text => ref $tree->{value}->[$_] } ]
                            : [$_, { port => "<$_>", text => ref $tree->{value}->[$_]->{value} } ]
                        } 0 .. $tree->{value}->$#*
                        ]
                    ]
                ],
            );

            $graph->add_edge(from => $parent, to => $tree->{refaddr});

            $parent = $tree->{refaddr};

            for (my $i=0; $i < $tree->{value}->@*; $i++) {

                next if ref $tree->{value}->[$i] eq "";

                add_edges($graph, $tree->{value}->[$i], "$parent:$i");
            }


        }
        elsif ($tree->{isa} eq "HASH") {

            $graph->add_node(
                name => $tree->{refaddr},
                shape => "record",
                label => [
                    [
                        $tree->{type},
                        [ map {
                            ref $tree->{value}->{$_} eq ""
                            ? [$_, $tree->{value}->{$_} ]
                            : [$_, { port => "<$_>", text => ref $tree->{value}->{$_}->{value} } ]
                        } sort keys $tree->{value}->%*
                        ]
                    ]
                ],
            );

            $graph->add_edge(from => $parent, to => $tree->{refaddr});

            $parent = $tree->{refaddr};

            for my $key (sort keys $tree->{value}->%*) {

                next if ref $tree->{value}->{$key} eq "";

                add_edges($graph, $tree->{value}->{$key}, "$parent:$key");
            }



        }
    }

}

sub make_graph_file {
    my $dsc = shift;
    my ($top, $label);

    my $graph = GraphViz2->new(
        edge    => {color    => "black" },
        global  => {directed => 1       },
        graph   => {rankdir  => "TP"    },
        node    => {shape    => "rectangle"},
    );

    if (ref $dsc eq "") {
        $top = 0;
        $graph->add_node(name => $top, label => $dsc);
    }
    else {
        $top = genname(0);
        $graph->add_node(name => $top, style => "invis");

        add_edges($graph, $dsc, $top);
    }

    my $format      = shift // "png";
    my $output_file = shift // "graphviz_dsc_output.$format";
    $graph->run(format => $format, output_file => $output_file);
}


# make_graph_file(traverse($node));
# make_graph_file(traverse(\%data));

make_graph_file(traverse(LWP::UserAgent->new));



__END__

graphviz
- edge list

tree
- 










