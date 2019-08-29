#!/usr/bin/env perl
# Script to read in a latex file or directory and its subdirectories and check for typographic
# and syntax errors of various sort.
# See https://github.com/erich666/chex_latex for details.

#
# Usage: perl chex_latex.pl
#     this checks all files in the current directory
#
# Usage: perl chex_latex.pl advlite.tex
#     checks just this tex file.
#
# Usage: perl chex_latex.pl latex_docs/thesis
#     check all *.tex files in the directory latex_docs/thesis, and its subdirectories
#
# See 'sub USAGE' below for command-line options.

use strict;

use File::Find;
# options for tests. You can set these to whatever defaults you like
my $style = 1;
my $picky = 0;
my $formal = 1;
my $dashes = 1;
my $usstyle = 1;
my $textonly = 0;
my $testlisting = 0; # If > 0, check code line length as set

# If this phrase is found in the comment on a line, ignore that line for various tests.
# Feel free to add your own "$ok &&" for the various tests below, I didn't go nuts with it.
my $okword = "chex_latex";

# Specify which file has \bibitem references in it, both to avoid style checks on this file and
# to perform specialized tests on this file.
my $refstex = "refs.tex";

# put any files you want to skip into this list
my %skip_filename = (
# for example:
#	"./Boffins_for_Bowling/main.tex"  => "skip",
);

# internal stuff
my $foundref = 0;
my $untouchedtheline;
my $theline;
my $i;
my $input;
my $cfnum;
my $conum;
my $lastl;
my $numbib;
my $title_type;
my $caps_used;
my $caps_loc;
my %filenames_found;
my %cite;
my %label;
my %labelimportant;
my %labelfigure;
my %ref;
my %biborder;
my %bibitem;
my %emfound;
my %eminput;
my @codefiles;
my @citeorder;
my @citeloc;
my @cap_title;
my @cap_title_loc;
my $ok;
my $figcaption = '';
my $figlabel = '';
my $figcenter = '';

# scan command line arguments
my @dirs;
while (@ARGV) {
	# check 
	my $arg = shift(@ARGV) ;
	# does it start with a "-"?
	if ( substr($arg,0,1) eq '-' ) {
		# go through characters and interpret them
		my $chars = substr($arg,1);
		for ( $i=0; $i < length($chars); $i++ ) {
			my $char = substr($chars, $i, 1);
			if ( $char eq 'd' ) {
				# set $dashes to false, to ignore dash tests
				$dashes = 0;
			} elsif ( $char eq 'f' ) {
				# set $formal to false, to allow informal bits such as contractions
				$formal = 0;
			} elsif ( $char eq 'p' ) {
				# set $picky to TRUE, to check for things that may be stylistically suspect
				$picky = 1;
			} elsif ( $char eq 's' ) {
				# set $style to TRUE to catch a number of style problems
				$style = 1;
			} elsif ( $char eq 'u' ) {
				# set $usstyle to false, to ignore U.S. punctuation style tests for period or comma outside quotes
				$usstyle = 0;
			} elsif ( $char eq 'c' ) {
				# test lines of code for if they're longer than the value set
				$testlisting = shift(@ARGV);
				if ( length($testlisting) == 0 || $testlisting < 1 ) {
					printf STDERR "ABORTING: Code line length test not set. Syntax is '-c 71' or other number of characters.\n";
					$testlisting = 0;
					&USAGE();
					exit 0;
				}
			# TODO - hook these up
			} elsif ( $char eq 'O' ) {
				# instead of "chex_latex" meaning the line is OK, you can put your own single word.
				$okword = shift(@ARGV);
				if ( length($okword) == 0 || $i+1 < length($chars) ) {
					print STDERR "The -o option must be followed by a word.'\n";
					&USAGE();
					exit 0;
				}
			} elsif ( $char eq 'R' ) {
				# instead of refs.tex, set your own bibitem file.
				$refstex = shift(@ARGV);
				if ( length($refstex) == 0 || $i+1 < length($chars) ) {
					printf STDOUT "Reference tex file unset.\n";
					$refstex = '';
				}
			} else {
				print STDERR "Unknown argument character '$char'.\n";
				&USAGE();
				exit 0;
			}
		}
	} else {
		# we assume the argument must then be a directory or file - add it appropriately
		if ( -e $arg ) {
			if ( -d $arg) {
				# directory
				push @dirs, $arg;
			} else {
				$codefiles[$cfnum] = $arg;
				$cfnum++;
				if ( !($arg =~ /.tex$/) ) {
					if ( $textonly != 1) {
						printf STDOUT "Files will be treated as plain text.\n";
					}
					$textonly = 1;
				}
			}
		} else {
			printf STDERR "The argument >$arg< is neither a valid file nor an option.\n";
			&USAGE();
			exit 0;
		}
	}
}

# if specific files were listed, don't recurse directories
if ( $cfnum == 0 ) {
	if ( scalar @dirs == 0 ) { 
		$dirs[0] = '.';	# default is current directory
	}
	my $dirchop = 0 ;
	# silly hack to remove "./" from front of string.
	if ( $dirs[0] eq '.' ) {
		$dirchop = 2 ;
	}
	find( \&READRECURSIVEDIR, @dirs, );
}

&PROCESSFILES();

exit 0;

#=========================================================

sub USAGE
{
	print "Usage: perl chex_latex.pl [-dfpsu] [-O okword] [-R refs.tex] [directory [directory...]]\n";
	print "  -c # - check number of characters in a line of code against the value passed in, e.g., 80.\n";
	print "  -d - turn off dash tests for '-' or '--' flagged as needing to be '---'.\n";
	print "  -f - turn off formal writing check; allows contractions and other informal usage.\n";
	print "  -p - turn ON picky style check, which looks for more style problems but is not so reliable.\n";
	print "  -s - turn ON style check; looks for poor usage, punctuation, and consistency.\n";
	print "  -u - turn off U.S. style tests for putting commas and periods inside quotes.\n";
}

sub READRECURSIVEDIR
{
	if ( m/\.(tex)$/ ) {
		$codefiles[$cfnum] = $File::Find::name;
		$cfnum++;
	}
}

