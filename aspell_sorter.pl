# Read in list of misspelled words from aspell,
# See https://github.com/erich666/chex_latex for details.

# Win32 setup here: https://notepad-plus-plus.org/community/topic/8206/method-to-install-gnu-aspell-win32-dictionaries-and-spell-check-plugin-on-n
#
# I run by:
#
# C:\temp\booktex02022018> c:\cygwin64\bin\cat.exe *.tex > alltext.txt
#     C:\Program Files (x86)\Aspell>bin\aspell list -t < C:\temp\booktex02022018\alltext.txt > C:\temp\booktex02022018\alltypos.txt
#
# C:\Program Files (x86)\Aspell>bin\aspell list -t < C:\temp\booktex02022018\alltext.txt > C:\temp\booktex02022018\alltypos.txt
#
# C:\Users\erich\Documents\_Documents\_book\RTRbook4\tools>perl check_spelling.pl C:\temp\booktex02022018\alltypos.txt > spell_check.txt
#
# The perl part is in that last list:
#
#     check_spelling.pl alltypos.txt > spell_check.txt
#
# which simply sorts the words in the alltypos.txt file, which has a misspelled word per line. The file produced is all uppercase (easy to get rid of authors that way), then all lowercase.

while (@ARGV) {
	# check 
	$arg = shift(@ARGV) ;
	&READ($arg) ;
}

foreach $elem ( sort alphabetical ( keys %words ) ) {
	print "$elem\t\t\t\tcount is $words{$elem}\n";
}


exit ;

sub READ {
	local($fname) = @_[0] ;

	die "can't open $fname: $!\n"
		unless open(INFILE,$fname) ;

	while (<INFILE>) {
		chop;       # strip record separator
		$words{$_}++;
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
