#!/usr/bin/perl

# https://www.json.org/json-en.html

# ./json_greppath.pl big_json.json

use strict;
use warnings;
no warnings "utf8";
binmode STDIN,  ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";
use Encode qw(decode);
    @ARGV = map { decode "UTF-8", $_ } @ARGV;

# BOLD RED like grep(1)
use constant   RESET => "\e[0m";
use constant    BOLD => "\e[1m";
use constant   BLACK => "\e[30m";
use constant     RED => "\e[31m";
# RED, YELLOW and GREEN for malformed json, like perl6
use constant   GREEN => "\e[32m";
use constant  YELLOW => "\e[33m";
use constant    BLUE => "\e[34m";
use constant MAGENTA => "\e[35m";
use constant    CYAN => "\e[36m";
use constant  BRIGHT_YELLOW => "\e[93m";

my $json;
my $jq_output = 0;
$/=undef;

sub usage {
print STDERR <<"USAGE";
  usage :        json_greppath FILE [jq] [-i] [not] [and|or] [--] [PATTERNS]
      cat FILE | json_greppath      [jq] [-i] [not] [and|or] [--] [PATTERNS]
USAGE
}

sub help {
print STDERR <<"HELP";
  usage :        json_greppath FILE [jq] [-i] [not] [and|or] [--] [PATTERNS]
      cat FILE | json_greppath      [jq] [-i] [not] [and|or] [--] [PATTERNS]

  jq           output suitable for the jq CLI utility
  -i           case insensitive
  not          selection is inversed
  and          all PATTERNS must found a match among the keys, indexes and the terminal value of a single "path"
  or           any PATTERN  must found a match among the keys, indexes and the terminal value of a single "path"
  --           after '--', everything is interpreted as PATTERNS
  PATTERN      Perl regular expresion. Quotes are sometime required to avoid shell interpolation,
               and metacharacters must be escaped if they should match literally
HELP
}

if (@ARGV) {

# 	if (-e $ARGV[0]) { local @ARGV = shift; $json = <ARGV>   }
	if (-e $ARGV[0]) { open FH, "<:utf8", $ARGV[0]; $json = <FH>; close FH; shift; }
	elsif ($ARGV[0] =~ /^(?:-{0,2}h|-{0,2}help)$/) {
		help(); exit
	}
}
elsif (not -t STDIN) { $json = <STDIN>  }	# if json from STDIN and patterns in @ARGV, does not work
else { usage(); exit }

if (@ARGV) {
	if ($ARGV[0] =~ /^-{0,2}jq$/ ) { $jq_output = 1; shift }
}

# tokenizer
my $end = 0;
my @tokens;
# stack-based tree walking
my @stack;
my @paths;
my @indexes;
my ($token,$value);
my $container;

