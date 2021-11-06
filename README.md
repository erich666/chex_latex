# chex_latex
LaTeX and text file checking tool. [Install Perl](https://www.activestate.com/activeperl) and run by:

    perl chex_latex.pl

See all the options further down, e.g., you might consider '-p' if you want all possible warnings.

This Perl script reads your .tex files and looks for potential problems, such as doubled words ("the the") and many other bugs. Put it in your directory of .tex files and run it to look for common mistakes. If a message confuses you, look in the Perl script itself, as there are comments and links about some of the issues flagged. You can also use this script on raw text files; the script will automatically not do LaTeX testing.

You might disagree with some of the problems flagged, but with chex_latex.pl you are at least aware of all of them. A few minutes wading through these can catch errors hard to notice otherwise. That said, if you disagree, don't take the script's word for it. This program is no substitute for understanding the rules of grammar and LaTeX. One other trick I recommend: paste your text into Microsoft Word and see what it turns up.

The chex_latex.pl script tests for:
* Doubled words, such as "the the."
* Problems with spacing. For example, a sentence ending with with "GPU." should be "GPU\@." so that the space following is a "long space."
* Grammatical goofs or clunky phrasing, as well as rules for formal writing, such as not using contractions.
* Potential [inter-word vs. inter-sentence spacing problems](https://en.wikibooks.org/wiki/LaTeX/Text_Formatting#Space_between_words_and_sentences).
* Any figure \label's that do not have any \ref's, and vice versa.
* \index markers that get opened but not closed, or vice versa.
* Common misspellings in computer graphics, e.g., "tesselation" and "frustrum" (and it's easy to add your own).
* Any \bibitems's that do not have any \cite's, and vice versa.
* And much else - more than 300 tests in all.

As an example, here is testfile.tex file; first, look it over yourself:

	\section{Algorithms that Use Hardware}
	Here we'll discuss the very many algorithms that can be implemented on the GPU. For more information, Castelli
	\cite{Castelli2018} gives a thorough overview of the use of mip-maps for level of detail, compute shaders for
	frustrum culling, etc. and discusses which APIs support these techniques. Basically, you can use anything from
	DirectX 12\index{DirectX 12} with C++ to WebGL\index{WebGL} with Javascript/index{JS2018} as your API , due
	to that these all talk to the same underlying hardware. More specifically, there is literally no better way to
	to accelerate processing data, vs. using just the CPU--so ''just do it''.

Before looking below, what errors do you see? By typing "perl chex_latex.pl testfile.tex", here's what chex_latex.pl finds:

	SERIOUS: Title has a word 'that' that is uncapitalized, on line 1 in testfile.tex.
		The program is set to require that titles are capitalized.
		To override, use '-t' on the command line to allow uncapitalized titles.
		To be sure, you can test your title at https://capitalizemytitle.com/
	Sentence ending in the capital letters GPU should have a '\@.' for spacing, on line 2 in testfile.tex.
	SERIOUS: For formal writing, no contractions: ''ll' to ' will' on line 2 in testfile.tex.
		If you do not want to test for formal usage, put '-f' in the command line.
	tip: consider removing or replacing 'very' on line 2 in testfile.tex.
		'very' tends to weaken a sentence. Try substitutes: https://www.grammarcheck.net/very/
	\cite needs a tilde ~\cite before citation to avoid separation, on line 3 in testfile.tex.
	'mip-map' to 'mipmap' (no hyphen), on line 3 in testfile.tex.
	POSSIBLY SERIOUS: you may need to change 'etc.' to 'etc.\' to avoid having a 'double-space'
		appear after the period, on line 4 in testfile.tex.
		(To be honest, it's better to avoid 'etc.' altogether, as it provides little to no information.)
	MISSPELLING: 'frustrum' to 'frustum' on line 4 in testfile.tex.
	tip: you can probably remove 'basically' on line 4 in testfile.tex.
	hint: try to avoid using etc., as it adds no real information; on line 4 in testfile.tex.
		If you do end up using etc., if you don't use it at the end of a sentence, add a backslash: etc.\
	SERIOUS: '/index' should be \index, on line 5 in testfile.tex.
	SERIOUS: change ' ,' to ',' (space in front of comma), on line 5 in testfile.tex.
	Please change 'Javascript' to 'JavaScript' on line 5 in testfile.tex.
	tip: 'due to that' to 'because' on line 6 in testfile.tex.
	tip: 'more specifically' to 'specifically' on line 6 in testfile.tex.
	tip: you can probably not use 'literally' (and may mean 'figuratively') on line 6 in testfile.tex.
		If you think it's truly OK (e.g., it's part of a technical term, or you just like it),
		either edit this perl script, or put on the end of this line of your .tex file the comment '% chex_latex'.
	SERIOUS: word duplication problem of word 'to' on line 7 in testfile.tex.
	possibly serious: change '--' (short dash) to '---' on line 7 in testfile.tex, unless you are specifying a range.
	SERIOUS: U.S. punctuation rule, change ''. to .'' on line 7 in testfile.tex.
	SERIOUS: the first right double-apostrophe '' should probably be a left double-apostrophe ``, on line 7 in testfile.tex.
	SERIOUS: change 'vs.' to 'versus' to avoid having a 'double-space' appear after the period,
		or use 'vs.\' on line 7 in testfile.tex.
	Not capitalized at start of sentence (or the period should have a \ after it), on line 7 in testfile.tex.
	==========================================================================================================

This script is in no way foolproof and will natter about all sorts of things you may not care about. Since it's a Perl script, it's easy for you to delete or modify any tests that you don't like.

# Installation and Use

Install Perl from say https://www.activestate.com/activeperl, put chex_latex.pl somewhere (easiest is to put it in the directory with your .tex files, else you'll need to specify the path to this file), go to the directory where your .tex files are and then:

    perl chex_latex.pl
  
and all .tex files in your directory and subdirectories will be read and checked for this and that. If you run this command in your downloaded repository, you should get the error list shown at the top of this page for the testfile.tex file included.

To run on a single file, here shown on Windows with an absolute path:

    perl chex_latex.pl C:\Users\you\your_thesis\chapter1.tex
	
For all files in a directory, here shown with a relative path:

    perl chex_latex.pl work_files/my-thesis-master

This script is one used for the book _Real-Time Rendering_ and so has a bunch of book-specific rules. Blithely ignore our opinions or, better yet, comment out the warning lines you don't like in the script (the program's just a text file, nothing complex). You can also add "% chex_latex" to the end of any line in your .tex file in order to have this script skip some error tests on it, e.g.:

    This method of using data is reasonable. % don't flag "data is" - chex_latex

The "chex_latex" says the line is OK and won't be tested. Beware, though: if you make any other errors on this line in the future, they also won't be tested.

The main options are:

	-d - turn off dash tests for '-' or '--' flagged as needing to be '---'.
	-f - turn off formal writing check; allows contractions and other informal usage.
	-l - ignore duplicate labels, citations, references; use when running on a directory tree of unrelated chapters.
	-p - turn ON picky style check, which looks for more style problems but is not so reliable.
	-s - turn off style check; looks for poor usage, punctuation, and consistency problems.
	-t - turn off title capitalization check; titles are assumed to be properly capitalized otherwise.
	-u - turn off U.S. style tests for putting commas and periods inside quotes.
	
So, if you want all the tests, do:

	perl chex_latex.pl -p [directory or files]
	
If you want the bare minimum, checking just for LaTeX problems and doubled words, do:

    perl chex_latex.pl -dlstfu [directory or files]

To run this checker against plain text files, just specify the files, as normal:

	perl chex_latex.pl my_text_file.txt another_text_file.txt
	
If any file is found that does not end in ".tex," the LaTeX-specific tests will be disabled (for all files, so don't mix .tex with .txt).

This script will also ignore any text between the following pairs of lines:

@<foo>>=     <--- really, just searches for "@<" at the start of a line
lines of your source code here...
@.

and

\draft
lines of your draft text here that you don't want tested...
\enddraft

Two other more obscure options:

    -O okword
	
Instead of adding a comment "% chex_latex" to lines you want the script to ignore, you could change the keyword to something else, e.g., "-O ignore_lint" would ignore all lines where you put "% ignore_lint" in a comment.

    -R refs.tex
	
By default, the file "refs.tex" is the one that contains \bibitem entries. Our book uses these, just about no one else does. If you do use \bibitem, this one is worth setting to your references file. It will tell you whether you reference something that doesn't exist in the references file, and whether any references in the file are not used in the text.

One last obscure option:

    -c 100

This will go through your file and tell you if any lines are longer than 100 characters.

Thanks to John Owens for providing a bunch of the program's tips and technical articles for testing.

# Bonus Tool: Aspell Sorter for Batch Spell Checking

Interactive spell checkers are fine for small documents, but for long ones I find it tedious to step through every word flagged as not being in the dictionary. Most of the time these are names, and for each hit I have to choose "ignore/add/fix" or whatever. I just want to toss in *.tex files and get a long list back of what words failed. Here's how I do it. My contribution is a little Perl script at the end that consolidates results.

The main piece is the program [_Aspell_](http://aspell.net/). For Windows, find the binaries [here](http://aspell.net/win32/) - old but fine. For Windows the best setup explanation I found is [here](https://web.archive.org/web/20160208031126/https://notepad-plus-plus.org/community/topic/8206/method-to-install-gnu-aspell-win32-dictionaries-and-spell-check-plugin-on-n) - a little involved, but entirely worth it to me.

After installing, I first put all .tex files into one test file. For example, on Windows:

    type *.tex > alltext.txt
	
On linuxy systems:

    cat *.tex > alltext.txt
	
Say that file is now in C:\temp. I then run Aspell on this file by going to the Aspell directory and doing this:

    bin\aspell list -t < C:\temp\alltext.txt > C:\temp\alltypos.txt

This gives a long file of misspelled (or, more likely, not found, such as names) words, in order encountered. The same author's name will show up a bunch of times, code bits will get listed again and again, and other spurious problems flagged. I find it much faster to look at a sorted list of typos, showing each word just once. I recommend starting at the end of the list and working upward. This process can cut down the number of words you need to examine by [a factor of five](http://www.realtimerendering.com/blog/free-editing-tools-and-tips/).

To make such a list, use the script aspell_sorter.pl:

    perl aspell_sorter.pl alltypos.txt > spell_check.txt
	
which rips CamelCase words into their components and sorts the words in the alltypos.txt file, removing duplicates and giving a count. The file produced first lists all CamelCase words (first words, then words after the first), then all capitalized words (it is easier to skim past authors that way), then all lowercase. Sometimes the Aspell dictionaries leave words out, flagging false positives. You can avoid many of these by taking this output spell_check.txt file and pasting its contents into MS Word, for example, which will give a red underline only to words it thinks are misspelled. Also, words with a multibyte character, such as an apostrophe, can cause words such as "don't" to be listed as "don". Before testing I sometimes search on such apostrophes ’ and convert them to '.

There are lots of false positives, such as CamelCase words and authors names, so I'll usually start by looking at the end of the spell_check.txt file, where the lowercase words hang out. Also, you can modify the script itself by setting $spellcount = 1 (or any other value, for the maximum number of repeats). If set, only words "misspelled" one time will be listed. You risk missing some word that is consistently misspelled, but the list is often considerably shorter (I've found it [2-3 times shorter](http://www.realtimerendering.com/blog/free-editing-tools-and-tips/)), as false positives found more than once are culled out.

That's it - nothing fancy, but it has saved me a considerable amount of time and turned up some typos I would probably not have found otherwise. I can also save the results file, so if I later change .tex files, I can make a new spell_check.txt and do a "diff" to see if I've introduced any new errors.

Aspell also works on plaintext files, so if you can extract your text into a simple text file you can use this process to perform batch spell checking on anything. For other free tools, see [my blog post](http://www.realtimerendering.com/blog/free-editing-tools-and-tips/).