# chex_latex
LaTeX file checking tool.

This Perl script reads your .tex files and looks for potential problems, such as doubled words ("the the") and a lot of other problems. LaTeX-specific features include:
* Look for potential [inter-word vs. inter-sentence spacing problems](https://en.wikibooks.org/wiki/LaTeX/Text_Formatting#Space_between_words_and_sentences), if you care.
* Look for \label and \ref markers, and note any figure \label's that do not have any \ref's, and vice versa.
* Look for \bibitem and \cite markers, note any \bibitems's that do not have any \cite's, and vice versa.
* Look for \index markers that get opened but not closed, or vice versa.

This script is in no way foolproof, and will natter about all sorts of things you may not care about. Since it's a Perl script, it's easy for you to edit and delete or modify any tests that you don't like. Or, just look at the "SERIOUS:" lines and see if anything important turns up.

# Installation and Use

Install Perl from say https://www.activestate.com/activeperl, put chex_latex.pl somewhere (easiest is to put it in the directory with your .tex files, else you need to specify the path to this file), go to the directory where your .tex files are and then:

    perl chex_latex.pl
  
and all .tex files in your directory and subdirectories will be read and checked for this and that. For a single file:

    perl chex_latex.pl yourfile.tex

This script is one used for the book ''Real-Time Rendering'' and so has a bunch of book-specific rules. I hope to make it more general and customizable in the future. For now, blithely ignore our opinions or, better yet, just comment out or delete the lines you don't like in the script. You can also add "% chex_latex" to the end of any line in your .tex file in order to have this script skip some error tests on it, e.g.:

    This method of using data is reasonable. % don't flag "data is" - chex_latex

The "chex_latex" says the line is OK and won't be tested. Of course, if you make any other errors on this line in the future, they also won't be tested. I should add a "force testing" flag... (and so begins the endless addition of flags.)
