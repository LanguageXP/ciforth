dnl Copyright(2000): Albert van der Horst, HCC FIG Holland by GNU Public License
dnl $Id$
define(divert,)
divert(-1)
changequote({,})dnl
dnl Define a word index on channel 2
dnl        the wordset index on channel 4 
dnl        and a definition for the second pass on channel 0
define({forthvar}, <I>$1</I>)
define({forthdefi}, <I>$1</I>)
define({forthsamp}, <B>$1</B>)
define({forthexample},{<P><B>$1</B><P>})
define({forthcode}, {<A HREF="#$1">$1</A>})
define({forthxref}, {<A HREF="#$1">See also $1</A>})
dnl ----------------------- worddoc ------------------------------------
define({worddoc},
{divert(2)dnl
forthcode({$2}) __})dnl
dnl ----------------------- worddocsafe  ------------------------------------
define({worddocsafe},
{divert(2)dnl
forthcode({$2}) __})dnl
dnl ----------------------- worddocchapter -----------------------------
define({worddocchapter},
{divert(4)dnl
<A HREF="#$1INDEX">$1</A>})
dnl ----------------------- worddocchapterend  -----------------------------
define({worddocchapterend},{dnl})dnl
divert(0)dnl
<HTML>
<HEAD>
dnl<META HTTP-EQUIV="Content-Type" CONTENT="text/html"; charset="iso-8859-1">
   <TITLE>Fig-Forth 3.0 Manual</TITLE>
</HEAD>
<BODY>

<H1>
GLOSSARY OF GENERIC FIGFORTH figforthversion</H1>

divert(1)dnl
<P>
<HR><A NAME=GLOSSARY INDEX></A>
<H1>
GLOSSARY INDEX</H1>
<P>
Here you can select the glossary entry of a 
word. All words in the basic set are documented.
<P>
divert(3)dnl
<P>
<HR><A NAME=WORDSET INDEX></A>
<H1>
GLOSSARY INDEX BY WORDSET</H1>
Here you can select the description of a 
Wordsets: small sets of words that work together.
These are intended to give more insight in how to use the
words in cooperation.
<P>
Note: the first reference under `see also' of a word is the wordset to
which it belongs.
<P>
divert(0)dnl
dnl Normal description comes after the definitions but before the menu's
dnl and contents.



