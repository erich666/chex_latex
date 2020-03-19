# Read in list of misspelled words from aspell,
# See https://github.com/erich666/chex_latex for details.

# Win32 setup for aspell here: https://notepad-plus-plus.org/community/topic/8206/method-to-install-gnu-aspell-win32-dictionaries-and-spell-check-plugin-on-n
#
# I run by putting all my *.tex files in some temporary directory, e.g., C:\temp\booktex02022018. In that directory I then:
#
# C:\temp\booktex02022018> c:\cygwin64\bin\cat.exe *.tex > alltext.txt
#
# "C:\Program Files (x86)\Aspell\bin\aspell" list -t < C:\temp\booktex02022018\alltext.txt > C:\temp\booktex02022018\alltypos.txt
#
# perl C:\Users\ehaines\Documents\_documents\Github\chex_latex\aspell_sorter.pl alltypos.txt > spell_sort.txt
#
# The perl part is in that last list:
#
#     check_spelling.pl alltypos.txt > spell_check.txt
#
# which simply sorts the words in the alltypos.txt file, which has a misspelled word per line. The file produced is all uppercase (easy to get rid of authors that way), then all lowercase.

# to print out only those words "misspelled" once, set $spellcount to 1; once or twice, set to 2, etc.
my $spellcount = 0;

# change this to whatever you want the minimum word length to be tested. Making this longer can help skip over two-letter variables, for example, e.g., "dx".
my $wordlength = 0;

while (@ARGV) {
	# check 
	$arg = shift(@ARGV) ;
	&READ($arg) ;
}

foreach $elem ( sort alphabetical ( keys %words ) ) {
	if ( $spellcount == 0 || $spellcount >= $words{$elem} ) {
		print "$elem\t\t\t\tcount is $words{$elem}\n";
	}
}


exit ;

sub READ {
	local($fname) = @_[0] ;

	die "can't open $fname: $!\n"
		unless open(INFILE,$fname) ;

	while (<INFILE>) {
		chop;       # strip record separator
		# clean out words with â in them - a flaw with aspell
		# this is an apostrophe character, e.g, donâ is the "don" in don't
		# That said, this test is a bit flaky, it doesn't catch them all, I don't know why.
		if ( !/â/) {
			# if a word is camel case, separate it into its constituent words
			my $str = $_;
			my $camelFound = 0;
			while (length($str)>$wordlength) {
				# throw away whatever is before the last capital letter in the camel case word (if there is one)
				if ($str =~ /[A-Z]*([A-Z][a-z]+)/) {
					# logic here's not quite right, but close enough...
					if ( length($1) > $wordlength ) {
						if ( length($') == 0 ) {
							# if just a single capitalized word is found, save it without any prefix
							$words{(($camelFound>1) ? '+ ' : '') . $1}++;
						} else {
							$words{(($camelFound>1) ? '+ ' : '* ') . $1}++;
						}
					}
					$str = $';
					$camelFound++;
				} else {
					#end loop
					$str = '';
				}
			}
			if (!$camelFound && (length($_) > $wordlength)) {
				$words{$_}++;
			}
		}
	}
}

# foreach $elem ( sort by_value keys %freq )
sub by_value { $chars{$b} <=> $chars{$a} ; }

# foreach $mm ( sort numerically (keys %medianit) ) {
sub numerically { $a <=> $b ; }

sub lcalphabetical {
    # compares lower-cased versions of the strings
    lc($a) cmp lc($b);
}

sub alphabetical {
    # compares lower-cased versions of the strings
    $a cmp $b;
}
