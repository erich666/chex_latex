# chex_latex
LaTeX file checking tool.

This Perl script reads your .tex files and looks for potential problems, such as doubled words ("the the") and many other bugs. Put it in your directory of .tex files and run it to look for common mistakes. You can also use it on raw text files, just use the -r option to disable LaTeX-specific warnings.

As an example, here is a snippet of a .tex file; first, look it over yourself:

	\section{Algorithms that Use Hardware}
	Here we'll discuss the very many algorithms that can be implemented on the GPU. For more information, Castelli
	\cite{Castelli2018} gives a thorough overview of the use of mip-maps for level of detail, compute shaders for
	frustrum culling, etc. and discusses which APIs support these techniques. Basically, you can use anything from
	DirectX 12\index{DirectX 12} with C++ to WebGL\index{WebGL} with Javascript/index{Javascript} as your API ,
	due to that these all talk to the same underlying hardware. More specifically, there is literally no better way to
	to accelerate processing data, vs. using just the CPU--so ''just do it''.

Here's what chex_latex.pl finds in a fraction of a second:

	file is testfile.tex
	SERIOUS: Title has a word 'Use' that is capitalized, on line 1 in .\testfile.tex.
		This does not match the style in the first \section encountered
		on line 1 at word 'that' in .\testfile.tex, which is an uncapitalized word.
	SERIOUS: Title has a word 'Hardware' that is capitalized, on line 1 in .\testfile.tex.
		This does not match the style in the first \section encountered
		on line 1 at word 'that' in .\testfile.tex, which is an uncapitalized word.
	Sentence ending in the capital letters GPU should have a '\@.' for spacing, on line 2 in .\testfile.tex.
	SERIOUS: no contractions: ''ll' to ' will' on line 2 in .\testfile.tex.
	\cite needs a tilde ~\cite before citation to avoid separation, on line 3 in .\testfile.tex.
	POSSIBLY SERIOUS: you may need to change 'etc.' to 'etc.\' to avoid having a 'double-space'
		appear after the period, on line 4 in .\testfile.tex.
		(To be honest, it's better to avoid 'etc.' altogether, as it provides little to no information.)
	MISSPELLING: 'frustrum' to 'frustum' on line 4 in .\testfile.tex.
	tip: you can probably remove 'basically' on line 4 in .\testfile.tex.
	SERIOUS: '/index' should be \index, on line 5 in .\testfile.tex.
	SERIOUS: change ' ,' to ',' (space in front of comma), on line 5 in .\testfile.tex.
	Please change 'Javascript' to 'JavaScript' on line 5 in .\testfile.tex.
	SERIOUS: change ' ,' to ',' (space in front of comma), on line 6 in .\testfile.tex.
	tip: 'due to that' to 'because' on line 6 in .\testfile.tex.
	tip: 'more specifically' to 'specifically' on line 6 in .\testfile.tex.
	tip: you can probably not use 'literally' (and may mean 'figuratively'), on line 6 in .\testfile.tex.
		If you think it's OK, put on the end of the line the comment '% chex_latex'
	SERIOUS: word duplication problem of word 'to' on line 7 in .\testfile.tex.
	SERIOUS: change '--' (short dash) to '---' on line 7 in .\testfile.tex.
	SERIOUS: U.S. punctuation rule, change ''. to .'' on line 7 in .\testfile.tex.
	SERIOUS: change 'vs.' to 'versus' to avoid having a 'double-space' appear after the period,
		or use 'vs.\' on line 7 in .\testfile.tex.
	Not capitalized at start of sentence (or the period should have a \ before it), on line 7 in .\testfile.tex.	==========================================================================================================

You might disagree with some of the problems flagged, but with chex_latex.pl you are at least aware of all of them. A few minutes wading through these can catch errors hard to notice otherwise.
	
The chex_latex.pl script tests for:
* Doubled words, such as "the the."
* Grammatical goofs or clunky phrasing, as well as rules for formal writing, such as not using contractions.
* Potential [inter-word vs. inter-sentence spacing problems](https://en.wikibooks.org/wiki/LaTeX/Text_Formatting#Space_between_words_and_sentences).
* Any figure \label's that do not have any \ref's, and vice versa.
* \index markers that get opened but not closed, or vice versa.
* Misspellings used in computer graphics, e.g., "tesselation" and "frustrum" (and it's easy to add your own).
* Any \bibitems's that do not have any \cite's, and vice versa.
* And much else - more than 300 tests in all.

This script is in no way foolproof, and will natter about all sorts of things you may not care about. Since it's a Perl script, it's easy for you to delete or modify any tests that you don't like.

# Installation and Use

Install Perl from say https://www.activestate.com/activeperl, put chex_latex.pl somewhere (easiest is to put it in the directory with your .tex files, else you need to specify the path to this file), go to the directory where your .tex files are and then:

    perl chex_latex.pl
  
and all .tex files in your directory and subdirectories will be read and checked for this and that. If you run this command in your downloaded repository, you should get the error list shown at the top of this page for the testfile.tex file included.

To run on a single file, here shown on Windows with an absolute path:

    perl chex_latex.pl C:\Users\you\your_thesis\chapter1.tex
	
For all files in a directory, here shown with a relative path:

    perl chex_latex.pl work_files/my-thesis-master

This script is one used for the book ''Real-Time Rendering'' and so has a bunch of book-specific rules. Blithely ignore our opinions or, better yet, comment out the warning lines you don't like in the script (the program's just a text file, nothing complex). You can also add "% chex_latex" to the end of any line in your .tex file in order to have this script skip some error tests on it, e.g.:

    This method of using data is reasonable. % don't flag "data is" - chex_latex

The "chex_latex" says the line is OK and won't be tested. Beware, though: if you make any other errors on this line in the future, they also won't be tested.

The options are:

	-d - turn off dash tests for '-' or '--' flagged as needing to be '---'.
	-f - turn off formal writing check; allows contractions and other informal usage.
	-p - turn ON picky style check, which looks for more style problems but is not so reliable.
	-s - turn off style check; looks for poor usage, punctuation, and consistency.
	-u - turn off U.S. style tests for putting commas and periods inside quotes.
	
So if you want all the tests, do:

	perl chex_latex.pl -p [directory or files]
	
If you want the bare minimum, do:

    perl chex_latex.pl -dfsu [directory or files]

If a message confuses you, look in the Perl script itself, as there are comments about some of the issues.

To run this checker against plain text files, just specify the files, as normal:

	perl chex_latex.pl my_text_file.txt another_text_file.txt
	
If any file is found that does not end in ".tex," the LaTeX-specific tests will be disabled (for all files, so don't mix .tex with .txt).

Two other more obscure options:

    -O okword
	
Instead of adding a comment "% chex_latex" to lines you want the script to ignore, you could change the keyword to something else, e.g. "-O ignore_lint" would ignore all lines where you put "% ignore_lint" in a comment.

    -R refs.tex
	
By default, the file "refs.tex" is the one that contains \bibitem entries. Our book uses these, just about no one else does. If you actually do use \bibitem, this one is worth setting to your references file. It will tell you whether you reference something that doesn't exist in the references file, and whether any references in the file are not used in the text.

Thanks to John Owens for providing a bunch of theses and technical articles for testing.

# Bonus Tool: Aspell Sorter for Batch Spell Checking

Interactive spell checkers are fine for small documents, but for long ones I find it tedious to step through every word flagged as not being in the dictionary. Most of the time these are names, and for each hit I have to choose "ignore/add/fix" or whatever. I just want to toss in *.tex files and get a long list back of what words failed. Here's how I do it. My contribution is a little Perl script at the end that consolidates results.

The main piece is the program [_Aspell_](http://aspell.net/). For Windows the best setup explanation I found is [here](https://notepad-plus-plus.org/community/topic/8206/method-to-install-gnu-aspell-win32-dictionaries-and-spell-check-plugin-on-n) - a little involved, but entirely worth it to me.

After installing, I first put all .tex files into one test file. For example, on Windows:

    type *.tex > alltext.txt
	
On linuxy systems:

    cat *.tex > alltext.txt
	
Say that file is now in C:\temp. I then run Aspell on this file by going to the Aspell directory and doing this:

    bin\aspell list -t < C:\temp\alltext.txt > C:\temp\alltypos.txt

This gives a long file of misspelled (or, more likely, not found, such as names) words, in order encountered. The same author's name will show up a bunch of times, code bits will get listed again and again, and other spurious problems flagged. I find it much faster to look at a sorted list of typos, showing each word just once.

To make such a list, use the script aspell_sorter.pl:

    perl aspell_sorter.pl alltypos.txt > spell_check.txt
	
which simply sorts the words in the alltypos.txt file, removing duplicates and giving a count. The file produced first lists all capitalized words (it is easy to skim past authors that way), then all lowercase.

That's it - nothing fancy, but it has saved me a considerable amount of time. I can also save the results file, change .tex files, and then make a new spell_check.txt and do a "diff" to see if I've introduced any new errors.

Aspell also works on plaintext files, so if you can extract your text into a simple text file you can use this process to perform batch spell checking on anything.