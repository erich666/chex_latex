# chex_latex
LaTeX file checking tool. Install Perl from say https://www.activestate.com/activeperl, put chex_latex.pl somewhere, go to the directory where your .tex files are and then:

  perl chex_latex.pl
  
and all .tex files in your directory and subdirectories will be read and checked for this and that.

This script is one used for the book ''Real-Time Rendering'' and so has a bunch of book-specific rules. I hope to make it more general and customizable in the future. For now, blithely ignore our opinions or, better yet, just comment out or delete the lines you don't like in the script. You can also add "% chex_latex" to the end of any line in your file in order to have this script skip some error tests on it, i.e., you can say a line is OK and should not be tested.
