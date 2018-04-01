#!/usr/contrib/bin/perl
# Script to read in a latex file or directory and its subdirectories and check for typographic
# and syntax errors of various sort.
# Some things:
#   * Look for \label and \ref markers, and note any figure \label's that do not have any \ref's.
#   * Look for \bibitem and \cite markers, note any \bibitems's that do not have any \cite's.

#
# Usage: perl chex_latex.pl
#     this checks all files in the current directory, since the default directory is .
#
# Usage: perl chex_latex.pl advlite.tex
#     checks just this tex file.
#
# Usage: perl chex_latex.pl ..
#     check all *.tex files in the directory above, and subdirectories
#

use File::Find;

my $okword = "chex_latex";

my $refstex = "refs.tex";
my $fronttex = "front.tex";
my $codetex = "codelistings.tex";

my $formal = 1;

# optional, off by default
my $style = 0;
my $superstyle = 0;


# scan command line arguments
my @dirs;
while (@ARGV) {
	# check 
	my $arg = shift(@ARGV) ;
	# does it start with a "-"?
	if ( substr($arg,0,1) eq '-' ) {
		# go through characters and interpret them
		my $chars = substr($arg,1);
		print "chars is $chars\n";
		for ( $i=0; $i < length($chars); $i++ ) {
			my $char = substr($chars, $i, 1);
			#if ( $char eq 'v' ) {
			#	# verbose TODO
			#	my $verbose = 1;
			#} els
			if ( $char eq 's' ) {
				# set $style to flag words with hyphens, such as "light-map" - these can be valid when used as adjectives, however, so it's probably too strict
				$style = 1;
			} elsif ( $char eq 'i' ) {
				# set $informal to true, to allow informal bits such as contractions
				$formal = 0;
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
					printf STDOUT "reference tex file unset\n";
					$refstex = '';
				}
			} elsif ( $char eq 'F' ) {
				# instead of front.tex, set your own bibitem file.
				$fronttex = shift(@ARGV);
				if ( length($fronttex) == 0 || $i+1 < length($chars) ) {
					printf STDOUT "front tex file unset\n";
					$fronttex = '';
				}
			} elsif ( $char eq 'C' ) {
				# instead of codelistings.tex, set your own bibitem file.
				$codetex = shift(@ARGV);
				if ( length($codetex) == 0 || $i+1 < length($chars) ) {
					printf STDOUT "codelistings tex file unset\n";
					$codetex = '';
				}
			} else {
				print STDERR "Unknown argument character '$char'.\n";
				&USAGE();
				exit 0;
			}
		}
	} else {
		# we assume the argument must then be a directory - add it there
		push @dirs, $arg;
	}
}

if ( scalar @dirs == 0 ) { 
	$dirs[0] = '.';	# default is current directory
}
my $dirchop = 0 ;
# silly hack to remove "./" from front of string.
if ( $dirs[0] eq '.' ) {
	$dirchop = 2 ;
}
find( \&READRECURSIVEDIR, @dirs, );

&PROCESSFILES();

exit 0;

#=========================================================

