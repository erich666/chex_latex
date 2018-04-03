# chex_latex
LaTeX file checking tool.

This Perl script reads your .tex files and looks for potential problems, such as doubled words ("the the") and a lot of other problems. Put it in your directory of .tex files and run it to look for common problems.

As an example, here is a snippet of a .tex file; look it over for problems yourself:

	\section{Algorithms that Use Hardware}
	Here we'll discuss the very many algorithms that can be implemented on the GPU. For more information, Castelli
	\cite{Castelli2018} gives a thorough overview of the use of mip-maps for level of detail, compute shaders for
	frustrum culling, etc. and discusses which APIs support these techniques. Basically, you can use anything from
	DirectX 12\index{DirectX 12} with C++ to WebGL\index{WebGL} with Javascript\index{Javascript} as your API/index{API} ,
	due to that these all talk to the same underlying hardware. More specifically, there is literally no better way to
	to accelerate processing data, vs. using just the CPU--so ''just do it''.

Here's what chex_latex.pl finds in a fraction of a second:

	file is testfile.tex
	POSSIBLY SERIOUS: Section title has a word 'that' uncapitalized, on line 1 in ./testfile.tex.
		Ignore if this word 'that' is a 'connector word' such as 'in' or 'and' -
		you can test your title at https://capitalizemytitle.com/
		Also, feel free to go into the code and comment out this test!
	Sentence ending in the capital letters GPU should have a '\@.' for spacing, on line 2 in ./testfile.tex.
	SERIOUS: no contractions: ''ll' to ' will' on line 2 in ./testfile.tex.
	POSSIBLY SERIOUS: you may need to change 'etc.' to 'etc\.' to avoid having a 'double-space'
		appear after the period, on line 4 in ./testfile.tex.
		(To be honest, it's better to avoid 'etc.' altogether, as it provides little to no information.)
	MISSPELLING: 'frustrum' to 'frustum' on line 4 in ./testfile.tex.
	tip: you can probably remove 'basically' on line 4 in ./testfile.tex.
	SERIOUS: '/index' should be \index, on line 5 in ./testfile.tex.
	SERIOUS: change ' ,' to ',' (space in front of comma), on line 5 in ./testfile.tex.
	Please change 'Javascript' to 'JavaScript' on line 5 in ./testfile.tex.
	SERIOUS: change ' ,' to ',' (space in front of comma), on line 6 in ./testfile.tex.
	tip: 'due to that' to 'because' on line 6 in ./testfile.tex.
	tip: 'more specifically' to 'specifically' on line 6 in ./testfile.tex.
	tip: you can probably not use 'literally' (and may mean 'figuratively'), on line 6 in ./testfile.tex.
		If you think it's OK, put on the end of the line the comment '% chex_latex'
	SERIOUS: word duplication problem of word 'to' on line 7 in ./testfile.tex.
	SERIOUS: change '--' (short dash) to '---' on line 7 in ./testfile.tex.
	SERIOUS: change 'vs.' to 'versus' to avoid having a 'double-space' appear after the period,
		or use 'vs\.' on line 7 in ./testfile.tex.
	Not capitalized at start of sentence (or the period should have a \ before it), on line 7 in ./testfile.tex.
	==========================================================================================================

You might disagree with some of the problems flagged, but with chex_latex.pl you are at least aware of them. A few minutes wading through them can catch errors hard to notice otherwise.
	
The chex_latex.pl script tests for:
* Doubled words, such as "the the."
* Grammatical goofs or clunky phrasing, as well as rules for formal writing, such as not using contractions.
* Potential [inter-word vs. inter-sentence spacing problems](https://en.wikibooks.org/wiki/LaTeX/Text_Formatting#Space_between_words_and_sentences).
* Any figure \label's that do not have any \ref's, and vice versa.
* \index markers that get opened but not closed, or vice versa.
* Misspellings used in computer graphics, e.g., "tesselation" and "frustrum" (and it's easy to add your own).
* Any \bibitems's that do not have any \cite's, and vice versa.
* And much else - more than 300 tests in all.

This script is in no way foolproof, and will natter about all sorts of things you may not care about. Since it's a Perl script, it's easy for you to edit and delete or modify any tests that you don't like.

# Installation and Use

Install Perl from say https://www.activestate.com/activeperl, put chex_latex.pl somewhere (easiest is to put it in the directory with your .tex files, else you need to specify the path to this file), go to the directory where your .tex files are and then:

    perl chex_latex.pl
  
and all .tex files in your directory and subdirectories will be read and checked for this and that. If you run this command in your downloaded repository, you should get the error list shown at the top of this page for the testfile.tex file included.

To run on a single file, here shown on Windows with an absolute path:

    perl chex_latex.pl C:\Users\you\your_thesis\chapter1.tex
	
For all files in a directory, here shown with a relative path:

    perl chex_latex.pl work_files\my-thesis-master

This script is one used for the book ''Real-Time Rendering'' and so has a bunch of book-specific rules. Blithely ignore our opinions or, better yet, comment out the warning lines you don't like in the script (the program's just a text file, nothing complex). You can also add "% chex_latex" to the end of any line in your .tex file in order to have this script skip some error tests on it, e.g.:

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

If a message confuses you, look in the Perl script itself, as there are comments about some of the issues.

Two other more obscure options:

    -O okword
	
Instead of adding a comment "% chex_latex" to lines you want the script to ignore, you could change the keyword to something else, e.g. "-O ignore_lint" would ignore all lines where you put "% ignore_lint" in a comment.

    -R refs.tex
	
By default, the file "refs.tex" is the one that contains \bibitem entries. Our book uses these, just about no one else does. If you actually do use \bibitem, this one is worth setting to your references file. It will tell you whether you reference something that doesn't exist in the references file, and whether any references in the file are not used in the text.

Thanks to John Owens for providing a bunch of theses and technical articles for testing.