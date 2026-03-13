#!/usr/bin/env python3
# Script to read in a latex file or directory and its subdirectories and check for typographic
# and syntax errors of various sort.
# See https://github.com/erich666/chex_latex for details on how to install and use it.
#
# Usage: python chex_latex.py
#     this checks all files in the current directory
#
# Usage: python chex_latex.py advlite.tex
#     checks just this tex file.
#
# Usage: python chex_latex.py latex_docs/thesis
#     check all *.tex files in the directory latex_docs/thesis, and its subdirectories
#
# See 'def usage' below for command-line options.

import sys
import os
import re
import glob
import json

# options for tests. You can set these to whatever defaults you like
style = 1
picky = 0
formal = 1
dashes = 1
labels = 1
usstyle = 1
textonly = 0
testlisting = 0  # If > 0, check code line length as set
checkpackages = 0  # If set, check \usepackage against approved list

# If you want to always have titles for sections, etc. be capitalized, set this to 1, else 0.
# If set to 0, then lowercase titles such as "Testing results" are allowed, but are still checked
# against other multi-word titles used in this document. For example, if earlier you said
# "The Algorithm", the document is then using caps in one section, but not in another, and so
# will flag an error.
force_title_cap = 1

# If this phrase is found in the comment on a line, ignore that line for various tests.
# Feel free to add your own "ok and" for the various tests below, I didn't go nuts with it.
okword = "chex_latex"

# Specify which file has \bibitem references in it, both to avoid style checks on this file and
# to perform specialized tests on this file.
refstex = "refs.tex"

# Specify which file has the approved packages list in JSON format.
# Use the -P option to set this file path and enable package checking.
packagesjson = ""
approved_packages = {}

# put specific files you want to skip into this list.
# NOTE: this script ignores all files with "tikz" in the path; this is done in read_recursive_dir.
# These files were found to cause a lot of false positives with no gain.
# See https://www.overleaf.com/learn/latex/TikZ_package
skip_filename = {
    # for example:
    #   "./Boffins_for_Bowling/main.tex": "skip",
}

# internal stuff
foundref = 0
untouchedtheline = ""
theline = ""
input_file = ""  # $input in Perl; current file being processed
cfnum = 0
conum = 0
lastl = ""
numbib = 0
title_type = ""
caps_used = ""
caps_loc = ""
filenames_found = {}
cite = {}
label = {}
labelimportant = {}
labelfigure = {}
ref = {}
biborder = {}
bibitem = {}
emfound = {}
eminput = {}
codefiles = []
citeorder = []
citeloc = []
cap_title = [0, 0, 0, 0, 0]
cap_title_loc = ["", "", "", "", ""]
ok = 0
figcaption = ''
figlabel = ''
figcenter = ''

flag_formal = 1

line_number = 0  # replaces Perl's $.


def usage():
    print("Usage: python chex_latex.py [-dfpsu] [-O okword] [-P packages.json] [-R refs.tex] [directory [directory...]]")
    print("  -c # - check number of characters in a line of code against the value passed in, e.g., 80.")
    print("  -d - turn off dash tests for '-' or '--' flagged as needing to be '---'.")
    print("  -f - turn off formal writing check; allows contractions and other informal usage.")
    print("  -l - ignore duplicate labels, citations, references; use when running on a directory tree of unrelated chapters.")
    print("  -p - turn ON picky style check, which looks for more style problems but is not so reliable.")
    print("  -P packages.json - specify a JSON file with approved \\usepackage names to check against.")
    print("  -s - turn off style check; looks for poor usage, punctuation, and consistency problems.")
    print("  -t - turn off title capitalization check. Titles are still checked for internal consistency.")
    print("  -u - turn off U.S. style tests for putting commas and periods inside quotes.")
    print("  -O word - this script ignores lines with comments 'chex_latex' in them. Use -O to change this keyword.")
    print("  -R [refs.tex] - specify which file has \\bibitem references in it, if any, for specialized testing.")


def load_approved_packages():
    """Simple parser for JSON array of strings like:
    [
        "package1",
        "package2"
    ]
    """
    global approved_packages, packagesjson
    try:
        with open(packagesjson, 'r') as pkgfile:
            for line in pkgfile:
                # Look for quoted strings: "packagename"
                m = re.search(r'"([^"]+)"', line)
                if m:
                    pkg = m.group(1)
                    approved_packages[pkg] = 1
    except IOError as e:
        print(f"Can't open packages file {packagesjson}: {e}", file=sys.stderr)
        sys.exit(1)
    count = len(approved_packages)
    print(f"Loaded {count} approved packages from {packagesjson}")


def check_use_package(line, is_ok):
    """Parse the \\usepackage or \\RequirePackage line to extract package name(s).
    Handles: \\usepackage{pkg}, \\usepackage[options]{pkg}, \\usepackage{pkg1,pkg2,pkg3}
    """
    global line_number, input_file

    # Skip if line has the okword comment
    if is_ok:
        return

    # Remove any comment from the line first (but not escaped \%)
    line = line.replace('\\%', 'ESCAPEDPERCENT')
    if '%' in line:
        line = line[:line.index('%')]
    line = line.replace('ESCAPEDPERCENT', '\\%')

    # Match \usepackage or \RequirePackage with optional options and the package name(s)
    m = re.search(r'\\(?:usepackage|RequirePackage)(?:\s*\[[^\]]*\])?\s*\{([^}]+)\}', line)
    if m:
        packages_str = m.group(1)
        # Split by comma in case multiple packages are listed
        packages = re.split(r'\s*,\s*', packages_str)
        for pkg in packages:
            # Trim whitespace
            pkg = pkg.strip()
            if len(pkg) > 0 and pkg not in approved_packages:
                print(f"ERROR: unapproved package '{pkg}' used on line {line_number} in {input_file}.")


def read_recursive_dir(dirs):
    """Walk directories to find .tex files, ignoring tikz files."""
    global codefiles, cfnum
    for d in dirs:
        for root, dirnames, filenames in os.walk(d):
            for filename in filenames:
                if filename.endswith('.tex') and 'tikz' not in filename:
                    fullpath = os.path.join(root, filename)
                    if 'tikz' not in fullpath:
                        codefiles.append(fullpath)
                        cfnum += 1


def process_files():
    """Process all collected .tex files and perform cross-file checks."""
    global input_file, filenames_found, labels, cfnum, conum, foundref
    global label, ref, labelfigure, labelimportant, cite, bibitem, biborder
    global citeorder, citeloc

    for i in range(cfnum):
        fld = codefiles[i].split('/')
        nextfile = fld[-1]
        # not vital for a book
        # if nextfile in filenames_found:
        #     print(f"BEWARE: two .tex files with same name {nextfile} found in directory or subdirectory.")
        filenames_found[nextfile] = 1

        input_file = codefiles[i]
        if input_file not in skip_filename:
            read_code_file()

    # better would be to always check labels, etc., among files in the same directory, clear list when a new directory is hit. TODO
    if labels:
        potential = 0
        for elem in sorted(label.keys()):
            if elem not in ref:
                # check if figure is labeled. TODO: should add tables
                if labelfigure.get(elem) == 1 and labelimportant.get(elem):
                    if potential == 0:
                        potential = 1
                        print("\n\n*************************\nPOTENTIAL ERRORS FOLLOW:")
                    print(f"Labeled, but not referenced via \\ref: {elem} in '{label[elem]}'")

        # element referenced but not found
        critical = 0
        for elem in sorted(ref.keys()):
            if elem not in label and not ('code:' in elem or 'list:' in elem):
                if critical == 0:
                    critical = 1
                    print("\n\n*************************\nCRITICAL ERRORS FOLLOW:")
                print(f"Referenced, does not exist (perhaps you meant to \\cite and not \\ref or \\pageref?): '{elem}' in '{ref[elem]}'")

        if foundref:
            # element cited but not found
            for elem in sorted(cite.keys()):
                if elem not in bibitem:
                    if critical == 0:
                        critical = 1
                        print("\n\n*************************\nCRITICAL ERRORS FOLLOW:")
                    print(f"Cited, does not exist (perhaps you meant to \\ref?): '{elem}' in '{cite[elem]}'")

        # bad citation order
        for i in range(conum):
            subf = citeorder[i]
            fldc = subf.split(',')
            checkit = True
            for j in range(1, len(fldc)):
                if checkit and biborder.get(fldc[j-1], 0) > biborder.get(fldc[j], 0):
                    checkit = False
                    print(f"ERROR: citations *{subf}* out of order (or reference missing) at {citeloc[i]}")

        # bibitems not referenced
        print("==========================================================================================================")
        for elem in sorted(bibitem.keys()):
            if elem not in cite:
                if critical == 0:
                    critical = 1
                    print("\n\n*************************\nCRITICAL ERRORS FOLLOW:")
                print(f"bibitem not referenced: {elem} in {bibitem[elem]}")



def WORDTEST(pstring: str, phrase: str, estring: str, end: str) -> int:
    if end in estring:
        return 0
    if phrase in pstring:
        return 1
    return 0


def SAYOK() -> None:
    print("    If you think it's truly OK (e.g., it's part of a technical term, or you just like it),")
    if textonly:
        print("    you can ignore this warning, or edit this script and comment it out.")
    else:
        print("    either edit this script, or put on the end of this line of your .tex file the comment '% chex_latex'.")


_CONNECTOR_WORDS_LOWER = {
    "and", "or", "versus", "from", "between", "a", "by", "on", "in",
    "into", "is", "as", "about", "over", "an", "to", "for", "of",
    "with", "per", "via", "and/or", "but", "if", "nor", "at", "off",
    "up", "the",
    # questionable – currently excluded:
    #   "so", "yet"
}

_CONNECTOR_WORDS_CAPITALIZED = {
    "And", "Or", "Versus", "From", "Between", "A", "By", "On", "In",
    "Into", "Is", "As", "About", "Over", "An", "To", "For", "Of",
    "With", "Per", "Via", "And/Or", "But", "If", "Nor", "At", "Off",
    "Up", "The",
}


def CONNECTOR_WORD(testword: str, loc: int) -> int:
    if testword in _CONNECTOR_WORDS_LOWER:
        return 1
    # capitalized and shouldn't be?
    if loc != 0 and testword in _CONNECTOR_WORDS_CAPITALIZED:
        return 2
    return 0


# ---------------------------------------------------------------------------
# CAPITALIZED – check whether the first character of *testword* is uppercase.
#
# Returns:
#   -1 – word starts with backslash (LaTeX command, ignore it)
#    1 – first character is A-Z or 0-9
#    0 – first character is lowercase
# ---------------------------------------------------------------------------
def CAPITALIZED(testword: str) -> int:
    if not testword:
        return 0
    fc = testword[0]
    if fc == '\\':
        return -1   # ignore word, e.g., \small
    if re.match(r'[A-Z0-9]', fc):
        return 1
    return 0


# ---------------------------------------------------------------------------
# SECTION_MISMATCH – check whether *word*'s capitalisation matches the style
# already recorded for the current section type.
#
# Uses / mutates the module-level globals:
#   theline, line_number, input_file, force_title_cap,
#   cap_title, cap_title_loc, title_type, caps_used, caps_loc
#
# Returns 1 on mismatch, 0 otherwise.
# ---------------------------------------------------------------------------
def SECTION_MISMATCH(word: str) -> int:
    global title_type, caps_used, caps_loc

    cap = CAPITALIZED(word)
    # ignore word?
    if cap == -1:
        return 0

    ind = None
    if '\\chapter{' in theline:
        ind = 0
        title_type = '\\chapter'
    elif '\\section{' in theline:
        ind = 1
        title_type = '\\section'
    elif '\\subsection{' in theline:  # TODO add \subsection*{ and similar
        ind = 2
        title_type = '\\subsection'
    elif '\\subsubsection{' in theline:
        ind = 3
        title_type = '\\subsubsection'
    elif '\\title{' in theline:
        ind = 4
        title_type = '\\title'

    if ind is None:
        return 0

    # to force title to be capitalized (as in GPU Gems), set to 2 here;
    # else set force_title_cap to False
    if force_title_cap:
        cap_title[ind] = 2

    if cap_title[ind]:
        # check if this chapter's/section's/etc. capitalisation matches the first one's
        if cap_title[ind] != (2 if cap else 1):
            # mismatch
            caps_used = cap_title[ind] - 1
            caps_loc = cap_title_loc[ind]
            return 1
    else:
        # first encounter, so record whether second word is capitalised or not
        cap_title[ind] = 2 if cap else 1
        cap_title_loc[ind] = f"on line {line_number} at word '{word}' in {input_file}"

    return 0


# ---------------------------------------------------------------------------
# FLAG_FORMAL – one-shot message telling the user how to suppress formal-
# usage warnings.  After firing once, silences itself.
# ---------------------------------------------------------------------------
def FLAG_FORMAL() -> None:
    global flag_formal
    if flag_formal:
        flag_formal = False
        print("    If you do not want to test for formal usage, put '-f' in the command line.")