sub USAGE
{
	print "Usage: perl chex_latex.pl [-si] [-O okword] [-R refs.tex] [-F front.tex] [-C codelistings.tex] [directory [directory...]]\n";
	print "  -s - turn ON style check; looks for poor usage and punctuation.\n"
	print "  -i - turn off formal writing check; allows contractions and other informal usage.\n"
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
	$incolldet = 0;
	for ( $i = 0 ; $i < $cfnum ; $i++ ) {
		if ($verbose) { printf "Reading file $codefiles[$i]\n"; }
		@fld = split('/',$codefiles[$i]);	# split
		$nextfile = $fld[$#fld];
		my @subfld;
		@subfld = split('\.',$nextfile);
		$filecore = $subfld[0];
		$path = substr($codefiles[$i],$dirchop,length($codefiles[$i])-length($nextfile)-$dirchop);
#printf "PATH: $path vs $codefiles[$i]\n";
		print "file is $nextfile\n";
		if ( exists($filenames_found{$nextfile}) ) {
			print "ABORT: two .tex files with same name $nextfile found in directory or subdirectory - please clean up.\n";
		}
		$filenames_found{$nextfile} = 1;

		$input = $codefiles[$i];
		&READCODEFILE();
	}

	$critical = 0;
	$potential = 0;
	# figure labeled with "fig_" but not referenced.
	foreach $elem ( sort keys %label ) {
		if ( !exists( $ref{$elem} ) ) {
			if ( $elem =~ /fig_/ || $elem =~ /plate_/ ) {
				if ( $potential == 0 ) { $potential = 1; printf "\n\n*************************\nPOTENTIAL ERRORS FOLLOW:\n"; }
				print "labeled, but not referenced via \\ref: $elem in $label{$elem}\n";
			}
		}
	}
	# element referenced but not found
	foreach $elem ( sort keys %ref ) {
		if ( !exists( $label{$elem} ) ) {
			if ( $critical == 0 ) { $critical = 1; printf "\n\n*************************\nCRITICAL ERRORS FOLLOW:\n"; }
			print "referenced, does not exist (perhaps you meant to \\cite and not \\ref or \\pageref?): $elem in $ref{$elem}\n";
		}
	}
	# element cited but not found
	foreach $elem ( sort keys %cite ) {
		if ( !exists( $bibitem{$elem} ) ) {
			if ( $critical == 0 ) { $critical = 1; printf "\n\n*************************\nCRITICAL ERRORS FOLLOW:\n"; }
			print "cited, does not exist (perhaps you meant to \\ref?): $elem in $cite{$elem}\n";
		}
	}

	# bad citation order
	for ($i = 0; $i < $conum ; $i++ ){
		$subf = $citeorder[$i];
		@fldc = split(/,/,$subf);
		$checkit = 1;
		#printf "on $i with $subf\n";
		for ($j = 1; $j <= $#fldc && $checkit; $j++ ) {
			if ( $biborder{$fldc[$j-1]} > $biborder{$fldc[$j]} ) {
				$checkit = 0;
				print "ERROR: citations *$subf* out of order (or reference missing) at $citeloc[$i]\n";
			}
		}
	}
	
	# bibitems not referenced
	printf "----------------------\n";
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
	if ( $input =~ /refs.tex/ ) { $isref = 1; } else { $isref = 0; }
	if ( $input =~ /front.tex/ ) { $isfront = 1; } else { $isfront = 0; }
	if ( $input =~ /codelistings.tex/ ) { $iscode = 1; } else { $iscode = 0; }

	$ignore_first = 1;

	# now the code file read
	unless (open(DATAFILE,$input)) {
		printf STDERR "Can't open $input: $!\n";
		exit 1 ;
	}
	while (<DATAFILE>) {
		chop;       # strip record separator
		$theline = $_;
		$skip = 0;
		$period_problem = 0;
		
		# cut rest of any line with includegraphics and trim= on it
		if ( $theline =~ /\\includegraphics\[/ ) {
			if ( $theline =~ /trim=/ ) {
				# lame, we just delete rest of line, but want to avoid junk like:
				# trim=2.3in 0in 0in 0in
				# which flags a word duplication problem.
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
		if ( $theline =~ /\\subfloat/ ) { $theline = $`; }

		
		# if the line has chex_latex on it in the comments, can ignore certain flagged problems,
		# and ignore figure names.
		$ok = ( $theline =~ /$okword/ ); # TODO - look only in comments
		$twook |= $ok;
		# hit a new paragraph?
		$newpara = (length($theline) == 0);
		# convert \% to Pct so we don't confuse it with a comment.
		$theline =~ s/\\%/PercentSign/g;
		# if ( $theline =~ /PercentSign/ ) { print "FOUND: $theline\n"; }
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
		$twoline = ' ' . $prev_line . ' ' . $theline . ' ';

		# index searcher: find left |( and right |) index entries and make sure they match up.
		$str = $twoline;
		$newtwoline = '';

		# index test
		while ( $str =~ /\\index\{([\d\w_".'\~\-\$& !^()\/\|\\@]+)}/ ) {
			$indexname = $1;

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
					printf "ERROR: found right index {$`|)} without left index in $nextfile.\n    Perhaps you repeated this right entry?\n";
				} else {
					$indexlong{$`}--;
					if ( $indexlong{$`} == 0 ) {
						delete $indexlong{$`};
					}
				}
			} 
		}
		$newtwoline .= $str;
		#if ( $twoline ne $newtwoline ) {
		#	print "twoline $twoline\n and newline $newtwoline\n";
		#}
		# twoline now has the index entries removed from it.
		$twoline = $newtwoline;
		$lctwoline = lc($twoline);
		
		$str = $theline;
		if ( $str =~ /see\{([\d\w_".'\~\-\$& !^()\/\|\\@]+)}/ ) {
			$seestr = $1;
			if ( $seestr =~ /!/ ) {
				print "Error: ''$seestr'', replace exclamation point with comma and space, on line $.\n";
			}
		}

		$lctheline = lc($theline);
		
		# check for section, etc. and see that words are capitalized
		# can compare with Chicago online https://capitalizemytitle.com/ - may need to add more connector words to this subroutine.
		if ( 
			$theline =~ /\\chapter\{([A-Za-z| -]+)\}/ ||
			$theline =~ /\\section\{([A-Za-z| -]+)\}/ ||
			$theline =~ /\\subsection\{([A-Za-z| -]+)\}/ ||
			$theline =~ /\\subsubsection\{([A-Za-z| -]+)\}/ ) {
			#print "section found $1 for $theline\n";
			@wds = split(/[ -]/,$1);	# split
			$dump = 0;
			#$dump = ( $lctheline =~ /ambient/ );
			for ($i = 0; $i <= $#wds; $i++ ) {
				if ( $dump ) {
					print "testing $i of $#wds $wds[$i] in $input\n";
				}
				my $sw = &CONNECTOR_WORD($wds[$i], $i);
				if ( $sw == 2 ) {
					print "POSSIBLY SERIOUS: Section title has a word '$wds[$i]' that should not be capitalized, on line $. in $input.\n";
					print "    You can test your title at https://capitalizemytitle.com/\n";
				}
				elsif ( $sw == 0 && (length($wds[$i]) > 0) && !&CAPITALIZED($wds[$i]) ) {
					# feel free to comment this one out, or comment out subsection or similar above, for the
					# types of sections where you don't capitalize
					print "Possibly SERIOUS: Section title has a word '$wds[$i]' uncapitalized, on line $. in $input.\n";
					print "    Ignore if this word '$wds[$i]' is a 'connector word' such as 'in' or 'and' -\n";
					print "    you can test your title at https://capitalizemytitle.com/\n";
					print "    Also, feel free to go into the code and comment out this test!\n";
				}
			}

		}

		# check if we're in an equation or verbatim section
		if ( $theline =~ /begin\{equation/ || 
			$theline =~ /begin\{eqnarray/ || 
			$theline =~ /begin\{IEEEeqnarray/ || 
			$theline =~ /begin\{align/ || 
			$theline =~ /begin\{lstlisting}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{figure}/ ) {
			$infigure = 1;
		}
		if ( $theline =~ /begin\{gather}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{tabbing}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{tabular}/ ) {
			$inequation = 1;
			#print "tabular start line $.\n";
		}
		if ( $theline =~ /begin\{align}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{verbatim}/ ) {
			$inequation = 1;
		}
		if ( $theline =~ /begin\{quote\}/ ) {
			$inquote = 1;
		}
		if ( $theline =~ /begin\{tabular/ ) {
			$intable = 1;
		}

		# let the main testing begin!
		
		# ------------------------------------------
		# Check doubled words. Possibly the most useful test in the whole script
		# the crazy one, from https://stackoverflow.com/questions/23001408/perl-regular-expression-matching-repeating-words, catches all duplicate words such as "the the"
		if( !$twook && !$intable && !$inequation && $lctwoline =~ /(?:\b(\w+)\b) (?:\1(?: |$))+/ && $1 ne 'em' ) {
			print "SERIOUS: word duplication problem of word '$1' on line $. in $input.\n";
		}
		# surprisingly common
		if( $lctwoline  =~ / a the / ) {
			print "'a the' to 'the' on line $. in $input.\n";
		}
		if( $lctwoline  =~ / the a / ) {
			print "'the a' to 'the' on line $. in $input.\n";
		}

		# ---------------------------------------------------------
		# bibitem stuff, if you use this style. bibitems are assumed to be in refs.tex
		if( ($input =~ /refs.tex/) && ($prev_line =~ /bibitem/) ) {
			# does next line have a " and " without a "," before the space?
			if ( !$ok && ( $theline =~ / and / || $theline =~ / and,/ ) ) {
				if ( substr($`,-1) ne ',' ) { # && substr($`,-1) ne ' ' ) {
					print "SERIOUS: refs.tex has an author line with \"and\" but no comma before the \"and\", on line $. in $input.\n";
				}
			}
			# does line not have a "," at the end?
			if ( !$ok && !($theline =~ /,$/) && !($theline =~ /``/) ) { # && !($theline =~ /{/) ) {
				print "SERIOUS: refs.tex has an author line without a comma at the end, on line $. in $input.\n";
				print "  (or, put all authors on one line, please.)\n";
			}
			# does last name of first author not have a comma after it?
			if ( !$ok ) {
				@bibname = split( /\s+/, $theline );
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
						print "SERIOUS: refs.tex first author ''$bibname[0], firstname'' has no comma at end of last name, on line $. in $input.\n";
					}
				}
			}
		}

		# ---------------------------------------------------------
		# citation problem: use a ~ instead of a space so that the citation is connected with the content before it.
		if( $theline =~ /[\s\w\.,}]\\cite\{/ ) {
			print "\\cite problem on line $. in $input, needs a tilde ~\\cite before citation.\n";
		}
		# has the tilde, but there's a space before the tilde
		if( $theline =~ /\s~\\cite\{/ ) {
			print "\\cite problem on line $. in $input, remove the space before the tilde ~\\cite.\n";
		}
		if( $theline =~ /\/cite/ ) {
			print "SERIOUS: '/cite' $& problem, should use backslash, on line $. in $input.\n";
		}
		if( $theline =~ /\/ref/ && !($theline =~ /{eps/ || $theline =~ /{figures/) && !($input =~ /refs.tex/) ) {
			print "SERIOUS: '/ref' $& problem, should use backslash, on line $. in $input.\n";
		}
		if( $theline =~ /\/label/ ) {
			print "SERIOUS: '/label' $& problem, should use backslash, on line $. in $input.\n";
		}

		# ----------------------------------------------------------
		# index entry tests
		if( $theline =~ /\/index\{/ && !($input =~ /refs.tex/) ) {
			print "SERIOUS: '/index' $& problem, should be \\index, on line $. in $input.\n";
		}
		if( $theline =~ /\\index/ && !($input =~ /refs.tex/) ) {
			# look at index entry - only looks at first one in line, though.
			$index = $';
			if ( $index =~ /\|/ && !($index =~ /\|see/) && !($index =~ /\|nn/) && !($index =~ /\|emph/) && !($index =~ /\|\(/) && !($index =~ /\|\)/) ) {
				print "SERIOUS: '\index' has a '|' without a 'see' or similar after it, on line $. in $input. Did you mean '!'?\n";
			}
		}
		# reference needs tilde
		if( $theline =~ /[\s\w\.,}]\\ref\{/ ) {
			$testit = $`;
			if ( !( $testit =~ /and$/ ) && !( $testit =~ /,$/ ) ) { # don't worry about second number for figure being on same line.
				print "\\ref problem on line $. in $input, needs a tilde ~\\ref before reference.\n";
			}
		}
		# pageref needs tilde
		if( $theline =~ /[\s\w\.,}]\\pageref\{/ ) {
			$testit = $`;
			if ( !( $testit =~ /and$/ ) && !( $testit =~ /,$/ ) ) { # don't worry about second number for figure being on same line.
				print "\\pageref problem on line $. in $input, needs a tilde ~\\pageref before reference.\n";
			}
		}
		# if it says "page" before the reference
		if( $theline =~ /page~\\ref/ ) {
			print "\\ref should probably be a \\pageref on line $.\n";
		}
		# cite should have a \ before this keyword
		if( $theline =~ /~cite\{/ ) {
			print "\\cite problem on line $. in $input, missing \\.\n";
		}
		# ref should have a \ before this keyword
		if( $theline =~ /~ref\{/ ) {
			print "\\ref problem on line $. in $input, missing \\.\n";
		}
		# pageref should have a \ before this keyword
		if( $theline =~ /~pageref\{/ ) {
			print "\\pageref problem on line $. in $input, missing \\.\n";
		}
		$str = $theline;
		# label used twice
		while ( $str =~ /\\label\{([\w_]+)}/ ) {
			$str = $';
			if ( exists($label{$1}) ) {
				print "ERROR: duplicate label $1\n";
			}
			$label{$1} = $nextfile;
		}
		$str = $theline;
		# record the refs for later comparison
		while ( $str =~ /\\ref\{([\w_]+)}/ ) {
			$str = $';
			$ref{$1} = $nextfile;
		}
		while ( $str =~ /\\pageref\{([\w_]+)}/ ) {
			$str = $';
			$ref{$1} = $nextfile;
		}
		if( $twoline  =~ /\w\|\}/ && !$inequation && !$intable && !($input =~ /book.tex/) && !($twoline  =~ /\\frac/) ) {
			print "SERIOUS: bad index end at $&, change to char}, on line $. in $input.\n";
		}
		if( $twoline  =~ /\(\|\}/ ) {
			print "SERIOUS: bad index start at (|}, change to |(}, on line $. in $input.\n";
		}
		
		# -----------------------------------------------
		# bibitem related
		$str = $theline;
		# for bibitems, did prev_line (i.e., the previous bibitem) end with a period? All should! comments are deleted.
		if ( $str =~ /\\bibitem\{([\w_']+)}/ ) {
			$k = chop $prev_real_line;
			#printf "k is $k\n";
			$kk = chop $prev_real_line;
			#printf "k is $k\n";
			if ( $k ne '.' && $kk ne '.' && !$ignore_first ) {
				printf "no period on around line $lastl in $input.\n";
			}
			$ignore_first = 0;
		}
		while ( $str =~ /\\bibitem\{([\w_']+)}/ ) {
			$str = $';
			if ( exists($bibitem{$1}) ) {
				print "ERROR: duplicate bibitem $1\n";
			}
			$bibitem{$1} = $nextfile;
			$biborder{$1} = $numbib++;
		}
		$str = $theline;
		while ( $str =~ /\\cite\{([\w_,'\s*]+)}/ ) {
			$front = $`;
			$str = $';
			$subf = $1;
			$subf =~ s/ //g;
			@fldc = split(/,/,$subf);	# split
			if ($#fldc > 0) {
				# more than one citation, keep for checking alpha order later
				$citeorder[$conum] = $subf;
				$citeloc[$conum] = "$. in $nextfile";
				$conum++;
			}
			if ($#fldc >= 0 ) {
				for ($i = 0; $i <= $#fldc; $i++ ) {
					$cite{$fldc[$i]} = $nextfile;
				}
			} else {
				$cite{$1} .= $nextfile . ' ';
			}
		}

		# digits with space, some european style, use commas instead
		if( !$isfront && $theline =~ /\d \d\d\d/ ) {
			print "POSSIBLY SERIOUS: digits with space '$&' might be wrong\n    Use commas, e.g. '300 000' should be `300,000' on line $. in $input.\n";
		}
		
		# ----------------------------------------------------------------
		# Punctuation
		# single dash should be ---
		# test could be commented out because it could be an equation, e.g., 9 - 4
		if( $theline =~ / - / && !$inequation ) {
			if ( !($` =~ /\$/) ) {
				print "SERIOUS: change ' - ' to '---' on line $. in $input.\n";
			}
		}
		# -- to ---, if words on both sides (otherwise this might be a page number range)
		if( !$isref && !$inequation && $lctwoline =~ /[a-z]--\w/ ) {
			if ( !($` =~ /\$/) ) {
				print "SERIOUS: change '--' (short dash) to '---' on line $. in $input.\n";
			}
		}
		# U.S. style: period goes inside the quotes, much as we might wish it to be different.
		if( $theline =~ /''\./ ) {
			if ( !($` =~ /\$/) ) {
				print "SERIOUS: U.S. punctuation rule, change ''. to .'' on line $. in $input.\n";
			}
		}
		# U.S. punctuation test for commas, same deal.
		if( $theline  =~ /'',/ && !($theline  =~ /gotcha/) ) {
			print "SERIOUS: U.S. punctuation rules state that '', should be ,'' on line $. in $input.\n";
		}

		# This doesn't actually work, though I wish it would - I want to detect a "true" right-leaning apostrophe
		#if( $theline  =~ /\�/ ) {
		#	print "SERIOUS: the special right-leaning apostrophe '�' should be a normal apostrophe on line $. in $input.\n";
		#}
		if( $theline  =~ /''\./ ) {
			print "SERIOUS: ''.' should be .'' on line $. in $input.\n";
		}
		
		# see https://english.stackexchange.com/questions/34378/etc-with-postpositioned-brackets-at-the-end-of-a-sentence
		if( $twoline =~ / etc/ && !($' =~ /^\./) ) {
			print "SERIOUS: 'etc' isn't followed by a . on line $. in $input.\n";
		}
		# we like to avoid ending a sentence with a preposition.
		if( $twoline  =~ / with\. / && 
			!($input =~ /surfs.tex/) ) { # hiding the one exception...
			print "consider: 'with.' at end of sentence on line $. in $input. Reword if it's not convoluted to do so.\n";
		}
		if( $theline  =~ /\/footnote/ ) {
			print "SERIOUS: change '/footnote' to '\\footnote' on line $. in $input.\n";
		}
		if( $theline  =~ /~\\footnote/ ) {
			print "SERIOUS: change '~\\footnote' to '\\footnote' on line $. in $input.\n";
		}
		# Great one, but you have to hand check the finds TODO END
		#if( $lctwoline  =~ /\w\\footnote/ ) {
		#	print "SERIOUS: 'w\\footnote' to ' \\footnote' on line $. in $input.\n";
		#}
		if( !$ok && $theline  =~ / -- / ) {
			print "POTENTIALLY SERIOUS: change ' -- ' to the full dash '---' on line $. in $input.\n";
		}
		if( $twoline  =~ / --- / ) {
			print "SERIOUS: ' --- ' should not have spaces before and after it, on line $. in $input.\n";
		} elsif( $twoline  =~ /--- / ) {
			print "SERIOUS: '--- ' should not have a space after it, on line $. in $input.\n";
		} elsif( $twoline  =~ / ---/ && !$inquote ) {
			print "SERIOUS: ' ---' should not have a space before it, on line $. in $input.\n";
		}
		if( $isref && $twoline  =~ /pp. \d+-\d+/ ) {
			print "ERROR: '$&' page number has only one dash, on line $. in $input.\n";
		}
		if( !$twook && !$isref && $twoline  =~ / \[\d+-\d+\]/) {
			print "ERROR: '$&' date range has only one dash, needs two, on line $. in $input.\n";
		}
		if( !$twook && !$isref && $twoline  =~ / \(\d+-\d+\)/) {
			print "ERROR: '$&' date range needs to use brackets, [], not parentheses, and\n    has only one dash, needs two, on line $. in $input.\n";
		}
		if ( $theline =~ /\?\-/ && ($input =~ /refs.tex/) ) {
			print "There's a ?- page reference (how do these get there? I think it's a hidden character before the first - from copy and paste of Computer Graphics Forum references), on line $. in $input.\n";
		}
		if ( $theline =~ /\-\?/ && ($input =~ /refs.tex/) ) {
			print "There's a -? page reference (how do these get there? I think it's a hidden character before the first - from copy and paste of Computer Graphics Forum references), on line $. in $input.\n";
		}
		if( $twoline  =~ /_\{diff\}/ ) {
			print "SERIOUS: change _{diff} to _{\\Diff}, on line $. in $input.\n";
		}
		if( $theline  =~ /\/times/ ) {
			print "SERIOUS: change '/times' to '\\times' on line $. in $input.\n";
		}
		#if( $isref && !($twoline  =~ /--/) && $twoline  =~ /-/ ) {
		#	print "Warning: '$_' in refs has only one dash, on line $. in $input.\n";
		#}
		# good, but must hand check:
		#if( $twoline  =~ /one dimensional/ ) {
		#	print "'one dimensional' to 'one-dimensional' on line $. in $input.\n";
		#}

		# adding spaces is nice to do for readability, but not dangerous:
		#if( $twoline  =~ /\d\\times/ ) {
		#	print "left \\times problem on line $. in $input.\n";
		#}
		# nice to do for readability, but not dangerous:
		#if( $twoline  =~ /\\times\d/ ) {
		#	print "right \\times spacing problem on line $. in $input.\n";
		#}
		
		# TODO - may want to suppress with, say, -t - text-only testing.
		# Latex-specific
		if( $theline  =~ /�/ ) {
			print "SERIOUS: the punctuation � should change to a ' (vertical) apostrophe on line $. in $input.\n";
		}
		if( !$inequation && $theline  =~ /"/ && !($theline  =~ /\\"/) && !$iscode ) {
			print "SERIOUS: the double-apostrophe \" should change to a \'\' on line $. in $input.\n";
		}

		if( $twoline && $twoline =~ / Corp\. / ) {
			print "'Corp. ' needs backslash 'Corp\\.' to avoid wide space after period, on line $. in $input.\n";
		}
		if( !$twook && $twoline =~ / Inc\. / ) {
			print "'Inc. ' needs backslash 'Inc\\.' to avoid wide space after period, on line $. in $input.\n";
		}
		if( $twoline  =~ /\.\) / ) {
			print "POSSIBLY SERIOUS: '.) ' needs a \\ after it to avoid extra space, on line $. in $input.\n";
		}
		if( !($twoline =~ /\$/) && !($twoline =~ /''/) && $twoline  =~ /\.\./ && !$inequation ) {
			print "Doubled periods, on line $. in $input.\n";
		}
		if( $twoline  =~ /,,/ ) {
			print "Doubled commas, on line $. in $input.\n";
		}
		# experimental...
		# Latex will by default make a "short space" after a capital letter followed by a period.
		# For example: Franklin D. Roosevelt. For longer sets of capital letters, e.g. GPU, DNA,
		# we want to have a "long space," as in: "There are many types of DNA.  We will discuss..."
		if( !$ok && !$inequation && $theline  =~ /([A-Z][A-Z]+)\./ ) {
			print "Sentence ending in the capital letters $1 should have a '\\@.' for spacing, on line $. in $input.\n";
		}

		# this one can flake if there's a ) at the end of a line - it should really find the
		# credit at the end of the caption.
		if( !$ok && $infigure && $theline =~ /\w\)}/ ) {
			print "Credit needs period at end, on line $. in $input.\n";
		}
		if( $twoline  =~ /Image Courtesy/ || $twoline  =~ /Images Courtesy/ ) {
			print "Change 'Courtesy' to 'courtesy' on line $. in $input.\n";
		}
		if( $lctwoline  =~ /[\d+] ms/ ) {
			print "' ms' to '~ms' to avoid having the number separated from its units, on line $. in $input.\n";
		}
		if( $lctwoline  =~ /[\d+] fps/ ) {
			print "' FPS' to '~FPS' to avoid having the number separated from its units, on line $. in $input.\n";
		}
		if( $lctwoline  =~ /[\d+] Hz/ ) {
			print "' Hz' to '~Hz' to avoid having the number separated from its units, on line $. in $input.\n";
		}		
		# ----------------------------------
		# Style: comma and period punctuation
		if( $twoline  =~ /i\.e\. / ) {
			print "SERIOUS: 'i.e. ' should have a comma after it, not a space, on line $. in $input.\n";
			$period_problem = 1;
		}
		if( $twoline  =~ /e\.g\. / ) {
			print "SERIOUS: 'e.g. ' should have a comma after it, not a space, on line $. in $input.\n";
			$period_problem = 1;
		}
		if( $lctwoline  =~ / et al/ ) {
			$post = $';
			if ( !($post =~ /^\./ || $post =~ /^ia/) ) {
				print "'et al' is not followed by '.' or 'ia' on line $. in $input.\n";
			}
		}
		if( !$twook && $twoline  =~ / al\. / ) {
			print "POSSIBLY SERIOUS: change 'et al.' to 'et al.\\' if you are not ending a sentence, on line $. in $input.\n";
			$period_problem = 1;
		}
		if( $twoline  =~ / \. / ) {
			print "SERIOUS: change ' .' to '.' (space in front of period), on line $. in $input.\n";
		}
		if( $twoline  =~ / \,/ ) {
			print "SERIOUS: change ' ,' to ',' (space in front of comma), on line $. in $input.\n";
		}
		# If you use a ".", you need to do something like ".~" to avoid having the period treated
		# as if it's the end of a sentence, which causes a bit of additional space to get added after it.
		# Easiest is to just spell out vs.
		if( !$isref && $twoline  =~ / vs\./ && !$ok ) {
			print "SERIOUS: change 'vs.' to 'versus' to avoid period inter-sentence/inter-word spacing problem, or use 'vs\\.' on line $. in $input.\n";
		}
		if( !$isref && $twoline =~ / vs / ) {
			print "SERIOUS: change 'vs' to 'versus' on line $. in $input\n";
		}
		if( !$isref && $twoline  =~ / etc\./ && !$ok ) {
			print "POSSIBLY SERIOUS: change 'etc.' to 'etc\\.' to avoid period inter-sentence/inter-word spacing problem, on line $. in $input.\n    (To be honest, it's better to avoid 'etc.' altogether, as it provides little to no information.)\n";
			$period_problem = 1;
		}
		
		# ---------------------------------------------------
		# grammatical, or other word-related problems
		if( $theline  =~ /TODO/ ) {
			print "Beware, there is a TODO in the text itself at line $. in $input.\n";
		}
		# OK: straight on, later on.
		#if( $twoline  =~ / on\. / ) {
		#	print "SERIOUS: sentence finishes with 'on.' problem on line $. in $input.\n";
		#}
		if( $twoline  =~ / at\. / ) {
			print "SERIOUS: sentence finishes with 'at.' problem on line $. in $input.\n";
		}
		# some of these, not so terrible.
		#if( $twoline  =~ / in\. / ) {
		#	print "SERIOUS: sentence finishes with 'in.' problem on line $. in $input.\n";
		#}
		if( $twoline  =~ / of\. / ) {
			print "SERIOUS: sentence finishes with 'of.' problem on line $. in $input.\n";
		}
		if( $twoline  =~ / for\. / ) {
			print "SERIOUS: sentence finishes with 'for.' problem on line $. in $input.\n";
		}
		if( $twoline  =~ /\. [a-z]/ && !($twoline  =~ /a\.k\.a\./) && !$isref && !$isfront && !$inequation && !$period_problem ) {
			print "Not capitalized at start of sentence (or the period should have a \\ after it), on line $. in $input.\n";
		}
		if( $theline  =~ /Javascript/) {
			print "Please change 'Javascript' to 'JavaScript' on line $. in $input.\n";
		}
		if( $lctheline  =~ /frustrum/ ) {
			print "MISSPELLING: 'frustrum' to 'frustum' on line $. in $input.\n";
		}
		
		# -----------------------------
		# Clunky or wrong
		if( $twoline  =~ / to\. / ) {
			print "SERIOUS: ending a sentence with 'to.' is not so great, on line $. in $input.\n";
		}
		if( !$isref && $lctheline  =~ /irregardless/ && !$inquote ) {
			print "No, never use 'irregardless' on line $. in $input.\n";
		}
		if( !$isref && $lctheline  =~ /necessitate/ && !$inquote ) {
			print "Please don't use 'necessitate' on line $. in $input.\n";
		}
		if( !$isref && $lctheline  =~ /firstly/ && !$inquote ) {
			print "Do not say 'firstly', say 'first' on line $. in $input.\n";
		}
		if( $lctwoline  =~ /amongst/ ) {
			print "Change 'amongst' to 'among' on line $. in $input.\n";
		}
		if( $lctwoline =~ / try and/ ) {
			print "Change 'try and' to 'try to' on line $. in $input, or reword to 'along with' or similar.\n";
		}
		if( $twoline  =~ /relatively to / ) {
			print "tip: 'relatively to' probably wants to be 'relative to' on line $. in $input.\n";
		}
		if( !$isref && !$twook && $lctwoline =~ /so as to / ) {
			print "tip: you probably should replace 'so as to' with 'to' or similar on line $. in $input, or rewrite.\n    It's a wordy phrase.\n";
			print "    If you think it's OK, put on the end of the line the comment '% chex_latex'\n";
		}
		if( $lctwoline =~ /due to that/ ) {
			print "tip: 'due to that' to 'because' on line $. in $input.\n";
		}
		if( $lctwoline =~ /more specifically/ ) {
			print "tip: 'more specifically' to 'specifically' on line $. in $input.\n";
		}
		if( $lctwoline  =~ /made out of/ ) {
			print "shortening tip: replace 'made out of' with 'made from' on line $. in $input.\n";
		}
		if( !$isref && $lctwoline =~ /due to the fact that/ && !$inquote ) {
			print "tip: replace 'due to the fact that' with 'because' on line $. in $input.\n";
		}
		if( !$isref && $lctheline  =~ /on account of/ && !$inquote ) {
			print "tip: change 'on account of/' to 'because' on line $. in $input.\n";
		}
		if( !$isref && $lctheline  =~ /basically/ && !$inquote ) {
			print "tip: you can probably remove 'basically' on line $. in $input.\n";
		}
		if( !$isref && $lctheline  =~ /orientate/ && !$inquote ) {
			print "tip: you probably don't want to use 'orientate' on line $. in $input.\n";
		}
		if( !$isref && $lctheline  =~ /thusly/ && !$inquote ) {
			print "tip: change 'thusly' to 'thus' or 'therefore' on line $. in $input.\n";
		}
		if( !$isref && $lctwoline  =~ /point in time/ && !$inquote ) {
			print "tip: avoid the wordy phrase 'point in time' at this point in time, on line $. in $input.\n";
		}
		if( !$isref && !$ok && $lctheline  =~ /literally/ && !$inquote ) {
			print "tip: you can probably not use 'literally' (and may mean 'figuratively'), on line $. in $input.\n";
			print "    If you think it's OK, put on the end of the line the comment '% chex_latex'\n";
		}
		if( $lctwoline =~ / a lot more/ ) {
			print "tip: replace 'a lot' with 'much' on line $. in $input.\n";
		}
		if( $lctwoline =~ /and also / ) {
			print "tip: you probably should replace 'and also' with 'and' on line $. in $input, or reword to 'along with' or similar.\n";
		}
		if( $lctwoline =~ /the reason why is because/ ) {
			print "tip: 'the reason why is because' is crazy wordy, so rewrite, on line $. in $input.\n";
		}
		if( $lctwoline  =~ /fairly straightforward/ ) {
			print "shortening tip: replace 'fairly straightforward' with 'straightforward' on line $. in $input.\n";
		}

		if ( $formal ) {
			# -----------------------------
			# Formal style
			if( !$isref && $lctwoline  =~ / got / && !$inquote ) {
				print "Please don't use 'got' on line $. in $input.\n";
			}
			if( $lctwoline =~ / lots of/ ) {
				print "For formal writing, change 'lots of' to 'many' or 'much' on line $. in $input.\n";
			}
			if( $lctwoline =~ / lots / ) {
				print "For formal writing, change 'lots' to 'many' or 'much' on line $. in $input.\n";
			}
			if( !$twook && !$isref && $lctwoline  =~ / cheap/ && !$inquote ) { # not the lennart quote
				print "Please use 'less costly' instead of 'cheap', as 'cheap' implies poor quality, on line $. in $input.\n";
			}
			if( $lctwoline  =~ /and\/or/ ) {
				print "Please do not use 'and/or' on line $. in $input.\n";
			}
			if( $lctwoline  =~ / a lot of / ) {
				print "Avoid informal 'a lot of', change to 'many', 'much', 'considerable' or similar, on line $. in $input.\n";
			} elsif( $lctwoline  =~ / a lot / ) {
				print "Avoid informal 'a lot', change to 'much' on line $. in $input.\n";
			}
			# left out because of "can not only provide", which is fine
			#if( $lctwoline  =~ /can not / ) {
			#	print "'can not' to 'cannot' on line $. in $input.\n";
			#}
			if( $lctheline  =~ /n't/ && !$inquote && !$isref ) {
				print "SERIOUS: no contractions: 'n't' to ' not' on line $. in $input.\n";
			}
			if( $lctheline  =~ /let's/ && !$inquote && !$isref ) {	# don't check for in refs.tex
				print "SERIOUS: no contractions: 'let's' to 'let us' or reword, on line $. in $input.\n";
			}
			if( $lctheline  =~ /we've/ && !$inquote && !$isref ) {	# don't check for in refs.tex
				print "SERIOUS: no contractions: 'we've' to 'we have' or reword, on line $. in $input.\n";
			}
			if( $lctwoline  =~ / it's/ && !$inquote && !($input =~ /refs.tex/) ) {
				print "SERIOUS: no contractions: 'it's' to 'it is' on line $. in $input.\n";
			}
			if( $theline  =~ /'re/ && !$inquote ) {
				print "SERIOUS: no contractions: ''re' to ' are' on line $. in $input.\n";
			}
			if( $theline  =~ /'ll/ && !$inquote ) {
				print "SERIOUS: no contractions: ''ll' to ' will' on line $. in $input.\n";
			}
			if( !$isref && $theline =~ /formulas/ ) {
				print "Change 'formulas' to 'formulae' on line $. in $input, or rewrite.\n";
			}
			if( $twoline  =~ /Generally / ) {
				print "add comma: after 'Generally' on line $. in $input.\n";
			}
		}
		
		if ( $style  ) {
			# ------------------------------------------------
			# Personal preferences, take them or leave them
			# "Substitute 'damn' every time you�re inclined to write 'very,'" said Mark Twain. "Your editor will delete it and the writing will be just as it should be." https://lifehacker.com/replace-very-with-damn-to-improve-your-writing-1708460103
			# Try to find a substitute, e.g., "very small" could become "minute" or "tiny"
			if( !$isref && (($lctwoline =~ / very/ && !$inquote ) || ($lctwoline =~ /^very/))) {
				print "tip: remove or replace 'very' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /really/ && !$inquote ) { # not the lennart quote
				print "shortening tip: remove 'really' on line $. in $input.\n";
			}
			if( !$isref && $lctwoline =~ / interesting/ ) {
				print "tip: reconsider 'interesting' on line $. in $input, probably delete it\n    or change to 'key', 'noteworthy', 'notable', 'different', or 'worthwhile'.\n    Everything in your work should be interesting.\n    Say why something is of interest, and write so that it is indeed interesting.\n";
			}
			if( !$isref && !$twook && $lctwoline =~ /in terms of / ) {
				print "tip: you probably should replace 'in terms of' with 'using' or 'by' or 'and' on line $. in $input, or rewrite.\n    It's a wordy phrase.\n";
				print "    If you think it's OK, put on the end of the line the comment '% chex_latex'\n";
			}
			if( !$isref && $twoline  =~ / etc\. / ) {
				print "hint: try to avoid using etc., as it adds no real information; on line $. in $input.\n";
			}
			if( !$isref && !$twook && $lctwoline  =~ /data is/ ) {
				print "possible tip: 'data' should be plural, not singular, on line $. in $input. Reword?\n    Sometimes it is fine, e.g., 'the analysis of the data is taking a long time.' since analysis is singular.\n";
				print "    If you think it's OK, put on the end of the line the comment '% chex_latex'\n";
			}
			# see http://www.quickanddirtytips.com/education/grammar/use-versus-utilize?page=1
			if( !$isref && $lctheline  =~ /utiliz/ && !($lctheline  =~ /utilization/) && !$ok && !$inquote && !$isfront ) {
				print "Change the 'utiliz-' form to 'use' or similar, on line $. in $input.\n    'Utiliz-' sounds big and looks impressive but isn't needed - keep it simple.\n";
				print "    If you think it's truly OK (use it maybe once a chapter), put on the end of the line the comment '% chex_latex'\n";
			}

			# -----------------------------------------------------
			# Words and phrases - definitely personal preferences, but based on common practice
			if( !$isref && $lctheline  =~ /performant/ ) {
				print "'performant' not fully accepted as a word, so change to 'efficient' or 'powerful' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /six dimensional/ ) {
				print "'six dimensional' to 'six-dimensional' on line $. in $input.\n";
			}
			if( $theline  =~ /fps/ ) {
				print "'fps' to 'FPS' on line $. in $input.\n";
			}
			if( $theline  =~ /LoD/ ) {
				print "'LoD' to 'LOD' on line $. in $input.\n";
			}
			if( ($lctheline  =~ /parameterisation/) ) {
				print "The British spelling 'parameterisation' should change to 'parameterization' on line $. in $input. MAGA.\n";
			}
			if( ($lctwoline  =~ /blackbody/) ) {
				print "'blackbody' should change to 'black-body' on line $. in $input.\n";
			}
			if( ($theline  =~ /black body/) ) {
				print "'black body' should change to 'black-body' on line $. in $input.\n";
			}
			if( ($lctwoline  =~ /spot light/) ) {
				print "'spot light' should change to 'spotlight' on line $. in $input.\n";
			}
			if( ($theline  =~ /spot-light/) ) {
				print "'spot-light' should change to 'spotlight' on line $. in $input.\n";
			}
			if( $lctheline  =~ /frame buffer/ && !$isref ) {
				print "'frame buffer' to 'framebuffer' on line $. in $input.\n";
			}
			# yes, this is inconsistent with the above; chosen by Google search populariy
			if( $lctheline  =~ /framerate/ && !$isref ) {
				print "'framerate' to 'frame rate' on line $. in $input.\n";
			}
			if( $lctheline  =~ /pre-filter/ && !$isref ) {
				print "'pre-filter' to 'prefilter' on line $. in $input.\n";
			}
			if( $lctheline  =~ /pre-process/ && !$isref ) {
				print "'pre-process' to 'preprocess' on line $. in $input.\n";
			}
			# https://www.grammarly.com/blog/modeling-or-modelling/
			if( $lctheline  =~ /modelling/ && !$isref ) {
				print "In the U.S., we prefer 'modelling' to 'modeling' on line $. in $input.\n";
			}
			if( $lctheline  =~ /bandlimit/ && !$isref ) {
				print "'bandlimit' to 'band-limit' on line $. in $input.\n";
			}
			if( $lctheline  =~ / raycast/ && !$isref ) {
				print "'raycast' to 'ray cast' on line $. in $input.\n";
			}
			if( $lctheline  =~ / raytrace/ && !$isref ) {
				print "'raytrace' to 'ray trace' on line $. in $input.\n";
			}
			if( $lctheline  =~ / raytracing/ && !$isref ) {
				print "'raytracing' to 'ray tracing' on line $. in $input.\n";
			}
			if( $lctwoline  =~ / lob / ) {
				print "'lob' to 'lobe' on line $. in $input.\n";
			}
			if( $lctheline  =~ /frustums/ && !$isref ) {
				print "'frustums' to 'frusta' on line $. in $input.\n";
			}
			if( $twoline  =~ / 6D/ ) {
				print "'6D' to 'six-dimensional' on line $. in $input.\n";
			}
			#if( $twoline  =~ /similarly to / ) {
			#	print "'similarly to' probably wants to be 'similar to' on line $; better yet, reword, as #it's generally awkward. in $input.\n";
			#}
			if( $lctwoline =~ /five dimensional/ ) {
				print "'five dimensional' to 'five-dimensional' on line $. in $input.\n";
			}
			if( $twoline  =~ / 5D/ ) {
				print "'5D' to 'five-dimensional' on line $. in $input.\n";
			}
			#if( $lctwoline =~ /four dimensional/ ) {
			#	print "'four dimensional' to 'four-dimensional' on line $. in $input.\n";
			#}
			if( $twoline  =~ / 4D/
				&& !($twoline=~/Entrim/) ) {
				print "'4D' to 'four-dimensional' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /Ph.D./) {
				print "'Ph.D.' to 'PhD' on line $. in $input.\n";
			}
			if( $twoline  =~ / id / && !($twoline  =~ / id Software/)) {
				print "Please change 'id' to 'ID' on line $. in $input.\n";
			}
			if( $twoline  =~ / id~/) {
				print "Please change 'id' to 'ID' on line $. in $input.\n";
			}
			if( $twoline  =~ / ids /) {
				print "Please change 'ids' to 'IDs' on line $. in $input.\n";
			}
			if( $twoline  =~ / ids~/) {
				print "Please change 'ids' to 'IDs' on line $. in $input.\n";
			}
			if( $lctheline  =~ /middle-ware/) {
				print "Please change 'middle-ware' to 'middleware' on line $. in $input.\n";
			}
			# good manual test
			#if( $lctwoline =~ /three dimensional/ && !($input =~ /refs.tex/) ) {
			#	print "'three dimensional' to 'three-dimensional' on line $. in $input.\n";
			#}
			if( !$isref && $twoline  =~ / 3D /
					&& !($twoline=~/Interactive 3D/)
					&& !($twoline=~/Stanford 3D/)
					&& !($twoline=~/3D print/)
					&& !($twoline=~/projection!3D triangle to 2D/)
					&& !($twoline=~/3D Game Engine/)
					&& !($twoline=~/3D Graphics/)
					&& !($twoline=~/Source 3D data/)
					&& !($twoline=~/3D Game Programming/)
				) {
				print "'3D' to 'three-dimensional' on line $. in $input.\n";
			}
			#if( $lctwoline =~ /two dimensional/ ) {
			#	print "'two dimensional' to 'two-dimensional' on line $. in $input.\n";
			#}
			if( !$isref && $twoline  =~ / 2D /
					&& !($twoline=~/projection!3D triangle to 2D/)
				) {
				print "'2D' to 'two-dimensional' on line $. in $input.\n";
			}
			if( !$isref && $twoline  =~ / 1D/ ) {
				print "'1D' to 'one-dimensional' on line $. in $input.\n";
			}
			if( !$isref && $twoline  =~ /^So / && !($twoline  =~ /^So far/)) { # https://english.stackexchange.com/questions/30436/when-do-we-need-to-put-a-comma-after-so
				print "'So' should be 'So,' or combine with previous sentence, on line $. in $input.\n";
			}
			#if( $twoline  =~ /^Also / ) { # https://english.stackexchange.com/questions/30436/when-do-we-need-to-put-a-comma-after-so
			#	print "'So' should be 'So,' or combine with previous sentence, on line $. in $input.\n";
			#}
			#if( $twoline  =~ / Also / ) {
			#	print "'So' should be 'So,' or combine with previous sentence, on line $. in $input.\n";
			#}
			# If you must use "start point", also then use "end point" when talking about the other end. If it's just "end point" by itself, "endpoint" is fine. Searching around, colldet.tex is the only chapter using "start point" by itself. isect.tex uses "start and end points". Normally we say things like "both endpoints," "the endpoints match," etc.
			if( $lctwoline =~ /startpoint/ ) {
				print "'startpoint' to 'start point' on line $. in $input.\n";
			}
			#if( $lctwoline =~ /end point/ ) {
			#	print "'end point' to 'endpoint' on line $. in $input.\n";
			#}
			if( $lctheline =~ /back-fac/ && !($input =~ /book.tex/)) {
				print "'back-face' to 'backface' on line $. in $input.\n";
			}
			if( $lctwoline =~ /back fac/ && (!($twoline  =~ /front and back fac/) && !($twoline  =~ /front or back fac/) && !($twoline  =~ /front and the back fac/)) ) {
				print "'back face' to 'backface' on line $. in $input.\n";
			}
			if( $lctheline =~ /front-fac/ && !($input =~ /book.tex/)) {
				print "'front-face' to 'frontface' on line $. in $input.\n";
			}
			if( $lctwoline =~ /front-fac/ && !($input =~ /book.tex/)) {
				print "'front-face' to 'frontface' on line $. in $input.\n";
			}
			if( $lctheline =~ /wire-fram/ && !($input =~ /book.tex/)) {
				print "'wire-frame' to 'wireframe' on line $. in $input.\n";
			}
			if( $lctwoline =~ /wire frame/ && !($input =~ /book.tex/)) {
				print "'wire frame' to 'wireframe' on line $. in $input.\n";
			}
			if( !$isref && $lctwoline =~ /sub-pixel/ ) {
				print "'sub-pixel' to 'subpixel' on line $. in $input.\n";
			}
			# Good, but need to be done manually:
			#if( $twoline =~ /On the left / && $infigure ) {
			#	print "'On the left ' to 'On the left, ' on line $. in $input.\n";
			#}
			#if( $twoline =~ /On the right / && $infigure ) {
			#	print "'On the right ' to 'On the right, ' on line $. in $input.\n";
			#}
			if( $lctheline  =~ /counter-clockwise/ && !($input =~ /book.tex/) ) {
				print "'counter-clockwise' to 'counterclockwise' on line $. in $input.\n";
			}
			if( $lctwoline =~ /anti-alias/ && !($input =~ /book.tex/) && !($input =~ /refs.tex/)  ) {
				print "'anti-alias' to 'antialias' on line $. in $input.\n";
			}
			if( $lctheline =~ /modelled/ && !($input =~ /book.tex/) ) {
				print "'modelled' to 'modeled' on line $. in $input.\n";
			}
			if( $lctheline =~ /tessela/ && !($input =~ /refs.tex/) && !($input =~ /book.tex/) ) {
				print "'tessela' to 'tessella' on line $. in $input.\n";
			}
			# good manual test:
			#if( $lctwoline  =~ /on-the-fly/ ) {
			#	print "'on-the-fly' to 'on the fly' on line $. in $input.\n";
			#}
			if( $lctwoline  =~ /greyscale/ ) {
				print "'greyscale' to 'grayscale' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /speed-up/ ) {
				print "'speed-up' to 'speedup' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /semi-transparen/ ) {
				print "'semi-transparen' to 'semitransparen' on line $. in $input.\n";
			}
			if( $twoline  =~ /In this way / ) {
				print "'In this way ' to 'In this way,' on line $. in $input.\n";
			}
			if( $twoline  =~ /For example / ) {
				print "'For example ' to 'For example,' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /off-screen/ ) {
				print "'off-screen' to 'offscreen' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /view point/ ) {
				print "'view point' to 'viewpoint' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /gray scale/ ) {
				print "'gray scale' to 'grayscale' on line $. in $input.\n";
			}
			if( !$isref && $lctwoline  =~ /post process/ ) {
				print "'post process' to 'post-process' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /postprocess/ ) {
				print "'postprocess' to 'post-process' on line $. in $input.\n";
			}
			if( !$isref && $lctwoline  =~ /half space/ ) {
				print "'half space' to 'half-space' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /halfspace/ ) {
				print "'halfspace' to 'half-space' on line $. in $input.\n";
			}
			#if( !($input =~ /refs.tex/) && !$intable && !$inequation && !($twoline  =~ /type id : /) && $twoline  =~ /: [a-z]/ ) {
			#	print "colon problem '$&' on line $. in $input.\n";
			#}
			if( !$isref && $lctheline  =~ /pre-comput/ ) {
				print "'pre-comput*' to 'pre-comput*' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && $lctheline =~ /mip-map/ ) {
				print "'mip-map' to 'mipmap' (no hyphen), on line $. in $input.\n";
			}
			if( !$ok && !$isref && ($lctheline =~ / (cubemap)/ || ($style && $lctheline =~ /(cube-map)/)) ) {
				print "change '$1' to 'cube map' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$ok && !$isref && ($lctheline =~ / (lightmap)/ || ($style && $lctheline =~ /(light-map)/)) ) {
				print "change '$1' to 'light map' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$ok && !$isref && ($lctheline =~ / (screenspace)/ || ($style && $lctheline =~ /(screen-space)/)) ) {
				print "change '$1' to 'screen space' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$ok && !$isref && ($lctheline =~ / (raytrac)/ || ($style && $lctheline =~ /(ray-trac)/)) ) {
				print "change '$1' to 'ray trac*' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$ok && !$isref && ($lctheline =~ / (pathtrac)/ || ($style && $lctheline =~ /(path-trac)/)) ) {
				print "change '$1' to 'path trac*' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$ok && !$isref && $lctheline =~ / (sub-surface)/ ) {
				print "change '$1' to 'subsurface' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$ok && !$isref && $lctheline =~ / (preintegrate)/ ) {
				print "change '$1' to 'pre-integrate' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$ok && !$isref && $lctheline =~ / (pre-calculate)/ ) { # slight google preference for this, but we'll go precalculate
				print "change '$1' to 'precalculate' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$ok && !$isref && $lctheline =~ / (pre-compute)/ ) {
				print "change '$1' to 'precompute' on line $. in $input, or add '% chex_latex' to line.\n";
			}
			if( !$isref && $lctheline  =~ /grey/ ) { # http://www.dictionary.com/e/gray-or-grey/
				print "change 'grey' to 'gray' on line $. in $input. MAGA!\n";
			}
			if( !$isref && $lctheline  =~ /non-linear/ ) {
				print "change 'non-linear' to 'nonlinear' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /haloes/ ) {
				print "change 'haloes' to 'halos' on line $. in $input. MAGA!\n";
			}
			if( !$ok && !$isref && $lctheline  =~ /zeroes/ ) {
				print "change 'zeroes' to 'zeros' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /un-blur/ ) {
				print "change 'un-blur' to 'unblur' (no hyphen), on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /off-line/ ) {
				print "change 'off-line' to 'offline' (no hyphen), on line $. in $input.\n";
			}
			if( !$isref && $theline  =~ /XBox/ || $theline  =~ /XBOX/ ) {
				print "change 'XBox' to 'Xbox' on line $. in $input.\n";
			}
			if( !$isref && $theline  =~ /Renderman/ ) {
				print "change 'Renderman' to 'RenderMan' on line $. in $input.\n";
			}
			if ( $theline =~ /Game Developer Conference/ && ($input =~ /refs.tex/) ) {
				print "change 'Game Developer Conference' to 'Game Developers Conference' on line $. in $input.\n";
			}
			if( $theline  =~ /Direct3D/ && !($input =~ /refs.tex/) && !($input =~ /rendpipe.tex/) ) {
				print "'Direct3D' to 'DirectX' on line $. in $input.\n";
			}
			if( !($theline  =~ /PLAYSTATION/) && ($theline  =~ /Playstation/ || $theline  =~ /PlayStation/) && !$isref ) {
				print "'Playstation' to 'PLAYSTATION' on line $. in $input.\n";
			}
			if( $theline  =~ /nvidia/  && !($theline =~ "bibitem" || $theline =~ "cite") ) {
				print "'Nvidia' to 'NVIDIA' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /parametriz/ && !($input =~ /book.tex/) ) {
				print "'parametrization' to 'parameterization' on line $. in $input.\n";
			}
			if( $lctheline  =~ /tradeoff/ && !($input =~ /refs.tex/) ) {
				print "'tradeoff' to 'trade-off' on line $. in $input.\n";
			}
			if( $lctheline  =~ /absorbtion/ ) {
				print "'absorbtion' to 'absorption' on line $. in $input.\n";
			}
			if( !$twook && $twoline  =~ / gauss/ ) {
				print "'gauss' to 'Gauss' on line $. in $input.\n";
			}
			if( !$twook && $lctwoline  =~ / gbuffer/ ) {
				print "'gbuffer' to 'G-buffer' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /ad-hoc/ ) {
				print "'ad-hoc' to 'ad hoc' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /lowpass/ ) {
				print "'lowpass' to 'low-pass' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /highpass/ ) {
				print "'highpass' to 'high-pass' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /nonboundary/ ) {
				print "'nonboundary' to 'non-boundary' on line $. in $input.\n";
			}
			if( !$isref && !($twoline  =~ /\\subsection/) && $twoline  =~ /n-Patch/ ) {
				print "'N-Patch' to 'N-patch' on line $. in $input.\n";
			}
			if( $lctwoline  =~ /fill-rate/ ) {
				print "'fill-rate' to 'fill rate' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /bigger/ ) {
				print "'bigger' to 'larger' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /biggest/ ) {
				print "'biggest' to 'greatest' or similar, on line $. in $input.\n";
			}
			if( !$isref && $lctwoline  =~ /self intersect/ ) {
				print "'self intersect' to 'self-intersect', as it's a common term, on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /bidimensional/ ) {
				print "'bidimensional' to 'two-dimensional', mr. fancy pants, on line $. in $input.\n";
			}
			if( $lctheline  =~ /fillrate/ ) {
				print "'fillrate' to 'fill rate' on line $. in $input.\n";
			}
			# more popular on Google
			if( !$isref && $lctwoline  =~ /run time/ ) {
				print "'run time' to 'runtime', for consistency, on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /videogame/ ) {
				print "'videogame' to 'video game' on line $. in $input.\n";
			}
			if( !$isref && $lctheline  =~ /videocamera/ ) {
				print "'videocamera' to 'video camera' on line $. in $input.\n";
			}
			if( !$isref && $lctwoline  =~ /pseudo code/ ) {
				print "SERIOUS: change 'pseudo code' to 'pseudocode' on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /January/ ) {
				print "change January to Jan. in line $. in $input.\n";
			}
			if( $isref && $theline  =~ /February/ ) {
				print "change February to Feb. in line $. in $input.\n";
			}
			if( $isref && $theline  =~ /September/ ) {
				print "change September to Sept. in line $. in $input.\n";
			}
			if( $isref && $theline  =~ /October/ ) {
				print "change October to Oct. in line $. in $input.\n";
			}
			if( $isref && $theline  =~ /November/ ) {
				print "change November to Nov. in line $. in $input.\n";
			}
			if( $isref && $theline  =~ /December/ ) {
				print "change December to Dec. in line $. in $input.\n";
			}
			if( $isref && $theline  =~ /Jan\.,/ ) {
				print "No comma needed after Jan. on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /Feb\.,/ ) {
				print "No comma needed after Feb. on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /March,/ ) {
				print "No comma needed after March on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /April,/ ) {
				print "No comma needed after April on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /May,/ ) {
				print "No comma needed after May on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /June,/ ) {
				print "No comma needed after June on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /July,/ ) {
				print "No comma needed after July on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /August,/ ) {
				print "No comma needed after August on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /Sept\.,/ ) {
				print "No comma needed after Sept. on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /Oct\.,/ ) {
				print "No comma needed after Oct. on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /Nov\.,/ ) {
				print "No comma needed after Nov. on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /Dec\.,/ ) {
				print "No comma needed after Dec. on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /course notes/ ) {
				print "Change 'course notes' to 'course' on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /JCGT/ ) {
				print "SERIOUS: do not use JCGT abbreviation in reference on line $. in $input.\n";
			}
			if( $isref && $theline  =~ /JGT/ ) {
				print "SERIOUS: do not use JGT abbreviation in reference on line $. in $input.\n";
			}
			# slight Google preference, and https://en.wikipedia.org/wiki/Lookup_table
			if( !$isref && !$ok && $lctheline =~ /look-up/ ) {
				print "Change 'look-up table' to 'lookup table' or similar on line $. in $input.\n";
			}
			if( !$isref && $lctheline =~ /[\s]disc[\s\.,:;?]/ ) {
				print "Change 'disc' to 'disk' on line $. in $input.\n";
			}
			if( !$isref && $lctheline =~ /exemplif/ ) {
				print "Change 'exemplify' to 'give an example' or 'show' on line $. in $input.\n";
			}
			if( !$isref && $lctheline =~ /[\s]discs[\s\.,:;?]/ ) {
				print "Change 'discs' to 'disks' on line $. in $input.\n";
			}

			# nice for a final check TODO END, but kind of crazed
			if ( $superstyle ) {
				# TODO this first one is good to check throughout TODO EAH
				# done:
				#if( $lctwoline  =~ / lets/ ) {	# don't check for in refs.tex
				#	print "lets - maybe you mean 'let's' which should go to 'let us' or reword, on line $. in $input.\n";
				#}
				if( !$isref && $lctwoline  =~ /a number of/ && !$twook ) {
					print "shortening tip: replace 'a number of' with 'several' (or possibly even remove), on line $. in $input.\n";
					print "    If you think it's truly OK, put on the end of the line the comment '% chex_latex'\n";
				}
				if( !$isref && $lctwoline  =~ /in particular/ ) {
					print "shortening tip: perhaps remove 'in particular' on line $. in $input.\n";
					print "    If you think it's truly OK, put on the end of the line the comment '% chex_latex'\n";
				}
				if( !$isref && $lctwoline  =~ /similar to/ ) {
					print "shortening tip: perhaps replace 'similar to' with 'like' on line $. in $input.\n";
					print "    If you think it's truly OK, put on the end of the line the comment '% chex_latex'\n";
				}
				if( !$isref && $lctwoline  =~ /in order to/ ) {
					print "shortening tip: perhaps replace 'in order to' with 'to' on line $. in $input.\n";
					print "    If you think it's truly OK, put on the end of the line the comment '% chex_latex'\n";
				}
				if( !$isref && $lctwoline  =~ / all of the/ && !($lctwoline  =~ /or all of the/) ) {
					print "shortening tip: replace 'all of' with 'all' on line $. in $input.\n";
					print "    If you think it's truly OK, put on the end of the line the comment '% chex_latex'\n";
				}
				if( !$isref && $lctwoline  =~ /the majority of/ ) {
					print "shortening tip: replace 'the majority of' with 'most' on line $. in $input.\n";
					print "    If you think it's truly OK, put on the end of the line the comment '% chex_latex'\n";
				}
				if( !$isref && $lctwoline =~ / quite/ ) {
					print "The word 'quite' is a cheat for 'very' - can we avoid it? Line $. in $input.\n";
				}
				if( $lctwoline =~ /kind of/ && !$twook ) {
					print "If you don't mean 'type of', for formal writing, change 'kind of' to 'somewhat, rather, or slightly' on line $. in $input.\n";
					print "    If you think it's OK, put on the end of the line the comment '% chex_latex'\n";
				}
				# finds some problems, but plenty of false positives:
				if( $isref && $theline  =~ /\w''/ ) {
					print "ERROR: reference title does not have comma before closed quotes, on line $. in $input.\n";
				}
			}
		}
		# ones people do:
		# Don't write "He only kicked that ball ten yards" when you mean "He kicked that ball only ten yards." 

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
			$theline =~ /end\{IEEEeqnarray/ || 
			$theline =~ /end\{align/ || 
			$theline =~ /end\{lstlisting}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{figure}/ ) {
			$infigure = 0;
		}
		if ( $theline =~ /end\{gather}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{tabbing}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{tabular}/ ) {
			$inequation = 0;
			#print "tabular end line $.\n";
		}
		if ( $theline =~ /end\{align}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{verbatim}/ ) {
			$inequation = 0;
		}
		if ( $theline =~ /end\{quote\}/ ) {
			$inquote = 0;
		}
		if ( $theline =~ /end\{tabular/ ) {
			$intable = 0;
		}
		
		$twook = $ok;

		} else {
			# the end-if for whether there is anything on the line
			if ( $newpara ) {
				$prev_line = '';
			}
		}
	}

	close DATAFILE;

	foreach $elem ( sort keys %indexlong ) {
		print "ERROR: index entry started, not ended: {$elem|( in $input.\n";
	}
	undef %indexlong;
}


sub CONNECTOR_WORD
{
	my $testword = shift;
	my $loc = shift;
	if ( $testword eq "and" ||
		$testword eq "versus" ||
		$testword eq "from" ||
		$testword eq "between" ||
		$testword eq "a" ||
		$testword eq "by" ||
		$testword eq "on" ||
		$testword eq "in" ||
		$testword eq "as" ||
		$testword eq "about" ||
		$testword eq "an" ||
		$testword eq "to" ||
		$testword eq "for" ||
		$testword eq "of" ||
		$testword eq "with" ||
		$testword eq "the" ) {
		if ( $dump ) {
			print "returning 1 for $testword\n";
		}
		return 1;
	}
	# capitalized and shouldn't be?
	if ( $loc != 0 &&
		($testword eq "And" ||
		$testword eq "Versus" ||
		$testword eq "From" ||
		$testword eq "Between" ||
		$testword eq "A" ||
		$testword eq "By" ||
		$testword eq "On" ||
		$testword eq "As" ||
		$testword eq "About" ||
		$testword eq "An" ||
		$testword eq "To" ||
		$testword eq "For" ||
		$testword eq "Of" ||
		$testword eq "With" ||
		$testword eq "The" )) {
		if ( $dump ) {
			print "returning 2 for $testword\n";
		}
		return 2;
	}
		if ( $dump ) {
			print "returning 0 for $testword\n";
		}
	return 0;
}

sub CAPITALIZED
{
	my $testword = shift;
	my $fc = substr( $testword, 0, 1 );
	if ( $fc =~ /[A-Z]/ ) {
		return 1;
	}
	return 0;
}

