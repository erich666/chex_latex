# chex_latex
LaTeX file checking tool.

This Perl script reads your .tex files and looks for potential problems, such as doubled words ("the the") and a lot of other problems. LaTeX-specific features include:
* Look for potential [inter-word vs. inter-sentence spacing problems](https://en.wikibooks.org/wiki/LaTeX/Text_Formatting#Space_between_words_and_sentences), if you care.
* Look for \label and \ref markers, and note any figure \label's that do not have any \ref's, and vice versa.
* Look for \bibitem and \cite markers, note any \bibitems's that do not have any \cite's, and vice versa.
* Look for \index markers that get opened but not closed, or vice versa.
* Look for common grammatical goofs or clunky phrasing.

This script is in no way foolproof, and will natter about all sorts of things you may not care about. Since it's a Perl script, it's easy for you to edit and delete or modify any tests that you don't like.

# Installation and Use

Install Perl from say https://www.activestate.com/activeperl, put chex_latex.pl somewhere (easiest is to put it in the directory with your .tex files, else you need to specify the path to this file), go to the directory where your .tex files are and then:

    perl chex_latex.pl
  
and all .tex files in your directory and subdirectories will be read and checked for this and that. For a single file:

    perl chex_latex.pl yourfile.tex
	
For a different directory, called say ''work_files\my-thesis-master'':

    perl chex_latex.pl yourfile.tex work_files\my-thesis-master

This script is one used for the book ''Real-Time Rendering'' and so has a bunch of book-specific rules. Blithely ignore our opinions or, better yet, comment out the warning lines you don't like in the script. You can also add "% chex_latex" to the end of any line in your .tex file in order to have this script skip some error tests on it, e.g.:

    This method of using data is reasonable. % don't flag "data is" - chex_latex

The "chex_latex" says the line is OK and won't be tested. Beware, though: if you make any other errors on this line in the future, they also won't be tested.

The options are:

	-d - turn off dash tests for '-' or '--' flagged as needing to be '...'.
	-i - turn off formal writing check; allows contractions and other informal usage.
	-p - turn ON picky style check, which looks for more style problems but is not so reliable.
	-s - turn ON style check; looks for poor usage, punctuation, and consistency.
	-t - turn off capitalization check for section titles.
	-u - turn off U.S. style tests for putting commas and periods inside quotes.
	
So if you want all the tests, do:

	perl chex_latex.pl -ps [directory or files]
	
If you want the bare minimum, do:

    perl chex_latex.pl -ditu [directory or files]
	
Two other more obscure options:

    -O okword
	
Instead of adding a comment "% chex_latex" to lines you want the script to ignore, you could change the keyword to something else, e.g. "-O ignore_lint" would ignore all lines where you put "% ignore_lint" in a comment.

    -R refs.tex
	
By default, the file "refs.tex" is the one that contains \bibitem entries. Our book uses these, just about no one else does. If you actually do use \bibitem, this one is worth setting to your references file. It will tell you whether you reference something that doesn't exist in the references file, and whether any references in the file are not used in the text.