def read_code_file():
    """Read and check a single .tex or text file."""
    global input_file, cfnum, line_number, untouchedtheline, theline, ok
    global foundref, figcaption, figlabel, figcenter
    global numbib, conum, lastl, label, ref, cite, bibitem, biborder
    global emfound, eminput, cap_title, cap_title_loc, citeorder, citeloc
    global labelimportant, labelfigure, title_type, caps_used, caps_loc

    isref = 1 if re.search(refstex, input_file) else 0
    infigure = 0
    inequation = 0
    inlisting = 0
    insidecode = 0
    intable = 0
    inquote = 0
    ignore_first = 0
    indexlong = {}
    subfigure = 0
    tabsfound = 0
    justlefteq = 0
    # justleftlisting = 0
    justblankline = 0
    duplicate_count = 0
    insource = 0
    indraft = 0
    prev_line = ''
    lcprev_line = ''
    prev_real_line = ''

    # now the code file read
    try:
        datafile = open(input_file, 'r', encoding='utf-8', errors='replace')
    except IOError as e:
        print(f"Can't open {input_file}: {e}", file=sys.stderr)
        sys.exit(1)

    # if there is more than one file being parsed, note the separation of files
    if cfnum > 1:
        print(f"\n================================================\nFILE: {input_file}:")

    line_number = 0
    for raw_line in datafile:
        line_number += 1
        # strip trailing newline/carriage return
        raw_line = raw_line.rstrip('\r\n')
        untouchedtheline = theline = raw_line
        skip = 0
        period_problem = 0

        # if we're in source code or draft text, ignore them
        if re.search(r'^\@\<', theline):
            insource = 1
        elif re.search(r'^\@\.', theline):
            insource = 0
        elif '\\draft' in theline:
            indraft = 1
        elif '\\enddraft' in theline:
            indraft = 0

        if insource or indraft:
            skip = 1

        # if the line has chex_latex on it in the comments, can ignore certain flagged problems,
        # and ignore figure names.
        if re.search(okword, theline):  # TODO - look only in comments for okword
            ok = 1  # to turn off "% chex_latex" testing, simply set ok = 0


        else:
            ok = 0

        twook = ok

        if theline == '':
            justblankline = 1

        # test if there's a blank line after an equation - go see if there should be.
        if picky and justlefteq:
            if theline == '':
                print(f"EQUATION ends with blank line after it, on line {line_number} in {input_file}.")
                print("    This can often give too much white space between the equation and the text.")
            justlefteq = 0

        # cut rest of any line with includegraphics and trim= on it
        # really, just delete the whole line
        if '\\includegraphics[' in theline:
            # delete line
            theline = ''

        # other lines that get ignored
        m = re.search(r'\\def', theline)
        if m:
            theline = theline[:m.start()]
        m = re.search(r'\\graphicspath', theline)
        if m:
            theline = theline[:m.start()]

        m_usepackage = re.search(r'\\usepackage', theline)
        m_requirepackage = re.search(r'\\RequirePackage', theline)
        if m_usepackage or m_requirepackage:
            # Check packages against approved list if enabled
            if checkpackages:
                check_use_package(untouchedtheline, ok)
            m = m_usepackage if m_usepackage else m_requirepackage
            theline = theline[:m.start()]

        for cmd in [r'\\counterwithout', r'\\hyphenation', r'\\definecolor',
                    r'\\newcommand', r'\\ifthenelse', r'\\renewcommand',
                    r'\\hypersetup', r'\\STATE', r'\\WHILE', r'\\IF',
                    r'\\ELSE', r'\\draw', r'\\node', r'\\foreach',
                    r'\\fill', r'\\vfill', r'\\subfloat', r'\\input',
                    r'\\bibliography', r'\\import', r'\\addbibresource']:
            m = re.search(cmd, theline)
            if m:
                theline = theline[:m.start()]

        m = re.search(r'\\centering', theline)
        if m:
            theline = theline[:m.start()]
            figcenter = 'has centering'

        # hit a new paragraph?
        newpara = (len(theline) == 0)
        # convert \% to Pct so we don't confuse it with a comment.
        theline = re.sub(r'\\%', 'PercentSign', theline)
        # now trim any comment from the line.
        m = re.search(r'%', theline)
        if m:
            theline = theline[:m.start()]
        # convert back
        theline = re.sub(r'PercentSign', '%', theline)
        # chop whitespace away from the end of the line
        theline = theline.rstrip()
        # chop whitespace away from the beginning of the line
        theline = theline.lstrip()

        if skip:
            theline = ""

        # else if line is blank or a control line, move along, nothing to see here.
        if skip or len(theline) > 0:

            # previous "last token" and next line joined, to look for multiline problems.
            twoline = ' ' + prev_line + ' ' + theline + ' '

            # index searcher: find left |( and right |) index entries and make sure they match up.
            str_val = twoline
            newtwoline = ' '

            # index test
            while not textonly:
                m = re.search(r'\\index\{([\d\w_".\'\~\-\$& !^()/\|\\@]+)}', str_val)
                if not m:
                    break
                indexname = m.group(1)

                str_val = str_val[m.end():]
                newtwoline += str_val[:m.start()] if False else twoline[len(twoline) - len(str_val) - (len(str_val)):m.start()]
                # Correct prematch: everything before the match in the current str_val
                # We need to track prematch properly
                # Let me redo this logic more carefully
                pass

            # Redo the index test loop more carefully
            str_val = twoline
            newtwoline = ' '

            while not textonly:
                m = re.search(r'\\index\{([\d\w_".\'\~\-\$& !^()/\|\\@]+)}', str_val)
                if not m:
                    break
                indexname = m.group(1)
                prematch = str_val[:m.start()]
                str_val = str_val[m.end():]
                newtwoline += prematch

                m2 = re.search(r'\|\(', indexname)
                if m2:
                    key = indexname[:m2.start()]
                    if key not in indexlong:
                        indexlong[key] = 0
                    indexlong[key] += 1
                    if indexlong[key] > 1:
                        print(f"SERIOUS: nested index of same term, very dangerous, on line {line_number} in {input_file}.")
                else:
                    m2 = re.search(r'\|\)', indexname)
                    if m2:
                        key = indexname[:m2.start()]
                        if key not in indexlong:
                            print("ERROR: found right index {" + key + "|)} without left index in " + input_file + ".")
                            print("    Perhaps you repeated this right entry?")
                        else:
                            indexlong[key] -= 1
                            if indexlong[key] == 0:
                                del indexlong[key]

            newtwoline += str_val + ' '
            # twoline now has the index entries removed from it.
            twoline = newtwoline
            lctwoline = twoline.lower()

            str_val = theline
            m = re.search(r'see\{([\d\w_".\'\~\-\$& !^()/\|\\@]+)}', str_val)
            if not textonly and m:
                seestr = m.group(1)
                if '!' in seestr:
                    print(f"Error: ''{seestr}'', replace exclamation point with comma and space, on line {line_number}")

            lctheline = theline.lower()

            # have to do this one early, as includegraphics gets culled out
            if re.search(r'begin\{subfigure}', theline) or re.search(r'begin\{minipage}', theline):
                subfigure = 1

            # it's not so nice to make width=1.0, 100%, as the figure will look wider than the text.
            if style and not testlisting and not ok and not subfigure and '\\includegraphics[' in theline:
                if (not subfigure and 'width=1.0\\' in theline) or 'width=\\' in theline:
                    print(f"POSSIBLE OVERHANG: please make the figure width a maximum of 0.95, on line line {line_number} in {input_file}.")

            # check for section, etc. and see that words are capitalized
            title_match = None
            if not testlisting:
                for pat in [r'\\chapter\{([A-Za-z| -]+)\}',
                            r'\\section\{([A-Za-z| -]+)\}',
                            r'\\subsection\{([A-Za-z| -]+)\}',
                            r'\\subsubsection\{([A-Za-z| -]+)\}',
                            r'\\title\{([A-Za-z| -\\,]+)\}']:
                    title_match = re.search(pat, theline)
                    if title_match:
                        break

            if title_match:
                wds = re.split(r'[ -]', title_match.group(1))
                for i in range(len(wds)):
                    if i == 0:
                        # first word - just check for capitalization
                        if CAPITALIZED(wds[i]) == 0:
                            print(f"LIKELY SERIOUS: Chapter or Section's first word '{wds[i]}' is not capitalized, on line {line_number} in {input_file}.")
                    else:
                        sw = CONNECTOR_WORD(wds[i], i)
                        if not ok and sw == 2:
                            print(f"LIKELY SERIOUS: Chapter or Section title has a word '{wds[i]}' that should not be capitalized, on line {line_number} in {input_file}.")
                            print("    You can test your title at https://capitalizemytitle.com/")
                        elif sw == 0 and len(wds[i]) > 0 and SECTION_MISMATCH(wds[i]):
                            cap_msg = "uncapitalized" if caps_used else "capitalized"
                            print(f"SERIOUS: Title has a word '{wds[i]}' that is {cap_msg}, on line {line_number} in {input_file}.")
                            if force_title_cap:
                                print("    The program is set to require that titles are capitalized.")
                                print("    To override, use '-t' on the command line to allow uncapitalized titles.")
                            else:
                                cap_msg2 = "a capitalized" if caps_used else "an uncapitalized"
                                print(f"    This does not match the style in the first {title_type} encountered")
                                print(f"    {caps_loc}, which is {cap_msg2} word.")
                            if caps_used:
                                print("    To be sure, you can test your title at https://capitalizemytitle.com/")

            # check if we're in an equation or verbatim section
            if ('begin{equation' in theline or
                    'begin{eqnarray' in theline or
                    'begin{comment' in theline or
                    'begin{IEEEeqnarray' in theline or
                    'begin{align' in theline or
                    '\\[' in theline or
                    re.search(r'begin\{lstlisting}', theline)):
                inequation = 1
                if re.search(r'begin\{lstlisting}', theline):
                    inlisting = 1
                if justblankline and (re.search(r'begin\{equation}', theline) or
                                      re.search(r'begin\{eqnarray}', theline) or
                                      re.search(r'begin\{IEEEeqnarray}', theline)):
                    print(f"The equation has a blank line in front of it - is this intentional? On line {line_number} in {input_file}.")
                if justblankline and inlisting:
                    print(f"The line before the code listing is blank, on line {line_number} in {input_file}.")
                    print("    This can lead to large gaps between text and code. Did you mean to?")

            justblankline = 0

            if re.search(r'begin\{figure}', theline) or re.search(r'begin\{tikzpicture}', theline):
                infigure = 1
                subfigure = 0
            if re.search(r'begin\{gather}', theline):
                inequation = 1
            if re.search(r'begin\{tabbing}', theline):
                inequation = 1
            if re.search(r'begin\{falign}', theline):
                inequation = 1
            if re.search(r'begin\{verbatim}', theline):
                inequation = 1
            if 'begin{quote}' in theline:
                inquote = 1
            if 'begin{tabular' in theline:
                # turn off equation tests, too, in tables
                intable = 1
                inequation = 1

            # let the main testing begin!
            if inlisting and (testlisting > 0):
                if (not ok and
                        'label=' not in theline and
                        'caption=' not in theline and
                        'language=' not in theline and
                        'morekeywords=' not in theline and
                        'basicstyle=' not in theline and
                        'mathescape=' not in theline):
                    # A ] will end the definitions.
                    if not insidecode and ']' in theline:
                        insidecode = 1
                    if insidecode:
                        # OK, real code, I think. Figure out character count
                        codestr = untouchedtheline
                        if not tabsfound and 't' in codestr:
                            print(f"***TABS FOUND IN LISTING: first found on line {line_number} in {input_file}.")
                            tabsfound = 1
                        if '$' in codestr:
                            print(f">>>EQUATION FOUND IN LISTING on line {line_number} in {input_file}.")
                        # expand tabs to spaces, four spaces to the tab.
                        codestr = codestr.expandtabs(4)
                        # convert references to equation numbers, roughly using 5 spaces.
                        codestr = re.sub(r'\\ref\{[\w_:-]+}', 'X.X', codestr)
                        # remove all $ for math equations
                        codestr = re.sub(r'\$', '', codestr)
                        codelen = len(codestr)
                        if codelen > testlisting:
                            print(f"CODE POSSIBLY TOO LONG: {codelen} characters on line {line_number} in {input_file}.")
                            print(f"    code: {codestr}")

            # ------------------------------------------
            # Check doubled words. Possibly the most useful test in the whole script
            m = re.search(r'(?:\b(\w+)\b) (?:\1(?: |$))+', lctwoline)
            if not twook and not infigure and not intable and not inequation and m and m.group(1) != 'em':
                if textonly:
                    duplicate_count += 1
                # lazy coding: duplicate_count never increases if a .tex file
                if duplicate_count <= 5:
                    print(f"SERIOUS: word duplication problem of word '{m.group(1)}' on line {line_number} in {input_file}.")
                if textonly:
                    if duplicate_count <= 5:
                        print("    Since this is a text file, this warning might be spurious.")
                    if duplicate_count == 5:
                        print("    *** Five duplicates found, which is unlikely, so further warnings are suppressed.")

            # surprisingly common
            if not twook and ' a the ' in lctwoline:
                print(f"SERIOUS: 'a the' to 'the' on line {line_number} in {input_file}.")
            if not twook and ' the a ' in lctwoline:
                print(f"SERIOUS: 'the a' to 'the' on line {line_number} in {input_file}.")

            # ---------------------------------------------------------
            # bibitem stuff, if you use this style. bibitems are assumed to be in refs.tex
            if isref and 'bibitem' in prev_line:
                # does next line have a " and " without a "," before the space?
                if not ok:
                    m_and = re.search(r' and ', theline)
                    m_andc = re.search(r' and,', theline)
                    if m_and or m_andc:
                        m_test = m_and if m_and else m_andc
                        prematch = theline[:m_test.start()]
                        if len(prematch) == 0 or prematch[-1] != ',':
                            print(f"SERIOUS: {refstex} has an author line with \"and\" but no comma before the \"and\", on line {line_number} in {input_file}.")
                # does line not have a "," at the end?
                if not ok and not re.search(r',$', theline) and not re.search(r'``', theline):
                    print(f"SERIOUS: {refstex} has an author line without a comma at the end, on line {line_number} in {input_file}.")
                    print("  (or, put all authors on one line, please.)")
                # does last name of first author not have a comma after it?
                if not ok:
                    bibname = theline.split()
                    if len(bibname) >= 1:
                        if (not re.search(r',$', bibname[0]) and
                                '``' not in bibname[0] and
                                '\\em' not in bibname[0] and
                                bibname[0].lower() != "de" and
                                bibname[0].lower() != "do" and
                                bibname[0].lower() != "el" and
                                bibname[0].lower() != "van" and
                                bibname[0].lower() != "nvidia" and
                                bibname[0].lower() != "team" and
                                bibname[0].lower() != r"nie\ss" and
                                bibname[0].lower() != "di"):
                            print(f"SERIOUS: {refstex} first author ''{bibname[0]}, firstname'' has no comma at end of last name, on line {line_number} in {input_file}.")

            # ---------------------------------------------------------
            # citation problem: use a ~ instead of a space so that the citation is connected with the content before it.
            if not twook and not infigure and re.search(r'[\s\w\.,}]\\cite\{', twoline):
                print(f"\\cite needs a tilde ~\\cite before citation to avoid separation, on line {line_number} in {input_file}.")
            # has the tilde, but there's a space before the tilde
            if not twook and re.search(r'\s~\\cite\{', twoline):
                print(f"\\cite - remove the space before the tilde ~\\cite, on line {line_number} in {input_file}.")
            if not ok and '\\cite{}' in theline:
                print(f"SERIOUS: \\cite is empty, on line {line_number} in {input_file}.")
            if not ok and '/cite{' in theline:
                m = re.search(r'/cite\{', theline)
                print(f"SERIOUS: '/cite' {m.group()} problem, should use backslash, on line {line_number} in {input_file}.")
            if not ok and '/ref{' in theline and not ('{eps' in theline or '{figures' in theline) and not isref:
                m = re.search(r'/ref\{', theline)
                print(f"SERIOUS: '/ref' {m.group()} problem, should use backslash, on line {line_number} in {input_file}.")
            # yes, use twoline here.
            if (not ok and not inequation and not infigure and '\\ref{' in theline and
                    not ('figure' in lctwoline or 'chapter' in lctwoline or
                         'section' in lctwoline or 'equation' in lctwoline or
                         'table' in lctwoline or 'listing' in lctwoline or
                         'appendix' in lctwoline or
                         'fig.' in lctwoline or 'ch.' in lctwoline or
                         'sec.' in lctwoline or 'eq.' in lctwoline)):
                print(f"SERIOUS: '\\ref' doesn't have 'Figure', 'Section', 'Equation', 'Table', or 'Appendix'")
                print(f"    or an abbreviation for these - Fig., Ch., Sec., Eq.")
                print(f"    in front of it, on line {line_number} in {input_file}.")
            if not ok and '/label{' in theline:
                m = re.search(r'/label\{', theline)
                print(f"SERIOUS: '/label' {m.group()} problem, should use backslash, on line {line_number} in {input_file}.")

            # ----------------------------------------------------------
            # index entry tests
            if not ok and '/index{' in theline and not isref:
                print(f"SERIOUS: '/index' should be \\index, on line {line_number} in {input_file}.")
            if not ok and '\\index' in theline and not isref:
                # look at index entry - only looks at first one in line, though.
                m = re.search(r'\\index', theline)
                index_rest = theline[m.end():]
                if ('|' in index_rest and
                        '|see' not in index_rest and
                        '|nn' not in index_rest and
                        '|emph' not in index_rest and
                        '|(' not in index_rest and
                        '|)' not in index_rest):
                    print(f"SERIOUS: '\\index' has a '|' without a 'see' or similar after it, on line {line_number} in {input_file}. Did you mean '!'?")

            # reference needs tilde
            if not ok:
                m = re.search(r'[\s\w\.,}]\\ref\{', theline)
                if m:
                    testit = theline[:m.start()]
                    if not re.search(r'and$', testit) and not re.search(r',$', testit):
                        print(f"\\ref needs a tilde ~\\ref before reference, on line {line_number} in {input_file}.")

            # pageref needs tilde
            if not ok:
                m = re.search(r'[\s\w\.,}]\\pageref\{', theline)
                if m:
                    testit = theline[:m.start()]
                    if not re.search(r'and$', testit) and not re.search(r',$', testit):
                        print(f"\\pageref needs a tilde ~\\pageref before reference, on line {line_number} in {input_file}.")

            # if it says "page" before the reference
            if not ok and 'page~\\ref' in theline:
                print(f"\\ref should probably be a \\pageref on line {line_number}")

            # cite should have a \ before this keyword
            if not ok and '~cite{' in theline:
                print(f"'cite' is missing a leading \\ for '\\cite' on line {line_number} in {input_file}.")
            if style and 'see~\\cite{' in theline:
                print(f"do not use `see~\\cite', on line {line_number} in {input_file} - do not consider citations something you can point at.")
            # ref should have a \ before this keyword
            if not ok and '~ref{' in theline:
                print(f"'ref' is missing a leading \\ for '\\ref' on line {line_number} in {input_file}.")
            # pageref should have a \ before this keyword
            if not ok and '~pageref{' in theline:
                print(f"'pageref' is missing a leading \\ for \\pageref on line {line_number} in {input_file}.")

            str_val = theline
            # label used twice; also check for label={code} in listings
            if ('\\label{' in str_val or
                    ('label=' in str_val and
                     'xlabel=' not in str_val and
                     'ylabel=' not in str_val and
                     'label=\\' not in str_val)):
                foundlabel = 0
                while True:
                    m = re.search(r'\\label\{([\w_:#\-\s]+)}', str_val)
                    if not m:
                        m = re.search(r'label=\{([\w_:#\-\s]+)}', str_val)
                    if not m:
                        m = re.search(r'label=([\w_:#\-\s]+)', str_val)
                    if not m:
                        break
                    str_val = str_val[m.end():]
                    foundlabel = 1
                    lbl = m.group(1)
                    if labels and lbl in label:
                        print(f"CRITICAL ERROR: duplicate label '{lbl}' - change it in this file to be unique.")
                    # don't really need to check for unused label if label is in a subfigure.
                    labelimportant[lbl] = not subfigure
                    label[lbl] = input_file
                    if infigure:
                        figlabel = input_file
                        labelfigure[lbl] = 1
                    if ok:
                        # there are some weird ways to reference figures, so allow us to mark labels as referenced manually
                        ref[lbl] = input_file
                if foundlabel == 0:
                    print(f"INTERNAL ERROR: a label was found but not properly parsed by chex_latex, on line {line_number} in {input_file}.")

            str_val = theline
            # record the refs for later comparison
            while True:
                m = re.search(r'\\ref\{([\w_:-]+)}', str_val)
                if not m:
                    break
                str_val = str_val[m.end():]
                ref[m.group(1)] = input_file

            str_val = theline
            while True:
                m = re.search(r'\\pageref\{([\w_:-]+)}', str_val)
                if not m:
                    break
                str_val = str_val[m.end():]
                ref[m.group(1)] = input_file

            str_val = theline
            while True:
                m = re.search(r'\\Cref\{([\w_:-]+)}', str_val)
                if not m:
                    break
                str_val = str_val[m.end():]
                ref[m.group(1)] = input_file

            if (not twook and re.search(r'\w\|\}', twoline) and re.search(r'\\index\{', twoline) and
                    not inequation and not intable and '\\frac' not in twoline):
                m = re.search(r'\w\|\}', twoline)
                print(f"SERIOUS: bad index end at {m.group()}, change to char}}, on line {line_number} in {input_file}.")
            if not twook and '(|}' in twoline:
                print(f"SERIOUS: bad index start at (||}}, change to |(}}, on line {line_number} in {input_file}.")

            if '\\caption{' in theline or '\\captionof{' in theline:
                figcaption = 'has a caption'
            if '\\begin{tabular}' in theline:
                figcenter = 'has centering via tabular'

            # -----------------------------------------------
            # bibitem related
            str_val = theline
            # for bibitems, did prev_line (i.e., the previous bibitem) end with a period?
            m = re.search(r'\\bibitem\{([\w_\']+)}', str_val)
            if m:
                # chop last char from prev_real_line
                k = prev_real_line[-1] if len(prev_real_line) > 0 else ''
                kk = prev_real_line[-2] if len(prev_real_line) > 1 else ''
                if k != '.' and kk != '.' and not ignore_first:
                    print(f"no period on around line {lastl} in {input_file}.")
                ignore_first = 0
                foundref = 1

            while True:
                m = re.search(r'\\bibitem\{([\w_\']+)}', str_val)
                if not m:
                    break
                str_val = str_val[m.end():]
                if m.group(1) in bibitem:
                    print(f"ERROR: duplicate bibitem {m.group(1)}")
                bibitem[m.group(1)] = input_file
                biborder[m.group(1)] = numbib
                numbib += 1

            str_val = theline
            while True:
                m = re.search(r'\\cite\{([\w_,\'\s*]+)}', str_val)
                if not m:
                    break
                str_val = str_val[m.end():]
                citelist = m.group(1)
                subf = m.group(1).replace(' ', '')
                fldc = subf.split(',')
                if len(fldc) > 1:
                    # more than one citation, keep for checking alpha order later
                    citeorder.append(subf)
                    citeloc.append(f"{line_number} in {input_file}")
                if len(fldc) >= 1:
                    for c in fldc:
                        cite[c] = input_file
                else:
                    cite[m.group(1)] = cite.get(m.group(1), '') + input + ' '

            # digits with space, some european style, use commas instead
            m = re.search(r'\d \d\d\d', theline)
            if not ok and not textonly and not infigure and m:
                print(f"POSSIBLY SERIOUS: digits with space '{m.group()}' might be wrong")
                print(f"    Use commas, e.g., '300 000' should be '300,000' on line {line_number} in {input_file}.")

            # ----------------------------------------------------------------
            # Punctuation
            # always test for the following, as these are dumb
            if not ok and 'i.~e.' in theline:
                print(f"SERIOUS: don't put a space in 'i.e.', remove the tilde ~ on line {line_number} in {input_file}.")
                period_problem = 1
            if not ok and 'i. e.' in theline:
                print(f"SERIOUS: don't put a space in 'i.e.' on line {line_number} in {input_file}.")
                period_problem = 1
            if not ok and 'e.~g.' in theline:
                print(f"SERIOUS: don't put a space inside 'e.g.', remove the tilde ~ on line {line_number} in {input_file}.")
                period_problem = 1
            if not ok and 'e. g.' in theline:
                print(f"SERIOUS: don't put a space inside 'e.g.' on line {line_number} in {input_file}.")
                period_problem = 1

            if dashes:
                # single dash should be ---
                if not ok and not textonly and ' - ' in theline and not inequation:
                    if '$' not in twoline:
                        print(f"SERIOUS: change ' - ' to '---' on line {line_number} in {input_file}.")
                # -- to ---, if words on both sides
                if not twook and not textonly and not isref and not inequation:
                    m = re.search(r'[a-z]--\w', lctwoline)
                    if m and '--based' not in lctheline:
                        prematch = lctwoline[:m.start()]
                        if '$' not in prematch:
                            print(f"possibly serious: change '--' (short dash) to '---' on line {line_number} in {input_file}, unless you are specifying a range or a pair of researchers, such as Cook--Torrance, or something not normally hyphenated, such as New York--based.")
                            print("    You can use the -d option on the command line to turn off all dash warnings.")

            if usstyle:
                # U.S. style: period goes inside the quotes
                if not ok and "''." in theline:
                    m = re.search(r"''\.", theline)
                    prematch = theline[:m.start()]
                    if '$' not in prematch:
                        print(f"SERIOUS: U.S. punctuation rule, change ''. to .'' on line {line_number} in {input_file}.")
                # U.S. punctuation test for commas
                if not ok and "''," in theline and 'gotcha' not in theline:
                    print(f"SERIOUS: U.S. punctuation rules state that '', should be ,'' on line {line_number} in {input_file}.")

                # U.S. spelling preferences
                if not ok and 'modelling' in lctheline and not isref:
                    print(f"In the U.S., we prefer 'modeling' to 'modelling' on line {line_number} in {input_file}.")
                if not ok and 'modelled' in lctheline and not isref:
                    print(f"In the U.S., we prefer 'modeled' to 'modelled' on line {line_number} in {input_file}.")

                # directional words
                us_direction_words = [
                    ('outwards', 'outward'),
                    ('inwards', 'inward'),
                    ('towards', 'toward'),
                    ('backwards', 'backward'),
                    ('afterwards', 'afterward'),
                    ('upwards', 'upward'),
                    ('downwards', 'downward'),
                ]
                for brit, amer in us_direction_words:
                    if not ok and not isref and re.search(brit, lctheline):
                        print(f"In the U.S., '{brit}' is not as popular as '{amer}' on line {line_number} in {input_file}.")

                # forwards is special
                if not ok and not isref and 'forwards' in lctheline:
                    print(f"In the U.S., 'forwards' is not as popular as 'forward', unless used as ''forwards mail'' etc., on line {line_number} in {input_file}.")

                if not ok and not isref and 'grey' in lctheline:
                    print(f"In the U.S., change 'grey' to 'gray' on line {line_number} in {input_file}.")
                if not ok and not isref and 'haloes' in lctheline:
                    print(f"In the U.S., change 'haloes' to 'halos' on line {line_number} in {input_file}.")
                if not ok and not isref and 'focuss' in lctheline:
                    print(f"In the U.S., change 'focuss*' to 'focus*', don't double the s's, on line {line_number} in {input_file}.")
                if not ok and not isref and 'parametriz' in lctheline:
                    print(f"In the U.S., change 'parametrization' to 'parameterization' on line {line_number} in {input_file}.")

                # i.e. and e.g. comma rules
                if not twook and ('i.e. ' in twoline or 'i.e.~' in twoline):
                    print(f"Nomrally, in the U.S. 'i.e.' usually has a comma after it, not a space - if nothing else, make sure you choose one or the other and stick with it; on line {line_number} in {input_file}.")
                    period_problem = 1
                if not ok and 'i.e.:' in theline:
                    print(f"SERIOUS: in the U.S. 'i.e.' should have a comma after it, not a colon, on line {line_number} in {input_file}.")
                    period_problem = 1
                if not twook and ('e.g. ' in twoline or 'e.g.~' in twoline):
                    print(f"SERIOUS: in the U.S. 'e.g.' usually has a comma after it, not a space - if nothing else, make sure you choose one or the other and stick with it; on line {line_number} in {input_file}.")
                    period_problem = 1
                if not ok and 'e.g.:' in theline:
                    print(f"SERIOUS: in the U.S. 'e.g.' should have a comma after it, not a colon, on line {line_number} in {input_file}.")
                    period_problem = 1

                # British spellings
                british_spellings = [
                    (r'parameterisation', "The British spelling 'parameterisation' should change to 'parameterization'"),
                    (r'signalled', "The British spelling 'signalled' should change to 'signaled',"),
                    (r'diagonalis', "The British spelling 'diagonalis*' should change to 'diagonaliz*'"),
                    (r'visualis', "The British spelling 'visualis*' should change to 'visualiz*'"),
                    (r'quantis', "The British spelling 'quantis*' should change to 'quantiz*'"),
                    (r'fulfils', "The spelling 'fulfils' should change to the U.S. spelling 'fulfills',"),
                    (r'artefact', "The British spelling 'artefact' should change to 'artifact'"),
                    (r'behaviour', "The British spelling 'behaviour' should change to 'behavior'"),
                    (r'neighbour', "The British spelling 'neighbour' should change to 'neighbor'"),
                    (r'favour', "The British spelling 'favour' should change to 'favor'"),
                    (r'analyse', "The British spelling 'analyse' should change to 'analyze'"),
                    (r'discretis', "The British spelling 'discretis*' should change to 'discretiz*'"),
                    (r'generalis', "The British spelling 'generalis*' should change to 'generaliz*'"),
                    (r'emphasise', "The British spelling 'emphasise' should change to 'emphasize'"),
                    (r'parametris', "The British spelling 'parametris*' should change to 'parametriz*'"),
                    (r'summarise', "The British spelling 'summarise' should change to 'summarize'"),
                    (r'theatre', "The British spelling 'theatre' should change to 'theater'"),
                ]
                for pattern, msg in british_spellings:
                    # Some checks require not isref, some don't. Check original Perl for each.
                    # signalled, diagonalis, visualis, quantis, fulfils need not isref
                    # parameterisation doesn't. artefact-theatre don't in original (but they do check !$ok).
                    needs_not_isref = pattern in ['signalled', 'diagonalis', 'visualis', 'quantis', 'fulfils']
                    if not ok and re.search(pattern, lctheline):
                        if needs_not_isref and isref:
                            continue
                        print(f"{msg} on line {line_number} in {input_file}.")

                # fulfil (not fulfils) - uses twoline
                if not twook and not isref and 'fulfil ' in lctwoline:
                    print(f"The spelling 'fulfil' should change to the U.S. spelling 'fulfill', on line {line_number} in {input_file}.")

                if not ok and 'acknowledgement' in lctheline and not isref:
                    print(f"'acknowledgement' to U.S. spelling 'acknowledgment' (delete second 'e' - really!) on line {line_number} in {input_file}.")
                if not ok and 'judgement' in lctheline and not isref:
                    print(f"Optional but recommended: 'judgement' to more common U.S. spelling 'judgment' on line {line_number} in {input_file}.")

            # see https://english.stackexchange.com/questions/34378/etc-with-postpositioned-brackets-at-the-end-of-a-sentence
            if not twook:
                m = re.search(r' etc', twoline)
                if m:
                    postmatch = twoline[m.end():]
                    if not postmatch.startswith('.'):
                        print(f"SERIOUS: 'etc' isn't followed by a '.' on line {line_number} in {input_file}.")

            if not twook and not isref and not textonly and not inequation and re.search(r'\. \d', twoline):
                print(f"A sentence should not start with a numeral (unless it's a year), on line {line_number} in {input_file}.")

            # ---------------------------------------------------------------
            # Continuation of while loop body processing each line of a LaTeX file.
            # Lines 1200-2100 of chex_latex.pl
            # ---------------------------------------------------------------

            # look for 3x and so on. Ignore if in something like ObjectToWorld3x4
            m = re.search(r'(\d+)x', lctheline)
            if not ok and not isref and not textonly and not inequation and m and not re.search(r'\w\d+x', lctheline) and not re.search(r' 0x', lctheline) and not re.search(r'\$', lctheline):
                print(f"Do not use {m.group(1)}x, use ${m.group(1)} \\times$, on line {line_number} in {input_file}.")
            if not ok and '/footnote' in theline:
                print(f"SERIOUS: change '/footnote' to '\\footnote' on line {line_number} in {input_file}.")
            if not ok and '~\\footnote' in theline:
                print(f"SERIOUS: change '~\\footnote' to '\\footnote' on line {line_number} in {input_file}.")
            # Great one, but you have to hand check the finds TODO END
            #if not twook and re.search(r'\w\\footnote', lctwoline):
            #    print(f"SERIOUS: 'w\\footnote' to ' \\footnote' on line {line_number} in {input_file}.")
            # flushright usually means someone's making a quote, so I guess two dashes is OK?
            # See https://www.complang.tuwien.ac.at/anton/latex/ltx-430.html for the quick summary of how to use dashes.
            if not ok and not textonly and dashes and (' -- ' in theline or ' --~' in theline) and 'flushright' not in theline:
                print(f"POTENTIALLY SERIOUS: change ' -- ' to the full dash '---' on line {line_number} in {input_file}.")
            if dashes and not intable and not twook and not textonly:
                if ' --- ' in twoline:
                    print(f"SERIOUS: ' --- ' should not have spaces before and after it, on line {line_number} in {input_file}.")
                elif '--- ' in twoline:
                    print(f"SERIOUS: '--- ' should not have a space after it, on line {line_number} in {input_file}.")
                elif ' ---' in twoline and not inquote and 'flushright' not in twoline:
                    print(f"SERIOUS: ' ---' should not have a space before it, on line {line_number} in {input_file}.")
            m = re.search(r'pp\. \d+-\d+', twoline)
            if not twook and isref and not textonly and m:
                print(f"ERROR: '{m.group()}' page number has only one dash, on line {line_number} in {input_file}.")
            m = re.search(r' \[\d+-\d+\]', twoline)
            if not twook and not isref and not textonly and m:
                print(f"ERROR: '{m.group()}' date range has only one dash, needs two, on line {line_number} in {input_file}.")
            else:
                m = re.search(r'\d+-\d+', theline)
                if not ok and not isref and not textonly and m and not inequation and '\\cite' not in theline and '$' not in theline and not re.search(r'^\\', theline):
                    print(f"ERROR: '{m.group()}' need two dashes between numbers, on line {line_number} in {input_file}.")
            m = re.search(r' \(\d+-\d+\)', theline)
            if not ok and not isref and not textonly and m and '$' not in theline:
                print(f"ERROR: '{m.group()}' date range needs to use brackets, [], not parentheses, and\n    has only one dash, needs two, on line {line_number} in {input_file}.")
            if not ok and '?-' in theline and isref:
                print(f"There's a ?- page reference (how do these get there? I think it's a hidden character before the first - from copy and paste of Computer Graphics Forum references), on line {line_number} in {input_file}.")
            if not ok and '/times' in theline:
                print(f"SERIOUS: change '/times' to '\\times' on line {line_number} in {input_file}.")
            #if not twook and isref and '--' not in twoline and '-' in twoline:
            #    print(f"Warning: '{theline}' in refs has only one dash, on line {line_number} in {input_file}.")
            # good, but must hand check:
            #if not twook and 'one dimensional' in twoline:
            #    print(f"'one dimensional' to 'one-dimensional' on line {line_number} in {input_file}.")

            # adding spaces is nice to do for readability, but not dangerous:
            #if not twook and re.search(r'\d\\times', twoline):
            #    print(f"left \\times problem on line {line_number} in {input_file}.")
            # nice to do for readability, but not dangerous:
            #if not twook and re.search(r'\\times\d', twoline):
            #    print(f"right \\times spacing problem on line {line_number} in {input_file}.")

            # Latex-specific
            # lots more foreign letters could be tested here... https://www.computerhope.com/issues/ch000657.htm
            if not ok and not textonly and (re.search(r'\u00e4', theline) or re.search(r'\u00f6', theline) or re.search(r'\u00fc', theline)):
                print(f"Some LaTeX tools don't like these: found an umlaut, use \\\"\u007bletter\u007d instead, on line {line_number} in {input_file}.")
            if not ok and not textonly and (re.search(r'\u00e1', theline) or re.search(r'\u00e9', theline) or re.search(r'\u00ed', theline) or re.search(r'\u00f3', theline) or re.search(r'\u00fa', theline)):
                print(f"Some LaTeX tools don't like these: found an accent, use \\'\u007bletter\u007d instead, on line {line_number} in {input_file}.")
            if not ok and not textonly and '<<< HEAD' in theline:
                print(f"SERIOUS: Unresolved merge problem, on line {line_number} in {input_file}.")
            if not twook and not textonly and '\\textregistered ' in twoline:
                print(f"Spacing: you probably want to change `\\textregistered ' to '\\textregistered\\ ' so that there is space after it, on line {line_number} in {input_file}.")
            if not ok and not textonly and re.search(r'\u2019', theline):
                print(f"Warning: you may need to change the nonstandard apostrophe to a proper LaTeX ' (vertical) apostrophe on line {line_number} in {input_file}.")
            elif not ok and not textonly and re.search(r'\u2018', theline):
                print(f"SERIOUS: change nonstandard single-quote mark to a proper LaTeX ` (vertical) apostrophe on line {line_number} in {input_file}.")
            if not ok and not textonly and re.search(r'\u2013', theline):
                print(f"SERIOUS: change nonstandard dash to a proper LaTeX - dash on line {line_number} in {input_file}.")
            # see https://www.maths.tcd.ie/~dwilkins/LaTeXPrimer/QuotDash.html
            if not ok and not textonly and not inequation and '"' in theline and '\\"' not in theline and not re.search(r'\w+"', theline):
                print(f"Note: the double apostrophe \" (used only for right-side quotes in LaTeX) should likely change to a `` or '' on line {line_number} in {input_file}.")
            if not ok and not textonly and not inequation and re.search(r'\u201d', theline) and not re.search(r'\\"', theline):
                print(f"SERIOUS: the double apostrophe should change to a '' on line {line_number} in {input_file}.")
            elif not ok and not textonly and not inequation and re.search(r'\u201c', theline) and not re.search(r'\\"', theline):
                print(f"SERIOUS: the double apostrophe should change to a '' on line {line_number} in {input_file}.")
            if not twook and not textonly and not inequation and " '" in twoline:
                if " ''" in twoline:
                    print(f"POSSIBLY SERIOUS: the first right double-apostrophe '' should probably be a left double-apostrophe ``, on line {line_number} in {input_file}.")
                elif not re.search(r" '[0-9]", twoline):
                    # not an abbreviation of the year, like '25
                    print(f"POSSIBLY SERIOUS: the first right apostrophe ' should probably be a left apostrophe , on line {line_number} in {input_file}.")
            if not twook and not textonly and not inequation and ' `' in twoline and ' ``' not in twoline:
                print(f"POSSIBLY SERIOUS: the left apostrophe ` should likely be a left double-apostrophe ``, on line {line_number} in {input_file}.")

            if not twook and not textonly and twoline and ' Corp. ' in twoline:
                print(f"'Corp. ' may need a backslash 'Corp.\\ ' to avoid a wide space after period\n    (unless it's the end of a sentence), on line {line_number} in {input_file}.")
            if not twook and not textonly and ' Inc. ' in twoline:
                print(f"'Inc. ' may need a backslash 'Inc.\\ ' to avoid a wide space after period\n    (unless it's the end of a sentence), on line {line_number} in {input_file}.")
            if not twook and not textonly and ' Ltd. ' in twoline:
                print(f"'Ltd. ' may need a backslash 'Ltd.\\ ' to avoid a wide space after period\n    (unless it's the end of a sentence), on line {line_number} in {input_file}.")
            # the false positives on this one vastly outweigh the true positives, e.g. "MSc (Tech.)\ at some university"
            # is a case where you would want the "\" but for a parenthetical sentence you want the full space after the period,
            # i.e., latex by default works fine.
            #if not twook and not textonly and not inequation and '.)' in twoline:
            #    print(f"POSSIBLY SERIOUS: '.)\\' - remove the \\ after it to avoid 'short' space, on line {line_number} in {input_file}.")
            # last bit on this line: if text, then ignore "..."
            # also ignore "../" as this could be an "include" path in an .html file
            if not textonly and '$' not in twoline and "''" not in twoline and '..' in twoline and '{..' not in twoline and not inequation and '...' not in twoline and '../' not in twoline:
                print(f"Doubled periods, on line {line_number} in {input_file}.")
            # if the first comma is backslashed, that means it's a thin unbreakable space, e.g., https://tex.stackexchange.com/questions/390995/what-is-the-difference-between-tilde-and-backslash-comma-for-a-nonbreak
            if not twook and not infigure and ',,' in twoline and '\\,,' not in twoline:
                print(f"Doubled commas, on line {line_number} in {input_file}.")
            # experimental...
            # Latex will by default make a "short space" after a capital letter followed by a period.
            # For example: Franklin D. Roosevelt. For longer sets of capital letters, e.g., GPU, DNA,
            # we want to have a "long space," as in: "There are many types of DNA.  We will discuss..."
            # Also ignore any line starting with a \ as it's probably some command, like \acmDOI{XXXXXXX.XXXXXXX}
            m = re.search(r'([A-Z][A-Z]+)\.', theline)
            if not ok and not textonly and not inequation and not infigure and m and not re.search(r'^\\', theline):
                print(f"Sentence ending in the capital letters '{m.group(1)}.' should instead be '{m.group(1)}\\@.' to have proper 'long' spacing after the period,\n    on line {line_number} in {input_file}.")
            m = re.search(r'([A-Z][A-Z]+)\)\.', theline)
            if not ok and not textonly and not inequation and not infigure and m:
                print(f"Sentence ending in the capital letters '{m.group(1)}' and ').' should instead be '{m.group(1)})\\@.' to have proper 'long' spacing after the period,\n    on line {line_number} in {input_file}.")

            if style and not twook and not textonly and ('Image Courtesy' in twoline or 'Images Courtesy' in twoline):
                print(f"Change 'Courtesy' to 'courtesy' on line {line_number} in {input_file}.")
            if not twook and not textonly and re.search(r'[\d+] ms', lctwoline):
                print(f"' ms' to '~ms' to avoid having the number separated from its units, on line {line_number} in {input_file}.")
            m = re.search(r'([\.\d]+)ms', theline)
            if style and not ok and not textonly and not isref and not inequation and m:
                print(f"Change '{m.group(1)}ms' to '{m.group(1)}~ms' (i.e., add a space), on line {line_number} in {input_file}.")
            if not twook and not textonly and re.search(r'[\d+] fps', lctwoline):
                print(f"' FPS' to '~FPS' to avoid having the number separated from its units, on line {line_number} in {input_file}.")
            m = re.search(r'(\d+)fps', theline)
            if style and not ok and not isref and not inequation and m:
                print(f"Change '{m.group(1)}FPS' to '{m.group(1)}~FPS' (i.e., add a space), on line {line_number} in {input_file}.")
            if style and not ok and 'fps' in theline:
                print(f"'fps' to 'FPS' on line {line_number} in {input_file}.")
            if not twook and not textonly and re.search(r'[\d+] spp', lctwoline):
                print(f"' SPP' to '~SPP' to avoid having the number separated from its units, on line {line_number} in {input_file}.")
            m = re.search(r'(\d+)spp', theline)
            if style and not ok and not isref and not inequation and m:
                print(f"Change '{m.group(1)}SPP' to '{m.group(1)}~SPP' (i.e., add a space), on line {line_number} in {input_file}.")
            if style and not ok and 'fps' in theline:
                print(f"'spp' to 'SPP' on line {line_number} in {input_file}.")
            if not twook and not textonly and re.search(r'[\d+] Hz', lctwoline):
                print(f"' Hz' to '~Hz' to avoid having the number separated from its units, on line {line_number} in {input_file}.")
            m = re.search(r'(\d+)hz', lctheline)
            if style and not ok and not isref and not inequation and m:
                print(f"Change '{m.group(1)}Hz' to '{m.group(1)}~Hz' (i.e., add a space), on line {line_number} in {input_file}.")
            m = re.search(r'(\d+)K ', theline)
            if style and not ok and not isref and not inequation and m:
                print(f"Change '{m.group(1)}K' to '{m.group(1)}k' (i.e., lowercase 'k'), on line {line_number} in {input_file}.")
            m = re.search(r'(\d+) k ', lctwoline)
            if style and not twook and not isref and not inequation and m:
                print(f"Change '{m.group(1)} k' to '{m.group(1)}k' (i.e., lowercase 'k'), on line {line_number} in {input_file}.")
            # ----------------------------------
            # Style: comma and period punctuation
            if formal and not twook and re.search(r'\w\se\.g\.', twoline):
                print(f"SERIOUS: ' e.g.' does not have a comma before it, on line {line_number} in {input_file}.")
            if formal and not twook and ' et al' in lctwoline:
                m = re.search(r' et al(.*)', lctwoline)
                if m:
                    post = m.group(1)
                    if not re.search(r'^\.', post) and not re.search(r'^ia', post):
                        print(f"'et al' is not followed by '.', i.e., 'et al.', on line {line_number} in {input_file}.")
            if not twook and ' et alia' in lctwoline:
                print(f"Use 'et al.\\ ' instead of 'et alia', on line {line_number} in {input_file}.")
            if not twook and 'et. al' in twoline:
                print(f"Change 'et. al.' to 'et al.' (no first period), on line {line_number} in {input_file}.")
            if not twook and re.search(r'et al\.~\\cite\{\w+\}\s+[A-Z]', twoline):
                print(f"et al. citation looks like it needs a period after the citation, on line {line_number} in {input_file}.")
            # see https://english.stackexchange.com/questions/121054/which-one-is-correct-et-al-s-or-et-al
            # and https://forum.wordreference.com/threads/how-to-use-the-possessive-s-with-et-al.1621357/
            # Typical rewrite of "Marquando et al.'s work" is "The work by Marquando et al."
            if formal and "et al.'s" in lctwoline:
                print(f"Rewrite to avoid 'et al.'s', which is half Latin, half English, on line {line_number} in {input_file}.")
            if not twook and not textonly and ' al. ' in twoline:
                print(f"POSSIBLY SERIOUS: change 'et al.' to 'et al.\\ ' if you are not ending a sentence, on line {line_number} in {input_file}.")
                period_problem = 1
            if not twook and not inequation and not textonly and ' . ' in twoline:
                print(f"SERIOUS: change ' .' to '.' (remove space in front of period), on line {line_number} in {input_file}.")
            if not twook and not textonly and not inequation and ' ,' in twoline and 'ldots ,' not in twoline:
                print(f"SERIOUS: change ' ,' to ',' (remove space in front of comma), on line {line_number} in {input_file}.")
            # If you use a ".", you need to do something like ".~" to avoid having the period treated
            # as if it's the end of a sentence, which causes a bit of additional space to get added after it.
            # Easiest is to just spell out vs.
            if not twook and not isref and not textonly and ' vs. ' in twoline:
                print(f"SERIOUS: change 'vs.' to 'versus' to avoid having a 'double-space' appear after the period,\n    or use 'vs.\\ ' on line {line_number} in {input_file}.")
            if formal and not twook and not isref and ' vs ' in twoline:
                print(f"SERIOUS: change 'vs' to 'versus' on line {line_number} in {input_file}")
            if not twook and not isref and not textonly and re.search(r' etc\. [a-z]', twoline):
                print(f"POSSIBLY SERIOUS: you may need to change 'etc.' to 'etc.\\ ' to avoid having a 'double-space'\n    appear after the period, on line {line_number} in {input_file}.\n    (To be honest, it's better to avoid 'etc.' altogether, as it provides little to no information.)")
                period_problem = 1

            # ---------------------------------------------------
            # grammatical, or other word-related problems
            if not ok and 'TODO' in theline:
                print(f"Beware, there is a TODO in the text itself at line {line_number} in {input_file}.")
                print(f"    the line says: {theline}")
            # common misspellings
            if 'frustrum' in lctheline:
                print(f"MISSPELLING: 'frustrum' to 'frustum' on line {line_number} in {input_file}.")
            if 'octtree' in lctheline:
                print(f"MISSPELLING: 'octtree' to 'octree' on line {line_number} in {input_file}.")
            if 'hierarchal' in lctheline:
                print(f"MISSPELLING: 'hierarchal' to 'hierarchical' on line {line_number} in {input_file}.")
            if 'hierarchial' in lctheline:
                print(f"MISSPELLING: 'hierarchial' to 'hierarchical' on line {line_number} in {input_file}.")
            if 'descendent' in lctheline:
                print(f"Likely misspelled, unless used as an adjective: 'descendent' to 'descendant' on line {line_number} in {input_file}.")
            if not inequation and ' hermite' in twoline:
                print(f"MISSPELLING: 'hermite' to 'Hermite', on line {line_number} in {input_file}.")
            if not inequation and ' phong' in twoline:
                print(f"MISSPELLING: 'phong' to 'Phong', on line {line_number} in {input_file}.")
            if not inequation and ' gouraud' in twoline:
                print(f"MISSPELLING: 'gouraud' to 'Gouraud', on line {line_number} in {input_file}.")
            # more style oriented - normally useful, but you can turn it off with -s
            if style:
                if not twook and not textonly and re.search(r'\. [a-z]', twoline) and not re.search(r'a\.k\.a\.', twoline) and not re.search(r'\.\.\.', twoline) and not isref and not inequation and not period_problem:
                    print(f"Not capitalized at start of sentence{'' if textonly else ' (or the period should have a \\\\ after it)'}, on line {line_number} in {input_file}.")
                # we like to avoid ending a sentence with a preposition.
                if not twook and ' with. ' in twoline:
                    print(f"consider: 'with.' at end of sentence on line {line_number} in {input_file}. Reword if it's not convoluted to do so.")
                if not ok and 'Javascript' in theline:
                    print(f"Please change 'Javascript' to 'JavaScript' on line {line_number} in {input_file}.")
                # see https://linguaholic.com/linguablog/comma-before-or-after-thus/
                if 'Thus ' in theline:
                    print(f"You likely want a comma after 'Thus' on line {line_number} in {input_file}.")
                if 'However ' in theline:
                    print(f"You likely want a comma after 'However' on line {line_number} in {input_file}.")
                if 'Fortunately ' in theline:
                    print(f"You likely want a comma after 'Fortunately' on line {line_number} in {input_file}.")
                if 'Additionally ' in theline:
                    print(f"You likely want a comma after 'Additionally' on line {line_number} in {input_file}.")
                if 'Therefore ' in theline:
                    print(f"You likely want a comma after 'Therefore' on line {line_number} in {input_file}.")
                if 'So ' in theline:
                    print(f"You likely want a comma after 'So' on line {line_number} in {input_file}.")
                if 'Indeed ' in theline:
                    print(f"You likely want a comma after 'Indeed' on line {line_number} in {input_file}.")
                if 'Finally ' in theline:
                    print(f"You likely want a comma after 'Finally' on line {line_number} in {input_file}.")
                # see https://www.grammarly.com/blog/commas-after-introductory-phrases/
                if 'For this reason ' in theline:
                    print(f"You likely want a comma after 'For this reason' on line {line_number} in {input_file}.")
                # your mileage may vary, depending on how you index, e.g., we do \index{k-d tree@$k$-d tree}
                if not twook and not textonly and not isref and 'k-d ' in lctwoline and 'k-d tree@' not in lctheline:
                    print(f"'k-d' to the more proper '$k$-d', on line {line_number} in {input_file}.")
                if not ok and not textonly and not isref and 'kd-tree' in lctheline:
                    print(f"'kd-tree' to the more proper '$k$-d tree', on line {line_number} in {input_file}.")
                if not twook and not textonly and not isref and 'kd tree' in lctwoline and 'kd tree@' not in lctheline:
                    print(f"'kd tree' to the more proper '$k$-d tree', on line {line_number} in {input_file}.")
                # leading space to avoid "n-bit mask" which would be fine
                if not twook and ' bit mask' in lctwoline:
                    print(f"'bit mask' to 'bitmask', on line {line_number} in {input_file}.")
                if not twook and 'screen space ambient' in lctwoline:
                    print(f"'screen space ambient' to 'screen-space ambient', on line {line_number} in {input_file}.")

                # -----------------------------
                # Clunky or wrong
                if not twook and ' to. ' in twoline:
                    print(f"SERIOUS: ending a sentence with 'to.' is not so great, on line {line_number} in {input_file}.")
                if not ok and not isref and 'irregardless' in lctheline and not inquote:
                    print(f"No, never use 'irregardless' on line {line_number} in {input_file}.")
                if not ok and not isref and 'na\\"ive' in lctheline and not inquote:
                    print(f"Change 'na\\\"ive' to good ole 'naive' on line {line_number} in {input_file}.")
                if not ok and not isref and 'necessitate' in lctheline and not inquote:
                    print(f"Please don't use 'necessitate' on line {line_number} in {input_file}.")
                if not ok and not isref and 'firstly' in lctheline and not inquote:
                    print(f"Do not say 'firstly' - say 'first' on line {line_number} in {input_file}.")
                if not ok and not isref and 'secondly' in lctheline and not inquote:
                    print(f"Do not say 'secondly' - say 'second' on line {line_number} in {input_file}.")
                if not ok and not isref and 'thirdly' in lctheline and not inquote:
                    print(f"Do not say 'thirdly' - say 'third' on line {line_number} in {input_file}.")
                if not ok and 'amongst' in lctheline:
                    print(f"Change 'amongst' to 'among' on line {line_number} in {input_file}.")
                if not twook and ' try and' in lctwoline:
                    print(f"Change 'try and' to 'try to' on line {line_number} in {input_file}, or reword to 'along with' or similar.")
                if not twook and 'relatively to ' in twoline:
                    print(f"tip: 'relatively to' probably wants to be 'relative to' on line {line_number} in {input_file}.")
                if not twook and not isref and 'so as to ' in lctwoline:
                    print(f"tip: you probably should replace 'so as to' with 'to' or similar on line {line_number} in {input_file}, or rewrite.\n    It's a wordy phrase.")
                    SAYOK()
                if not twook and 'due to that' in lctwoline:
                    print(f"tip: 'due to that' to 'because' on line {line_number} in {input_file}.")
                if not twook and 'more optimal' in lctwoline:
                    print(f"tip: 'more optimal' is illogical - 'optimal' means the best;\n    maybe try 'better optimized' on line {line_number} in {input_file}.")
                if not twook and 'more specifically' in lctwoline:
                    print(f"tip: 'more specifically' to 'specifically' on line {line_number} in {input_file}.")
                if not twook and 'made out of' in lctwoline:
                    print(f"shortening tip: replace 'made out of' with 'made from' on line {line_number} in {input_file}.")
                # optionally, remove infigure &&
                if not twook and infigure and 'as can be seen' in lctwoline:
                    print(f"shortening tip: remove 'as can be seen', since we are looking at a figure, on line {line_number} in {input_file}.")
                if not twook and not isref and 'due to the fact that' in lctwoline and not inquote:
                    print(f"tip: replace 'due to the fact that' with 'because' on line {line_number} in {input_file}.")
                if not ok and not isref and 'on account of' in lctheline and not inquote:
                    print(f"tip: change 'on account of/' to 'because' on line {line_number} in {input_file}.")
                if not ok and not isref and 'basically' in lctheline and not inquote:
                    print(f"tip: you can probably remove 'basically' on line {line_number} in {input_file}.")
                if not ok and not isref and 'orientate' in lctheline and not inquote:
                    print(f"tip: you probably don't want to use 'orientate' on line {line_number} in {input_file}.")
                if not ok and not isref and 'thusly' in lctheline and not inquote:
                    print(f"tip: change 'thusly' to 'thus' or 'therefore' on line {line_number} in {input_file}.")
                if not twook and not isref and 'point in time' in lctwoline and not inquote:
                    print(f"tip: avoid the wordy phrase 'point in time' at this point in time on line {line_number} in {input_file}.")
                if not ok and not isref and 'literally' in lctheline and not inquote:
                    print(f"tip: you can probably not use 'literally' (and may mean 'figuratively') on line {line_number} in {input_file}.")
                    SAYOK()
                if not twook and ' a lot more' in lctwoline:
                    print(f"tip: replace 'a lot' with 'much' on line {line_number} in {input_file}.")
                if not twook and 'and also ' in lctwoline:
                    print(f"tip: you probably should replace 'and also' with 'and' on line {line_number} in {input_file},\n    or reword to 'along with' or similar.")
                if not twook and 'the reason why is because' in lctwoline:
                    print(f"tip: 'the reason why is because' is crazy wordy, so rewrite, on line {line_number} in {input_file}.")
                if not twook and 'fairly straightforward' in lctwoline:
                    print(f"shortening tip: replace 'fairly straightforward' with 'straightforward' on line {line_number} in {input_file}.")
                # https://dict.leo.org/forum/viewGeneraldiscussion.php?idforum=4&idThread=331883&lp=ende
                if not ok and 'well-suited' in lctheline:
                    print(f"It is likely that 'well-suited' should be 'well suited', unless it's an adjective before a noun, on line {line_number} in {input_file}.")
                    SAYOK()
                # rules about hyphens: https://www.grammarbook.com/punctuation/hyphens.asp - Rule 3, "physically" is an adverb
                if not isref and 'physically-based' in lctheline:
                    print(f"'physically-based' should change to 'physically based' (adding the hyphen is becoming accepted, but it's incorrect, so let's fight that trend, OK? See the book 'Physically Based Rendering,' for example) on line {line_number} in {input_file}.")
                if not ok and 'ly-used' in lctheline:
                    print(f"'*ly-used' should probably change to '*ly used' on line {line_number} in {input_file}.")
                if not ok and 'bottom-left' in lctheline:
                    print(f"'bottom-left' should change to 'bottom left' on line {line_number} in {input_file}.")
                if not ok and 'bottom-right' in lctheline:
                    print(f"'bottom-right' should change to 'bottom right' on line {line_number} in {input_file}.")
                if not ok and 'top-left' in lctheline:
                    print(f"'top-left' should change to 'top left' on line {line_number} in {input_file}.")
                if not ok and 'top-right' in lctheline:
                    print(f"'top-right' should change to 'top right' on line {line_number} in {input_file}.")
                if not ok and 'lower-left' in lctheline:
                    print(f"'lower-left' should change to 'lower left' on line {line_number} in {input_file}.")
                if not ok and 'lower-right' in lctheline:
                    print(f"'lower-right' should change to 'lower right' on line {line_number} in {input_file}.")
                if not ok and 'upper-left' in lctheline:
                    print(f"'upper-left' should change to 'upper left' on line {line_number} in {input_file}.")
                if not ok and 'upper-right' in lctheline:
                    print(f"'upper-right' should change to 'upper right' on line {line_number} in {input_file}.")
                # always hyphenated
                if 'view dependent' in lctwoline:
                    print(f"'view dependent' should change to 'view-dependent' on line {line_number} in {input_file}.")
                if 'view independent' in lctwoline:
                    print(f"'view independent' should change to 'view-independent' on line {line_number} in {input_file}.")
                if WORDTEST(lctwoline, "defacto ", lcprev_line, "defacto"):
                    print(f"SERIOUS: change 'defacto' to 'de facto' on line {line_number} in {input_file}.")
                # from Dreyer's English, a great book, from "The Trimmables", phrases that can be shortened without loss
                if not twook and not isref and 'absolutely certain' in lctwoline:
                    print(f"'absolutely certain' can shorten to 'certain' on line {line_number} in {input_file}.")
                if not twook and not isref and 'absolutely certain' in lctwoline:
                    print(f"'absolute certainty' can shorten to 'certainty' on line {line_number} in {input_file}.")
                if not twook and not isref and 'absolutely essential' in lctwoline:
                    print(f"'absolutely essential' can shorten to 'essential' on line {line_number} in {input_file}.")
                if not twook and not isref and 'all-time record' in lctwoline:
                    print(f"'all-time record' can shorten to 'record' on line {line_number} in {input_file}.")
                if not twook and not isref and 'advance planning' in lctwoline:
                    print(f"'advance planning' can shorten to 'planning' on line {line_number} in {input_file}.")
                if not twook and not isref and 'advance warning' in lctwoline:
                    print(f"'advance warning' can shorten to 'warning' on line {line_number} in {input_file}.")
                if not twook and not isref and 'blend together' in lctwoline:
                    print(f"'blend together' can shorten to 'blend' on line {line_number} in {input_file}.")
                if not twook and not isref and 'close proximity' in lctwoline:
                    print(f"Your call: 'close proximity' can shorten to 'proximity' on line {line_number} in {input_file}.\n    'close proximity' is a common phrase but is often redundant; 'proximity' might do.")
                if not twook and not isref and 'blend together' in lctwoline:
                    print(f"'blend together' can shorten to 'blend' on line {line_number} in {input_file}.")
                if not twook and not isref and 'general consensus' in lctwoline:
                    print(f"'general consensus' can shorten to 'consensus' on line {line_number} in {input_file}.")
                if not twook and not isref and 'continue on ' in lctwoline:
                    print(f"'continue on' can shorten to 'continue' on line {line_number} in {input_file}.")
                if not twook and not isref and 'disappear from sight' in lctwoline:
                    print(f"'disappear from sight' can shorten to 'disappear' on line {line_number} in {input_file}.")
                if not twook and not isref and 'earlier in time' in lctwoline:
                    print(f"'earlier in time' can shorten to 'earlier' on line {line_number} in {input_file}.")
                if not twook and not isref and 'end product' in lctwoline:
                    print(f"'end product' can shorten to 'product' on line {line_number} in {input_file}.")
                if not twook and not isref and 'end result' in lctwoline:
                    print(f"'end result' can shorten to 'result' (if you are comparing to an intermediate result, how about 'ultimate result'?) on line {line_number} in {input_file}.")
                if not twook and not isref and 'equally as ' in lctwoline:
                    print(f"'equally as' can shorten to 'equally' or 'as' - don't use both on line {line_number} in {input_file}.")
                if not twook and not isref and 'exact same' in lctwoline:
                    print(f"'exact same' can shorten to 'same' on line {line_number} in {input_file}.")
                if not twook and not isref and 'fall down ' in lctwoline:
                    print(f"'fall down' can shorten to 'fall' on line {line_number} in {input_file}.")
                if not twook and not isref and 'fetch back ' in lctwoline:
                    print(f"'fetch back' can shorten to 'fetch' on line {line_number} in {input_file}.")
                if not twook and not isref and 'few in number' in lctwoline:
                    print(f"'few in number' can shorten to 'few' on line {line_number} in {input_file}.")
                if not twook and not isref and 'final outcome' in lctwoline:
                    print(f"'final outcome' can shorten to 'outcome' on line {line_number} in {input_file}.")
                if not twook and not isref and 'follow after' in lctwoline:
                    print(f"'follow after' can shorten to 'follow' on line {line_number} in {input_file}.")
                if not twook and not isref and 'from whence' in lctwoline:
                    print(f"'from whence' can shorten to 'whence' (since 'whence' means 'from where') on line {line_number} in {input_file}.")
                if not twook and not isref and 'full gamut' in lctwoline:
                    print(f"'full gamut' can shorten to 'gamut' ('gamut' is a full range of something) on line {line_number} in {input_file}.")
                if not twook and not isref and 'full extent' in lctwoline:
                    print(f"'full extent' can shorten to 'extent' ('extent' is its own range) on line {line_number} in {input_file}.")
                if not twook and not isref and 'broad spectrum' in lctwoline:
                    print(f"'broad spectrum' can shorten to 'spectrum' ('spectrum' means a full range) on line {line_number} in {input_file}.")
                if not twook and not isref and 'complete range' in lctwoline:
                    print(f"'complete range' can shorten to 'range' on line {line_number} in {input_file}.")
                if not twook and not isref and 'future plans' in lctwoline:
                    print(f"'future plans' can shorten to 'plans' on line {line_number} in {input_file}.")
                if not twook and not isref and 'gather together' in lctwoline:
                    print(f"'gather together' can shorten to 'gather' on line {line_number} in {input_file}.")
                if not twook and not isref and 'briefly glance' in lctwoline:
                    print(f"'briefly glance' can shorten to 'glance' on line {line_number} in {input_file}.")
                if not twook and not isref and 'glance briefly' in lctwoline:
                    print(f"'glance briefly' can shorten to 'glance' on line {line_number} in {input_file}.")
                if not twook and not isref and 'hollow tube' in lctwoline:
                    print(f"'hollow tube' can shorten to 'tube' on line {line_number} in {input_file}.")
                if not twook and not isref and 'on an hourly basis' in lctwoline:
                    print(f"'on an hourly basis' can shorten to 'hourly' on line {line_number} in {input_file}.")
                if not twook and not isref and 'on a daily basis' in lctwoline:
                    print(f"'on a daily basis' can shorten to 'daily' on line {line_number} in {input_file}.")
                if not twook and not isref and 'on a monthly basis' in lctwoline:
                    print(f"'on a monthly basis' can shorten to 'monthly' on line {line_number} in {input_file}.")
                if not twook and not isref and 'on a yearly basis' in lctwoline:
                    print(f"'on a yearly basis' can shorten to 'yearly' on line {line_number} in {input_file}.")
                if not twook and not isref and 'join together' in lctwoline:
                    print(f"'join together' can shorten to 'join' on line {line_number} in {input_file}.")
                if not twook and not isref and 'last of all' in lctwoline:
                    print(f"'last of all' might shorten to 'last' on line {line_number} in {input_file}.")
                if not twook and not isref and 'lift up' in lctwoline:
                    print(f"'lift up' can shorten to 'lift' on line {line_number} in {input_file}.")
                if not twook and not isref and 'merge together' in lctwoline:
                    print(f"'merge together' can shorten to 'merge' on line {line_number} in {input_file}.")
                if not twook and not isref and 'might possibly' in lctwoline:
                    print(f"'might possibly' can shorten to 'might' on line {line_number} in {input_file}.")
                if not twook and not isref and 'moment in time' in lctwoline:
                    print(f"'moment in time' can shorten to 'moment' on line {line_number} in {input_file}.")
                if not twook and not isref and 'more superior' in lctwoline:
                    print(f"'more superior' can shorten to 'superior' on line {line_number} in {input_file}.")
                if not twook and not isref and 'mutual cooperation' in lctwoline:
                    print(f"'mutual cooperation' can shorten to 'cooperation' on line {line_number} in {input_file}.")
                if not twook and not isref and 'orbit around' in lctwoline:
                    print(f"'orbit around' can shorten to 'orbit' on line {line_number} in {input_file}.")
                if not ok and not isref and 'overexaggerate' in lctheline and not inquote:
                    print(f"Do not say 'overexaggerate' - say 'exaggerate' on line {line_number} in {input_file}.")
                if not twook and not isref and 'past history' in lctwoline:
                    print(f"'past history' can shorten to 'history' on line {line_number} in {input_file}.")
                if not twook and not isref and 'personal opinion' in lctwoline:
                    print(f"'personal opinion' can shorten to 'opinion' on line {line_number} in {input_file}.")
                if not twook and not isref and 'plan ahead' in lctwoline:
                    print(f"'plan ahead' can shorten to 'plan' on line {line_number} in {input_file}.")
                if not ok and not isref and 'preplan' in lctheline and not inquote:
                    print(f"Do not say 'preplan' - say 'plan' on line {line_number} in {input_file}.")
                if not twook and not isref and 'raise up ' in lctwoline:
                    print(f"'raise up' can shorten to 'raise' on line {line_number} in {input_file}.")
                if not twook and not isref and ' reason why' in lctwoline:
                    print(f"'reason why' can shorten to 'reason', if you like, on line {line_number} in {input_file}.")
                if not twook and not isref and 'regular routine' in lctwoline:
                    print(f"'regular routine' can shorten to 'routine' on line {line_number} in {input_file}.")
                if not twook and not isref and 'recall back' in lctwoline:
                    print(f"'recall back' can shorten to 'recall' on line {line_number} in {input_file}.")
                if not twook and not isref and 'return back' in lctwoline:
                    print(f"'return back' can shorten to 'return' on line {line_number} in {input_file}.")
                if not twook and not isref and 'revert back' in lctwoline:
                    print(f"'revert back' can shorten to 'revert' on line {line_number} in {input_file}.")
                if not twook and not isref and ' rise up ' in lctwoline and not inquote:
                    print(f"'rise up' can shorten to 'rise' (Hamilton notwithstanding) on line {line_number} in {input_file}.")
                if not twook and not isref and 'short in length' in lctwoline and not inquote:
                    print(f"'short in length' can shorten to 'short' on line {line_number} in {input_file}.")
                if not twook and not isref and 'shuttle back and forth' in lctwoline and not inquote:
                    print(f"'shuttle back and forth' can shorten to 'shuttle' on line {line_number} in {input_file}.")
                if not twook and not isref and 'sink down ' in lctwoline and not inquote:
                    print(f"'sink down' can shorten to 'sink' on line {line_number} in {input_file}.")
                if not twook and not isref and 'skirt around' in lctwoline and not inquote:
                    print(f"'skirt around' can shorten to 'skirt' on line {line_number} in {input_file}.")
                if not twook and not isref and 'sudden impulse' in lctwoline and not inquote:
                    print(f"'sudden impulse' can shorten to 'impulse' on line {line_number} in {input_file}.")
                if not twook and not isref and 'surrounded on all sides' in lctwoline and not inquote:
                    print(f"'surrounded on all sides' can shorten to 'surrounded' on line {line_number} in {input_file}.")
                if not twook and not isref and 'undergraduate student' in lctwoline and not inquote:
                    print(f"'undergraduate student' can shorten to 'undergraduate' on line {line_number} in {input_file}.")
                if not twook and not isref and 'unexpected surprise' in lctwoline and not inquote:
                    print(f"'unexpected surprise' can shorten to 'surprise' on line {line_number} in {input_file}.")
                if not twook and not isref and 'unsolved myster' in lctwoline and not inquote:
                    print(f"'unsolved mystery' can shorten to 'mystery' on line {line_number} in {input_file}.")
                if not twook and not isref and 'usual custom' in lctwoline and not inquote:
                    print(f"'usual custom' can shorten to 'custom' on line {line_number} in {input_file}.")
            if formal:
                # -----------------------------
                # Formal style
                # See https://www.vappingo.com/word-blog/when-is-it-okay-to-use-contractions-in-formal-writing/
                # "Do not use contractions in documents that serve formal purposes, such as legal contracts,
                # [and] submissions to professional publications."
                # http://grammar.ccc.commnet.edu/grammar/numbers.htm
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " math ", lcprev_line, "math"):
                    print(f"For formal writing, 'math' should change to 'mathematics' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " got ", lcprev_line, "got"):
                    print(f"For formal writing, please do not use 'got' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not twook and ' lots of' in lctwoline and not inquote and (prev_line.lower() != "lots"):
                    print(f"For formal writing, change 'lots of' to 'many' or 'much' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                elif not twook and not isref and not inquote and WORDTEST(lctwoline, " lots ", lcprev_line, "lots"):
                    print(f"For formal writing, change 'lots' to 'many' or 'much' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " cheap ", lcprev_line, "cheap"):
                    print(f"Please use 'less costly' instead of 'cheap' as 'cheap' implies poor quality, on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                # see http://www.slaw.ca/2011/07/27/grammar-legal-writing/ for various style guides opinions (all against)
                if not ok and not isref and 'and/or' in lctheline and not inquote:
                    print(f"For formal writing, please do not use 'and/or' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not twook and ' a lot of ' in lctwoline and not inquote:
                    print(f"Avoid informal 'a lot of' - change to 'many,' 'much,' 'considerable,' or similar, on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                elif not twook and ' a lot ' in lctwoline and not inquote:
                    print(f"Avoid informal 'a lot' - change to 'much' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                # left out because of "can not only provide", which is fine
                #if not twook and 'can not ' in lctwoline:
                #    print(f"'can not' to 'cannot' on line {line_number} in {input_file}.")
                if not ok and "n't" in lctheline and not inquote and not isref:
                    print(f"SERIOUS: For formal writing, no contractions: 'n't' to ' not' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not ok and "let's" in lctheline and not inquote and not isref:
                    print(f"SERIOUS: For formal writing, no contractions: 'let's' to 'let us' or reword, on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not ok and "we've" in lctheline and not inquote and not isref:
                    print(f"SERIOUS: For formal writing, no contractions: 'we've' to 'we have' or reword, on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " it's ", lcprev_line, "it's"):
                    print(f"SERIOUS: For formal writing, no contractions: 'it's' to 'it is' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not ok and "'re" in theline and not inquote:
                    print(f"SERIOUS: For formal writing, no contractions: ''re' to ' are' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not ok and "'ll" in theline and not inquote:
                    print(f"SERIOUS: For formal writing, no contractions: ''ll' to ' will' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not ok and not isref and 'formulas' in theline and not inquote:
                    print(f"For formal writing, change 'formulas' to 'formulae' on line {line_number} in {input_file}.\n  But, it's your choice, see https://www.lexico.com/definition/formula\n  and https://www.grammar-monster.com/plurals/plural_of_formula.htm")
                    FLAG_FORMAL()
                if not twook and not twook and not isref and not inquote and WORDTEST(twoline, " Generally ", prev_line, "Generally"):
                    print(f"add comma: after 'Generally' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                # But, And, Also are possible to use correctly, but hard: https://www.quickanddirtytips.com/education/grammar/can-i-start-a-sentence-with-a-conjunction
                # Some avoidance strategies: http://www.bookpromotionhub.com/6341/5-ways-to-avoid-starting-a-sentence-with-but-or-and/
                if not twook and not isref and not inquote and (WORDTEST(twoline, " But ", prev_line, "but") or WORDTEST(twoline, " But,", prev_line, "but,")):
                    print(f"Usually avoid starting sentences with the informal `But', on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                # usually annoying, a run-on sentence
                if not twook and not isref and not inquote and (WORDTEST(twoline, " And ", prev_line, "and") or WORDTEST(twoline, " And,", prev_line, "and,")):
                    print(f"Avoid starting sentences with the informal `And', on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                # can be OK, your call...
                if not twook and not isref and not inquote and (WORDTEST(twoline, " Also ", prev_line, "also") or WORDTEST(twoline, " Also,", prev_line, "also,")):
                    print(f"Usually avoid starting sentences with the informal `Also', on line {line_number} in {input_file}.")
                    FLAG_FORMAL()

            if style:
                # ------------------------------------------------
                # Personal preferences, take them or leave them
                # Why no "very"?
                # See https://www.forbes.com/sites/katelee/2012/11/30/mark-twain-on-writing-kill-your-adjectives
                # (though it's not a Mark Twain quote, see https://quoteinvestigator.com/2012/08/29/substitute-damn/ )
                # Try to find a substitute, e.g., "very small" could become "minute" or "tiny"
                # substitutes site here: https://www.grammarcheck.net/very/
                # Most of the others are from Chapter 1 of "Dreyer's English".
                # Tool that can help, though it's not great: https://www.losethevery.com/
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " very", lcprev_line, "very"):
                    print(f"tip: consider removing or replacing 'very' on line {line_number} in {input_file}.")
                    print(f"    'very' tends to weaken a sentence. Try substitutes: https://www.grammarcheck.net/very/")
                if not twook and not isref and not inquote and formal and WORDTEST(lctwoline, " really", lcprev_line, "really"):
                    print(f"tip: for formal writing, consider removing or replacing 'really' on line {line_number} in {input_file}.")
                    print(f"    Perhaps try substitutes: https://www.grammarcheck.net/very/")
                    FLAG_FORMAL()
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " rather", lcprev_line, "rather") and 'rather than' not in lctwoline:
                    print(f"tip: consider removing or replacing 'rather' on line {line_number} in {input_file}.")
                    print(f"    Perhaps try substitutes: https://www.grammarcheck.net/very/")
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " quite", lcprev_line, "quite"):
                    print(f"tip: consider removing or replacing 'quite' on line {line_number} in {input_file}.")
                    print(f"    Perhaps try substitutes: https://www.grammarcheck.net/very/")
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " actually", lcprev_line, "actually"):
                    print(f"tip: remove the never-needed word 'actually' on line {line_number} in {input_file}.")
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " in fact", lcprev_line, "in fact"):
                    print(f"tip: consider removing 'in fact' on line {line_number} in {input_file}. It's often superfluous, in fact.")
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " surely", lcprev_line, "surely"):
                    print(f"tip: consider removing 'surely' on line {line_number} in {input_file}.")
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " of course", lcprev_line, "of course"):
                    print(f"tip: if it's obvious, why say it? Remove 'of course' on line {line_number} in {input_file}.")
                if not twook and not isref and not inquote and formal and WORDTEST(lctwoline, " pretty", lcprev_line, "pretty"):
                    print(f"tip: unless you mean something is pretty, replace or remove the modifier 'pretty' on line {line_number} in {input_file}.")
                    FLAG_FORMAL()
                if not twook and '(see figure' in lctwoline:
                    print(f"Try to avoid `(see Figure', make it a full sentence, on line {line_number} in {input_file}.")
                # This extra test at the end is not foolproof, e.g., if the line ended "Interestingly" or "interesting,"
                # A better test would be to pass in the phrase,
                if not twook and not isref and not inquote and WORDTEST(lctwoline, " interesting", lcprev_line, "interesting"):
                    print(f"tip: reconsider 'interesting' on line {line_number} in {input_file}, probably delete it\n    or change to 'key,' 'noteworthy,' 'notable,' 'different,' or 'worthwhile'.\n    Everything in your work should be interesting.\n    Say why something is of interest, and write so that it is indeed interesting.")
                #if not twook and not isref and 'in terms of ' in lctwoline:
                #    print(f"tip: 'in terms of' is a wordy phrase, on line {line_number} in {input_file}. Use it sparingly.")
                #    print(f"    You might consider instead using 'regarding' or 'concerning', or rewrite.")
                #    print(f"    For example, 'In terms of memory, algorithm XYZ uses less' could be 'Algorithm XYZ uses less memory.'")
                #    SAYOK()
                if not twook and not isref and not inquote and WORDTEST(twoline, " etc. ", lcprev_line, "etc."):
                    print(f"hint: try to avoid using etc., as it adds no real information; on line {line_number} in {input_file}.")
                    if not textonly:
                        print(f"    If you do end up using etc., if you don't use it at the end of a sentence, add a backslash: etc.\\")
                # nah, don't care about "data is" any more, the language has changed:
                # https://www.theguardian.com/news/datablog/2010/jul/16/data-plural-singular
                #if not twook and not isref and 'data is' in lctwoline:
                #    print(f"possible tip: 'data' should be plural, not singular, on line {line_number} in {input_file}. Reword?")
                #    print(f"    Sometimes it is fine, e.g., 'the analysis of the data is taking a long time.' since analysis is singular.")
                #    SAYOK()
                # see http://www.quickanddirtytips.com/education/grammar/use-versus-utilize?page=1
                if not ok and not inquote and not isref and 'utiliz' in lctheline:
                    print(f"Probably needlessly complex: change 'utiliz*' to 'use' or similar, on line {line_number} in {input_file}.")
                    SAYOK()
                # from the book "The Craft of Scientific Writing" by Michael Alley
                if not ok and not inquote and not isref and 'familiarization' in lctheline:
                    print(f"Needlessly complex: change 'familiarization' to 'familiarity' on line {line_number} in {input_file}.")
                if not twook and not inquote and not isref and 'has the functionability' in lctwoline:
                    print(f"Needlessly complex: change 'has the functionability' to 'can function' on line {line_number} in {input_file}.")
                if not twook and not inquote and not isref and 'has the operationability' in lctwoline:
                    print(f"Needlessly complex: change 'has the operationability' to 'can operate' on line {line_number} in {input_file}.")
                if not twook and not inquote and not isref and 'has the functionability' in lctwoline:
                    print(f"Needlessly complex: change 'has the functionability' to 'can function' on line {line_number} in {input_file}.")
                if not ok and not inquote and not isref and not inequation and 'facilitat' in lctheline:
                    print(f"Possibly needlessly complex: change 'facilitat*' to 'cause' or 'ease' or 'simplify' or 'help along' on line {line_number} in {input_file}.")
                if not ok and not inquote and not isref and 'finaliz' in lctheline:
                    print(f"Needlessly complex: change 'finaliz*' to 'end' on line {line_number} in {input_file}.")
                if not ok and not inquote and not isref and 'prioritiz' in lctheline:
                    print(f"Perhaps needlessly complex: change 'prioritiz*' to 'assess' or 'first choose' on line {line_number} in {input_file}.")
                if not ok and not inquote and not isref and 'aforementioned' in lctheline:
                    print(f"Needlessly complex: change 'aforementioned' to 'mentioned' on line {line_number} in {input_file}.")
                if not ok and not inquote and not isref and 'discretized' in lctheline:
                    print(f"Possibly needlessly complex if used as an adjective: consider changing 'discretized' to 'discrete' on line {line_number} in {input_file}.")
                    SAYOK()
                if not ok and not inquote and not isref and 'individualized' in lctheline:
                    print(f"Needlessly complex: change 'individualized' to 'individual' on line {line_number} in {input_file}.")
                if not ok and not inquote and not isref and 'personalized' in lctheline:
                    print(f"Possibly needlessly complex if used as an adjective: consider 'personalized' to 'personal' on line {line_number} in {input_file}.")
                    SAYOK()
                if not ok and not inquote and not isref and 'heretofore' in lctheline:
                    print(f"Needlessly complex: change 'heretofore' to 'previous' on line {line_number} in {input_file}.")
                if not ok and not inquote and not isref and 'hitherto' in lctheline:
                    print(f"Needlessly complex: change 'hitherto' to 'until now' on line {line_number} in {input_file}.")
                if not ok and not inquote and not isref and 'therewith' in lctheline:
                    print(f"Needlessly complex: change 'therewith' to 'with' on line {line_number} in {input_file}.")

                # -----------------------------------------------------
                # Words and phrases - definitely personal preferences, but mostly based on common practice
                # looks like the Internet got lowercased: https://blog.oxforddictionaries.com/2016/04/05/should-you-capitalize-internet/
                #if not ok and not isref and 'internet' in theline:
                #    print(f"'internet' should be capitalized, to 'Internet', on line {line_number} in {input_file}.")
                if not twook and not isref and 'monte carlo' in twoline:
                    print(f"'monte carlo' should be capitalized, to 'Monte Carlo', on line {line_number} in {input_file}.")
                if not ok and not isref and 'monte-carlo' in lctheline:
                    print(f"'Monte-Carlo' should not be hyphenated, to 'Monte Carlo', on line {line_number} in {input_file}.")
                # commented out, as I've seen people at Epic write "Unreal Engine" without "the"
                # Unreal Engine should have "the" before it, unless it's "Unreal Engine 4"
                # note that this test can fail, as the phrase has three words and, despite its name,
                # lctwoline is really "lc this line plus the last word of the previous line"
                #if not twook and not isref and 'unreal engine' in lctwoline and 'the unreal engine' not in lctwoline and not re.search(r'unreal engine \d', lctwoline):
                #    print(f"'Unreal Engine' should have 'the' before it, on line {line_number} in {input_file} (note: test is flaky).")
                # Performant used to be flagged by MS Word, but now it isn't. Debate was here:
                # https://english.stackexchange.com/questions/38945/what-is-wrong-with-the-word-performant
                #if not ok and not isref and 'performant' in lctheline:
                #    print(f"'performant' not fully accepted as a word, so change to 'efficient' or 'powerful' on line {line_number} in {input_file}.")
                if not ok and not isref and 'Earth' in theline and 'Google Earth' not in twoline and 'Visible Earth' not in twoline:
                    print(f"'Earth' should be 'the earth' (or change this rule to what you like), on line {line_number} in {input_file}.")
                if not ok and not isref and 'Moon ' in theline:
                    print(f"'Moon' probably wants to be 'the moon' (or change this rule to what you like), on line {line_number} in {input_file}.")

            # ---- continuation of while loop body, terminology/spelling checks ----

            # either is OK, https://en.wikipedia.org/wiki/Data_set - may someday use this one for a consistency check. TODO
            if not ok and not isref and 'dataset' in lctheline:
                print(f"'dataset' to 'data set' (either is fine, 'data set' is preferred, but your choice) on line {line_number} in {input_file}.")
            if not ok and not isref and 'depth-of-field' in lctheline:
                print(f"'depth-of-field' to 'depth of field' on line {line_number} in {input_file}.")
            if not twook and not isref and 'fall off' in lctwoline:
                print(f"'fall off' to 'falloff' on line {line_number} in {input_file}.")
            if not ok and not isref and 'fall-off' in lctheline:
                print(f"'fall-off' to 'falloff' on line {line_number} in {input_file}.")
            if not ok and not isref and 'farfield' in lctheline:
                print(f"'farfield' to 'far field' on line {line_number} in {input_file}.")
            if not ok and not isref and 'far-field' in lctheline:
                print(f"'far-field' to 'far field' on line {line_number} in {input_file}.")
            if not ok and not isref and 'nearfield' in lctheline:
                print(f"'nearfield' to 'near field' on line {line_number} in {input_file}.")
            if not ok and not isref and 'near-field' in lctheline:
                print(f"'near-field' to 'near field' on line {line_number} in {input_file}.")
            if not twook and not isref and 'six dimensional' in lctwoline:
                print(f"if used as an adjective, 'six dimensional' to 'six-dimensional' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and not isref and 'five dimensional' in lctwoline:
                print(f"if used as an adjective, 'five dimensional' to 'five-dimensional' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and not isref and 'four dimensional' in lctwoline:
                print(f"if used as an adjective, 'four dimensional' to 'four-dimensional' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and not isref and 'three dimensional' in lctwoline:
                print(f"if used as an adjective, 'three dimensional' to 'three-dimensional' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and not isref and 'two dimensional' in lctwoline:
                print(f"if used as an adjective, 'two dimensional' to 'two-dimensional' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and not isref and 'one dimensional' in lctwoline:
                print(f"if used as an adjective, 'one dimensional' to 'one-dimensional' on line {line_number} in {input_file}.")
                SAYOK()
            if not ok and 'LoD' in theline:
                print(f"'LoD' to 'LOD' on line {line_number} in {input_file}.")
            if not ok and 'rerender' in lctheline and not isref:
                print(f"'rerender' should change to 're-render', on line {line_number} in {input_file}.")
            if not ok and 'retro-reflect' in lctheline and not isref:
                print(f"'retro-reflect' should change to 'retroreflect', on line {line_number} in {input_file}.")
            if not ok and 'inter-reflect' in lctheline and not isref:
                print(f"'inter-reflect' should change to 'interreflect', on line {line_number} in {input_file}.")
            if not ok and 'level-of-detail' in lctheline and not isref:
                print(f"'level-of-detail' should change to 'level of detail' if used as a noun, on line {line_number} in {input_file}.")
            if not ok and 'micro-facet' in lctheline and not isref:
                print(f"'micro-facet' should change to 'microfacet', on line {line_number} in {input_file}.")
            if not ok and 'microdetail' in lctheline and not isref:
                print(f"'microdetail' should change to 'micro-detail', on line {line_number} in {input_file}.")
            if not ok and 'black-body' in lctheline:
                print(f"'black-body' should change to 'blackbody' on line {line_number} in {input_file}.")
            if not ok and 'black body' in lctwoline:
                print(f"'black body' should change to 'blackbody' on line {line_number} in {input_file}.")
            if not twook and 'spot light' in lctwoline:
                print(f"'spot light' should change to 'spotlight' on line {line_number} in {input_file}.")
            if not ok and 'spot-light' in theline:
                print(f"'spot-light' should change to 'spotlight' on line {line_number} in {input_file}.")
            if not twook and 'frame buffer' in lctwoline and not isref:
                print(f"'frame buffer' to 'framebuffer' on line {line_number} in {input_file}.")
            if not ok and 'frame-buffer' in lctheline and not isref:
                print(f"'frame-buffer' to 'framebuffer' on line {line_number} in {input_file}.")
            # yes, this is inconsistent with the above; chosen by Google search popularity
            if not ok and 'framerate' in lctheline and not isref:
                print(f"'framerate' to 'frame rate' on line {line_number} in {input_file}.")
            if not ok and 'pre-filter' in lctheline and not isref:
                print(f"'pre-filter' to 'prefilter' on line {line_number} in {input_file}.")
            if not ok and 'pre-process' in lctheline and not isref:
                print(f"'pre-process' to 'preprocess' on line {line_number} in {input_file}.")
            if not ok and 'bandlimit' in lctheline and not isref:
                print(f"'bandlimit' to 'band-limit' on line {line_number} in {input_file}.")
            if not ok and ' raycast' in lctheline and not isref:
                print(f"'raycast' to 'ray cast' on line {line_number} in {input_file}.")
            if not twook and ' lob ' in lctwoline:
                print(f"Typo? 'lob' to 'lobe' on line {line_number} in {input_file}.")
            if not ok and 'frustums' in lctheline and not isref:
                print(f"'frustums' to 'frusta' on line {line_number} in {input_file}.")
            if not ok and '$Z' in theline:
                print(f"Consistency check: $Z should be $z (or change this test), on line {line_number} in {input_file}.")
            if not twook and ' 6D' in twoline:
                print(f"'6D' to 'six-dimensional' on line {line_number} in {input_file}.")
            # things like "1:1" should be "$1:1$"
            if not twook and not isref and not inequation and ':1 ' in lctwoline and textonly != 1:
                print(f"'X:1' should be of the form '$X:1$', on line {line_number} in {input_file}.")
            if not twook and not isref and not inequation and ' : 1' in lctwoline and textonly != 1:
                print(f"'X : 1' should be of the form '$X:1$' (no spaces), on line {line_number} in {input_file}.")
            if not ok and not isref and ' PBRT' in twoline and textonly != 1:
                print(f"'PBRT' to '{{\\em pbrt}}', or cite the book or author, on line {line_number} in {input_file}.")
            if not ok and not isref and 'DX9' in theline:
                print(f"'DX9' to 'DirectX~9' on line {line_number} in {input_file}.")
            if not ok and not isref and 'DX10' in theline:
                print(f"'DX10' to 'DirectX~10' on line {line_number} in {input_file}.")
            if not ok and not isref and 'DX11' in theline:
                print(f"'DX11' to 'DirectX~11' on line {line_number} in {input_file}.")
            if not ok and not isref and 'DX12' in theline:
                print(f"'DX12' to 'DirectX~12' on line {line_number} in {input_file}.")
            if not twook and not isref and 'Direct X' in twoline:
                print(f"'Direct X' to 'DirectX' on line {line_number} in {input_file}.")
            if not ok and not isref and re.search(r'\u2122', theline) and textonly != 1:
                print(f"Put \\trademark instead of the TM symbol directly, if needed at all, on line {line_number} in {input_file}.")
            # "2-degree color-matching" is how that phrase is always presented
            if not ok and not isref and re.search(r'\d-degree', theline) and not re.search(r'color-matching', theline):
                print(f"'N-degree' to 'N degree' on line {line_number} in {input_file}.")
            if not ok and 'Ph.D' in theline:
                print(f"'Ph.D.' to 'PhD' on line {line_number} in {input_file}.")
            if not ok and 'M.S.' in theline:
                print(f"'M.S.' to 'MS' on line {line_number} in {input_file}.")
            if not ok and 'M.Sc.' in theline:
                print(f"'M.Sc.' to 'MSc' on line {line_number} in {input_file}.")
            if not twook and 'a MS' in twoline:
                print(f"'a MS' to 'an MS' on line {line_number} in {input_file}.")
            if not ok and 'B.S.' in theline:
                print(f"'B.S.' to 'BS' on line {line_number} in {input_file}.")
            if not ok and 'B.Sc.' in theline:
                print(f"'B.Sc.' to 'BSc' on line {line_number} in {input_file}.")
            if not twook and 'masters thesis' in lctwoline:
                print(f"'masters' to 'master's' on line {line_number} in {input_file}.")
            if not twook and 'masters degree' in lctwoline:
                print(f"'masters' to 'master's' on line {line_number} in {input_file}.")
            if not twook and 'bachelors degree' in lctwoline:
                print(f"'bachelors' to 'bachelor's' on line {line_number} in {input_file}.")
            if not twook and ' id ' in twoline and ' id Software' not in twoline:
                print(f"Please change 'id' to 'ID' on line {line_number} in {input_file}.")
            if not twook and ' id~' in twoline:
                print(f"Please change 'id' to 'ID' on line {line_number} in {input_file}.")
            if not twook and ' ids ' in twoline:
                print(f"Please change 'ids' to 'IDs' on line {line_number} in {input_file}.")
            if not twook and ' ids~' in twoline:
                print(f"Please change 'ids' to 'IDs' on line {line_number} in {input_file}.")
            if not ok and 'middle-ware' in lctheline:
                print(f"Please change 'middle-ware' to 'middleware' on line {line_number} in {input_file}.")
            if not ok and not isref and 'caption{}' in theline:
                print(f"IMPORTANT: every figure needs a caption, on line {line_number} in {input_file}.")
            if not ok and not isref and 'g-buffer' in theline:
                print(f"'g-buffer' to 'G-Buffer', on line {line_number} in {input_file}.")
            if not ok and not isref and 'G-Buffer' in theline:
                print(f"'G-Buffer' to 'G-buffer', on line {line_number} in {input_file}.")
            if not ok and not isref and 'z-buffer' in theline:
                print(f"'z-buffer' to 'Z-Buffer', on line {line_number} in {input_file}.")
            if not ok and not isref and 'Z-Buffer' in theline:
                print(f"'Z-Buffer' to 'Z-buffer', on line {line_number} in {input_file}.")
            if not twook and not isref and ' 1d ' in twoline:
                print(f"'1d' to '1D' on line {line_number} in {input_file}.")
            if not twook and not isref and ' 2d ' in twoline:
                print(f"'2d' to '2D' on line {line_number} in {input_file}.")
            if not twook and not isref and ' 3d ' in twoline:
                print(f"'3d' to '3D' on line {line_number} in {input_file}.")
            if not twook and not isref and re.search(r'^So ', twoline) and not re.search(r'^So far', twoline):
                # https://english.stackexchange.com/questions/30436/when-do-we-need-to-put-a-comma-after-so
                print(f"'So' should be 'So,' or combine with previous sentence, on line {line_number} in {input_file}.")
            # If you must use "start point", also then use "end point" when talking about the other end.
            if not twook and 'startpoint' in lctwoline:
                print(f"'startpoint' to 'start point' on line {line_number} in {input_file}.")
            if not ok and 'back-fac' in lctheline:
                print(f"'back-face' to 'backface' on line {line_number} in {input_file}.")
            if not twook and 'back fac' in lctwoline and not ('front and back fac' in twoline or 'front or back fac' in twoline or 'front and the back fac' in twoline):
                print(f"'back face' to 'backface' on line {line_number} in {input_file}.")
            if not ok and 'front-fac' in lctheline:
                print(f"'front-face' to 'frontface' on line {line_number} in {input_file}.")
            if not twook and 'front-fac' in lctwoline:
                print(f"'front-face' to 'frontface' on line {line_number} in {input_file}.")
            if not ok and 'wire-fram' in lctheline:
                print(f"'wire-frame' to 'wireframe' on line {line_number} in {input_file}.")
            if not twook and 'wire frame' in lctwoline:
                print(f"'wire frame' to 'wireframe' on line {line_number} in {input_file}.")
            if not twook and not isref and 'sub-pixel' in lctwoline:
                print(f"'sub-pixel' to 'subpixel' on line {line_number} in {input_file}.")
            if not ok and not isref and 'mis-categorize' in lctheline:
                print(f"'mis-categorize' to 'miscategorize', on line {line_number} in {input_file}.")
            if not ok and 'counter-clockwise' in lctheline:
                print(f"'counter-clockwise' to 'counterclockwise' on line {line_number} in {input_file}.")
            if not twook and 'anti-alias' in lctwoline and not isref:
                print(f"'anti-alias' to 'antialias' on line {line_number} in {input_file}.")
            if not twook and ' b spline' in lctwoline and not isref:
                print(f"'B spline' to 'B-spline' on line {line_number} in {input_file}.")
            if not ok and 'modelled' in lctheline:
                print(f"'modelled' to 'modeled' on line {line_number} in {input_file}.")
            if not ok and 'tessela' in lctheline and not isref:
                print(f"'tessela' to 'tessella' on line {line_number} in {input_file}.")
            if not twook and 'greyscale' in lctwoline:
                print(f"'greyscale' to 'grayscale' on line {line_number} in {input_file}.")
            if not twook and 'speed-up' in lctwoline:
                print(f"'speed-up' to 'speedup' on line {line_number} in {input_file}.")
            # see https://english.stackexchange.com/questions/4300/semi-transparent-what-is-used-in-between
            if not twook and 'semi-transparen' in lctwoline:
                print(f"'semi-transparen' to 'semitransparen' on line {line_number} in {input_file}.")
            if not twook and 'In this way ' in twoline:
                print(f"'In this way ' to 'In this way,' on line {line_number} in {input_file}.")
            if not twook and 'For example ' in twoline:
                print(f"'For example ' to 'For example,' on line {line_number} in {input_file}.")
            if not ok and 'off-screen' in lctheline:
                print(f"'off-screen' to 'offscreen' on line {line_number} in {input_file}.")
            if not ok and 'on-screen' in lctheline:
                print(f"'on-screen' to 'onscreen' on line {line_number} in {input_file}.")
            if not ok and 'photo-realistic' in lctheline:
                print(f"'photo-realistic' to 'photorealistic' on line {line_number} in {input_file}.")
            if not ok and 'point-cloud' in lctheline:
                print(f"'point-cloud' to 'point cloud' on line {line_number} in {input_file}.")
            if not twook and 'straight forward' in lctwoline:
                print(f"You likely want to change 'straight forward' to 'straightforward' on line {line_number} in {input_file}.")
                print("    See https://www.englishforums.com/English/StraightForwardStraightforward/bcjwmp/post.htm")
                SAYOK()
            if not twook and 'view point' in lctwoline:
                print(f"'view point' to 'viewpoint' on line {line_number} in {input_file}.")
            if not twook and 'gray scale' in lctwoline:
                print(f"'gray scale' to 'grayscale' on line {line_number} in {input_file}.")
            if not twook and not isref and 'post process' in lctwoline:
                print(f"'post process' to 'post-process' on line {line_number} in {input_file}.")
            if not ok and not isref and 'postprocess' in lctheline:
                print(f"'postprocess' to 'post-process' on line {line_number} in {input_file}.")
            if not twook and not isref and 'half space' in lctwoline:
                print(f"'half space' to 'half-space' on line {line_number} in {input_file}.")
            if not ok and not isref and 'halfspace' in lctheline:
                print(f"'halfspace' to 'half-space' on line {line_number} in {input_file}.")
            if not ok and not isref and 'lock-less' in lctheline:
                print(f"'lock-less' to 'lockless' (no hyphen), on line {line_number} in {input_file}.")
            if not ok and not isref and 'bi-directional' in lctheline:
                print(f"'bi-directional' to 'bidirectional' (no hyphen), on line {line_number} in {input_file}.")
            if not ok and not isref and 'over-blur' in lctheline:
                print(f"'over-blur' to 'overblur' (no hyphen), on line {line_number} in {input_file}.")
            if not ok and not isref and 'multi-sampl' in lctheline:
                print(f"'multi-sampl*' to 'multisampl*' (no hyphen), on line {line_number} in {input_file}.")
            if not twook and not isref and '$uv$ coordinates' in lctwoline:
                print(f"'$uv$ coordinates' to 'UV coordinates', on line {line_number} in {input_file}.")
            # $uv$ might even be more correct, but UV coordinates is standard
            if not ok and not isref and '$uv$-coordinates' in lctheline:
                print(f"'$uv$-coordinates' to 'UV coordinates', on line {line_number} in {input_file}.")
            if not ok and not isref and 'mip-map' in lctheline:
                print(f"'mip-map' to 'mipmap' (no hyphen), on line {line_number} in {input_file}.")
            if not ok and not isref and 'mip map' in lctheline:
                print(f"'mip map' to 'mipmap' (no space), on line {line_number} in {input_file}.")
            if not twook and not isref and 'wall clock time' in lctwoline:
                print(f"'wall clock time' to 'wall-clock time', on line {line_number} in {input_file}.")
            if not twook and not isref and 'RT PSO' in twoline:
                print(f"'RT PSO' to 'RTPSO', on line {line_number} in {input_file}.")
            m = re.search(r' (cubemap)', lctheline) if not ok and not isref and not inequation else None
            if not m and not ok and not isref and not inequation and style:
                m = re.search(r'(cube-map)', lctheline)
            if m:
                print(f"Change '{m.group(1)}' to 'cube map' on line {line_number} in {input_file}.")
                SAYOK()
            m = re.search(r' (lightmap)', lctheline) if not ok and not isref else None
            if not m and not ok and not isref and style:
                m = re.search(r'(light-map)', lctheline)
            if m:
                print(f"Change '{m.group(1)}' to 'light map' on line {line_number} in {input_file}.")
                SAYOK()
            if not ok and not isref:
                m = re.search(r' (screenspace)', lctheline)
                if m:
                    print(f"Change '{m.group(1)}' to 'screen space' on line {line_number} in {input_file}.")
                    SAYOK()
            if not ok and not isref and 'DXR' not in theline and 'DirectX' not in theline:
                m = re.search(r' (raytrac)', lctheline)
                if m:
                    print(f"Change '{m.group(1)}' to 'ray trac*' on line {line_number} in {input_file}.")
                    SAYOK()
            # doing a rough survey, there are considerably more articles without the hyphen than with
            if not ok and not isref and style:
                m = re.search(r'(ray-trac)', lctheline)
                if m:
                    print(f"Consistency: change '{m.group(1)}' to 'ray trac*' (it's the norm), on line {line_number} in {input_file}.")
            if not isref and 'directx ray tracing' in lctwoline:
                print(f"Change 'DirectX ray tracing' to 'DirectX Raytracing' as this is how Microsoft writes it, on line {line_number} in {input_file}.")
            if not isref and 'Directx raytracing' in twoline:
                print(f"Change 'DirectX raytracing' to 'DirectX Raytracing' (capitalize the 'r'), as this is how Microsoft writes it, on line {line_number} in {input_file}.")
            if not isref and style:
                m = re.search(r' (pathtrac)', lctheline)
                if m:
                    print(f"Consistency: change '{m.group(1)}' to 'path trac*' on line {line_number} in {input_file}.")
            if not isref and style:
                m = re.search(r'(path-trac)', lctheline)
                if m:
                    print(f"Consistency: change '{m.group(1)}' to 'path trac*' (it's the norm), on line {line_number} in {input_file}.")
            if not ok and not isref:
                m = re.search(r' (raymarch)', lctheline)
                if not m and style:
                    m = re.search(r'(ray-march)', lctheline)
                if m:
                    print(f"Change '{m.group(1)}' to 'ray march*' on line {line_number} in {input_file}.")
                    SAYOK()
            if not ok and not isref:
                m = re.search(r' (sub-surface)', lctheline)
                if m:
                    print(f"Change '{m.group(1)}' to 'subsurface' on line {line_number} in {input_file}.")
                    SAYOK()
            if not ok and not isref:
                m = re.search(r' (preintegrate)', lctheline)
                if m:
                    print(f"Change '{m.group(1)}' to 'pre-integrate' on line {line_number} in {input_file}.")
                    SAYOK()
            if not ok and not isref:
                m = re.search(r' (pre-calculate)', lctheline)
                if m:
                    # slight google preference for this, but we'll go precalculate
                    print(f"Change '{m.group(1)}' to 'precalculate' on line {line_number} in {input_file}.")
                    SAYOK()
            if not ok and not isref:
                m = re.search(r' (pre-comput)', lctheline)
                if m:
                    print(f"Change '{m.group(1)}' to 'precomput*' on line {line_number} in {input_file}.")
                    SAYOK()
            if not ok and not isref and 'non-linear' in lctheline:
                print(f"Change 'non-linear' to 'nonlinear' on line {line_number} in {input_file}.")
            if not ok and not isref and 'non-planar' in lctheline:
                print(f"Change 'non-planar' to 'nonplanar' on line {line_number} in {input_file}.")
            if not ok and not isref and 'pre-pass' in lctheline:
                print(f"Change 'pre-pass' to 'prepass' on line {line_number} in {input_file}.")
            if not ok and not isref and 'zeroes' in lctheline:
                print(f"Change 'zeroes' to 'zeros' on line {line_number} in {input_file}.")
            if not ok and not isref and 'un-blur' in lctheline:
                print(f"Change 'un-blur' to 'unblur' (no hyphen), on line {line_number} in {input_file}.")
            if not ok and not isref and 'use-case' in lctheline:
                print(f"Change 'use-case' to 'use case' (no hyphen), on line {line_number} in {input_file}.")
            # our general rule: if Merriam-Webster says it's a word, it's a word
            if not ok and not isref and 'multi-stage' in lctheline:
                print(f"Change 'multi-stage' to 'multistage' (no hyphen), on line {line_number} in {input_file}.")
            if not ok and not isref and 'XYZ-space' in lctheline:
                print(f"Change 'XYZ-space' to 'XYZ space' (no hyphen), on line {line_number} in {input_file}.")
            if not ok and not isref and 'spatio-temporal' in lctheline:
                print(f"Change 'spatio-temporal' to 'spatiotemporal', on line {line_number} in {input_file}.")
            if not ok and not isref and 'close-up' in lctheline:
                print(f"Could change 'close-up' to the more modern 'closeup', on line {line_number} in {input_file}.")
            if not twook and not isref and 'multi channel' in lctwoline:
                print(f"Change 'multi channel' to 'multichannel', on line {line_number} in {input_file}.")
            if not ok and not isref and 'multi-channel' in lctheline:
                print(f"Change 'multi-channel' to 'multichannel', on line {line_number} in {input_file}.")
            if not twook and not isref and 'multi ' in lctwoline:
                print(f"It is unlikely that you want 'multi' with a space after it, on line {line_number} in {input_file}.")
            if not twook and not isref and 'pseudo code' in lctwoline:
                print(f"Change 'pseudo code' to 'pseudocode', on line {line_number} in {input_file}.")
            if not ok and not isref and 'pseudo-code' in lctheline:
                print(f"Change 'pseudo-code' to 'pseudocode', on line {line_number} in {input_file}.")
            if not twook and not isref and 'pseudo ' in lctwoline:
                print(f"It is unlikely that you want 'pseudo' with a space after it, on line {line_number} in {input_file}.")
            if not twook and not isref and 'ray-generation shader' in lctwoline:
                print(f"Change 'ray-generation' to 'ray generation' (no hyphen), on line {line_number} in {input_file}.")
            if not ok and not isref and 'reexecute' in lctheline:
                print(f"Change 'reexecute' to 're-execute', on line {line_number} in {input_file}.")
            if not ok and not isref and ('XBox' in theline or 'XBOX' in theline):
                print(f"Change 'XBox' to 'Xbox' on line {line_number} in {input_file}.")
            if not ok and not isref and 'x-box' in lctheline:
                print(f"Change 'XBox' to 'Xbox' on line {line_number} in {input_file}.")
            if not ok and not isref and 'Renderman' in theline:
                print(f"Change 'Renderman' to 'RenderMan' on line {line_number} in {input_file}.")
            if not ok and not isref and 'GeForce' not in theline and 'geforce' in lctheline:
                print(f"Change 'Geforce' to 'GeForce' on line {line_number} in {input_file}.")
            # https://www.nvidia.com/en-us/geforce/graphics-cards/rtx-2080-ti/
            if not ok and not isref and '080ti' in lctheline:
                print(f"Change '*080Ti' to '*080~Ti' on line {line_number} in {input_file}.")
            if not ok and not isref:
                m = re.search(r'(rtcore)', lctheline)
                if m:
                    print(f"Change '{m.group(1)}' to 'RT Core' on line {line_number} in {input_file}.")
            if not twook and not isref:
                m = re.search(r'(rt core)', lctwoline)
                if m:
                    print(f"Change '{m.group(1)}' to 'RT~Core' on line {line_number} in {input_file}.")
            if not ok and not isref:
                m = re.search(r'(RT~core)', theline)
                if m:
                    print(f"Change '{m.group(1)}' to 'RT~Core' on line {line_number} in {input_file}.")
            if not ok and not isref and '080 ti' in theline:
                print(f"Change '*080 ti' to '*080~Ti' on line {line_number} in {input_file}.")
            elif not textonly and not ok and not isref and '0 Ti' in theline:
                print(f"Change '*0 Ti' to '*0~Ti' on line {line_number} in {input_file}.")
            if not textonly and not ok and not isref and 'titan v' in lctheline:
                print(f"Change 'Titan V' to 'Titan~V' on line {line_number} in {input_file}.")
            if not twook and 'gtx 2080' in lctwoline:
                print(f"Change 'GTX' to 'RTX' on line {line_number} in {input_file}.")
            if not ok and 'Game Developer Conference' in theline:
                print(f"Change 'Game Developer Conference' to 'Game Developers Conference' on line {line_number} in {input_file}.")
            if not ok and not inequation and 'Direct3D' in theline and not isref:
                print(f"Just our own preference: 'Direct3D' to 'DirectX' on line {line_number} in {input_file}.")
            if not ok and 'Playstation' in theline and not isref:
                print(f"'Playstation' to 'PlayStation' on line {line_number} in {input_file}.")
            # NVIDIA in caps; ignore in a URL
            if not ok and 'nvidia' in theline and 'nvidia.com' not in theline and 'bibitem' not in theline and 'cite' not in theline:
                print(f"'nvidia' to 'NVIDIA' on line {line_number} in {input_file}.")
            if not ok and 'Nvidia' in theline and 'bibitem' not in theline and 'cite' not in theline:
                print(f"'Nvidia' to 'NVIDIA' on line {line_number} in {input_file}.")
            if not twook and ' a NVIDIA' in twoline:
                print(f"'a NVIDIA' to 'an NVIDIA' on line {line_number} in {input_file}.")
            # won't catch them all, but better than not catching any.
            if not twook and ' can not ' in lctwoline:
                print(f"'can not' to 'cannot' on line {line_number} in {input_file}.")
            if not ok and 'trade off' in lctwoline and not isref:
                print(f"possible fix: 'trade off' to 'trade-off', if not used as a verb, on line {line_number} in {input_file}.")
            if not ok and 'absorbtion' in lctheline:
                print(f"'absorbtion' to 'absorption' on line {line_number} in {input_file}.")
            if not twook and not inequation and 'fourier' in twoline:
                print(f"'fourier' to 'Fourier' on line {line_number} in {input_file}.")
            if not twook and not inequation and 'fresnel' in twoline:
                print(f"'fresnel' to 'Fresnel' on line {line_number} in {input_file}.")
            if not twook and not inequation and ' gauss' in twoline:
                print(f"'gauss' to 'Gauss' on line {line_number} in {input_file}.")
            if not twook and not inequation and 'lambert' in twoline:
                print(f"'lambert' to 'Lambert' on line {line_number} in {input_file}.")
            if not twook and not inequation and ' russian' in twoline:
                print(f"'russian' to 'Russian' on line {line_number} in {input_file}.")
            if not twook and not inequation and ' gbuffer' in lctwoline:
                print(f"'gbuffer' to 'G-buffer' on line {line_number} in {input_file}.")
            if not twook and not inequation and ' zbuffer' in lctwoline:
                print(f"'zbuffer' to 'Z-buffer' on line {line_number} in {input_file}.")
            if not ok and 'ad-hoc' in lctheline:
                print(f"'ad-hoc' to 'ad hoc' on line {line_number} in {input_file}.")
            if not ok and 'co-author' in lctheline:
                print(f"'co-author' to 'coauthor' on line {line_number} in {input_file}.")
            if not ok and not inequation and 'lowpass' in lctheline:
                print(f"'lowpass' to 'low-pass' on line {line_number} in {input_file}.")
            if not ok and 'highpass' in lctheline:
                print(f"'highpass' to 'high-pass' on line {line_number} in {input_file}.")
            if not twook and 'high frequency' in lctwoline:
                print(f"If an adjective, 'high frequency' to 'high-frequency' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and 'high level' in lctwoline:
                print(f"If an adjective, 'high level' to 'high-level' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and 'high fidelity' in lctwoline:
                print(f"If an adjective, 'high fidelity' to 'high-fidelity' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and 'higher quality' in lctwoline:
                print(f"If an adjective, 'higher quality' to 'higher-quality' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and 'floating point' in lctwoline:
                print(f"If an adjective, 'floating point' to 'floating-point' on line {line_number} in {input_file}.")
                SAYOK()
            if not ok and 'nonboundary' in lctheline:
                print(f"'nonboundary' to 'non-boundary' on line {line_number} in {input_file}.")
            if not ok and 'penumbrae' in lctheline:
                print(f"'penumbrae' to 'penumbras' on line {line_number} in {input_file}.")
            if not twook and 'one bounce' in lctwoline:
                print(f"You may want 'one bounce' to 'one-bounce' (add hyphen) if an adjective, on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and 'multi bounce' in lctwoline:
                print(f"'multi bounce' to 'multiple-bounce' on line {line_number} in {input_file}.")
            if not ok and 'multibounce' in lctheline:
                print(f"'multibounce' to 'multiple-bounce' on line {line_number} in {input_file}.")
            if not ok and 'multi-bounce' in lctheline:
                print(f"'multi-bounce' to 'multiple-bounce' on line {line_number} in {input_file}.")
            if not twook and 'multiple bounce' in lctwoline and 'multiple bounces' not in lctwoline:
                print(f"'multiple bounce' to 'multiple-bounce' on line {line_number} in {input_file}.")
            if not ok and 'multidimensional' in lctheline:
                print(f"'multidimensional' to 'multi-dimensional' on line {line_number} in {input_file}.")
            if not ok and 'multilayer' in lctheline:
                print(f"'multilayer' to 'multi-layer' on line {line_number} in {input_file}.")
            if not ok and 'multibound' in lctheline:
                print(f"'multibound' to 'multi-bound' on line {line_number} in {input_file}.")
            # searching the ACM Digital Library, 47 entries use "tone mapping" as two words
            if not twook and 'tonemap' in lctwoline:
                print(f"'tonemap' to 'tone map' if a noun, 'tone-map' if an adjective, on line {line_number} in {input_file}.")
            if not twook and not isref and 'n-Patch' in twoline:
                print(f"'n-Patch' to 'N-patch' on line {line_number} in {input_file}.")
            if not twook and 'fill-rate' in lctwoline:
                print(f"'fill-rate' to 'fill rate' on line {line_number} in {input_file}.")
            if not ok and not isref and formal and 'bigger' in lctheline:
                print(f"'bigger' to 'larger' on line {line_number} in {input_file}.")
                FLAG_FORMAL()
            if not ok and not isref and formal and 'biggest' in lctheline:
                print(f"'biggest' to 'greatest' or similar, on line {line_number} in {input_file}.")
                FLAG_FORMAL()
            if not twook and not isref and 'self intersect' in lctwoline and 'self intersection' not in lctwoline:
                print(f"'self intersect' to 'self-intersect' as it's a common term, on line {line_number} in {input_file}.")
            if not ok and not isref and 'bidimensional' in lctheline:
                print(f"'bidimensional' to 'two-dimensional' mr. fancy pants, on line {line_number} in {input_file}.")
            if not ok and 'fillrate' in lctheline:
                print(f"'fillrate' to 'fill rate' on line {line_number} in {input_file}.")
            # more popular on Google
            if not twook and not isref and 'run time' in lctwoline:
                print(f"'run time' to 'runtime' for consistency, on line {line_number} in {input_file}.")
            if not ok and not isref and 'videogame' in lctheline:
                print(f"'videogame' to 'video game' on line {line_number} in {input_file}.")
            if not ok and not isref and 'videocamera' in lctheline:
                print(f"'videocamera' to 'video camera' on line {line_number} in {input_file}.")
            if not ok and isref and 'January' in theline:
                print(f"Change January to Jan. in line {line_number} in {input_file}.")
            if not ok and isref and 'February' in theline:
                print(f"Change February to Feb. in line {line_number} in {input_file}.")
            if not ok and isref and (re.search(r'March \d', twoline) or re.search(r'March,', twoline)):
                print(f"Change March to Mar. in line {line_number} in {input_file}.")
            if not ok and isref and 'September' in theline:
                print(f"Change September to Sept. in line {line_number} in {input_file}.")
            if not ok and isref and 'October' in theline:
                print(f"Change October to Oct. in line {line_number} in {input_file}.")
            if not ok and isref and 'November' in theline:
                print(f"Change November to Nov. in line {line_number} in {input_file}.")
            if not ok and isref and 'December' in theline:
                print(f"Change December to Dec. in line {line_number} in {input_file}.")
            if not ok and isref and 'Jan.,' in theline:
                print(f"No comma needed after Jan. on line {line_number} in {input_file}.")
            if not ok and isref and 'Feb.,' in theline:
                print(f"No comma needed after Feb. on line {line_number} in {input_file}.")
            if not ok and isref and 'March,' in theline:
                print(f"No comma needed after March on line {line_number} in {input_file}.")
            if not ok and isref and 'April,' in theline:
                print(f"No comma needed after April on line {line_number} in {input_file}.")
            if not ok and isref and 'May,' in theline:
                print(f"No comma needed after May on line {line_number} in {input_file}.")
            if not ok and isref and 'June,' in theline:
                print(f"No comma needed after June on line {line_number} in {input_file}.")
            if not ok and isref and 'July,' in theline:
                print(f"No comma needed after July on line {line_number} in {input_file}.")
            if not ok and isref and 'August,' in theline:
                print(f"No comma needed after August on line {line_number} in {input_file}.")
            if not ok and isref and 'Sept.,' in theline:
                print(f"No comma needed after Sept. on line {line_number} in {input_file}.")
            if not ok and isref and 'Oct.,' in theline:
                print(f"No comma needed after Oct. on line {line_number} in {input_file}.")
            if not ok and isref and 'Nov.,' in theline:
                print(f"No comma needed after Nov. on line {line_number} in {input_file}.")
            if not ok and isref and 'Dec.,' in theline:
                print(f"No comma needed after Dec. on line {line_number} in {input_file}.")
            if not ok and isref and 'course notes' in theline:
                print(f"Change 'course notes' to 'course' on line {line_number} in {input_file}.")
            if not ok and isref and 'JCGT' in theline:
                print(f"SERIOUS: do not use JCGT abbreviation in reference on line {line_number} in {input_file}.")
            if not ok and isref and 'JGT' in theline:
                print(f"SERIOUS: do not use JGT abbreviation in reference on line {line_number} in {input_file}.")
            # slight Google preference, and https://en.wikipedia.org/wiki/Lookup_table
            if not ok and not isref and 'look-up' in lctheline:
                print(f"Change 'look-up table' to 'lookup table' or similar on line {line_number} in {input_file}.")
            if not ok and not isref and re.search(r'[\s]disc[\s\.,:;?]', lctheline):
                print(f"Change 'disc' to 'disk' on line {line_number} in {input_file}.")
            if not ok and not isref and 'exemplif' in lctheline:
                print(f"You might change 'exemplify' to 'give an example', 'show', or 'demonstrate', on line {line_number} in {input_file}.")
            if not ok and not isref and re.search(r'[\s]discs[\s\.,:;?]', lctheline):
                print(f"Change 'discs' to 'disks' on line {line_number} in {input_file}.")
            # https://www.merriam-webster.com/dictionary/nonnegative says it's good
            if not twook and not isref and 'non-negativ' in lctwoline:
                print(f"Change 'non-negativ' to 'nonnegativ' on line {line_number} in {input_file}.")
            if not ok and not isref and 'non-physical' in lctheline and 'non-physically' not in lctheline:
                print(f"Change 'non-physical' to 'nonphysical' on line {line_number} in {input_file}.")
            if not ok and not isref and 'non-random' in lctheline:
                print(f"Change 'non-random' to 'nonrandom' on line {line_number} in {input_file}.")
            if not ok and not isref and 'non-uniform' in lctheline:
                print(f"Change 'non-uniform' to 'nonuniform' on line {line_number} in {input_file}.")
            if not ok and not isref and 'non-zero' in lctheline:
                print(f"Change 'non-zero' to 'nonzero' on line {line_number} in {input_file}.")

            # nice for a final check one time, but kind of crazed and generates false positives
            if picky:
                if not twook and ' at. ' in twoline:
                    print(f"Noteworthy: sentence finishes with the preposition 'at.' on line {line_number} in {input_file}.")
                if not twook and ' of. ' in twoline:
                    print(f"Noteworthy: sentence finishes with the preposition 'of.' on line {line_number} in {input_file}.")
                if not twook and ' for. ' in twoline:
                    print(f"Noteworthy: sentence finishes with the preposition 'for.' on line {line_number} in {input_file}.")
                if not twook and not isref and 'a number of' in lctwoline:
                    print(f"shortening tip: replace 'a number of' with 'several' (or possibly even remove), on line {line_number} in {input_file}.")
                    SAYOK()
                if not twook and not isref and 'in particular' in lctwoline:
                    print(f"shortening tip: perhaps remove 'in particular' on line {line_number} in {input_file}.")
                    SAYOK()
                if not twook and not isref and 'a large number of' in lctwoline:
                    print(f"shortening tip: perhaps replace 'a large number of' with 'many' on line {line_number} in {input_file}.")
                    SAYOK()
                if not twook and not isref and 'the majority of' in lctwoline:
                    print(f"shortening tip: replace 'the majority of' with 'most' on line {line_number} in {input_file}.")
                    SAYOK()
                if not twook and 'kind of' in lctwoline:
                    print(f"If you don't mean 'type of' for formal writing, change 'kind of' to 'somewhat, rather, or slightly' on line {line_number} in {input_file}.")
                    SAYOK()
                # finds some problems, but plenty of false positives:
                if not ok and isref and re.search(r"\w''", theline):
                    print(f"ERROR: reference title does not have comma before closed quotes, on line {line_number} in {input_file}.")

            # promoted from "picky"
            # The non-picky version - at the start of a sentence is particularly likely to be replaceable.
            if not twook and not isref and 'In order to' in twoline:
                print(f"shortening tip: perhaps replace 'In order to' with 'to' on line {line_number} in {input_file}.")
                SAYOK()
            # see https://www.grammar-monster.com/lessons/all_of.htm
            if (not twook and not isref and ' all of ' in lctwoline
                    and ' all of them' not in lctwoline
                    and ' all of which' not in lctwoline
                    and ' all of this' not in lctwoline
                    and ' all of these' not in lctwoline
                    and ' all of space' not in lctwoline
                    and ' all of you' not in lctwoline
                    and ' all of us' not in lctwoline
                    and ' all of his' not in lctwoline
                    and ' all of her' not in lctwoline
                    and ' all of it' not in lctwoline):
                print(f"shortening tip: replace 'all of' with 'all' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and not isref and ' off of ' in lctwoline:
                print(f"shortening tip: replace 'off of' with 'off' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and not isref and ' on the basis of ' in lctwoline:
                print(f"shortening tip: replace 'on the basis of' with 'based on' on line {line_number} in {input_file}.")
                SAYOK()
            if not twook and not isref and ' first of all, ' in lctwoline:
                print(f"shortening tip: replace 'first of all,' with 'first,' on line {line_number} in {input_file}.")
                SAYOK()

            # ---- end of the "skip" block (the large terminology/style checks section) ----
            # This closes the block that began with: if not skip:

            # warn if an italicized term is repeated
            if not ok and not isref and not infigure:
                m = re.search(r'\{\\em ([\d\w_".\'\~\-\$& !^()/\|\\@]+)\}', twoline)
                if m:
                    term = m.group(1)
                    # if there are capitals in the term, ignore it - probably a title
                    if term.lower() == term:
                        if term in emfound and input == eminput.get(term, ''):
                            print(f"Warning: term '{term}' is emphasized a second time at line {line_number} in {input_file}.")
                            print(f"    First found at {emfound[term]}.")
                        else:
                            emfound[term] = f"line {line_number} in {input_file}"
                            eminput[term] = input_file

            # save the last token on this line so we can join it to the next line
            fld = theline.split()
            if not newpara and len(fld) > 0:
                prev_line = fld[-1]
                # if the last token is an index, ignore it
                if re.search(r'\\index\{[\d\w_".\'\-\$ !()/\|\\@]+\}', prev_line):
                    prev_line = ''
                if isref:
                    prev_real_line = prev_line
                    lastl = line_number
            else:
                prev_line = ''

            # close up sections at the *end* of testing, so that two-line tests work properly
            if ('end{equation' in theline
                    or 'end{eqnarray' in theline
                    or 'end{comment' in theline
                    or 'end{IEEEeqnarray' in theline
                    or 'end{align' in theline
                    or '\\]' in theline
                    or 'end{lstlisting}' in theline):
                inequation = 0
                if 'end{lstlisting}' in theline:
                    inlisting = 0
                    insidecode = 0
                if 'end{equation}' in theline or 'end{eqnarray}' in theline or 'end{IEEEeqnarray}' in theline:
                    justlefteq = 1
            if 'end{figure}' in theline:
                infigure = 0
                # did the figure have a caption and a label?
                if not ok and figlabel == '':
                    print(f"ERROR: Figure doesn't have a label, on line {line_number} in {input_file}.")
                if not ok and figcaption == '':
                    print(f"ERROR: Figure doesn't have a caption, on line {line_number} in {input_file}.")
                figlabel = ''
                figcaption = ''
                figcenter = ''
            if 'end{tikzpicture}' in theline:
                infigure = 0
            if 'end{gather}' in theline:
                inequation = 0
            if 'end{tabbing}' in theline:
                inequation = 0
            if 'end{falign}' in theline:
                inequation = 0
            if 'end{verbatim}' in theline:
                inequation = 0
            if 'end{quote}' in theline:
                inquote = 0
            if 'end{tabular' in theline:
                inequation = 0
                intable = 0

            twook = ok

            # ---- else branch: the line was empty/blank ----
            # (In the Perl code this is the else for "if there is anything on the line")
            # This is handled by the main loop structure; if we reach here, the line had content.
            # The blank-line case sets prev_line = '' if newpara is true,
            # which is handled in the "else" of the outer if block in the main loop.

            lcprev_line = prev_line.lower()

        # ---- end of while loop (end of file processing) ----

        # close the file (handled by the with statement if using one, or explicitly)
        # datafile.close()  # if not using 'with'

        # Report any unclosed index entries
        for elem in sorted(indexlong.keys()):
            print(f"ERROR: index entry started, not ended: {{{elem}|( in {input_file}.")
        indexlong.clear()



    datafile.close()



# =========================================================
# Main execution
# =========================================================
if __name__ == '__main__':
    dirs = []
    argv = sys.argv[1:]  # skip script name
    i = 0
    while i < len(argv):
        arg = argv[i]
        i += 1
        # does it start with a "-"?
        if arg.startswith('-'):
            chars = arg[1:]
            j = 0
            while j < len(chars):
                char = chars[j]
                j += 1
                if char == 'd':
                    dashes = 0
                elif char == 'f':
                    formal = 0
                elif char == 'l':
                    labels = 0
                elif char == 't':
                    force_title_cap = 0
                elif char == 'p':
                    picky = 1
                elif char == 's':
                    style = 0
                elif char == 'u':
                    usstyle = 0
                # arguments followed by another argument
                elif char == 'c':
                    if i < len(argv):
                        testlisting = int(argv[i])
                        i += 1
                    else:
                        testlisting = 0
                    if testlisting < 1:
                        print("ABORTING: Code line length test not set. Syntax is '-c 71' or other number of characters.", file=sys.stderr)
                        testlisting = 0
                        usage()
                        sys.exit(0)
                elif char == 'O':
                    if i < len(argv) and j >= len(chars):
                        okword = argv[i]
                        i += 1
                    else:
                        print("The -O option must be followed by a word.'", file=sys.stderr)
                        usage()
                        sys.exit(0)
                elif char == 'R':
                    if i < len(argv) and j >= len(chars):
                        refstex = argv[i]
                        i += 1
                    else:
                        print("Reference tex file unset.")
                        refstex = ''
                elif char == 'P':
                    if i < len(argv) and j >= len(chars):
                        packagesjson = argv[i]
                        i += 1
                    else:
                        print("The -P option must be followed by a JSON file path.", file=sys.stderr)
                        usage()
                        sys.exit(0)
                    if not os.path.exists(packagesjson):
                        print(f"The packages JSON file '{packagesjson}' does not exist.", file=sys.stderr)
                        sys.exit(1)
                    checkpackages = 1
                else:
                    print(f"Unknown argument character '{char}'.", file=sys.stderr)
                    usage()
                    sys.exit(0)
        else:
            # we assume the argument must then be a directory or file - test if it exists and add it appropriately
            if os.path.exists(arg):
                if os.path.isdir(arg):
                    dirs.append(arg)
                else:
                    # a text file, I guess...
                    codefiles.append(arg)
                    cfnum += 1
                    if not arg.endswith('.tex'):
                        if textonly != 1:
                            print("Files will be treated as plain text.")
                        textonly = 1
            else:
                print(f"The argument >{arg}< is neither a valid file nor directory, nor an option.", file=sys.stderr)
                usage()
                sys.exit(0)

    # if specific files were listed, don't recurse directories
    if cfnum == 0:
        if len(dirs) == 0:
            dirs.append('.')  # default is current directory
        read_recursive_dir(dirs)

    # Load approved packages from JSON file if specified
    if checkpackages and len(packagesjson) > 0:
        load_approved_packages()

    process_files()

    sys.exit(0)