while (not $end){

	if    ($json =~ m/\G  \{    /gcx)  { push @tokens,  { type => "curly_open",     value => "{"     } }
	elsif ($json =~ m/\G  \}    /gcx)  { push @tokens,  { type => "curly_close",    value => "}"     } }
	elsif ($json =~ m/\G  \[    /gcx)  { push @tokens,  { type => "square_open",    value => "["     } }
	elsif ($json =~ m/\G  \]    /gcx)  { push @tokens,  { type => "square_close",   value => "]"     } }
	elsif ($json =~ m/\G   ,    /gcx)  { push @tokens,  { type => "comma",          value => ","     } }
	elsif ($json =~ m/\G   :    /gcx)  { push @tokens,  { type => "colon",          value => ":"     } }
	elsif ($json =~ m/\G  true  /gcx)  { push @tokens,  { type => "true",           value => "true"  } }
	elsif ($json =~ m/\G  false /gcx)  { push @tokens,  { type => "false",          value => "false" } }
	elsif ($json =~ m/\G  null  /gcx)  { push @tokens,  { type => "null",           value => "null"  } }

	elsif ($json =~ m/\G[ \n\r\t]+/gc) { 1; }	# more laxed version of whitespace than specification
					# allows the tokenizing of multiple JSON in a single file and separated by newlines

	#-----------------------------------------------------------------------------
	#	any unicode codepoint except " or \ or control characters
	#	[^"\\]  ???

	elsif ($json =~ m@\G	\"	(
				(?:			
					   [^"\\]
				|   (?: \\["\\/bfnrt] | \\u[0-9a-fA-F]{4} )

				)*
						)	\"
					@gcx) { push @tokens, { type => "string", value => $1 } }

	#-----------------------------------------------------------------------------
	elsif ($json =~ m/\G(  [-]?	(?: 0 | [1-9] [0-9]* ) 
								(?: \. [0-9]+  )?			(?# fraction)
								(?: [eE] [-+]? [0-9]+ )?	(?# exponent)

					)/gcx) { push @tokens, { type => "number", value => $1 } }
	#-----------------------------------------------------------------------------

	else { $end = 1 }
}


my $initial_state = "root";
my $state = $initial_state;
# our $state = $initial_state;
our @container_stack; 	# keep track of if we are inside an object or inside an array
our $i;
my %state_transition;
my %state_transition_subroutine;

my $object_opening = sub {
	if (@container_stack) {
		push @stack, {type => "index", value => $indexes[-1]} if $container_stack[-1] eq "array";
	}
	push @container_stack, "object";

	if ($tokens[$i+1]->{type} eq "curly_close") {  # empty object
		push @paths, [ @stack, { type => "empty", value => "{}" } ];
	}
};


my $object_closing = sub {
	if (@container_stack >= 2) {
		$indexes[-1]++ if $container_stack[-2] eq "array";
	}
	pop @container_stack;
	pop @stack;		# if $container_stack[-1] eq "object" delete key, elsif eq "array" delete index
};

my $array_opening = sub {
	if (@container_stack) {
		push @stack, {type => "index", value => $indexes[-1]} if $container_stack[-1] eq "array";
	}
	push @container_stack, "array";

	if (@indexes) { push @indexes, 0 }
	else          { $indexes[0]  = 0 }

	if ($tokens[$i+1]->{type} eq "square_close") {  # empty array
		push @paths, [ @stack, { type => "empty", value => "[]" } ];
	}
};


my $array_closing = sub {
	pop @indexes;
	if (@container_stack >= 2) {
		$indexes[-1]++ if $container_stack[-2] eq "array";
	}
	pop @container_stack;
	if ($container_stack[-1] eq "object") {
		pop @stack;		# delete key
	}
};

my $object_value = sub {
	my ($value, $type) = @_;

	if (@container_stack) {
		if ($container_stack[-1] eq "array") {
			push @stack, {type => "index", value => $indexes[-1]};
			$indexes[-1]++;
		}
	}
	push @stack, {type => $type, value => $value};
	push @paths, [@stack];
	pop @stack;		# delete terminal value
	pop @stack;		# delete key

};

my $array_value = sub {
# 	print "SUB array_value\n";
	my ($value, $type) = @_;

	if (@container_stack) {
		if ($container_stack[-1] eq "array") {
			push @stack, {type => "index", value => $indexes[-1]};
			$indexes[-1]++;
		}
	}
	push @stack, {type => $type, value => $value};
	push @paths, [@stack];
	pop @stack;		# delete terminal value
	pop @stack;		# delete current index
};

my $key = sub {
	my $value = shift;
	push @stack, { type => "key", value => $value };
	$token = $token;
};

# my $comma = sub {
# 	if ($container_stack[-1] eq "array") {
# 		$token = "array_comma";
# 	}
# 	elsif ($container_stack[-1] eq "object") {
# 		$token = "object_comma";
# 	}
# };


my $no_op = sub {
	return;
};

my $malformed = sub {
	my $j;
	my $reconstructed_json = "";
	my $color;
	if (-t STDOUT) { $color = 1 }
	else           { $color = 0 }

	pos($json) = 0;
	my $state = $initial_state;
	@container_stack = ();

	for ($j=0; $j < $i; $j++) {

		($token, $value) = ( $tokens[$j]->{type}, $tokens[$j]->{value} );

		if ($token eq "comma") {
			if ($container_stack[-1] eq "array") {
				$token = "array_comma";
			}
			elsif ($container_stack[-1] eq "object") {
				$token = "object_comma";
			}
		}

		$state = $state_transition{$state}->{$token};

		if ($state =~ /^(?:object|array)_(opening|closing)$/) {
			$state_transition_subroutine{$state}->($value, $token);
		}

		if ($tokens[$j]->{type} eq "string") {
			$json =~ m/\G([ \n\r\t]*"\Q$tokens[$j]->{value}\E")/gc;
			$reconstructed_json .= $1;
		}
		else {
			$json =~ m/\G([ \n\r\t]*\Q$tokens[$j]->{value}\E)/gc;
			$reconstructed_json .= $1;
		}
	}
	$json =~ m/\G([ \n\r\t]*)/;
	$reconstructed_json .= $1;

	my $newlines =      $reconstructed_json =~ tr/\n/\n/;
	my $line_number = 1 + $newlines;
	my $column = 1 + length $reconstructed_json;

	local $\="";
	local $,="";

	print STDERR "Malformed json file :\n";
	print STDERR " Unexpcted token of type ($tokens[$j]->{type}) after token ($state) inside ($container_stack[-1])\n";
	print STDERR " at line $line_number column $column\n\n";
	

	if ($color) {
		print STDERR GREEN, $reconstructed_json, RESET;
		print STDERR YELLOW, "( HERE --> )", RESET;
# 		print STDERR "( HERE --> )";

		if ($tokens[$j]->{type} eq "string") {
			print STDERR RED, "\"$tokens[$j]->{value}\"", RESET;
		}
		else {
			print STDERR RED, $tokens[$j]->{value}, RESET;
		}
	}
	else {
		print STDERR $reconstructed_json;
		print STDERR "( HERE --> )";

		if ($tokens[$j]->{type} eq "string") {
			print STDERR "\"$tokens[$j]->{value}\"";
		}
		else {
			print STDERR $tokens[$j]->{value};
		}
	}

	local $,="\n";
	local $\="\n";
	print "\n\nExpected any of :";

	my @token_meaning = (
              [            root => "just before the start of a JSON object / array"],
              [      curly_open => "{"     ],
              [     curly_close => "}"     ],
              [     square_open => "["     ],
              [    square_close => "]"     ],
              [          string => ""      ],
              [          number => ""      ],
              [            true => "true"  ],
              [           false => "false" ],
              [            null => "null"  ],
              [           comma => ","     ],
              [           colon =>, ":"    ],
              [             end => "EOF or start of an other JSON object / array"],
	);

	foreach my $tok (@token_meaning) {
		if (grep {/$tok->[0]/}
            grep {$state_transition{$state}->{$_} ne "malformed"}
            keys $state_transition{$state}->%*) {
			printf "  %-15s%s\n", $tok->@*;
		}
	}

	exit;
};

%state_transition = (

	          root => {   curly_open => "object_opening",
                         square_open => "array_opening",
	                          string => "malformed",
                              number => "malformed",
                                true => "malformed",
                               false => "malformed",
                                null => "malformed",
                        square_close => "malformed",
                         curly_close => "malformed",
                        object_comma => "malformed",
                         array_comma => "malformed",
                               colon => "malformed",
                                 end => "malformed",  
					},

	object_opening => {       string => "key",
                         curly_close => "object_closing",
                              number => "malformed",
                                true => "malformed",
                               false => "malformed",
                                null => "malformed",
                         square_open => "malformed",
                        square_close => "malformed",
                          curly_open => "malformed",
                        object_comma => "malformed",
                         array_comma => "malformed",
                               colon => "malformed",
                                 end => "malformed",  
					},

	 array_opening => {       string => "array_value",
                              number => "array_value",
                                true => "array_value",
                               false => "array_value",
                                null => "array_value",
                         square_open => "array_opening",
                        square_close => "array_closing",
                          curly_open => "object_opening",
                         curly_close => "malformed",
                        object_comma => "malformed",
                         array_comma => "malformed",
                               colon => "malformed",
                                 end => "malformed",  
					},

	           key => {        colon => "colon",
	                          string => "malformed",
                              number => "malformed",
                                true => "malformed",
                               false => "malformed",
                                null => "malformed",
                         square_open => "malformed",
                        square_close => "malformed",
                          curly_open => "malformed",
                         curly_close => "malformed",
                        object_comma => "malformed",
                         array_comma => "malformed",
                                 end => "malformed",  
					},

	         colon => {       string => "object_value",
                              number => "object_value",
                                true => "object_value",
                               false => "object_value",
                                null => "object_value",
                         square_open => "array_opening",
                          curly_open => "object_opening",
                        square_close => "malformed",
                         curly_close => "malformed",
                        object_comma => "malformed",
                         array_comma => "malformed",
                               colon => "malformed",
                                 end => "malformed",  
					},

	  object_value => { object_comma => "object_comma",
                         curly_close => "object_closing",
	                          string => "malformed",
                              number => "malformed",
                                true => "malformed",
                               false => "malformed",
                                null => "malformed",
                         square_open => "malformed",
                        square_close => "malformed",
                          curly_open => "malformed",
                         array_comma => "malformed",
                               colon => "malformed",
                                 end => "malformed",  
					},

	   array_value => {  array_comma => "array_comma",
                        square_close => "array_closing",
                              string => "malformed",
                              number => "malformed",
                                true => "malformed",
                               false => "malformed",
                                null => "malformed",
                         square_open => "malformed",
                          curly_open => "malformed",
                         curly_close => "malformed",
                        object_comma => "malformed",
                               colon => "malformed",
                                 end => "malformed",  
					},

	  object_comma => {       string => "key",
                              number => "malformed",
                                true => "malformed",
                               false => "malformed",
                                null => "malformed",
                         square_open => "malformed",
                        square_close => "malformed",
                          curly_open => "malformed",
                         curly_close => "malformed",
                        object_comma => "malformed",
                         array_comma => "malformed",
                               colon => "malformed",
                                 end => "malformed",  
					},

	   array_comma => {       string => "array_value",
                              number => "array_value",
                                true => "array_value",
                               false => "array_value",
                                null => "array_value",
                         square_open => "array_opening",
                          curly_open => "object_opening",
                        square_close => "malformed",
                         curly_close => "malformed",
                        object_comma => "malformed",
                         array_comma => "malformed",
                               colon => "malformed",
                                 end => "malformed",  
					},

	object_closing => { object_comma => "object_comma",
                         array_comma => "array_comma",
                         curly_close => "object_closing",
                        square_close => "array_closing",
                                 end => "root",
	                          string => "malformed",
                              number => "malformed",
                                true => "malformed",
                               false => "malformed",
                                null => "malformed",
                         square_open => "malformed",
                          curly_open => "malformed",
                               colon => "malformed",
					},

	 array_closing => { object_comma => "object_comma",
                         array_comma => "array_comma",
                         curly_close => "object_closing",
                        square_close => "array_closing",
                                 end => "root",
	                          string => "malformed",
                              number => "malformed",
                                true => "malformed",
                               false => "malformed",
                                null => "malformed",
                         square_open => "malformed",
                          curly_open => "malformed",
                               colon => "malformed",
					},
);


%state_transition_subroutine = (

	object_opening => $object_opening,
	array_opening  => $array_opening,
	key            => $key,
	object_value   => $object_value,
	array_value    => $array_value,
	object_closing => $object_closing,
	array_closing  => $array_closing,
# 	comma          => $comma,
	object_comma   => $no_op,	# remove this ?
	array_comma    => $no_op,	# remove this ?
	colon          => $no_op,
	root           => $no_op,
    malformed      => $malformed,
);



for ($i=0; $i < @tokens; $i++) {

	($token, $value) = ( $tokens[$i]->{type}, $tokens[$i]->{value} );
	
	if ($token eq "comma") {
		if ($container_stack[-1] eq "array") {
			$token = "array_comma";
		}
		elsif ($container_stack[-1] eq "object") {
			$token = "object_comma";
		}
	}

	$state = $state_transition{$state}->{$token};

	$state_transition_subroutine{$state}->($value, $token);

	if (@container_stack == 0) {
		# in case there are several json objects one after the other in the same file
		$state = $state_transition{$state}->{"end"};
	}
}

unless ($state eq "root") {
	die " Malformed json file\n \"$state\" is not an accepting state\n";
}


my @path;
my @keys_and_values;	# allows regex_patterns to match individual keys/index/terminal values
						# and not in the entire string of one path.       example:  ^format$

# PREPARE THE PATH INFORMATION SO THAT IT IS SUITABLE BOTH FOR SEARCHING AND FOR PRETTY PRINTED OUTPUT

foreach my $branch (@paths) {
	@path = ();
	push @keys_and_values, [];

	for (my $i=0; $i < $branch->$#*; $i++) {		# processing terminal value below
		$_ = $branch->[$i];

		if ( $_->{type} eq "key") {					# STRING OF A KEY
			push $keys_and_values[-1]->@*,  $_;
		}
		elsif ( $_->{type} eq "index") {			# INDEX
			push $keys_and_values[-1]->@*,  $_;
		}
	}

	push $keys_and_values[-1]->@*,  $branch->[-1];  # STRING TERMINAL VALUE
}


sub print_grep_color {
	my $json_paths_to_grep = shift;
	my $patterns = shift;
	my $logic = shift;				# and / or
	my $not = shift;				# negative
	my $case_insensitive = shift;	# case insensitive or not
	my $color = shift;
	my $current_color;

	my $flip_flop;
	my $flip_flop_pat;
	my @pos_pat;
	my @pos;
	my %have_pattern_matched;

	my $path;
	my $pat;
	my $key;
	my $line;
	my $i;
	my $j;
	local $\="";
	local $,="";	

	sub reduce_and {
		foreach (@_) {
			return 0 if $_ == 0;
		}
		return 1;
	}

	sub reduce_or {
		foreach (@_) {
			return 1 if $_ == 1;
		}
		return 0;
	}

	# FOR EACH PATH
	while ($path = shift $json_paths_to_grep->@*) {
		%have_pattern_matched = map { $_ => 0 } $patterns->@*;

		if ($jq_output) { $line = "" } else { $line = "->" }

		# FOR EACH KEY or INDEX, plus the TERMINAL VALUE
		for ( $j=0; $j < $path->@*; $j++) {
			$key = $path->[$j]->{value};	# key / index / terminal value of the path
			@pos = ();
			$flip_flop = "0" x length $key;

			# FROM THE ARRAY OF POSITIONS OF MATCHES OF EACH PATTERN
			# OBTAIN THE OVERLAPPING ARRAY OF POSITIONS,
			# SO THE MATCHES CAN BE COLORED IN RED

			foreach $pat ($patterns->@*) {
				@pos_pat = ();
				$flip_flop_pat = "0" x length $key;

				if ($case_insensitive) {
					while ($key =~ /($pat)/ig) {				# find positions of all matches in a key/index/terminal value
						push @pos_pat, [$-[0], $+[0]];			# and foreach, push start and end positions
					}
				}
				else {
					while ($key =~ /($pat)/g) {					# find positions of all matches in a key/index/terminal value
						push @pos_pat, [$-[0], $+[0]];			# and foreach, push start and end positions
					}
				}
				foreach (@pos_pat) {
					substr $flip_flop_pat, $_->[0], $_->[1] - $_->[0], "1" x ($_->[1] - $_->[0]);
				}
				$flip_flop = $flip_flop | $flip_flop_pat; # accumulated OVERLAP of match positions over 1 key/index/terminal value

				if (@pos_pat) {		# this pattern match at least once for this key / index / value
					$have_pattern_matched{$pat} = $have_pattern_matched{$pat} | 1;	# bitwise-OR, logical-OR doesn't work for this
				}
				else {
					$have_pattern_matched{$pat} = $have_pattern_matched{$pat} | 0;
				}
			}

			# get the overlapping start and end positions of substrings that match for all the regex patterns
			# to obtain one flip-flop seqence of match / outside match alternation
			while ($flip_flop =~ /(1+)/g) {
				push @pos, [$-[0], $+[0]];
			}

			# PRETTY OUTPUT
			# put double-quotes around strings, { } around object keys and [ ] around array indexes
			if ($path->[$j]->{type} eq "key") {								# key
				if ($jq_output) {
					if ($path->[$j]->{value} =~ /^\d| / ) {
						$line .= ".\""
					}
					else { $line .= "." }
				}
# 				else { $line .= "{\"" }
# 				if ($color) {
# 					$line .= "{" . BOLD . BLUE . "\"";
# 				}
				else {
					if ($color and ! @$patterns) {
# 						$line .= "{\"";
						$line .= "{" . BOLD . BLUE . "\"";
						$current_color = BOLD . BLUE;
					}
					else {
						$line .= "{\"";
					}
				}
			}
			elsif ($path->[$j]->{type} eq "index") {						# array index
				if ($jq_output and $j == 0) {								# root container in an array
					$line .= ".["
				}
				else {
# 					$line .= "["
					if ($color and ! @$patterns) {
# 						$line .= "[" . BOLD . YELLOW;
# 						$line .= "[" . YELLOW;
# 						$line .= "[" . BRIGHT_YELLOW;
# 						$line .= "[" . MAGENTA;
# 						$line .= "[" . CYAN;
# 						$line .= "[" . RED;
						$line .= "[";
						$current_color = "";
					}
					else {
						$line .= "[";
					}
				}
			}
			elsif ($path->[$j]->{type} eq "string") {						# string terminal value
				if ($jq_output) {
					$line .= " --> \"";
				}
				else {
# 					$line .= "\"";
					if ($color and ! @$patterns) {
# 						$line .=  "\"";
						$line .= GREEN . "\"";
						$current_color = GREEN;
					}
					else {
						$line .= "\"";
					}
				}
			}
			elsif ($jq_output) { $line .= " --> " }							# terminal value that is not a string
			else {
				if ($jq_output) { $line .= " --> " }
# 				if ($color and ! @pos) {
				if ($color and ! @$patterns) {
					if ($path->[$j]->{type} eq "null") {
						$line .= BOLD . BLACK;
						$current_color .= BOLD . BLACK;
					}
				}
			}

			# COMPOSE THE LINE. ALTERNANCE OF COLORLESS AND COLORED (segments that match) SUBSTRINGS
			if (@pos and $color) {						# if at least one match in the current line
				$line .= substr $key, 0, $pos[0]->[0];									# before first match COLORLESS

				for($i=0; $i < @pos; $i++) {
					$line .=  BOLD . RED . substr($key, $pos[$i]->[0], $pos[$i]->[1] - $pos[$i]->[0]) . RESET;	# match COLORED
# 					$line .=  BOLD . RED . substr($key, $pos[$i]->[0], $pos[$i]->[1] - $pos[$i]->[0]) . RESET . $current_color;	# match COLORED
					if (defined $pos[$i+1]) {
						$line .=      substr $key, $pos[$i]->[1], $pos[$i+1]->[0] - $pos[$i]->[1];	# in-between matches COLORLESS
					}
				}
				$line .= substr($key, $pos[-1]->[1], length $key);									# after last match COLORLESS
			}
			else {
				$line .= $key;
			}

			# PRETTY OUTPUT
			# put double-quotes around strings, { } around object keys and [ ] around array indexes
			# and separate keys, indexes and values by an arrow ->
			if ($path->[$j]->{type} eq "key") {								# key
# 				if ($color) {
# 					$line .= RESET;
# 				}
				if ($jq_output) {
					if ($path->[$j]->{value} =~ /^\d| / ) {
						$line .= "\""
					}
				}
				else {
# 					$line .= "\"}->";
					if ($color and ! @$patterns) {
						$line .= BOLD . BLUE ."\"" . RESET ."}->";
					}
					else {
						$line .= "\"}->";
					}
				}
			}
			elsif ($path->[$j]->{type} eq "index") {						# array index
				if ($jq_output) {
					$line .= "]"
				}
				else {
# 					$line .= "]->";
					if ($color and ! @$patterns) {
						$line .= RESET ."]->";
					}
					else {
						$line .= "]->";
					}
				}
			}
			elsif ($path->[$j]->{type} eq "string") {						# string terminal value
# 				$line .= "\""
				if ($color and ! @$patterns) {
					$line .= GREEN . "\"" . RESET;
				}
				else {
					$line .= "\"";
				}
			}

		}

		if ($logic eq "or") {
			if ($not) {
				print $line . "\n" unless reduce_or(values %have_pattern_matched);
			}
			else {
				print $line . "\n" if reduce_or(values %have_pattern_matched);
			}
		}
		elsif ($logic eq "and") {
			if ($not) {
				print $line . "\n" unless reduce_and(values %have_pattern_matched);
			}
			else {
				print $line . "\n" if reduce_and(values %have_pattern_matched);
			}
		}
		else {	# "print all" case
			print $line . "\n";
		}
	}
}

my $color;
if (-t STDOUT) { $color = 1 }
else           { $color = 0 }

my $match;
my $all_matches;

unless (@ARGV) {
# 	print_grep_color(\@keys_and_values, [], "print all");
# 	print_grep_color(\@keys_and_values, \@ARGV, $logic, $not, $case_insensitive, $color);
	print_grep_color(\@keys_and_values, [], "print all", "", "", $color);
	exit;
}

my $case_insensitive = 0;		# case sensitive by default
my $logic = "and";				# all patterns have to match by default
my $not = 0;					# do not exclude matching patterns by default

for (1) {
	if ($ARGV[0] eq "-i") {							# INSENSITIVE
		shift;
		$case_insensitive = 1;
		redo;
	}
	if ($ARGV[0] =~ /^\-{0,2}or|^\-{0,2}any/) {		# ANY PATTERN HAVE TO MATCH
		shift;
		$logic = "or";
		redo;
	}
	elsif ($ARGV[0] =~ /^-{0,2}and|^-{0,2}all/) {	# ALL PATTERNS HAVE TO MATCH
		shift;
		$logic = "and";
		redo;
	}
	elsif ($ARGV[0] =~ /^-{0,2}not|^-{0,2}none/) {	# NEGATION
		shift;
		$not = 1;
		redo;
	}
	elsif ($ARGV[0] eq "--") {						# END OF OPTIONS, START OR REGEXES
		shift;
		last;
	}
}

print_grep_color(\@keys_and_values, \@ARGV, $logic, $not, $case_insensitive, $color);