sub PROCESSFILES
{
	my $i;
	my @fld;
	for ( $i = 0 ; $i < $cfnum ; $i++ ) {

		@fld = split('/',$codefiles[$i]);	# split
		my $nextfile = $fld[$#fld];
		my @subfld;
		@subfld = split('\.',$nextfile);
		#my $path = substr($codefiles[$i],$dirchop,length($codefiles[$i])-length($nextfile)-$dirchop);
		# not vital for a book
		#if ( exists($filenames_found{$nextfile}) ) {
		#	print "BEWARE: two .tex files with same name $nextfile found in directory or subdirectory.\n";
		#}
		$filenames_found{$nextfile} = 1;

		$input = $codefiles[$i];
		if ( !exists($skip_filename{$input}) ) {
			&READCODEFILE();
		}
	}

	my $elem;
	my $potential = 0;
	foreach $elem ( sort keys %label ) {
		if ( !exists( $ref{$elem} ) ) {
			# check if figure is labeled. TODO: should add tables
			if ( $labelfigure{$elem} == 1 && $labelimportant{$elem} ) {
				if ( $potential == 0 ) { $potential = 1; printf "\n\n*************************\nPOTENTIAL ERRORS FOLLOW:\n"; }
				print "Labeled, but not referenced via \\ref: $elem in \'$label{$elem}\'\n";
			}
		}
	}
	# element referenced but not found
	my $critical = 0;
	foreach $elem ( sort keys %ref ) {
		if ( !exists( $label{$elem} ) && !($elem =~ /code:/ || $elem =~ /list:/) ) {
			if ( $critical == 0 ) { $critical = 1; printf "\n\n*************************\nCRITICAL ERRORS FOLLOW:\n"; }
			print "Referenced, does not exist (perhaps you meant to \\cite and not \\ref or \\pageref?): \'$elem\' in \'$ref{$elem}\'\n";
		}
	}
	
	if ( $foundref ) {
		# element cited but not found
		foreach $elem ( sort keys %cite ) {
			if ( !exists( $bibitem{$elem} ) ) {
				if ( $critical == 0 ) { $critical = 1; printf "\n\n*************************\nCRITICAL ERRORS FOLLOW:\n"; }
				print "Cited, does not exist (perhaps you meant to \\ref?): \'$elem\' in \'$cite{$elem}\'\n";
			}
		}
	}

	# bad citation order
	for ($i = 0; $i < $conum ; $i++ ){
		my $subf = $citeorder[$i];
		my @fldc = split(/,/,$subf);
		my $checkit = 1;
		#printf "on $i with $subf\n";
		for ( my $j = 1; $j <= $#fldc && $checkit; $j++ ) {
			if ( $biborder{$fldc[$j-1]} > $biborder{$fldc[$j]} ) {
				$checkit = 0;
				print "ERROR: citations *$subf* out of order (or reference missing) at $citeloc[$i]\n";
			}
		}
	}
	
	# bibitems not referenced
	printf "==========================================================================================================\n";
	foreach $elem ( sort keys %bibitem ) {
		if ( !exists( $cite{$elem} ) ) {
			if ( $critical == 0 ) { $critical = 1; printf "\n\n*************************\nCRITICAL ERRORS FOLLOW:\n"; }
			print "bibitem not referenced: $elem in $bibitem{$elem}\n";
		}
	}
}

sub READCODEFILE
{
	my @fld;
	my $isref = 0;
	my $prev_line = '';
	my $lcprev_line = '';
	my $prev_real_line = '';
	if ( $input =~ /$refstex/ ) { $isref = 1; } else { $isref = 0; }
	my $infigure = 0;
	my $inequation = 0;
	my $inlisting = 0;
	my $insidecode = 0;
	my $intable = 0;
	my $inquote = 0;
	my $ignore_first = 0;
	my %indexlong;
	my $subfigure = 0;
	my $tabsfound = 0;
	my $justlefteq = 0;
	my $justblankline = 0;

	# now the code file read
	unless (open(DATAFILE,$input)) {
		printf STDERR "Can't open $input: $!\n";
		exit 1 ;
	}
	while (<DATAFILE>) {
		if ( /\R$/ ) {
			# should work in perl 5.10 and later
			chop;       # strip record separator
		}
		$untouchedtheline = $theline = $_;
		my $skip = 0;
		my $period_problem = 0;
		
		# if the line has chex_latex on it in the comments, can ignore certain flagged problems,
		# and ignore figure names.
		if ( $theline =~ /$okword/ ) { # TODO - look only in comments for okword
			$ok = 1; # to turn off "% chex_latex" testing, simply set $ok = 0;
		} else {
			$ok = 0;
		}
#printf "OK is $ok $. $theline\n";
		my $twook |= $ok;
		
		if ( $theline eq '' ) {
			$justblankline = 1;
		}
		
		# if ( $justlefteq ) {
			# if ( $theline eq '' ) {
				# $justlefteq++;
			# } else {
				# # trim any comment from the line.
				# if ( $theline =~ /%/ ) {
					# $theline = $`;
				# }
				# if ( $theline =~ /^where/ ) {
					# if ( $justlefteq > 1 ) {
						# print "WHERE might have a blank line before it, on line $. in $input.\n";
					# }
				# }
				# $justlefteq = 0;
			# }
		# }
		# test if there's a blank line after an equation - go see if there should be.
		if ( $picky && $justlefteq ) {
			if ( $theline eq '' ) {
				print "EQUATION ends with blank line after. OK? On line $. in $input.\n";
			}
			$justlefteq = 0;
		}

		# cut rest of any line with includegraphics and trim= on it
		# really, could just delete this line altogether, but let's leave open
		# the possibility we want to do something with it
		if ( $theline =~ /\\includegraphics\[/ ) {
			if ( $theline =~ /trim=/ ) {
				# delete rest of line, to avoid junk like:
				# trim=2.3in 0in 0in 0in
				# which flags a word duplication problem.
				$theline = $`;
			}
			elsif ( $theline =~ /{/ ) {
				# trim the image file name so that we don't check that for misspellings, etc.
				$theline = $`;
			}
		}
		# other lines that get ignored
		if ( $theline =~ /\\def/ ) { $theline = $`; }
		if ( $theline =~ /\\graphicspath/ ) { $theline = $`; }
		if ( $theline =~ /\\usepackage/ ) { $theline = $`; }
		if ( $theline =~ /\\counterwithout/ ) { $theline = $`; }
		if ( $theline =~ /\\hyphenation/ ) { $theline = $`; }
		if ( $theline =~ /\\definecolor/ ) { $theline = $`; }
		if ( $theline =~ /\\newcommand/ ) { $theline = $`; }
		if ( $theline =~ /\\ifthenelse/ ) { $theline = $`; }
		if ( $theline =~ /\\renewcommand/ ) { $theline = $`; }
		if ( $theline =~ /\\hypersetup/ ) { $theline = $`; }
		if ( $theline =~ /\\STATE/ ) { $theline = $`; }
		if ( $theline =~ /\\WHILE/ ) { $theline = $`; }
		if ( $theline =~ /\\IF/ ) { $theline = $`; }
		if ( $theline =~ /\\ELSE/ ) { $theline = $`; }
		if ( $theline =~ /\\draw/ ) { $theline = $`; }
		if ( $theline =~ /\\node/ ) { $theline = $`; }
		if ( $theline =~ /\\foreach/ ) { $theline = $`; }
		if ( $theline =~ /\\fill/ ) { $theline = $`; }
		if ( $theline =~ /\\vfill/ ) { $theline = $`; }
		if ( $theline =~ /\\subfloat/ ) { $theline = $`; }
		if ( $theline =~ /\\input/ ) { $theline = $`; }
		if ( $theline =~ /\\centering/ ) { $theline = $`; $figcenter = 'has centering'; }
		if ( $theline =~ /\\bibliography/ ) { $theline = $`; }
		if ( $theline =~ /\\import/ ) { $theline = $`; }
		#if ( $theline =~ /\\begin/ ) { $theline = $`; }
		#if ( $theline =~ /\\end/ ) { $theline = $`; }

		
		# hit a new paragraph?
		my $newpara = (length($theline) == 0);
		# convert \% to Pct so we don't confuse it with a comment.
		$theline =~ s/\\%/PercentSign/g;
		# now trim any comment from the line.
		if ( $theline =~ /%/ ) {
			$theline = $`;
		}
		# convert back
		$theline =~ s/PercentSign/%/g;
		# chop whitespace away from the end of the line, it will make lines join poorly & screw up searches for errors
		if ( $theline =~ /\s+$/ ) {
			$theline = $`;
		}
		if ( $theline =~ /^\s+/ ) {
			$theline = $';
		}
		if ( $skip ) {
			$theline = "";
		}
		# else if line is blank or a control line, move along, nothing to see here.
		if ( $skip || length($theline) > 0 ) {
		
		# previous "last token" and next line joined, to look for multiline problems.
		my $twoline = ' ' . $prev_line . ' ' . $theline . ' ';

		# index searcher: find left |( and right |) index entries and make sure they match up.
		my $str = $twoline;
		my $newtwoline = ' ';

		# index test
		while ( !$textonly && $str =~ /\\index\{([\d\w_".'\~\-\$& !^()\/\|\\@]+)}/ ) {
			my $indexname = $1;

			$str = $';
			$newtwoline .= $`;
			if ( $indexname =~ /\|\(/ ) {
				#print "left index *$`*\n";
				#print "middle index $&\n";
				$indexlong{$`}++;
				if ( $indexlong{$`} > 1 ) {
					print "SERIOUS: nested index of same term, very dangerous, on line $. in $input.\n";
				}
			} elsif ( $indexname =~ /\|\)/ ) {
				#print "right index *$`*\n";
				if ( !exists($indexlong{$`}) ) {
					printf "ERROR: found right index {$`|)} without left index in $input.\n    Perhaps you repeated this right entry?\n";
				} else {
					$indexlong{$`}--;
					if ( $indexlong{$`} == 0 ) {
						delete $indexlong{$`};
					}
				}
			} 
		}
		$newtwoline .= $str . ' ';
		#if ( !$twook && $twoline ne $newtwoline ) {
		#	print "twoline $twoline\n and newline $newtwoline\n";
		#}
		# twoline now has the index entries removed from it.
		$twoline = $newtwoline;
		my $lctwoline = lc($twoline);
		
		$str = $theline;
		if ( !$textonly && $str =~ /see\{([\d\w_".'\~\-\$& !^()\/\|\\@]+)}/ ) {
			my $seestr = $1;
			if ( $seestr =~ /!/ ) {
				print "Error: ''$seestr'', replace exclamation point with comma and space, on line $.\n";
			}
		}

		my $lctheline = lc($theline);

		# have to do this one early, as includegraphics gets culled out
		if ( $theline =~ /begin\{subfigure}/ || $theline =~ /begin\{minipage}/ ) {
			$subfigure = 1;
		}
		# it's not so nice to make width=1.0, 100%, as the figure will look wider than the text.
		if ( !$testlisting &&!$ok && !$subfigure && $theline =~ /\\includegraphics\[/ ) {
			if ( !$subfigure && $theline =~ /width=1.0\\/ || $theline =~ /width=\\/) {
				print "POSSIBLE OVERHANG: please make the figure width a maximum of 0.95, on line line $. in $input.\n";
			}
		}

		# check for section, etc. and see that words are capitalized
		# can compare with Chicago online https://capitalizemytitle.com/ - may need to add more connector words to this subroutine.
		if ( !$testlisting &&
			$theline =~ /\\chapter\{([A-Za-z| -]+)\}/ ||
			$theline =~ /\\section\{([A-Za-z| -]+)\}/ ||
			$theline =~ /\\subsection\{([A-Za-z| -]+)\}/ ||
			$theline =~ /\\subsubsection\{([A-Za-z| -]+)\}/ ||
			$theline =~ /\\title\{([A-Za-z| -\\,]+)\}/ ) {
			my @wds = split(/[ -]/,$1);	# split
			for ($i = 0; $i <= $#wds; $i++ ) {
				if ( $i == 0 ) {
					# first word - just check for capitalization, which should always be true for any form of title
					if ( CAPITALIZED($wds[$i]) == 0 ) {
						printf "LIKELY SERIOUS: Chapter or Section's first word '$wds[$i]' is not capitalized, on line $. in $input.\n";
					}
				} else {
					my $sw = &CONNECTOR_WORD($wds[$i], $i);
					if ( !$ok && $sw == 2 ) {
						# This test is always good, you should never capitalize connector words. Really.
						print "LIKELY SERIOUS: Chapter or Section title has a word '$wds[$i]' that should not be capitalized, on line $. in $input.\n";
						print "    You can test your title at https://capitalizemytitle.com/\n";
					} elsif ( $sw == 0 && (length($wds[$i]) > 0) && &SECTION_MISMATCH($wds[$i]) ) {
						# Not a connector word, and the capitalization is different than the previous word encountered
						# in this type of chapter/section/subsection, so flag it.
						printf "SERIOUS: Title has a word '$wds[$i]' that is %s, on line $. in $input.\n",
							$caps_used ? "uncapitalized" : "capitalized";
						print "    This does not match the style in the first $title_type encountered\n";
						printf "    $caps_loc, which is %s word.\n",
							$caps_used ? "a capitalized" : "an uncapitalized";
						if ( $caps_used ) {
							print "    Ignore if this word '$wds[$i]' is a 'connector word' such as 'in' or 'and' (and please report this bug).\n";
							print "    To be sure, you can test your title at https://capitalizemytitle.com/\n";
							print "    You could edit the code and comment out this test, or add the word to CONNECTOR_WORD in the program.\n";
						}
					}
				}
			}

		}

		# check if we're in an equation or verbatim section
		if ( $theline =~ /begin\{equation/ || 
			$theline =~ /begin\{eqnarray/ || 
			$theline =~ /begin\{comment/ || 
			$theline =~ /begin\{IEEEeqnarray/ || 
			$theline =~ /begin\{align/ || 
			$theline =~ /\\\[/ ||
			$theline =~ /begin\{lstlisting}/ ) {
			$inequation = 1;
			if ( $theline =~ /begin\{lstlisting}/ ) {
				$inlisting = 1;
			}
			if ( $justblankline && ($theline =~ /begin\{equation}/ || $theline =~ /begin\{eqnarray}/ || $theline =~ /begin\{IEEEeqnarray}/) ) {
				print "The equation has a blank line in front of it - is this intentional? On line $. in $input.\n";
			}
		}
		$justblankline = 0;
		if ( $theline =~ /begin\{figure}/ ||
			$theline =~ /begin\{tikzpicture}/ ) {
			$infigure = 1;
			$subfigure = 0;
		}
		if ( $theline =~ /begin\{gather}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{tabbing}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{falign}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{verbatim}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{quote\}/ ) {
			$inquote = 1;
		}
		if ( $theline =~ /begin\{tabular/ ) {
			# turn off equation tests, too, in tables
			$intable = 1;
			$inequation = 1;
		}

		# let the main testing begin!
		if ( $inlisting && ($testlisting > 0) ) {
			if ( !$ok &&
					!($theline =~ /label=/) && 
					!($theline =~ /caption=/) && 
					!($theline =~ /language=/) && 
					!($theline =~ /morekeywords=/) && 
					!($theline =~ /basicstyle=/) &&
					!($theline =~ /mathescape=/) ) {
				# A ] will end the definitions.
				if ( !$insidecode && $theline =~ /\]/ ) {
					$insidecode = 1;
				}
				if ( $insidecode ) {
					# OK, real code, I think. Figure out character count
					my $codestr = $untouchedtheline;
					if ( !$tabsfound && $codestr =~ /\t/ ) {
						printf "***TABS FOUND IN LISTING: first found on line $. in $input.\n";
						$tabsfound = 1;
					}
					if ( $codestr =~ /\$/ ) {
						printf ">>>EQUATION FOUND IN LISTING on line $. in $input.\n";
					}
					# clever expand tabs to spaces, four spaces to the tab.
					$codestr =~ s/\t+/' ' x (length($&) * 4 - length($`) % 4)/e;
					# convert references to equation numbers, roughly using 5 spaces.
					$codestr =~ s/\\ref\{([\w_:-]+)}/X.X/g;
					# remove all $ for math equations, just to cut down a bit and see if it all fits.
					$codestr =~ s/\$//g;
					my $codelen = length($codestr);
					if ( $codelen > $testlisting ) {
						printf "CODE POSSIBLY TOO LONG: $codelen characters on line $. in $input.\n";
						printf "    code: $codestr\n";
					}
				}
			}
		}
		
		# ------------------------------------------
		# Check doubled words. Possibly the most useful test in the whole script
		# the crazy one, from https://stackoverflow.com/questions/23001408/perl-regular-expression-matching-repeating-words, catches all duplicate words such as "the the"
		if( !$twook && !$infigure && !$intable && !$inequation && $lctwoline =~ /(?:\b(\w+)\b) (?:\1(?: |$))+/ && $1 ne 'em' ) {
			print "SERIOUS: word duplication problem of word '$1' on line $. in $input.\n";
		}
		# surprisingly common
		if( !$twook && $lctwoline =~ / a the / ) {
			print "'a the' to 'the' on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ / the a / ) {
			print "'the a' to 'the' on line $. in $input.\n";
		}

		# ---------------------------------------------------------
		# bibitem stuff, if you use this style. bibitems are assumed to be in refs.tex
		if( $isref && ($prev_line =~ /bibitem/) ) {
			# does next line have a " and " without a "," before the space?
			if ( !$ok && ( $theline =~ / and / || $theline =~ / and,/ ) ) {
				if ( substr($`,-1) ne ',' ) { # && substr($`,-1) ne ' ' ) {
					print "SERIOUS: $refstex has an author line with \"and\" but no comma before the \"and\", on line $. in $input.\n";
				}
			}
			# does line not have a "," at the end?
			if ( !$ok && !($theline =~ /,$/) && !($theline =~ /``/) ) { # && !($theline =~ /{/) ) {
				print "SERIOUS: $refstex has an author line without a comma at the end, on line $. in $input.\n";
				print "  (or, put all authors on one line, please.)\n";
			}
			# does last name of first author not have a comma after it?
			if ( !$ok ) {
				my @bibname = split( /\s+/, $theline );
				if ( $#bibname >= 0 ) {
					if ( !($bibname[0] =~ /,$/) && !($bibname[0] =~ /``/) && !($bibname[0] =~ /\\em/) && 
						lc($bibname[0]) ne "de" &&
						lc($bibname[0]) ne "do" &&
						lc($bibname[0]) ne "el" &&
						lc($bibname[0]) ne "van" &&
						lc($bibname[0]) ne "nvidia" &&
						lc($bibname[0]) ne "team" &&
						lc($bibname[0]) ne "nie\\ss" && # troublemaker :P
						lc($bibname[0]) ne "di" ) {
						print "SERIOUS: $refstex first author ''$bibname[0], firstname'' has no comma at end of last name, on line $. in $input.\n";
					}
				}
			}
		}

		# ---------------------------------------------------------
		# citation problem: use a ~ instead of a space so that the citation is connected with the content before it.
		if( !$twook && !$infigure && $twoline =~ /[\s\w\.,}]\\cite\{/ ) {
			print "\\cite needs a tilde ~\\cite before citation to avoid separation, on line $. in $input.\n";
		}
		# has the tilde, but there's a space before the tilde
		if( !$twook && $twoline =~ /\s~\\cite\{/ ) {
			print "\\cite - remove the space before the tilde ~\\cite, on line $. in $input.\n";
		}
		if( !$ok && $theline =~ /\\cite\{\}/ ) {
			print "SERIOUS: \\cite is empty, on line $. in $input.\n";
		}
		if( !$ok && $theline =~ /\/cite\{/ ) {
			print "SERIOUS: '/cite' $& problem, should use backslash, on line $. in $input.\n";
		}
		if( !$ok && $theline =~ /\/ref\{/ && !($theline =~ /{eps/ || $theline =~ /{figures/) && !$isref ) {
			print "SERIOUS: '/ref' $& problem, should use backslash, on line $. in $input.\n";
		}
		# yes, use twoline here.
		if( !$ok && !$inequation && !$infigure && $theline =~ /\\ref\{/ &&
			!($twoline =~ /Figure/ || $twoline =~ /Chapter/ || $twoline =~ /Section/ || $twoline =~ /Equation/ || 
			$twoline =~ /Table/ || $twoline =~ /Listing/ || $twoline =~ /Appendix/) ) {
			print "SERIOUS: '\\ref' doesn't have 'Figure', 'Section', 'Equation', 'Table', or 'Appendix'\n    in front of it, on line $. in $input.\n";
		}
		if( !$ok && $theline =~ /\/label\{/ ) {
			print "SERIOUS: '/label' $& problem, should use backslash, on line $. in $input.\n";
		}

		# ----------------------------------------------------------
		# index entry tests
		if( !$ok && $theline =~ /\/index\{/ && !$isref ) {
			print "SERIOUS: '/index' should be \\index, on line $. in $input.\n";
		}
		if( !$ok && $theline =~ /\\index/ && !$isref ) {
			# look at index entry - only looks at first one in line, though.
			my $index = $';
			if ( $index =~ /\|/ && !($index =~ /\|see/) && !($index =~ /\|nn/) && !($index =~ /\|emph/) && !($index =~ /\|\(/) && !($index =~ /\|\)/) ) {
				print "SERIOUS: '\index' has a '|' without a 'see' or similar after it, on line $. in $input. Did you mean '!'?\n";
			}
		}
		# reference needs tilde
		if( !$ok && $theline =~ /[\s\w\.,}]\\ref\{/ ) {
			my $testit = $`;
			if ( !( $testit =~ /and$/ ) && !( $testit =~ /,$/ ) ) { # don't worry about second number for figure being on same line.
				print "\\ref needs a tilde ~\\ref before reference, on line $. in $input.\n";
			}
		}
		# pageref needs tilde
		if( !$ok && $theline =~ /[\s\w\.,}]\\pageref\{/ ) {
			my $testit = $`;
			if ( !( $testit =~ /and$/ ) && !( $testit =~ /,$/ ) ) { # don't worry about second number for figure being on same line.
				print "\\pageref needs a tilde ~\\pageref before reference, on line $. in $input.\n";
			}
		}
		# if it says "page" before the reference
		if( !$ok && $theline =~ /page~\\ref/ ) {
			print "\\ref should probably be a \\pageref on line $.\n";
		}
		# cite should have a \ before this keyword
		if( !$ok && $theline =~ /~cite\{/ ) {
			print "'cite' is missing a leading \\ for '\\cite' on line $. in $input.\n";
		}
		if( $theline =~ /see~\\cite\{/ ) {
			print "do not use `see~\\cite', on line $. in $input - do not consider citations something you can point at.\n";
		}
		# ref should have a \ before this keyword
		if( !$ok && $theline =~ /~ref\{/ ) {
			print "'ref' is missing a leading \\ for '\\ref' on line $. in $input.\n";
		}
		# pageref should have a \ before this keyword
		if( !$ok && $theline =~ /~pageref\{/ ) {
			print "'pageref' is missing a leading \\ for \\pageref on line $. in $input.\n";
		}
		$str = $theline;
		# label used twice; also check for label={code} in listings
		if ( ($str =~ /\\label\{/) || ($str =~ /label\=/) ) {
			my $foundlabel = 0;
			while ( ($str =~ /\\label\{([\w_:-]+)}/) || ($str =~ /label\=\{([\w_:-]+)}/) || ($str =~ /label\=([\w_:-]+)/) ) {
				$str = $';
				$foundlabel = 1;
				if ( exists($label{$1}) ) {
					print "CRITICAL ERROR: duplicate label '$1' - change it in this file to be unique.\n";
				}
				# don't really need to check for unused label if label is in a subfigure.
				$labelimportant{$1} = !$subfigure;
				$label{$1} = $input;
				if ( $infigure ) {
					$figlabel = $input;
					$labelfigure{$1} = 1;
				}
				if ( $ok ) {
					# there are some weird ways to reference figures, e.g., \Cref{fig:primitive_id,fig:primitive_id2}, so allow us to mark labels as referenced manually, via % chex_latex
					$ref{$1} = $input;
				}
			}
			if ( $foundlabel == 0 ) {
				print "INTERNAL ERROR: a label was found but not properly parsed by chex_latex, on line $. in $input.\n";
			}
		}
		$str = $theline;
		# record the refs for later comparison
		# we could add some sort of !$ok or other test here in order to be able to mask off \refs for code listings:
		# e.g. Listing~\ref{lst_kernelcode}
		#which we don't detect currently.
		while ( $str =~ /\\ref\{([\w_:-]+)}/ ) {
			$str = $';
			$ref{$1} = $input;
		}
		$str = $theline;
		while ( $str =~ /\\pageref\{([\w_:-]+)}/ ) {
			$str = $';
			$ref{$1} = $input;
		}
		$str = $theline;
		while ( $str =~ /\\Cref\{([\w_:-]+)}/ ) {
			$str = $';
			$ref{$1} = $input;
		}
		if( !$twook && $twoline =~ /\w\|\}/ && $twoline =~ /\\index\{/ && !$inequation && !$intable && !($twoline =~ /\\frac/) ) {
			print "SERIOUS: bad index end at $&, change to char}, on line $. in $input.\n";
		}
		if( !$twook && $twoline =~ /\(\|\}/ ) {
			print "SERIOUS: bad index start at (|}, change to |(}, on line $. in $input.\n";
		}
		if( $theline =~ /\\caption\{/ || $theline =~ /\\captionof\{/ ) {
			$figcaption = 'has a caption';
		}
		if( $theline =~ /\\begin\{tabular\}/ ) {
			$figcenter = 'has centering via tabular';
		}
		
		# -----------------------------------------------
		# bibitem related
		$str = $theline;
		# for bibitems, did prev_line (i.e., the previous bibitem) end with a period? All should! comments are deleted.
		if ( $str =~ /\\bibitem\{([\w_']+)}/ ) {
			my $k = chop $prev_real_line;
			#printf "k is $k\n";
			my $kk = chop $prev_real_line;
			#printf "k is $k\n";
			if ( $k ne '.' && $kk ne '.' && !$ignore_first ) {
				printf "no period on around line $lastl in $input.\n";
			}
			$ignore_first = 0;
			$foundref = 1;
		}
		while ( $str =~ /\\bibitem\{([\w_']+)}/ ) {
			$str = $';
			if ( exists($bibitem{$1}) ) {
				print "ERROR: duplicate bibitem $1\n";
			}
			$bibitem{$1} = $input;
			$biborder{$1} = $numbib++;
		}
		$str = $theline;
		while ( $str =~ /\\cite\{([\w_,'\s*]+)}/ ) {
			$str = $';
			my $citelist = $1;
			# uncomment this test code if you want to manually check if citations are in right numerical order, if that
			# is how you are ordering things.
			#if ( $citelist =~ /,/ ) {
			#	printf "MULTIPLE CITATIONS '$citelist' at $. in $input\n";
			#}
			my $subf = $1;
			$subf =~ s/ //g;
			my @fldc = split(/,/,$subf);	# split
			if ($#fldc > 0) {
				# more than one citation, keep for checking alpha order later
				$citeorder[$conum] = $subf;
				$citeloc[$conum] = "$. in $input";
				$conum++;
			}
			if ($#fldc >= 0 ) {
				for ($i = 0; $i <= $#fldc; $i++ ) {
					$cite{$fldc[$i]} = $input;
				}
			} else {
				$cite{$1} .= $input . ' ';
			}
		}

		# digits with space, some european style, use commas instead
		if( !$ok && !$infigure && $theline =~ /\d \d\d\d/ ) {
			print "POSSIBLY SERIOUS: digits with space '$&' might be wrong\n    Use commas, e.g., '300 000' should be '300,000' on line $. in $input.\n";
		}

		# ----------------------------------------------------------------
		# Punctuation
		if ( $dashes ) {
			# single dash should be ---
			# test could be commented out because it could be an equation, e.g., 9 - 4
			if( !$ok && !$textonly && $theline =~ / - / && !$inequation ) {
				if ( !($twoline =~ /\$/) ) {
					print "SERIOUS: change ' - ' to '---' on line $. in $input.\n";
					#print "++++++ DEBUG: >$`< is the prefix.\n";
				}
			}
			# -- to ---, if words on both sides (otherwise this might be a page number range)
			if( !$twook && !$textonly && !$isref && !$inequation && $lctwoline =~ /[a-z]--\w/ && !($lctheline =~ /--based/ ) ) {
				if ( !($` =~ /\$/) ) {
					print "possibly serious: change '--' (short dash) to '---' on line $. in $input, unless you are specifying a range.\n";
				}
			}
		}
		if ( $usstyle ) {
			# U.S. style: period goes inside the quotes, much as we might wish it to be different.
			# Don't believe me? See http://www.thepunctuationguide.com/quotation-marks.html
			if( !$ok && $theline =~ /''\./ ) {
				if ( !($` =~ /\$/) ) {
					print "SERIOUS: U.S. punctuation rule, change ''. to .'' on line $. in $input.\n";
				}
			}
			# U.S. punctuation test for commas, same deal.
			if( !$ok && $theline =~ /'',/ && !($theline =~ /gotcha/) ) {
				print "SERIOUS: U.S. punctuation rules state that '', should be ,'' on line $. in $input.\n";
			}

			# https://www.grammarly.com/blog/modeling-or-modelling/
			if( !$ok && $lctheline =~ /modelling/ && !$isref ) {
				print "In the U.S., we prefer 'modeling' to 'modelling' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /outwards/ ) {
				print "In the U.S., 'outwards' should change to 'outward' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /inwards/ ) {
				print "In the U.S., 'inwards' should change to 'inward' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /towards/ ) {
				print "In the U.S., 'towards' should change to 'toward' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /backwards/ ) {
				print "In the U.S., 'backwards' should change to 'backward' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /forwards/ ) {
				print "In the U.S., 'forwards' should probably change to 'forward' unless used as ''forwards mail'' etc., on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /afterwards/ ) {
				print "In the U.S., 'afterwards' should probably change to 'afterward' unless used as ''forwards mail'' etc., on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /upwards/ ) {
				print "In the U.S., 'upwards' should change to 'upward' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /downwards/ ) {
				print "In the U.S., 'downwards' should change to 'downward' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /grey/ ) { # http://www.dictionary.com/e/gray-or-grey/
				print "In the U.S., change 'grey' to 'gray' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /haloes/ ) {
				print "In the U.S., change 'haloes' to 'halos' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /focuss/ ) {
				print "In the U.S., change 'focuss*' to 'focus*', don't double the s's, on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /parametriz/ ) {
				print "In the U.S., change 'parametrization' to 'parameterization' on line $. in $input.\n";
			}
			# see https://www.dailywritingtips.com/comma-after-i-e-and-e-g/ for example
			if( !$twook && ($twoline =~ /i\.e\. / || $twoline =~ /i\.e\.~/) ) {
				print "SERIOUS: in the U.S. 'i.e.' should have a comma after it, not a space, on line $. in $input.\n";
				$period_problem = 1;
			}
			if( !$ok && $theline =~ /i\.e\.:/ ) {
				print "SERIOUS: in the U.S. 'i.e.' should have a comma after it, not a colon, on line $. in $input.\n";
				$period_problem = 1;
			}
			if( !$twook && ($twoline =~ /e\.g\. / || $twoline =~ /e\.g\.~/) ) {
				print "SERIOUS: in the U.S. 'e.g.' should have a comma after it, not a space, on line $. in $input.\n";
				$period_problem = 1;
			}
			if( !$ok && $theline =~ /e\.g\.:/ ) {
				print "SERIOUS: in the U.S. 'e.g.' should have a comma after it, not a colon, on line $. in $input.\n";
				$period_problem = 1;
			}
			#if( !$twook && $twoline =~ /for example / ) {
			#	print "In the U.S. 'for example' typically should have a comma after it, not a space, on line $. in $input.\n";
			#	$period_problem = 1;
			#}
			if( !$ok && $lctheline =~ /parameterisation/ ) {
				print "The British spelling 'parameterisation' should change to 'parameterization' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /signalled/ ) {
				print "The British spelling 'signalled' should change to 'signaled', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /fulfils/ ) {
				print "The spelling 'fulfils' should change to the U.S. spelling 'fulfills', on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /fulfil / ) {
				print "The spelling 'fulfil' should change to the U.S. spelling 'fulfill', on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /acknowledgement/ && !$isref ) {
				print "'acknowledgement' to U.S. spelling 'acknowledgment' (delete second 'e' - really!) on line $. in $input.\n";
			}
		}
		
		# see https://english.stackexchange.com/questions/34378/etc-with-postpositioned-brackets-at-the-end-of-a-sentence
		if( !$twook && $twoline =~ / etc/ && !($' =~ /^\./) ) {
			print "SERIOUS: 'etc' isn't followed by a '.' on line $. in $input.\n";
		}
		if( !$twook && !$isref && !$inequation && $twoline =~ /\. \d/ ) {
			print "A sentence should not start with a numeral (unless it's a year), on line $. in $input.\n";
		}
		if( !$ok && !$isref && !$textonly && !$inequation && $lctheline =~ /(\d+)x/ && !($lctheline =~ / 0x/) && !($lctheline =~ /\$/) ) {
			print "Do not use $1x, use \$$1 \\times\$, on line $. in $input.\n";
		}
		# we like to avoid ending a sentence with a preposition.
		if( !$twook && $twoline =~ / with\. / ) {
			print "consider: 'with.' at end of sentence on line $. in $input. Reword if it's not convoluted to do so.\n";
		}
		if( !$ok && $theline =~ /\/footnote/ ) {
			print "SERIOUS: change '/footnote' to '\\footnote' on line $. in $input.\n";
		}
		if( !$ok && $theline =~ /~\\footnote/ ) {
			print "SERIOUS: change '~\\footnote' to '\\footnote' on line $. in $input.\n";
		}
		# Great one, but you have to hand check the finds TODO END
		#if( !$twook && $lctwoline =~ /\w\\footnote/ ) {
		#	print "SERIOUS: 'w\\footnote' to ' \\footnote' on line $. in $input.\n";
		#}
		if( !$ok && !$textonly && $dashes && ($theline =~ / -- / || $theline =~ / --~/) ) {
			print "POTENTIALLY SERIOUS: change ' -- ' to the full dash '---' on line $. in $input.\n";
		}
		if( $dashes && !$intable && !$twook && !$textonly ) {
			if ( $twoline =~ / --- / ) {
				print "SERIOUS: ' --- ' should not have spaces before and after it, on line $. in $input.\n";
			} elsif( $twoline =~ /--- / ) {
				print "SERIOUS: '--- ' should not have a space after it, on line $. in $input.\n";
			} elsif( $twoline =~ / ---/ && !$inquote ) {
				print "SERIOUS: ' ---' should not have a space before it, on line $. in $input.\n";
			}
		}
		if( !$twook && $isref && !$textonly && $twoline =~ /pp. \d+-\d+/ ) {
			print "ERROR: '$&' page number has only one dash, on line $. in $input.\n";
		}
		if( !$twook && !$isref && !$textonly && $twoline =~ / \[\d+-\d+\]/) {
			print "ERROR: '$&' date range has only one dash, needs two, on line $. in $input.\n";
		} elsif( !$ok && !$isref && !$textonly && $theline =~ /\d+-\d+/ && !$inequation && !($theline =~ /\\cite/) && !($theline =~ /\$/) ) {
			print "ERROR: '$&' need two dashes between numbers, on line $. in $input.\n";
		}
		if( !$ok && !$isref && !$textonly && $theline =~ / \(\d+-\d+\)/ && !($theline =~ /\$/) ) {
			print "ERROR: '$&' date range needs to use brackets, [], not parentheses, and\n    has only one dash, needs two, on line $. in $input.\n";
		}
		if ( !$ok && $theline =~ /\?\-/ && $isref ) {
			print "There's a ?- page reference (how do these get there? I think it's a hidden character before the first - from copy and paste of Computer Graphics Forum references), on line $. in $input.\n";
		}
		if( !$ok && $theline =~ /\/times/ ) {
			print "SERIOUS: change '/times' to '\\times' on line $. in $input.\n";
		}
		#if( !$twook && $isref && !($twoline =~ /--/) && $twoline =~ /-/ ) {
		#	print "Warning: '$_' in refs has only one dash, on line $. in $input.\n";
		#}
		# good, but must hand check:
		#if( !$twook && $twoline =~ /one dimensional/ ) {
		#	print "'one dimensional' to 'one-dimensional' on line $. in $input.\n";
		#}

		# adding spaces is nice to do for readability, but not dangerous:
		#if( !$twook && $twoline =~ /\d\\times/ ) {
		#	print "left \\times problem on line $. in $input.\n";
		#}
		# nice to do for readability, but not dangerous:
		#if( !$twook && $twoline =~ /\\times\d/ ) {
		#	print "right \\times spacing problem on line $. in $input.\n";
		#}

		# Latex-specific
		# lots more foreign letters could be tested here... ß https://www.computerhope.com/issues/ch000657.htm
		if( !$ok && !$textonly && ($theline =~ /(ä)/ || $theline =~ /(ö)/ || $theline =~ /(ü)/) ) {
			print "Some LaTeX tools don't like these: found an umlaut, use \\\"{letter} instead, on line $. in $input.\n";
		}
		if( !$ok && !$textonly && ($theline =~ /(á)/ || $theline =~ /(é)/ || $theline =~ /(í)/ || $theline =~ /(ó)/ || $theline =~ /(ú)/) ) {
			print "Some LaTeX tools don't like these: found an accent, use \\'{letter} instead, on line $. in $input.\n";
		}
		if ( !$ok && !$textonly && $theline =~ /<<< HEAD/ ) {
			print "SERIOUS: Unresolved merge problem, on line $. in $input.\n";
		}
		if ( !$twook && !$textonly && $twoline =~ /\textregistered / ) {
			print "Spacing: you probably want to change `\textregistered ' to '\textregistered\ ' so that there is space after it, on line $. in $input.\n";
		}
		if( !$ok && !$textonly && $theline =~ /’/ ) {
			print "SERIOUS: change nonstandard apostrophe to a proper LaTeX ' (vertical) apostrophe on line $. in $input.\n";
		}
		elsif( !$ok && !$textonly && $theline =~ /‘/ ) {
			print "SERIOUS: change nonstandard single-quote mark to a proper LaTeX ` (vertical) apostrophe on line $. in $input.\n";
		}
		if( !$ok && !$textonly && $theline =~ /–/ ) {
			print "SERIOUS: change nonstandard dash to a proper LaTeX - dash on line $. in $input.\n";
		}
		if( !$ok && !$textonly && !$inequation && $theline =~ /"/ && !($theline =~ /\\"/) ) {
			print "SERIOUS: the double apostrophe \" should change to a \'\' on line $. in $input.\n";
		}
		if( !$ok && !$textonly && !$inequation && $theline =~ /“/ && !($theline =~ /\\"/) ) {
			print "SERIOUS: the double apostrophe should change to a \'\' on line $. in $input.\n";
		}
		elsif( !$ok && !$textonly && !$inequation && $theline =~ /”/ && !($theline =~ /\\"/) ) {
			print "SERIOUS: the double apostrophe should change to a '' on line $. in $input.\n";
		}
		if( !$twook && !$textonly && !$inequation && $twoline =~ / '/ ) {
			print "SERIOUS: the right apostrophe ' should probably be a left double-apostrophe ``, on line $. in $input.\n";
		}
		if( !$twook && !$textonly && !$inequation && $twoline =~ / `/ && !($twoline =~ / ``/) ) {
			print "SERIOUS: the left apostrophe ` should likely be a left double-apostrophe ``, on line $. in $input.\n";
		}

		if( !$twook && !$textonly && $twoline && $twoline =~ / Corp\. / ) {
			print "'Corp. ' may need a backslash 'Corp.\\' to avoid a wide space after period\n    (unless it's the end of a sentence), on line $. in $input.\n";
		}
		if( !$twook && !$textonly && $twoline =~ / Inc\. / ) {
			print "'Inc. ' may need a backslash 'Inc.\\' to avoid a wide space after period\n    (unless it's the end of a sentence), on line $. in $input.\n";
		}
		if( !$twook && !$textonly && $twoline =~ / Ltd\. / ) {
			print "'Ltd. ' may need a backslash 'Ltd.\\' to avoid a wide space after period\n    (unless it's the end of a sentence), on line $. in $input.\n";
		}
		# the false positives on this one vastly outweigh the true positives, e.g. "MSc (Tech.)\ at some university"
		# is a case where you would want the "\" but for a parenthetical sentence you want the full space after the period,
		# i.e., latex by default works fine.
		#if( !$twook && !$textonly && !$inequation && $twoline =~ /\.\)/ ) {
		#	print "POSSIBLY SERIOUS: '.)\\' - remove the \\ after it to avoid 'short' space, on line $. in $input.\n";
		#}
		# last bit on this line: if text, then ignore "..."
		if( !($twoline =~ /\$/) && !($twoline =~ /''/) && $twoline =~ /\.\./ && !($twoline =~ /{\.\./) && !$inequation && (!$textonly || !($twoline =~ /\.\.\./))  ) {
			print "Doubled periods, on line $. in $input.\n";
		}
		if( !$twook && !$infigure && $twoline =~ /,,/ ) {
			print "Doubled commas, on line $. in $input.\n";
		}
		# experimental...
		# Latex will by default make a "short space" after a capital letter followed by a period.
		# For example: Franklin D. Roosevelt. For longer sets of capital letters, e.g., GPU, DNA,
		# we want to have a "long space," as in: "There are many types of DNA.  We will discuss..."
		if( !$ok && !$textonly && !$inequation && !$infigure && $theline =~ /([A-Z][A-Z]+)\./ ) {
			print "Sentence ending in the capital letters $1 should have a '\\@.' for spacing, on line $. in $input.\n";
		}
		if( !$ok && !$textonly && !$inequation && !$infigure && $theline =~ /([A-Z][A-Z]+)\)\./ ) {
			print "Sentence ending in the capital letters $1 and ) should have a ')\\@.' for spacing, on line $. in $input.\n";
		}

		if( !$twook && !$textonly && $twoline =~ /Image Courtesy/ || $twoline =~ /Images Courtesy/ ) {
			print "Change 'Courtesy' to 'courtesy' on line $. in $input.\n";
		}
		if( !$twook && !$textonly && $lctwoline =~ /[\d+] ms/ ) {
			print "' ms' to '~ms' to avoid having the number separated from its units, on line $. in $input.\n";
		}
		if( !$ok && !$isref && !$inequation && $theline =~ /([\.\d]+)ms/ ) {
			print "Change '$1ms' to '$1~ms' (i.e., add a space), on line $. in $input.\n";
		}
		if( !$twook && !$textonly && $lctwoline =~ /[\d+] fps/ ) {
			print "' FPS' to '~FPS' to avoid having the number separated from its units, on line $. in $input.\n";
		}
		if( !$ok && !$isref && !$inequation && $theline =~ /(\d+)fps/ ) {
			print "Change '$1FPS' to '$1~FPS' (i.e., add a space), on line $. in $input.\n";
		}
		if( !$ok && $theline =~ /fps/ ) {
			print "'fps' to 'FPS' on line $. in $input.\n";
		}
		if( !$twook && !$textonly && $lctwoline =~ /[\d+] Hz/ ) {
			print "' Hz' to '~Hz' to avoid having the number separated from its units, on line $. in $input.\n";
		}
		if( !$ok && !$isref && !$inequation && $lctheline =~ /(\d+)hz/ ) {
			print "Change '$1Hz' to '$1~Hz' (i.e., add a space), on line $. in $input.\n";
		}
		if( !$ok && !$isref && !$inequation && $theline =~ /(\d+)K / ) {
			print "Change '$1K' to '$1k' (i.e., lowercase 'k'), on line $. in $input.\n";
		}
		if( !$twook && !$isref && !$inequation && $lctwoline =~ /(\d+) k / ) {
			print "Change '$1 k' to '$1k' (i.e., lowercase 'k'), on line $. in $input.\n";
		}
		# ----------------------------------
		# Style: comma and period punctuation
		if( !$twook && $twoline =~ /\w\se\.g\./ ) {
			print "SERIOUS: ' e.g.' does not have a comma before it, on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ / et al/ ) {
			my $post = $';
			if ( !($post =~ /^\./ || $post =~ /^ia/) ) {
				print "'et al' is not followed by '.', i.e., 'et al.', on line $. in $input.\n";
			}
		}
		if( !$twook && $lctwoline =~ / et alia/ ) {
			print "Use 'et al.\\' instead of 'et alia', on line $. in $input.\n";
		}
		if( !$twook && $twoline =~ /et\. al/ ) {
			print "Change 'et. al.' to 'et al.' (no first period), on line $. in $input.\n";
		}
		if ( !$twook && $twoline =~ /et al.~\\cite\{\w+\}\s+[A-Z]/ ) { # \{\w+\} [A-Z]
			printf "et al. citation looks like it needs a period after the citation, on line $. in $input.\n";
		}
		# see https://english.stackexchange.com/questions/121054/which-one-is-correct-et-al-s-or-et-al
		# and https://forum.wordreference.com/threads/how-to-use-the-possessive-s-with-et-al.1621357/
		# Typical rewrite of "Marquando et al.'s work" is "The work by Marquando et al."
		if( $lctwoline =~ /et al.'s/ ) {
			print "Rewrite to avoid 'et al.'s', which is half Latin, half English, on line $. in $input.\n";
		}
		if( !$twook && !$textonly && $twoline =~ / al\. / ) {
			print "POSSIBLY SERIOUS: change 'et al.' to 'et al.\\' if you are not ending a sentence, on line $. in $input.\n";
			$period_problem = 1;
		}
		if( !$twook && !$inequation && $twoline =~ / \. / ) {
			print "SERIOUS: change ' .' to '.' (space in front of period), on line $. in $input.\n";
		}
		if( !$twook && !$inequation && $twoline =~ / \,/ ) {
			print "SERIOUS: change ' ,' to ',' (space in front of comma), on line $. in $input.\n";
		}
		# If you use a ".", you need to do something like ".~" to avoid having the period treated
		# as if it's the end of a sentence, which causes a bit of additional space to get added after it.
		# Easiest is to just spell out vs.
		if( !$twook && !$isref && !$textonly && $twoline =~ / vs\. / ) {
			print "SERIOUS: change 'vs.' to 'versus' to avoid having a 'double-space' appear after the period,\n    or use 'vs.\\' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $twoline =~ / vs / ) {
			print "SERIOUS: change 'vs' to 'versus' on line $. in $input\n";
		}
		if( !$twook && !$isref && !$textonly && $twoline =~ / etc\. [a-z]/ ) {
			print "POSSIBLY SERIOUS: you may need to change 'etc.' to 'etc.\\' to avoid having a 'double-space'\n    appear after the period, on line $. in $input.\n    (To be honest, it's better to avoid 'etc.' altogether, as it provides little to no information.)\n";
			$period_problem = 1;
		}
		
		# ---------------------------------------------------
		# grammatical, or other word-related problems
		if( !$ok && $theline =~ /TODO/ ) {
			print "Beware, there is a TODO in the text itself at line $. in $input.\n";
			print "    the line says: $theline\n";
		}
		if( !$twook && $twoline =~ /\. [a-z]/ && !($twoline =~ /a\.k\.a\./) && !($twoline =~ /\.\.\./) && !$isref && !$inequation && !$period_problem ) {
			printf "Not capitalized at start of sentence%s, on line $. in $input.\n", $textonly ? "" : " (or the period should have a \\ after it)";
		}
		if( !$ok && $theline =~ /Javascript/) {
			print "Please change 'Javascript' to 'JavaScript' on line $. in $input.\n";
		}
		if( $lctheline =~ /frustrum/ ) {
			print "MISSPELLING: 'frustrum' to 'frustum' on line $. in $input.\n";
		}
		if( $lctheline =~ /octtree/ ) {
			print "MISSPELLING: 'octtree' to 'octree' on line $. in $input.\n";
		}
		# your mileage may vary, depending on how you index, e.g., we do \index{k-d tree@$k$-d tree}
		if( !$twook && !$textonly && !$isref && $lctwoline =~ /k-d / && !($lctheline =~ /k-d tree@/) ) {
			print "'k-d' to the more proper '\$k\$-d', on line $. in $input.\n";
		}
		if( !$ok && !$textonly && !$isref && $lctheline =~ /kd-tree/ ) {
			print "'kd-tree' to the more proper '\$k\$-d tree', on line $. in $input.\n";
		}
		if( !$twook && !$textonly && !$isref && $lctwoline =~ /kd tree/ && !($lctheline =~ /kd tree@/) ) {
			print "'kd tree' to the more proper '\$k\$-d tree', on line $. in $input.\n";
		}
		if( $lctheline =~ /hierarchal/ ) {
			print "MISSPELLING: 'hierarchal' to 'hierarchical' on line $. in $input.\n";
		}
		if( $lctheline =~ /hierarchial/ ) {
			print "MISSPELLING: 'hierarchial' to 'hierarchical' on line $. in $input.\n";
		}
		if( $lctheline =~ /descendent/ ) {
			print "Likely misspelled, unless used as an adjective: 'descendent' to 'descendant' on line $. in $input.\n";
		}
		if( !$inequation && $twoline =~ / hermite/ ) {
			print "MISSPELLING: 'hermite' to 'Hermite', on line $. in $input.\n";
		}
		if( !$inequation && $twoline =~ / phong/ ) {
			print "MISSPELLING: 'phong' to 'Phong', on line $. in $input.\n";
		}
		if( !$inequation && $twoline =~ / gouraud/ ) {
			print "MISSPELLING: 'gouraud' to 'Gouraud', on line $. in $input.\n";
		}
		# leading space to avoid "n-bit mask" which would be fine
		if( !$twook && $lctwoline =~ / bit mask/ ) {
			print "'bit mask' to 'bitmask', on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ /screen space ambient/ ) {
			print "'screen space ambient' to 'screen-space ambient', on line $. in $input.\n";
		}
		
		# -----------------------------
		# Clunky or wrong
		if( !$twook && $twoline =~ / to\. / ) {
			print "SERIOUS: ending a sentence with 'to.' is not so great, on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /irregardless/ && !$inquote ) {
			print "No, never use 'irregardless' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /na\\"ive/ && !$inquote ) {
			print "Change 'na\\\"ive' to good ole 'naive' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /necessitate/ && !$inquote ) {
			print "Please don't use 'necessitate' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /firstly/ && !$inquote ) {
			print "Do not say 'firstly' - say 'first' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /secondly/ && !$inquote ) {
			print "Do not say 'secondly' - say 'second' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /thirdly/ && !$inquote ) {
			print "Do not say 'thirdly' - say 'third' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /amongst/ ) {
			print "Change 'amongst' to 'among' on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ / try and/ ) {
			print "Change 'try and' to 'try to' on line $. in $input, or reword to 'along with' or similar.\n";
		}
		if( !$twook && $twoline =~ /relatively to / ) {
			print "tip: 'relatively to' probably wants to be 'relative to' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /so as to / ) {
			print "tip: you probably should replace 'so as to' with 'to' or similar on line $. in $input, or rewrite.\n    It's a wordy phrase.\n";
			&SAYOK();
		}
		if( !$twook && $lctwoline =~ /due to that/ ) {
			print "tip: 'due to that' to 'because' on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ /more optimal/ ) {
			print "tip: 'more optimal' is illogical - 'optimal' means the best;\n    maybe try 'better optimized' on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ /more specifically/ ) {
			print "tip: 'more specifically' to 'specifically' on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ /made out of/ ) {
			print "shortening tip: replace 'made out of' with 'made from' on line $. in $input.\n";
		}
		# optionally, remove $infigure && 
		if( !$twook && $infigure && $lctwoline =~ /as can be seen/ ) {
			print "shortening tip: remove 'as can be seen', since we are looking at a figure, on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /due to the fact that/ && !$inquote ) {
			print "tip: replace 'due to the fact that' with 'because' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /on account of/ && !$inquote ) {
			print "tip: change 'on account of/' to 'because' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /basically/ && !$inquote ) {
			print "tip: you can probably remove 'basically' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /orientate/ && !$inquote ) {
			print "tip: you probably don't want to use 'orientate' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /thusly/ && !$inquote ) {
			print "tip: change 'thusly' to 'thus' or 'therefore' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /point in time/ && !$inquote ) {
			print "tip: avoid the wordy phrase 'point in time' at this point in time, on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /literally/ && !$inquote ) {
			print "tip: you can probably not use 'literally' (and may mean 'figuratively'), on line $. in $input.\n";
			&SAYOK();
		}
		if( !$twook && $lctwoline =~ / a lot more/ ) {
			print "tip: replace 'a lot' with 'much' on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ /and also / ) {
			print "tip: you probably should replace 'and also' with 'and' on line $. in $input,\n    or reword to 'along with' or similar.\n";
		}
		if( !$twook && $lctwoline =~ /the reason why is because/ ) {
			print "tip: 'the reason why is because' is crazy wordy, so rewrite, on line $. in $input.\n";
		}
		if( !$twook && $lctwoline =~ /fairly straightforward/ ) {
			print "shortening tip: replace 'fairly straightforward' with 'straightforward' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /as-is/ ) {
			print "'as-is' should be 'as is' on line $. in $input.\n";
		}
		# https://dict.leo.org/forum/viewGeneraldiscussion.php?idforum=4&idThread=331883&lp=ende
		if( !$ok && $lctheline =~ /well-suited/ ) {
			print "It is likely that 'well-suited' should be 'well suited', unless it's an adjective before a noun, on line $. in $input.\n";
			&SAYOK();
		}
		# rules about hyphens: https://www.grammarbook.com/punctuation/hyphens.asp
		if( !$isref && $lctheline =~ /physically-based/ ) {
			print "'physically-based' should change to 'physically based' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /ly-used/ ) {
			print "'*ly-used' should probably change to '*ly used' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /bottom-left/ ) {
			print "'bottom-left' should change to 'bottom left' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /bottom-right/ ) {
			print "'bottom-right' should change to 'bottom right' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /top-left/ ) {
			print "'top-left' should change to 'top left' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /top-right/ ) {
			print "'top-right' should change to 'top right' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /lower-left/ ) {
			print "'lower-left' should change to 'lower left' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /lower-right/ ) {
			print "'lower-right' should change to 'lower right' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /upper-left/ ) {
			print "'upper-left' should change to 'upper left' on line $. in $input.\n";
		}
		if( !$ok && $lctheline =~ /upper-right/ ) {
			print "'upper-right' should change to 'upper right' on line $. in $input.\n";
		}
		# always hyphenated
		if( $lctwoline =~ /view dependent/ ) {
			print "'view dependent' should change to 'view-dependent' on line $. in $input.\n";
		}
		if( $lctwoline =~ /view independent/ ) {
			print "'view independent' should change to 'view-independent' on line $. in $input.\n";
		}
		if( &WORDTEST($lctwoline,"defacto ",$lcprev_line,"defacto") ) {
			print "SERIOUS: change 'defacto' to 'de facto', on line $. in $input.\n";
		}
		# from Dreyer's English, a great book, from "The Trimmables", phrases that can be shortened without loss
		if( !$twook && !$isref && $lctwoline =~ /absolutely certain/ ) {
			print "'absolutely certain' can shorten to 'certain' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /absolutely certain/ ) {
			print "'absolute certainty' can shorten to 'certainty' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /absolutely essential/ ) {
			print "'absolutely essential' can shorten to 'essential' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /all-time record/ ) {
			print "'all-time record' can shorten to 'record' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /advance planning/ ) {
			print "'advance planning' can shorten to 'planning' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /advance warning/ ) {
			print "'advance warning' can shorten to 'warning' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /blend together/ ) {
			print "'blend together' can shorten to 'blend' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /close proximity/ ) {
			print "'close proximity' can shorten to 'proximity' (yes, 'close proximity' is a common phrase, but you might want to use a less redundant way to reword this sentence) on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /blend together/ ) {
			print "'blend together' can shorten to 'blend' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /general consensus/ ) {
			print "'general consensus' can shorten to 'consensus' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /continue on / ) {
			print "'continue on' can shorten to 'continue' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /disappear from sight/ ) {
			print "'disappear from sight' can shorten to 'disappear' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /earlier in time/ ) {
			print "'earlier in time' can shorten to 'earlier' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /end product/ ) {
			print "'end product' can shorten to 'product' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /end result/ ) {
			print "'end result' can shorten to 'result' (if you are comparing to an intermediate result, how about 'ultimate result'?) on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /equally as / ) {
			print "'equally as' can shorten to 'equally' or 'as' - don't use both, on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /exact same/ ) {
			print "'exact same' can shorten to 'same' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /fall down / ) {
			print "'fall down' can shorten to 'fall' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /fetch back / ) {
			print "'fetch back' can shorten to 'fetch' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /few in number/ ) {
			print "'few in number' can shorten to 'few' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /final outcome/ ) {
			print "'final outcome' can shorten to 'outcome' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /follow after/ ) {
			print "'follow after' can shorten to 'follow' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /from whence/ ) {
			print "'from whence' can shorten to 'whence' (since 'whence' means 'from where') on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /full gamut/ ) {
			print "'full gamut' can shorten to 'gamut' ('gamut' is a full range of something) on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /full extent/ ) {
			print "'full extent' can shorten to 'extent' ('extent' is its own range) on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /broad spectrum/ ) {
			print "'broad spectrum' can shorten to 'spectrum' ('spectrum' means a full range) on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /complete range/ ) {
			print "'complete range' can shorten to 'range' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /future plans/ ) {
			print "'future plans' can shorten to 'plans' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /gather together/ ) {
			print "'gather together' can shorten to 'gather' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /briefly glance/ ) {
			print "'briefly glance' can shorten to 'glance' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /glance briefly/ ) {
			print "'glance briefly' can shorten to 'glance' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /hollow tube/ ) {
			print "'hollow tube' can shorten to 'tube' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /on an hourly basis/ ) {
			print "'on an hourly basis' can shorten to 'hourly' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /on a daily basis/ ) {
			print "'on a daily basis' can shorten to 'daily' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /on a monthly basis/ ) {
			print "'on a monthly basis' can shorten to 'monthly' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /on a yearly basis/ ) {
			print "'on a yearly basis' can shorten to 'yearly' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /join together/ ) {
			print "'join together' can shorten to 'join' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /last of all/ ) {
			print "'last of all' might shorten to 'last' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /lift up/ ) {
			print "'lift up' can shorten to 'lift' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /merge together/ ) {
			print "'merge together' can shorten to 'merge' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /might possibly/ ) {
			print "'might possibly' can shorten to 'might' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /moment in time/ ) {
			print "'moment in time' can shorten to 'moment' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /more superior/ ) {
			print "'more superior' can shorten to 'superior' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /mutual cooperation/ ) {
			print "'mutual cooperation' can shorten to 'cooperation' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /orbit around/ ) {
			print "'orbit around' can shorten to 'orbit' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /overexaggerate/ && !$inquote ) {
			print "Do not say 'overexaggerate' - say 'exaggerate' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /past history/ ) {
			print "'past history' can shorten to 'history' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /personal opinion/ ) {
			print "'personal opinion' can shorten to 'opinion' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /plan ahead/ ) {
			print "'plan ahead' can shorten to 'plan' on line $. in $input.\n";
		}
		if( !$ok && !$isref && $lctheline =~ /preplan/ && !$inquote ) {
			print "Do not say 'preplan' - say 'plan' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /raise up / ) {
			print "'raise up' can shorten to 'raise' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ / reason why/ ) {
			print "'reason why' can shorten to 'reason', if you like, on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /regular routine/ ) {
			print "'regular routine' can shorten to 'routine' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /recall back/ ) {
			print "'recall back' can shorten to 'recall' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /return back/ ) {
			print "'return back' can shorten to 'return' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /revert back/ ) {
			print "'revert back' can shorten to 'revert' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ / rise up /  && !$inquote ) {
			print "'rise up' can shorten to 'rise' (Hamilton notwithstanding) on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /short in length/  && !$inquote ) {
			print "'short in length' can shorten to 'short' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /shuttle back and forth/  && !$inquote ) {
			print "'shuttle back and forth' can shorten to 'shuttle' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /sink down /  && !$inquote ) {
			print "'sink down' can shorten to 'sink' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /skirt around/  && !$inquote ) {
			print "'skirt around' can shorten to 'skirt' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /sudden impulse/  && !$inquote ) {
			print "'sudden impulse' can shorten to 'impulse' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /surrounded on all sides/  && !$inquote ) {
			print "'surrounded on all sides' can shorten to 'surrounded' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /undergraduate student/  && !$inquote ) {
			print "'undergraduate student' can shorten to 'undergraduate' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /unexpected surprise/  && !$inquote ) {
			print "'unexpected surprise' can shorten to 'surprise' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /unsolved myster/  && !$inquote ) {
			print "'unsolved mystery' can shorten to 'mystery' on line $. in $input.\n";
		}
		if( !$twook && !$isref && $lctwoline =~ /usual custom/  && !$inquote ) {
			print "'usual custom' can shorten to 'custom' on line $. in $input.\n";
		}
		if ( $formal ) {
			# -----------------------------
			# Formal style
			# See https://www.vappingo.com/word-blog/when-is-it-okay-to-use-contractions-in-formal-writing/
			# "Do not use contractions in documents that serve formal purposes, such as legal contracts,
			# [and] submissions to professional publications."
			# http://grammar.ccc.commnet.edu/grammar/numbers.htm
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," math ",$lcprev_line,"math") ) {
				print "For formal writing, 'math' should change to 'mathematics' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," got ",$lcprev_line,"got") ) {
				print "For formal writing, please do not use 'got' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ / lots of/ && !$inquote && (lc($prev_line) ne "lots") ) {
				print "For formal writing, change 'lots of' to 'many' or 'much' on line $. in $input.\n";
			} elsif( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," lots ",$lcprev_line,"lots") ) {
				print "For formal writing, change 'lots' to 'many' or 'much' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," cheap ",$lcprev_line,"cheap") ) {
				print "Please use 'less costly' instead of 'cheap' as 'cheap' implies poor quality, on line $. in $input.\n";
			}
			# see http://www.slaw.ca/2011/07/27/grammar-legal-writing/ for various style guides opinions (all against)
			if( !$ok && !$isref && $lctheline =~ /and\/or/ && !$inquote ) {
				print "For formal writing, please do not use 'and/or' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ / a lot of / && !$inquote ) {
				print "Avoid informal 'a lot of' - change to 'many,' 'much,' 'considerable,' or similar, on line $. in $input.\n";
			} elsif( !$twook && $lctwoline =~ / a lot / && !$inquote ) {
				print "Avoid informal 'a lot' - change to 'much' on line $. in $input.\n";
			}
			# left out because of "can not only provide", which is fine
			#if( !$twook && $lctwoline =~ /can not / ) {
			#	print "'can not' to 'cannot' on line $. in $input.\n";
			#}
			if( !$ok && $lctheline =~ /n't/ && !$inquote && !$isref ) {
				print "SERIOUS: For formal writing, no contractions: 'n't' to ' not' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /let's/ && !$inquote && !$isref ) {	# don't check for in refs.tex
				print "SERIOUS: For formal writing, no contractions: 'let's' to 'let us' or reword, on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /we've/ && !$inquote && !$isref ) {	# don't check for in refs.tex
				print "SERIOUS: For formal writing, no contractions: 'we've' to 'we have' or reword, on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," it's ",$lcprev_line,"it's") ) {
				print "SERIOUS: For formal writing, no contractions: 'it's' to 'it is' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /'re/ && !$inquote ) {
				print "SERIOUS: For formal writing, no contractions: ''re' to ' are' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /'ll/ && !$inquote ) {
				print "SERIOUS: For formal writing, no contractions: ''ll' to ' will' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /formulas/ && !$inquote ) {
				print "Change 'formulas' to 'formulae' on line $. in $input, or rewrite.\n";
			}
			if( !$twook && !$twook && !$isref && !$inquote && &WORDTEST($twoline," Generally ",$prev_line,"Generally")) {
				print "add comma: after 'Generally' on line $. in $input.\n";
			}
			# But, And, Also are possible to use correctly, but hard: https://www.quickanddirtytips.com/education/grammar/can-i-start-a-sentence-with-a-conjunction
			# Some avoidance strategies: http://www.bookpromotionhub.com/6341/5-ways-to-avoid-starting-a-sentence-with-but-or-and/
			if( !$twook && !$isref && !$inquote && 
				( &WORDTEST($twoline," But ",$prev_line,"but") || &WORDTEST($twoline," But,",$prev_line,"but,") ) ) {
				print "Usually avoid starting sentences with the informal `But', on line $. in $input.\n";
			}
			# usually annoying, a run-on sentence
			if( !$twook && !$isref && !$inquote && 
				( &WORDTEST($twoline," And ",$prev_line,"and") || &WORDTEST($twoline," And,",$prev_line,"and,") ) ) {
				print "Avoid starting sentences with the informal `And', on line $. in $input.\n";
			}
			# can be OK, your call...
			if( !$twook && !$isref && !$inquote && 
				( &WORDTEST($twoline," Also ",$prev_line,"also") || &WORDTEST($twoline," Also,",$prev_line,"also,") ) ) {
				print "Usually avoid starting sentences with the informal `Also', on line $. in $input.\n";
			}			
		}
		
		if ( $style  ) {
			# ------------------------------------------------
			# Personal preferences, take them or leave them
			# Why no "very"?
			# See https://www.forbes.com/sites/katelee/2012/11/30/mark-twain-on-writing-kill-your-adjectives
			# (though it's not a Mark Twain quote, see https://quoteinvestigator.com/2012/08/29/substitute-damn/ )
			# Try to find a substitute, e.g., "very small" could become "minute" or "tiny"
			# substitutes site here: https://www.grammarcheck.net/very/
			# Most of the others are from Chapter 1 of "Dreyer's English".
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," very",$lcprev_line,"very") )  {
				print "tip: consider removing or replacing 'very' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," actually",$lcprev_line,"actually") )  {
				print "tip: remove the never-needed word 'actually' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," rather",$lcprev_line,"rather") && !($lctwoline =~ /rather than/) )  {
				print "tip: consider removing or replacing 'rather' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," quite",$lcprev_line,"quite") )  {
				print "tip: consider removing or replacing 'quite' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," in fact",$lcprev_line,"in fact") )  {
				print "tip: consider removing 'in fact' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," surely",$lcprev_line,"surely") )  {
				print "tip: consider removing 'surely' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," of course",$lcprev_line,"of course") )  {
				print "tip: if it's obvious, why say it? Remove 'of course' on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inquote && $formal && &WORDTEST($lctwoline," pretty",$lcprev_line,"pretty") )  {
				print "tip: unless you mean something is pretty, replace or remove the modifier 'pretty' on line $. in $input.\n";
			}
			if( !$ok && !$isref && !$inquote && $lctheline =~ /really/ ) {
				print "tip: consider removing or replacing 'really' on line $. in $input.\n";
			}
			if( !$isref && !$twook && $lctwoline =~ / in fact / && !$inquote ) {
				print "Are you sure you want to use `in fact', on line $. in $input? It's often superfluous, in fact.\n";
			}
			if ( !$twook && $lctwoline =~ /\(see figure/ ) {
				print "Try to avoid `(see Figure', make it a full sentence, on line $. in $input.\n";
			}
			# This extra test at the end is not foolproof, e.g., if the line ended "Interestingly" or "interesting,"
			# A better test would be to pass in the phrase, 
			if( !$twook && !$isref && !$inquote && &WORDTEST($lctwoline," interesting",$lcprev_line,"interesting") ) {
				print "tip: reconsider 'interesting' on line $. in $input, probably delete it\n    or change to 'key,' 'noteworthy,' 'notable,' 'different,' or 'worthwhile'.\n    Everything in your work should be interesting.\n    Say why something is of interest, and write so that it is indeed interesting.\n";
			}
			#if( !$twook && !$isref && $lctwoline =~ /in terms of / ) {
			#	print "tip: 'in terms of' is a wordy phrase, on line $. in $input. Use it sparingly.\n    You might consider instead using 'regarding' or 'concerning', or rewrite.\n    For example, 'In terms of memory, algorithm XYZ uses less' could be 'Algorithm XYZ uses less memory.'\n";
			#	&SAYOK();
			#}
			if( !$twook && !$isref && !$inquote && &WORDTEST($twoline," etc. ",$lcprev_line,"etc.") ) {
				print "hint: try to avoid using etc., as it adds no real information; on line $. in $input.\n";
				if ( !$textonly ) {
				    print "    If you do end up using etc., if you don't use it at the end of a sentence, add a backslash: etc.\\\n";
				}
			}
			# nah, don't care about "data is" any more, the language has changed:
			# https://www.theguardian.com/news/datablog/2010/jul/16/data-plural-singular
			#if( !$twook && !$isref && $lctwoline =~ /data is/ ) {
			#	print "possible tip: 'data' should be plural, not singular, on line $. in $input. Reword?\n    Sometimes it is fine, e.g., 'the analysis of the data is taking a long time.' since analysis is singular.\n";
			#	&SAYOK();
			#}
			# see http://www.quickanddirtytips.com/education/grammar/use-versus-utilize?page=1
			if( !$ok && !$inquote && !$isref && $lctheline =~ /utiliz/ ) {
				print "Probably needlessly complex: change 'utiliz-' to 'use' or similar, on line $. in $input.\n";
				&SAYOK();
			}
			# from the book "The Craft of Scientific Writing" by Michael Alley
			if( !$ok && !$inquote && !$isref && $lctheline =~ /familiarization/ ) {
				print "Needlessly complex: change 'familiarization' to 'familiarity' on line $. in $input.\n";
			}
			if( !$twook && !$inquote && !$isref && $lctwoline =~ /has the functionability/ ) {
				print "Needlessly complex: change 'has the functionability' to 'can function' on line $. in $input.\n";
			}
			if( !$twook && !$inquote && !$isref && $lctwoline =~ /has the operationability/ ) {
				print "Needlessly complex: change 'has the operationability' to 'can operate' on line $. in $input.\n";
			}
			if( !$twook && !$inquote && !$isref && $lctwoline =~ /has the functionability/ ) {
				print "Needlessly complex: change 'has the functionability' to 'can function' on line $. in $input.\n";
			}
			if( !$ok && !$inquote && !$isref && !$inequation && $lctheline =~ /facilitat/ ) {
				print "Possibly needlessly complex: change 'facilitat-' to 'cause' or 'ease' or 'simplify' or 'help along' on line $. in $input.\n";
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /finaliz/ ) {
				print "Needlessly complex: change 'finaliz-' to 'end' on line $. in $input.\n";
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /prioritiz/ ) {
				print "Perhaps needlessly complex: change 'prioritiz-' to 'assess' or 'first choose' on line $. in $input.\n";
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /aforementioned/ ) {
				print "Needlessly complex: change 'aforementioned' to 'mentioned' on line $. in $input.\n";
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /discretized/ ) {
				print "Possibly needlessly complex if used as an adjective: consider changing 'discretized' to 'discrete' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /individualized/ ) {
				print "Needlessly complex: change 'individualized' to 'individual' on line $. in $input.\n";
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /personalized/ ) {
				print "Possibly needlessly complex if used as an adjective: consider 'personalized' to 'personal' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /heretofore/ ) {
				print "Needlessly complex: change 'heretofore' to 'previous' on line $. in $input.\n";
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /hitherto/ ) {
				print "Needlessly complex: change 'hitherto' to 'until now' on line $. in $input.\n";
			}
			if( !$ok && !$inquote && !$isref && $lctheline =~ /therewith/ ) {
				print "Needlessly complex: change 'therewith' to 'with' on line $. in $input.\n";
			}

			# -----------------------------------------------------
			# Words and phrases - definitely personal preferences, but mostly based on common practice
			# looks like the Internet got lowercased: https://blog.oxforddictionaries.com/2016/04/05/should-you-capitalize-internet/
			#if( !$ok && !$isref && $theline =~ /internet/ ) {
			#	print "'internet' should be capitalized, to 'Internet', on line $. in $input.\n";
			#}
			if( !$twook && !$isref && $twoline =~ /monte carlo/ ) {
				print "'monte carlo' should be capitalized, to 'Monte Carlo', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /monte-carlo/ ) {
				print "'Monte-Carlo' should not be hyphenated, to 'Monte Carlo', on line $. in $input.\n";
			}
			# commented out, as I've seen people at Epic write "Unreal Engine" without "the"
			# Unreal Engine should have "the" before it, unless it's "Unreal Engine 4"
			# note that this test can fail, as the phrase has three words and, despite its name,
			# lctwoline is really "lc this line plus the last word of the previous line"
			#if( !$twook && !$isref && $lctwoline =~ /unreal engine/ && !($lctwoline =~ /the unreal engine/) && !($lctwoline =~ /unreal engine \d/)) {
			#	print "'Unreal Engine' should have 'the' before it, on line $. in $input (note: test is flaky).\n";
			#}
			if( !$ok && !$isref && $lctheline =~ /performant/ ) {
				print "'performant' not fully accepted as a word, so change to 'efficient' or 'powerful' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /Earth/ && !($twoline =~ /Google Earth/) && !($twoline =~ /Visible Earth/) ) {
				print "'Earth' should be 'the earth' (or change this rule to what you like), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /Moon / ) {
				print "'Moon' probably wants to be 'the moon' (or change this rule to what you like), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /dataset/ ) {
				print "'dataset' to 'data set' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /depth-of-field/ ) {
				print "'depth-of-field' to 'depth of field' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /fall off/ ) {
				print "'fall off' to 'falloff' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /fall-off/ ) {
				print "'fall-off' to 'falloff' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /farfield/ ) {
				print "'farfield' to 'far field' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /far-field/ ) {
				print "'far-field' to 'far field' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /nearfield/ ) {
				print "'nearfield' to 'near field' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /near-field/ ) {
				print "'near-field' to 'near field' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /six dimensional/ ) {
				print "'six dimensional' to 'six-dimensional' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /five dimensional/ ) {
				print "'five dimensional' to 'five-dimensional' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /four dimensional/ ) {
				print "'four dimensional' to 'four-dimensional' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /three dimensional/ ) {
				print "'three dimensional' to 'three-dimensional' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /two dimensional/ ) {
				print "'two dimensional' to 'two-dimensional' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /one dimensional/ ) {
				print "'one dimensional' to 'one-dimensional' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /LoD/ ) {
				print "'LoD' to 'LOD' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /rerender/ && !$isref ) {
				print "'rerender' should change to 're-render', on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /retro-reflect/ && !$isref ) {
				print "'retro-reflect' should change to 'retroreflect', on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /inter-reflect/ && !$isref ) {
				print "'inter-reflect' should change to 'interreflect', on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /level-of-detail/ && !$isref ) {
				print "'level-of-detail' should change to 'level of detail', on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /micro-facet/ && !$isref ) {
				print "'micro-facet' should change to 'microfacet', on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /microdetail/ && !$isref ) {
				print "'microdetail' should change to 'micro-detail', on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /black-body/ ) {
				print "'black-body' should change to 'blackbody' on line $. in $input.\n";
			}
			if( !$ok && $lctwoline =~ /black body/ ) {
				print "'black body' should change to 'blackbody' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /spot light/ ) {
				print "'spot light' should change to 'spotlight' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /spot-light/ ) {
				print "'spot-light' should change to 'spotlight' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /frame buffer/ && !$isref ) {
				print "'frame buffer' to 'framebuffer' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /frame-buffer/ && !$isref ) {
				print "'frame-buffer' to 'framebuffer' on line $. in $input.\n";
			}
			# yes, this is inconsistent with the above; chosen by Google search populariy
			if( !$ok && $lctheline =~ /framerate/ && !$isref ) {
				print "'framerate' to 'frame rate' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /pre-filter/ && !$isref ) {
				print "'pre-filter' to 'prefilter' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /pre-process/ && !$isref ) {
				print "'pre-process' to 'preprocess' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /bandlimit/ && !$isref ) {
				print "'bandlimit' to 'band-limit' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ / raycast/ && !$isref ) {
				print "'raycast' to 'ray cast' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ / lob / ) {
				print "Typo? 'lob' to 'lobe' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /frustums/ && !$isref ) {
				print "'frustums' to 'frusta' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /\$Z/ ) {
				print "Consistency check: \$Z should be \$z (or change this test), on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ / 6D/ ) {
				print "'6D' to 'six-dimensional' on line $. in $input.\n";
			}
			# too common, and "similar to" often feels more precise in technical papers
			#if( !$twook && $twoline =~ /similarly to / ) {
			#	print "'similarly to' probably wants to be 'similar to' on line $; better yet, reword, as #it's generally awkward. in $input.\n";
			#}
			# things like "1:1" should be "$1:1$"
			if( !$twook && !$isref && !$inequation && $lctwoline =~ /:1 / && $textonly != 1) {
				print "'X:1' should be of the form '\$X:1\$', on line $. in $input.\n";
			}
			if( !$twook && !$isref && !$inequation && $lctwoline =~ / : 1/ && $textonly != 1 ) {
				print "'X : 1' should be of the form '\$X:1\$' (no spaces), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $twoline =~ / PBRT/ && $textonly != 1 ) {
				print "'PBRT' to '{\\em pbrt}', or cite the book or author, on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /DX9/ ) {
				print "'DX9' to 'DirectX~9' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /DX10/ ) {
				print "'DX10' to 'DirectX~10' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /DX11/ ) {
				print "'DX11' to 'DirectX~11' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /DX12/ ) {
				print "'DX12' to 'DirectX~12' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $twoline =~ /Direct X/ ) {
				print "'Direct X' to 'DirectX' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /™/ && $textonly != 1 ) {
				print "Put \trademark instead of the TM symbol directly, if needed at all, on line $. in $input.\n";
			}
			# "2-degree color-matching" is how that phrase is always presented
			if( !$ok && !$isref && $theline =~ /\d-degree/ && !($theline =~ /color-matching/) ) {
				print "'N-degree' to 'N degree' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /five dimensional/ ) {
				print "'five dimensional' to 'five-dimensional' on line $. in $input.\n";
			}
			#if( !$twook && $twoline =~ / 5D/ ) {
			#	print "'5D' to 'five-dimensional' on line $. in $input.\n";
			#}
			#if( !$twook && $lctwoline =~ /four dimensional/ ) {
			#	print "'four dimensional' to 'four-dimensional' on line $. in $input.\n";
			#}
			#if( !$twook && $twoline =~ / 4D/
			#	&& !($twoline=~/Entrim/) ) {
			#	print "'4D' to 'four-dimensional' on line $. in $input.\n";
			#}
			if( !$ok && $theline =~ /Ph\.D/) {
				print "'Ph.D.' to 'PhD' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /M\.S\./) {
				print "'M.S.' to 'MS' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /M\.Sc\./) {
				print "'M.Sc.' to 'MSc' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ /a MS/) {
				print "'a MS' to 'an MS' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /B\.S\./) {
				print "'B.S.' to 'BS' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /B\.Sc\./) {
				print "'B.Sc.' to 'BSc' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /masters thesis/ ) {
				print "'masters' to 'master's' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /masters degree/ ) {
				print "'masters' to 'master's' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /bachelors degree/ ) {
				print "'bachelors' to 'bachelor's' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ / id / && !($twoline =~ / id Software/)) {
				print "Please change 'id' to 'ID' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ / id~/) {
				print "Please change 'id' to 'ID' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ / ids /) {
				print "Please change 'ids' to 'IDs' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ / ids~/) {
				print "Please change 'ids' to 'IDs' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /middle-ware/) {
				print "Please change 'middle-ware' to 'middleware' on line $. in $input.\n";
			}
			# good manual test
			#if( !$twook && $lctwoline =~ /three dimensional/ && !$isref ) {
			#	print "'three dimensional' to 'three-dimensional' on line $. in $input.\n";
			#}
			if( !$ok && !$isref && $theline =~ /caption\{\}/ ) {
				print "IMPORTANT: every figure needs a caption, on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /g-buffer/ ) {
				print "'g-buffer' to 'G-Buffer', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /G-Buffer/ ) {
				print "'G-Buffer' to 'G-buffer', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /z-buffer/ ) {
				print "'z-buffer' to 'Z-Buffer', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /Z-Buffer/ ) {
				print "'Z-Buffer' to 'Z-buffer', on line $. in $input.\n";
			}
			if( !$twook && !$isref && $twoline =~ / 1d / ) {
				print "'1d' to '1D' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $twoline =~ / 2d / ) {
				print "'2d' to '2D' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $twoline =~ / 3d / ) {
				print "'3d' to '3D' on line $. in $input.\n";
			}
			#if( !$twook && !$isref && $twoline =~ / 3D /
			#		&& !($twoline=~/Interactive 3D/)
			#		&& !($twoline=~/Stanford 3D/)
			#		&& !($twoline=~/3D print/)
			#		&& !($twoline=~/projection!3D triangle to 2D/)
			#		&& !($twoline=~/3D Game Engine/)
			#		&& !($twoline=~/3D Graphics/)
			#		&& !($twoline=~/Source 3D data/)
			#		&& !($twoline=~/3D Game Programming/)
			#	) {
			#	print "'3D' to 'three-dimensional' on line $. in $input.\n";
			#}
			#if( !$twook && !$isref && $twoline =~ / 2D / ) {
			#	print "'2D' to 'two-dimensional' on line $. in $input.\n";
			#}
			#if( !$twook && !$isref && $twoline =~ / 1D/ ) {
			#	print "'1D' to 'one-dimensional' on line $. in $input.\n";
			#}
			if( !$twook && !$isref && $twoline =~ /^So / && !($twoline =~ /^So far/)) { # https://english.stackexchange.com/questions/30436/when-do-we-need-to-put-a-comma-after-so
				print "'So' should be 'So,' or combine with previous sentence, on line $. in $input.\n";
			}
			#if( !$twook && $twoline =~ /^Also / ) { # https://english.stackexchange.com/questions/30436/when-do-we-need-to-put-a-comma-after-so
			#	print "'So' should be 'So,' or combine with previous sentence, on line $. in $input.\n";
			#}
			#if( !$twook && $twoline =~ / Also / ) {
			#	print "'So' should be 'So,' or combine with previous sentence, on line $. in $input.\n";
			#}
			# If you must use "start point", also then use "end point" when talking about the other end. If it's just "end point" by itself, "endpoint" is fine. Normally we say things like "both endpoints," "the endpoints match," etc.
			if( !$twook && $lctwoline =~ /startpoint/ ) {
				print "'startpoint' to 'start point' on line $. in $input.\n";
			}
			#if( !$twook && $lctwoline =~ /end point/ ) {
			#	print "'end point' to 'endpoint' on line $. in $input.\n";
			#}
			if( !$ok && $lctheline =~ /back-fac/ ) {
				print "'back-face' to 'backface' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /back fac/ && (!($twoline =~ /front and back fac/) && !($twoline =~ /front or back fac/) && !($twoline =~ /front and the back fac/)) ) {
				print "'back face' to 'backface' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /front-fac/ ) {
				print "'front-face' to 'frontface' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /front-fac/ ) {
				print "'front-face' to 'frontface' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /wire-fram/ ) {
				print "'wire-frame' to 'wireframe' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /wire frame/ ) {
				print "'wire frame' to 'wireframe' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /sub-pixel/ ) {
				print "'sub-pixel' to 'subpixel' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /mis-categorize/ ) {
				print "'mis-categorize' to 'miscategorize', on line $. in $input.\n";
			}
			# Good, but need to be done manually:
			#if( !$twook && $twoline =~ /On the left / && $infigure ) {
			#	print "'On the left ' to 'On the left, ' on line $. in $input.\n";
			#}
			#if( !$twook && $twoline =~ /On the right / && $infigure ) {
			#	print "'On the right ' to 'On the right, ' on line $. in $input.\n";
			#}
			if( !$ok && $lctheline =~ /counter-clockwise/ ) {
				print "'counter-clockwise' to 'counterclockwise' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /anti-alias/ && !$isref  ) {
				print "'anti-alias' to 'antialias' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ / b spline/ && !$isref  ) {
				print "'B spline' to 'B-spline' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /modelled/ ) {
				print "'modelled' to 'modeled' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /tessela/ && !$isref ) {
				print "'tessela' to 'tessella' on line $. in $input.\n";
			}
			# good manual test:
			#if( !$twook && $lctwoline =~ /on-the-fly/ ) {
			#	print "'on-the-fly' to 'on the fly' on line $. in $input.\n";
			#}
			if( !$twook && $lctwoline =~ /greyscale/ ) {
				print "'greyscale' to 'grayscale' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /speed-up/ ) {
				print "'speed-up' to 'speedup' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /semi-transparen/ ) {
				print "'semi-transparen' to 'semitransparen' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ /In this way / ) {
				print "'In this way ' to 'In this way,' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ /For example / ) {
				print "'For example ' to 'For example,' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /off-screen/ ) {
				print "'off-screen' to 'offscreen' on line $. in $input.\n";
			}
			# really, do just to see, but normally this one's off
			#if( !$twook && $lctwoline =~ / on screen/ ) {
			#	print "Perhaps 'on screen' to 'onscreen' or 'on the screen' on line $. in $input.\n";
			#}
			if( !$ok && $lctheline =~ /on-screen/ ) {
				print "'on-screen' to 'onscreen' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /photo-realistic/ ) {
				print "'photo-realistic' to 'photorealistic' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /point-cloud/ ) {
				print "'point-cloud' to 'point cloud' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /straight forward/ ) {
				print "You likely want to change 'straight forward' to 'straightforward' on line $. in $input.\n";
				print "    See https://www.englishforums.com/English/StraightForwardStraightforward/bcjwmp/post.htm\n";
				&SAYOK();
			}
			if( !$twook && $lctwoline =~ /view point/ ) {
				print "'view point' to 'viewpoint' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /gray scale/ ) {
				print "'gray scale' to 'grayscale' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /post process/ ) {
				print "'post process' to 'post-process' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /postprocess/ ) {
				print "'postprocess' to 'post-process' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /half space/ ) {
				print "'half space' to 'half-space' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /halfspace/ ) {
				print "'halfspace' to 'half-space' on line $. in $input.\n";
			}
			#if( !$twook && !$isref && !$intable && !$inequation && !($twoline =~ /type id : /) && $twoline =~ /: [a-z]/ ) {
			#	print "colon problem '$&' on line $. in $input.\n";
			#}
			if( !$ok && !$isref && $lctheline =~ /lock-less/ ) {
				print "'lock-less' to 'lockless' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /bi-directional/ ) {
				print "'bi-directional' to 'bidirectional' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /over-blur/ ) {
				print "'over-blur' to 'overblur' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /multi-sampl/ ) {
				print "'multi-sampl*' to 'multisampl*' (no hyphen), on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /\$uv\$ coordinates/ ) {
				print "'\$uv\$ coordinates' to 'UV coordinates', on line $. in $input.\n";
			}
			# $uv$ might even be more correct, but UV coordinates is standard, https://en.wikipedia.org/wiki/UV_mapping
			if( !$ok && !$isref && $lctheline =~ /\$uv\$-coordinates/ ) {
				print "'\$uv\$-coordinates' to 'UV coordinates', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /mip-map/ ) {
				print "'mip-map' to 'mipmap' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /mip map/ ) {
				print "'mip map' to 'mipmap' (no space), on line $. in $input.\n";
			}
			# it's a toss up on this one, but make a stand ;). Also, https://www.ics.uci.edu/~yug10/projects/translucent/papers/Hanika_et_al-2015-Computer_Graphics_Forum.pdf and others use it.
			if( !$ok && !$isref && $lctheline =~ /next-event/ ) {
				print "'next-event' to 'next event' (no hyphen), on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /wall clock time/ ) {
				print "'wall clock time' to 'wall-clock time', on line $. in $input.\n";
			}
			if( !$twook && !$isref && $twoline =~ /RT PSO/ ) {
				print "'RT PSO' to 'RTPSO', on line $. in $input.\n";
			}
			if( !$ok && !$isref && !$inequation && ($lctheline =~ / (cubemap)/ || ($style && $lctheline =~ /(cube-map)/)) ) {
				print "Change '$1' to 'cube map' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$isref && ($lctheline =~ / (lightmap)/ || ($style && $lctheline =~ /(light-map)/)) ) {
				print "Change '$1' to 'light map' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$isref && $lctheline =~ / (screenspace)/ ) {
				print "Change '$1' to 'screen space' on line $. in $input.\n";
				&SAYOK();
			}
			# commented out, as it gets used as an adjective a lot
			#if( !$ok && !$isref && $style && $lctheline =~ /(screen-space)/ ) {
			#	print "if not used as an adjective, change '$1' to 'screen space' on line $. in $input.\n";
			#	&SAYOK();
			#}
			if( !$ok && !$isref && !($theline =~ /DXR/) && !($theline =~ /DirectX/) && ($lctheline =~ / (raytrac)/)) {
				print "Change '$1' to 'ray trac*' on line $. in $input.\n";
				&SAYOK();
			}
			# doing a rough survey, there are considerably more articles without the hyphen than with
			if( !$ok && !$isref && $style && $lctheline =~ /(ray-trac)/ ) {
				print "Consistency: change '$1' to 'ray trac*' (it's the norm), on line $. in $input.\n";
			}
			if( !$isref && $lctwoline =~ /directx ray tracing/) {
				print "Change 'DirectX ray tracing' to 'DirectX Raytracing' as this is how Microsoft writes it, on line $. in $input.\n";
			}
			if( !$isref && $twoline =~ /Directx raytracing/) {
				print "Change 'DirectX raytracing' to 'DirectX Raytracing' (capitalize the 'r'), as this is how Microsoft writes it, on line $. in $input.\n";
			}
			if( !$isref  && $style && $lctheline =~ / (pathtrac)/ ) {
				print "Consistency: change '$1' to 'path trac*' on line $. in $input.\n";
			}
			if( !$isref  && $style && $lctheline =~ /(path-trac)/ ) {
				print "Consistency: change '$1' to 'path trac*' (it's the norm), on line $. in $input.\n";
			}
			if( !$ok && !$isref && ($lctheline =~ / (raymarch)/ || ($style && $lctheline =~ /(ray-march)/)) ) {
				print "Change '$1' to 'ray march*' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$isref && $lctheline =~ / (sub-surface)/ ) {
				print "Change '$1' to 'subsurface' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$isref && $lctheline =~ / (preintegrate)/ ) {
				print "Change '$1' to 'pre-integrate' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$isref && $lctheline =~ / (pre-calculate)/ ) { # slight google preference for this, but we'll go precalculate
				print "Change '$1' to 'precalculate' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$isref && $lctheline =~ / (pre-comput)/ ) {
				print "Change '$1' to 'precomput*' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && !$isref && $lctheline =~ /non-linear/ ) {
				print "Change 'non-linear' to 'nonlinear' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /non-planar/ ) {
				print "Change 'non-planar' to 'nonplanar' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /pre-pass/ ) {
				print "Change 'pre-pass' to 'prepass' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /zeroes/ ) {
				print "Change 'zeroes' to 'zeros' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /un-blur/ ) {
				print "Change 'un-blur' to 'unblur' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /un-blur/ ) {
				print "Change 'un-blur' to 'unblur' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /use-case/ ) {
				print "Change 'use-case' to 'use case' (no hyphen), on line $. in $input.\n";
			}
			# our general rule, by the way, is that if Merriam-Webster says it's a word, it's a word: https://www.merriam-webster.com/dictionary/multistage
			if( !$ok && !$isref && $lctheline =~ /multi-stage/ ) {
				print "Change 'multi-stage' to 'multistage' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /XYZ-space/ ) {
				print "Change 'XYZ-space' to 'XYZ space' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /spatio-temporal/ ) {
				print "Change 'spatio-temporal' to 'spatiotemporal', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /close-up/ ) {
				print "Could change 'close-up' to the more modern 'closeup', on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /multi channel/ ) {
				print "Change 'multi channel' to 'multichannel', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /multi-channel/ ) {
				print "Change 'multi-channel' to 'multichannel', on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /multi / ) {
				print "It is unlikely that you want 'multi' with a space after it, on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /pseudo code/ ) {
				print "Change 'pseudo code' to 'pseudocode', on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /pseudo-code/ ) {
				print "Change 'pseudo-code' to 'pseudocode', on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /pseudo / ) {
				print "It is unlikely that you want 'pseudo' with a space after it, on line $. in $input.\n";
			}
			# strictly, no dash, but these help readability.
			#if( !$twook && !$isref && $lctwoline =~ /any-hit shader/ ) {
			#	print "Change 'any-hit' to 'any hit' (no hyphen), on line $. in $input.\n";
			#}
			#if( !$twook && !$isref && $lctwoline =~ /closest-hit shader/ ) {
			#	print "Change 'closest-hit' to 'closest hit' (no hyphen), on line $. in $input.\n";
			#}
			if( !$twook && !$isref && $lctwoline =~ /ray-generation shader/ ) {
				print "Change 'ray-generation' to 'ray generation' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /reexecute/ ) {
				print "Change 'reexecute' to 're-execute', on line $. in $input.\n";
			}
			if( !$ok && !$isref && ($theline =~ /XBox/ || $theline =~ /XBOX/) ) {
				print "Change 'XBox' to 'Xbox' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /x-box/ ) {
				print "Change 'XBox' to 'Xbox' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /Renderman/ ) {
				print "Change 'Renderman' to 'RenderMan' on line $. in $input.\n";
			}
			if( !$ok && !$isref && !($theline =~ /GeForce/) && $lctheline =~ /geforce/ ) {
				print "Change 'Geforce' to 'GeForce' on line $. in $input.\n";
			}
			# https://www.nvidia.com/en-us/geforce/graphics-cards/rtx-2080-ti/
			if( !$ok && !$isref && $lctheline =~ /080ti/ ) {
				print "Change '*080Ti' to '*080~Ti' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /(rtcore)/ ) {
				print "Change '$1' to 'RT Core' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /(rt core)/ ) {
				print "Change '$1' to 'RT~Core' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /(RT~core)/ ) {
				print "Change '$1' to 'RT~Core' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $theline =~ /080 ti/ ) {
				print "Change '*080 ti' to '*080~Ti' on line $. in $input.\n";
			} elsif( !$textonly && !$ok && !$isref && $theline =~ /0 Ti/ ) {
				print "Change '*0 Ti' to '*0~Ti' on line $. in $input.\n";
			}
			if( !$textonly && !$ok && !$isref && $lctheline =~ /titan v/ ) {
				print "Change 'Titan V' to 'Titan~V' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /gtx 2080/ ) {
				print "Change 'GTX' to 'RTX' on line $. in $input.\n";
			}
			if ( !$ok && $theline =~ /Game Developer Conference/ ) {
				print "Change 'Game Developer Conference' to 'Game Developers Conference' on line $. in $input.\n";
			}
			if( !$ok && !$inequation && $theline =~ /Direct3D/ && !$isref ) {
				print "Just our own preference: 'Direct3D' to 'DirectX' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /Playstation/ && !$isref ) {
				print "'Playstation' to 'PlayStation' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /nvidia/  && !($theline =~ "bibitem" || $theline =~ "cite") ) {
				print "'nvidia' to 'NVIDIA' on line $. in $input.\n";
			}
			if( !$ok && $theline =~ /Nvidia/  && !($theline =~ "bibitem" || $theline =~ "cite") ) {
				print "'Nvidia' to 'NVIDIA' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ / a NVIDIA/ ) {
				print "'a NVIDIA' to 'an NVIDIA' on line $. in $input.\n";
			}
			# won't catch them all (the trailing space could have a period, comma, etc.), but better than not catching any.
			if( !$twook && $lctwoline =~ / can not / ) {
				print "'can not' to 'cannot' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /tradeoff/ && !$isref ) {
				print "'tradeoff' to 'trade-off' on line $. in $input.\n";
			}
			if( !$ok && $lctwoline =~ /trade off/ && !$isref ) {
				print "possible fix: 'trade off' to 'trade-off', if not used as a verb, on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /absorbtion/ ) {
				print "'absorbtion' to 'absorption' on line $. in $input.\n";
			}
			if( !$twook && !$inequation && $twoline =~ / gauss/ ) {
				print "'gauss' to 'Gauss' on line $. in $input.\n";
			}
			if( !$twook && !$inequation && $lctwoline =~ / gbuffer/ ) {
				print "'gbuffer' to 'G-buffer' on line $. in $input.\n";
			}
			if( !$twook && !$inequation && $lctwoline =~ / zbuffer/ ) {
				print "'zbuffer' to 'Z-buffer' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /ad-hoc/ ) {
				print "'ad-hoc' to 'ad hoc' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /co-author/ ) {
				print "'co-author' to 'coauthor' on line $. in $input.\n";
			}
			if( !$ok && !$inequation && $lctheline =~ /lowpass/ ) {
				print "'lowpass' to 'low-pass' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /highpass/ ) {
				print "'highpass' to 'high-pass' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /high frequency/ ) {
				print "If an adjective, 'high frequency' to 'high-frequency' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && $lctwoline =~ /high level/ ) {
				print "If an adjective, 'high level' to 'high-level' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && $lctwoline =~ /high fidelity/ ) {
				print "If an adjective, 'high fidelity' to 'high-fidelity' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && $lctwoline =~ /higher quality/ ) {
				print "If an adjective, 'higher quality' to 'higher-quality' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && $lctwoline =~ /floating point/ ) {
				print "If an adjective, 'floating point' to 'floating-point' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$ok && $lctheline =~ /nonboundary/ ) {
				print "'nonboundary' to 'non-boundary' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /formulae/ ) {
				print "'formulae' to 'formulas' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /penumbrae/ ) {
				print "'penumbrae' to 'penumbras' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /one bounce/ ) {
				print "You may want 'one bounce' to 'one-bounce' (add hyphen) if an adjective, on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && $lctwoline =~ /multi bounce/ ) {
				print "'multi bounce' to 'multiple-bounce' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /multibounce/ ) {
				print "'multibounce' to 'multiple-bounce' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /multi-bounce/ ) {
				print "'multi-bounce' to 'multiple-bounce' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /multiple bounce/ && !($lctwoline =~ /multiple bounces/) ) {
				print "'multiple bounce' to 'multiple-bounce' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /multidimensional/ ) {
				print "'multidimensional' to 'multi-dimensional' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /multilayer/ ) {
				print "'multilayer' to 'multi-layer' on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /multibound/ ) {
				print "'multibound' to 'multi-bound' on line $. in $input.\n";
			}
			# searching the ACM Digital Library, 47 entries use "tone mapping" as two words, none as a single word
			if( !$twook && $lctwoline =~ /tonemap/ ) {
				print "'tonemap' to 'tone map' if a noun, 'tone-map' if an adjective, on line $. in $input.\n";
			}
			if( !$twook && !$isref && $twoline =~ /n-Patch/ ) {
				print "'n-Patch' to 'N-patch' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /fill-rate/ ) {
				print "'fill-rate' to 'fill rate' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $formal && $lctheline =~ /bigger/ ) {
				print "'bigger' to 'larger' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $formal && $lctheline =~ /biggest/ ) {
				print "'biggest' to 'greatest' or similar, on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline =~ /self intersect/ && !($lctwoline =~ /self intersection/) ) {
				print "'self intersect' to 'self-intersect' as it's a common term, on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /bidimensional/ ) {
				print "'bidimensional' to 'two-dimensional' mr. fancy pants, on line $. in $input.\n";
			}
			if( !$ok && $lctheline =~ /fillrate/ ) {
				print "'fillrate' to 'fill rate' on line $. in $input.\n";
			}
			# more popular on Google
			if( !$twook && !$isref && $lctwoline =~ /run time/ ) {
				print "'run time' to 'runtime' for consistency, on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /videogame/ ) {
				print "'videogame' to 'video game' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /videocamera/ ) {
				print "'videocamera' to 'video camera' on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /January/ ) {
				print "Change January to Jan. in line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /February/ ) {
				print "Change February to Feb. in line $. in $input.\n";
			}
			if( !$ok && $isref && ($twoline =~ /March \d/ || $twoline =~ /March,/) ) {
				print "Change March to Mar. in line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /September/ ) {
				print "Change September to Sept. in line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /October/ ) {
				print "Change October to Oct. in line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /November/ ) {
				print "Change November to Nov. in line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /December/ ) {
				print "Change December to Dec. in line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /Jan\.,/ ) {
				print "No comma needed after Jan. on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /Feb\.,/ ) {
				print "No comma needed after Feb. on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /March,/ ) {
				print "No comma needed after March on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /April,/ ) {
				print "No comma needed after April on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /May,/ ) {
				print "No comma needed after May on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /June,/ ) {
				print "No comma needed after June on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /July,/ ) {
				print "No comma needed after July on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /August,/ ) {
				print "No comma needed after August on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /Sept\.,/ ) {
				print "No comma needed after Sept. on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /Oct\.,/ ) {
				print "No comma needed after Oct. on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /Nov\.,/ ) {
				print "No comma needed after Nov. on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /Dec\.,/ ) {
				print "No comma needed after Dec. on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /course notes/ ) {
				print "Change 'course notes' to 'course' on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /JCGT/ ) {
				print "SERIOUS: do not use JCGT abbreviation in reference on line $. in $input.\n";
			}
			if( !$ok && $isref && $theline =~ /JGT/ ) {
				print "SERIOUS: do not use JGT abbreviation in reference on line $. in $input.\n";
			}
			# slight Google preference, and https://en.wikipedia.org/wiki/Lookup_table
			if( !$ok && !$isref && $lctheline =~ /look-up/ ) {
				print "Change 'look-up table' to 'lookup table' or similar on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /[\s]disc[\s\.,:;?]/ ) {
				print "Change 'disc' to 'disk' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /exemplif/ ) {
				print "Change 'exemplify' to 'give an example' or 'show' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /[\s]discs[\s\.,:;?]/ ) {
				print "Change 'discs' to 'disks' on line $. in $input.\n";
			}
			# https://www.merriam-webster.com/dictionary/nonnegative says it's good
			if( !$twook && !$isref && $lctwoline =~ /non-negativ/ ) {
				print "Change 'non-negativ' to 'nonnegativ' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /non-physical/ && !($lctheline =~ /non-physically/) ) {
				print "Change 'non-physical' to 'nonphysical' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /non-random/ ) {
				print "Change 'non-random' to 'nonrandom' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /non-uniform/ ) {
				print "Change 'non-uniform' to 'nonuniform' on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /non-zero/ ) {
				print "Change 'non-zero' to 'nonzero' on line $. in $input.\n";
			}
		}
		# nice for a final check one time, but kind of crazed and generates false positives
		if ( $picky ) {
			# Ending a sentence with a preposition is frowned on, but often without merit.
			# The warnings are here just to tip you off to check the sentence, as sometimes the sentence can
			# be reworded.
			# https://blog.oxforddictionaries.com/2011/11/28/grammar-myths-prepositions/
			#if( !$twook && $twoline =~ / on\. / ) {
			#	print "Noteworthy: sentence finishes with the preposition 'on.'  on line $. in $input.\n";
			#}
			if( !$twook && $twoline =~ / at\. / ) {
				print "Noteworthy: sentence finishes with the preposition 'at.' on line $. in $input.\n";
			}
			# some of these, not so terrible.
			#if( !$twook && $twoline =~ / in\. / ) {
			#	print "Noteworthy: sentence finishes with the preposition 'in.' on line $. in $input.\n";
			#}
			if( !$twook && $twoline =~ / of\. / ) {
				print "Noteworthy: sentence finishes with the preposition 'of.' on line $. in $input.\n";
			}
			if( !$twook && $twoline =~ / for\. / ) {
				print "Noteworthy: sentence finishes with the preposition 'for.' on line $. in $input.\n";
			}
			#if( !$twook && $lctwoline =~ / lets/ ) {	# don't check for in refs.tex
			#	print "lets - maybe you mean 'let's' which should go to 'let us' or reword, on line $. in $input.\n";
			#}
			if( !$twook && !$isref && $lctwoline =~ /a number of/ ) {
				print "shortening tip: replace 'a number of' with 'several' (or possibly even remove), on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && !$isref && $lctwoline =~ /in particular/ ) {
				print "shortening tip: perhaps remove 'in particular' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && !$isref && $lctwoline =~ /a large number of/ ) {
				print "shortening tip: perhaps replace 'a large number of' with 'many' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && !$isref && $lctwoline =~ /the majority of/ ) {
				print "shortening tip: replace 'the majority of' with 'most' on line $. in $input.\n";
				&SAYOK();
			}
			if( !$twook && !$isref && $lctwoline =~ / quite/ ) {
				print "The word 'quite' is a cheat for 'very' - can we avoid it? Line $. in $input.\n";
			}
			if( !$twook && $lctwoline =~ /kind of/ ) {
				print "If you don't mean 'type of' for formal writing, change 'kind of' to 'somewhat, rather, or slightly' on line $. in $input.\n";
				&SAYOK();
			}
			# finds some problems, but plenty of false positives:
			if( !$ok && $isref && $theline =~ /\w''/ ) {
				print "ERROR: reference title does not have comma before closed quotes, on line $. in $input.\n";
			}

			if( !$twook && !$isref && $twoline =~ /in order to/ ) {
				print "shortening tip: perhaps replace 'in order to' with 'to' on line $. in $input.\n";
				&SAYOK();
			}
		}
		# promoted from "picky"
		# The non-picky version - at the start of a sentence is particularly likely to be replaceable.
		if( !$twook && !$isref && $twoline =~ /In order to/ ) {
			print "shortening tip: perhaps replace 'In order to' with 'to' on line $. in $input.\n";
			&SAYOK();
		}
		if( !$twook && !$isref && $lctwoline =~ / all of / && 
			!($lctwoline =~ / all of which/) &&
			!($lctwoline =~ / all of this/) &&
			!($lctwoline =~ / all of these/) &&
			!($lctwoline =~ / all of it/)
			) {
			print "shortening tip: replace 'all of' with 'all' on line $. in $input.\n";
			&SAYOK();
		}
		if( !$twook && !$isref && $lctwoline =~ / off of / ) {
			print "shortening tip: replace 'off of' with 'off' on line $. in $input.\n";
			&SAYOK();
		}
		if( !$twook && !$isref && $lctwoline =~ / on the basis of / ) {
			print "shortening tip: replace 'on the basis of' with 'based on' on line $. in $input.\n";
			&SAYOK();
		}
		if( !$twook && !$isref && $lctwoline =~ / first of all, / ) {
			print "shortening tip: replace 'first of all,' with 'first,' on line $. in $input.\n";
			&SAYOK();
		}

		# warn if an italicized term is repeated
		if( !$ok && !$isref && !$infigure && $twoline =~ /{\\em ([\d\w_".'\~\-\$& !^()\/\|\\@]+)}/ ) {
			# if there are capitals in the term, ignore it - probably a title
			my $term = $1;
			if ( lc($term) eq $term ) {
				if ( exists($emfound{$term}) && $input eq $eminput{$term} ) {
					print "Warning: term ''$1'' is emphasized a second time at line $. in $input.\n    First found at $emfound{$1}.\n";
				} else {
					$emfound{$term} = "line $. in $input";
					$eminput{$term} = $input;
				}
			}
		}

		# save the last token on this line so we can join it to the next line
		@fld = split( /\s+/, $theline );
		if ( !$newpara && $#fld >= 0 ) {
			$prev_line = $fld[$#fld];
			# if the last token is an index, ignore it - we want the token at the end mostly for things like "the the"
			if( $prev_line =~ /\\index\{([\d\w_".'\-\$ !()\/\|\\@]+)}/ ) {
				$prev_line = '';
			}
			if ( $isref ) {
				$prev_real_line = $prev_line;
				#printf "prev_real_line is $prev_real_line\n";
				$lastl = $.;
			}
#print "*$theline* and last token is *$fld[$#fld]*\n";
		} else {
			$prev_line = '';
		}
		
		# close up sections at the *end* of testing, so that two-line tests work properly
		if ( $theline =~ /end\{equation/ || 
			$theline =~ /end\{eqnarray/ || 
			$theline =~ /end\{comment/ || 
			$theline =~ /end\{IEEEeqnarray/ || 
			$theline =~ /end\{align/ || 
			$theline =~ /\\\]/ ||
			$theline =~ /end\{lstlisting}/ ) {
			$inequation = 0;
			if ( $theline =~ /end\{lstlisting}/ ) {
				$inlisting = $insidecode = 0;
			}
			if ( $theline =~ /end\{equation}/ || $theline =~ /end\{eqnarray}/ || $theline =~ /end\{IEEEeqnarray}/ ) {
				$justlefteq = 1;
			}
		}
		if ( $theline =~ /end\{figure}/ ) {
			$infigure = 0;
			# did the figure have a caption and a label?
			if ( !$ok && $figlabel eq '' ) {
				print "ERROR: Figure doesn't have a label, on line $. in $input.\n";
			}
			if ( !$ok && $figcaption eq '' ) {
				print "ERROR: Figure doesn't have a caption, on line $. in $input.\n";
			}
			# optional: we think it's wise to always use \centering
			#if ( !$ok && $figcenter eq '' ) {
			#	print "ERROR: Figure doesn't have a \\centering command, on line $. in $input.\n";
			#}
			$figlabel = $figcaption = $figcenter = '';
		}
		if ( $theline =~ /end\{tikzpicture}/ ) {
			$infigure = 0;
		}
		if ( $theline =~ /end\{gather}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{tabbing}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{falign}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{verbatim}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{quote\}/ ) {
			$inquote = 0;
		}
		if ( $theline =~ /end\{tabular/ ) {
			$inequation = 0;
			$intable = 0;
		}

		$twook = $ok;

		} else {
			# the end-if for whether there is anything on the line
			if ( $newpara ) {
				$prev_line = '';
			}
		}
		$lcprev_line = lc($prev_line);
	}

	close DATAFILE;

	my $elem;
	foreach $elem ( sort keys %indexlong ) {
		print "ERROR: index entry started, not ended: {$elem|( in $input.\n";
	}
	undef %indexlong;
}

sub WORDTEST
{
	my $pstring = shift;
	my $phrase = shift;
	my $estring = shift;
	my $end = shift;
	if ( index($estring, $end) != -1 ) {
		# last word token contains previous word, so ignore error for this line - was caught last line.
		return 0;
	}
	if ( index($pstring, $phrase) != -1 ) {
		# problem found in this line, and not previously
		return 1;
	}
	# phrase not found
	return 0;
}

sub SAYOK
{
	print "    If you think it's truly OK (e.g., it's part of a technical term, or you just like it),\n";
	if ($textonly) {
		print "    you can ignore this warning, or edit this perl script and comment it out.\n";
	} else {
		print "    either edit this perl script, or put on the end of this line of your .tex file the comment '% chex_latex'.\n";
	}
}

sub CONNECTOR_WORD
{
	my $testword = shift;
	my $loc = shift;
	if ( $testword eq "and" ||
		$testword eq "or" ||
		$testword eq "versus" ||
		$testword eq "from" ||
		$testword eq "between" ||
		$testword eq "a" ||
		$testword eq "by" ||
		$testword eq "on" ||
		$testword eq "in" ||
		$testword eq "into" ||
		$testword eq "is" ||
		$testword eq "as" ||
		$testword eq "about" ||
		$testword eq "over" ||
		$testword eq "an" ||
		$testword eq "to" ||
		$testword eq "for" ||
		$testword eq "of" ||
		$testword eq "with" ||
		$testword eq "per" ||
		$testword eq "via" ||
		$testword eq "and/or" ||
		$testword eq "the" ) {
		return 1;
	}
	# capitalized and shouldn't be?
	if ( $loc != 0 &&
		($testword eq "And" ||
		$testword eq "Or" ||
		$testword eq "Versus" ||
		$testword eq "From" ||
		$testword eq "Between" ||
		$testword eq "A" ||
		$testword eq "By" ||
		$testword eq "On" ||
		$testword eq "In" ||
		$testword eq "Into" ||
		$testword eq "Is" ||
		$testword eq "As" ||
		$testword eq "About" ||
		$testword eq "Over" ||
		$testword eq "An" ||
		$testword eq "To" ||
		$testword eq "For" ||
		$testword eq "Of" ||
		$testword eq "With" ||
		$testword eq "Per" ||
		$testword eq "Via" ||
		$testword eq "And/Or" ||
		$testword eq "The" )) {
		return 2;
	}
	return 0;
}

sub SECTION_MISMATCH {
	my $word = shift;
	my $cap = CAPITALIZED($word);
	# ignore word?
	if ( $cap == -1 ) {
		return 0;
	}
	my $ind;
	if ( $theline =~ /\\chapter\{/ ) {
		$ind = 0;
		$title_type = '\chapter';
	} elsif ( $theline =~ /\\section\{/ ) {
		$ind = 1;
		$title_type = '\section';
	} elsif ( $theline =~ /\\subsection\{/ ) { # TODO add \subsection*{ and similar
		$ind = 2;
		$title_type = '\subsection';
	} elsif ( $theline =~ /\\subsubsection\{/ ) {
		$ind = 3;
		$title_type = '\subsubsection';
	} elsif ( $theline =~ /\\title\{/ ) {
		$ind = 4;
		$title_type = '\title';
	}
	# to force title to be capitalized (as in GPU Gems), set to 2 here;
	# else comment out this line, to check consistency between this title and other titles of the same type.
	$cap_title[$ind] = 2;

	if ( $cap_title[$ind] ) {
		# check if this chapter's/section's/etc. capitalization matches the first one's
		if ( $cap_title[$ind] != ($cap ? 2 : 1 ) ) {
			# mismatch
			$caps_used = $cap_title[$ind] - 1;
			$caps_loc = $cap_title_loc[$ind];
			return 1;
		}
	} else {
		# first encounter, so record whether second word is capitalized or not
		$cap_title[$ind] = $cap ? 2 : 1;
		$cap_title_loc[$ind] = "on line $. at word '$word' in $input";
	}
	return 0;
}

sub CAPITALIZED
{
	my $testword = shift;
	my $fc = substr( $testword, 0, 1 );
	if ( $fc =~ /\\/ ) {
		return -1;	# ignore word, e.g., \small
	}
	if ( $fc =~ /[A-Z0-9]/ ) {
		return 1;
	}
	return 0;
}

