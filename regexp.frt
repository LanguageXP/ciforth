( Copyright{2002}: Albert van der Horst, HCC FIG Holland by GNU Public License)

( $Id$)

: \D POSTPONE \ ; IMMEDIATE
\ : \D ;
'COUNT ALIAS C@+
: CELL/ 2 RSHIFT ;   \ From #addres to #cell.

REQUIRE @+
REQUIRE TRUE
REQUIRE WITHIN
REQUIRE 2R>
REQUIRE BOUNDS

INCLUDE set.frt
INCLUDE bits.frt
INCLUDE defer.frt

\ Regular expressions in Forth.
\ This package handles only simple regular expressions and replacements.
\ See the words RE-MATCH and RE-REPLACE for usage.
\ The following aspects are handled:
\    1. Compiling ^ (begin only)  $  (end only) and special characters + ? * [ ] < >
\    2. Grouping using ( ) , only for replacement.
\    4. Ranges and inversion of char set (between [ ] ).
\    3. Above characters must be escaped if used as is by \ , making \ a special char.
\    4. Some sets are escaped by \ (\w) , some non-printables are denoted by an
\       escape sequence.
\ 5. It is an error to escape characters that do no denote blank
\       space, are not special, nor are denoting a set, However ^ - $
\       etc. may be escaped where they are not special.

\ Implementation notes:
\ * Usually regular expressions are compiled into a buffer consisting of
\   tokens followed by strings or characters in some format.
\   We follow the same here, except that tokens are execution tokens.
\ * No attempt is done at reentrant code.
\ * \d \s \w etc. can be handled by just adding sets

\ Data structures :
\   a char set is a bit set, with a bit up for the matching character.
\   a string is a regular string variable (so with a cell count).

\ Configuration
1000 CONSTANT MAX-RE     \ # cells in a regular expression and copied expression.
128 8 / CONSTANT MAX-SET \ # chars in a charset. (So no char's > 0x80 !)

\ -----------------------------------------------------------------------
\                  char sets, generic part
\ -----------------------------------------------------------------------
: |  OVER SET-BIT ; \ Shorthand, about to be hidden.

\ This contains alternatingly a character, and a pointer to a charset.
\ The charset is denotated by this character preceeded by '\' e.g. \s.
100 SET CHAR-SET-SET     CHAR-SET-SET !SET

\ Allocate a char set and leave a POINTER to it.
: ALLOT-CHAR-SET   HERE MAX-SET 0 DO 0 C, LOOP ;
\ Note that ``ASCII'' null is excluded from every char-set!
\ The algorithm relied on it, but probably no longer.
\ For an identifying CHAR create an as yet empty char set with "NAME"
\ and add it to ``CHAR-SET-SET''.
\ Leave a POINTER to the set (to fill it in).
: CHAR-SET CREATE HERE CHAR-SET-SET 2SET+!  ALLOT-CHAR-SET DOES> ;
\ For a CHAR-SET ; convert it into its complementary set.
: INVERT-SET MAX-SET 0 DO DUP I + DUP C@ INVERT SWAP C! LOOP  0 SWAP CLEAR-BIT ;

\ Copy CHARSET 1 over CHARSET 2.
: COPY-SET MAX-SET MOVE ;

\ For CHAR and CHARSET return "it BELONGS to the charset".
: IN-CHAR-SET   BIT? ;

\ Add CHARSET1 to CHARSET2 .
: OR-SET! MAX-SET 0 DO OVER I + C@ OVER I + C@ OR OVER I + C! LOOP 2DROP ;

\ ------------------------------------------
\                  char sets, actual part
\ ------------------------------------------

REQUIRE ?BLANK      \ Indicating whether a CHAR is considered blank in this Forth.

\ Passing a 0 makes a char-set unfindable in ``CHAR-SET-SET''.

\ The set of characters to be escaped.
0 CHAR-SET \\     &. | &\ | &^ | &$ | &+ | &? | &* | &[ | &] | &< | &> | &( | &) |  DROP

\ For CHAR : "it IS special".
: SPECIAL?   \\ IN-CHAR-SET   ;

\ The empty set
0 CHAR-SET \EMPTY DROP

\ The set matched by .
0 CHAR-SET \.  ^J | INVERT-SET

\ The characters that can be part of a "word". In C this would be [a-zA-Z0-9_]
\ In c this would probably be \s (blank Space).
&w CHAR-SET \w   256 1 DO I ?BLANK 0= IF I | THEN LOOP DROP

\ Example of another set definition
\ &d CHAR-SET \d   &9 1+ &0 DO I | LOOP   DROP
\ &D CHAR-SET \D   \d OVER COPY-SET  INVERT-SET

'| HIDDEN

\ For CHAR: "it IS a quantifier".
: QUANTIFIER? >R R@ &+ = R@ &* = R@ &? = OR OR RDROP ;

\ -----------------------------------------------------------------------
\                  escape table
\ -----------------------------------------------------------------------
\ To SET add an escape CHAR and the escape CODE. Leave SET .
: | ROT DUP >R 2SET+! R> ;    \ Shorthand, about to be hidden.

\ This contains alternatingly an escaped character, and its ASCII meaning.
100 SET ESCAPE-TABLE     ESCAPE-TABLE !SET
ESCAPE-TABLE &n ^J |   &r ^M |   &b ^H |   &t ^I |   &e ^Z 1+ |
\ The special char's from \\ represent themselves when escaped.
MAX-SET 8 * 0 DO I SPECIAL? IF I DUP | THEN LOOP
DROP
'| HIDDEN

\ For CHARACTER return the ``ASCII'' VALUE it represents, when escaped.
\ else zero. Do not find at odd positions.
 : GET-ESCAPE
    ESCAPE-TABLE WHERE-IN-SET DUP IF
         DUP ESCAPE-TABLE - CELL/ 1 AND IF CELL+ @ ELSE DROP 0 THEN
    THEN ;

\ -----------------------------------------------------------------------
\                  matched substrings
\ -----------------------------------------------------------------------
\ This table contains the ends and starts of a number of strings.
\ 1. Offset 0 and 1 : the string in which a match is sought
\ 2. Offset 2 and 3 : the part that the matches the whole expression.
\ 3. Offset 4 and 5 : the parts that match subexpression 1, between first pair of ( and )
\ 2n. 2n+1 : subexpression n-1.

22 CONSTANT MAX-RANGES

CREATE STRING-TABLE MAX-RANGES CELLS ALLOT
\ To where has the table been used (during expression parsing).

\ For string INDEX, return WHERE its start address is stored. (end is one cell beyond)
: STRING[] 2* CELLS STRING-TABLE + ;

\ For CP : "It POINTS in the string to be matched."
: IN-STRING? STRING-TABLE 2@ SWAP WITHIN ;

\ For CHARPOINTER : "It POINTS (just) past the end of the input string"
: AT-END? STRING-TABLE CELL+ @ = ;

VARIABLE ALLOCATOR
\ Initialise ALLOCATOR
: !ALLOCATOR 4 ALLOCATOR ! ;

\ Give an error message for unmatched parantheses.
: ?ALLOCATOR ALLOCATOR @ 1 AND ABORT" Parenthesis ( ) not matched in re, user error" ;

\ Return a new ALLOCATOR index, and increment it.
: ALLOCATOR++
    ALLOCATOR @ DUP MAX-RANGES > ABORT" Too many substrings with ( ), max 9, user error"
    1 ALLOCATOR +! ;

\ Return a new INDEX for a '('.
: ALLOCATE( ALLOCATOR++
DUP 1 AND ABORT" ( where ) expected, inproper nesting, user error" ;
\ Return a new INDEX for a ')'.
: ALLOCATE) ALLOCATOR++
DUP 1 AND 0= ABORT" ) where ( expected, inproper nesting, user error" ;

\ Remember CHARPOINTER as the substring with INDEX.
: REMEMBER()
\D DUP 0 MAX-RANGES WITHIN 0= ABORT" substring index out of range, system error"
CELLS STRING-TABLE + ! ;

\ For ADDRESS containing a start end pair, return the STRING represented.
: SE@-STRING 2@ SWAP OVER - ;
\ For INDEX create a "word" that returns the matched string with that index.
: CREATE\ CREATE 1+ STRING[] , DOES> @ SE@-STRING ;

\ &9 1+ &0 DO   &\ PAD C!   I PAD 1+ C!   PAD 2 POSTFIX CREATE\ LOOP
0 CREATE\ \0    1 CREATE\ \1    2 CREATE\ \2    3 CREATE\ \3   4 CREATE\ \4
5 CREATE\ \5    6 CREATE\ \6    7 CREATE\ \7    8 CREATE\ \8   9 CREATE\ \9

\ -----------------------------------------------------------------------

\ The compiled pattern.
\ It contains xt's, strings and charsets in a sequential format, i.e.
\ you can only find out what it means by reading from the beginning.
\ It is NULL-ended.
\ BNF = <term>+ <endsentinel>
\ term = <quantifier>? <atom> CHAR-SET | 'ADVANCE-EXACT STRING-VARIABLE
\ atom = 'ADVANCE-CHAR
\ quantifier = 'ADVANCE? | 'ADVANCE+ | 'ADVANCE*
\ endsentinel = 0
\ For nested expressions one could add :
\ atom = 'ADVANCE( <term>+ <endsentinel>

CREATE RE-PATTERN MAX-RE CELLS ALLOT
\ Backup from ADDRESS one cell. Leave decremented ADDRESS.
: CELL- 0 CELL+ - ;
\ For CHARPOINTER and EXPRESSIONPOINTER :
\ bla bla + return "there IS a match"
\D DEFER .Zm DEFER .RE-C
: (MATCH)
\D CR "MATCHING: " TYPE OVER .Zm " With" TYPE CR DUP .RE-C
DUP >R
BEGIN DUP >R @+ DUP IF EXECUTE  THEN WHILE RDROP REPEAT
   DROP R>   DUP @ IF DROP R> FALSE ELSE RDROP TRUE THEN
\D DUP IF "MATCH" ELSE "FAILED" THEN CR TYPE
;


\ For CHARPOINTER and EXPRESSIONPOINTER :
\ as long as the character agrees with the matcher at the expression,
\ advance it.
\ Return CHARPOINTER advanced and EXPRESSIONPOINTER .
    \ From ONE TWO THREE FOUR leave THREE and TWO
    : KEEP32 DROP >R >R DROP R> R> SWAP ;
    \ From ONE TWO THREE FOUR leave ONE and FOUR
    : KEEP14 >R DROP DROP R> ;
: (ADVANCE*)   @+ >R BEGIN 2DUP R@ EXECUTE WHILE KEEP32 REPEAT KEEP14 RDROP ;

\ This would benefit from locals :
\ : (ADVANCE*) @+ LOCAL MATCHER   LOCAL EP   LOCAL CP  0 LOCAL EPNEW
\         BEGIN CP EP MATCHER EXECUTE WHILE DROP TO CP REPEAT
\         TO EPNEW DROP     CP EPNEW ;

\ For CHARPOINTER and EXPRESSIONPOINTER and BACKTRACKPOINTER :
\ if there is match between btp and cp with the ep,
\ return CHARPOINTER ann EXPRESSIONPOINTER incremented past the match,
\ else return BTP and EP. Plus "there IS a match".
: BACKTRACK \D ^ RSP@ H.
    >R BEGIN
        OVER R@ < IF RDROP FALSE EXIT THEN
        (MATCH) 0= WHILE
        \ WARNING: 1 - will go wrong if there is a larger gap between backtrackpoints
        \ i.e. when ADVANCE( is there that would use larger leaps than ADVANCE-CHAR.
        SWAP 1 - SWAP
    REPEAT
    RDROP TRUE ;

\ ----------------------------------------------------------------
\           xt's that may be present in a compiled expression
\ -----------------------------------------------------------------

\ All of those xt's accept a charpointer and an expressionpointer.
\ The char pointer points into the string to be matched that must be
\ zero ended. The expressionpointer points into the buffer with
\ Polish xt's, i.e. xt's to be executed with a pointer to the
\ data following the xt.
\ The character pointer is iether left as is, and return FALSE, or
\ If the match still stands after the operation intended,
\ it is bumped past the characters consumed.
\ The expression pointer is bumped past
\ data, and possibly more xt's and more data consumed.
\ The incremented pointers are returned, plus a true flag.
\ The xt's need not do a match, they can do an operation that
\ never fails, such as remembering a pointer.

\ For CHARPOINTER and EXPRESSIONPOINTER :
\ if the character matches the charset at the expression,
\ advance charpointer past the match, else leave it as is.
\ Advanvce the expressionpointer past the charset.
\ Return CHARPOINTER and EXPRESSIONPOINTER and "there IS a match".
\ In a regular expression buffer this xt must be followed by a char-set.
: ADVANCE-CHAR  OVER C@ OVER BIT? DUP >R IF SWAP CHAR+ SWAP THEN MAX-SET CHARS + R> ;


\ For CHARPOINTER and EXPRESSIONPOINTER :
\ if the char sequence at charpointer matches the string variable at the
\ expressionpointer, advance both past the match, else leave them as is.
\ Return CHARPOINTER and EXPRESSIONPOINTER and "there IS a match".
\ In a regular expression buffer this xt must be followed by a string.
: ADVANCE-EXACT  2DUP $@ CORA 0= DUP >R IF $@ >R SWAP R@ + SWAP R> + ALIGNED THEN R> ;

\ START OF TESTED FOR COMPILATION ONLY AREA

\ For CHARPOINTER and EXPRESSIONPOINTER :
\ if there is match between cp and the end of string with the ep,
\ return CHARPOINTER and EXPRESSIONPOINTER incremented past the match,
\ else return CP and EP. Plus "there IS a match".
\ (Note: this is the syncronisation, to be done when the expression does
\ *not* start with `^'.
: FORTRACK
    BEGIN 2DUP (MATCH) 0= WHILE
        2DROP   OVER AT-END? IF FALSE EXIT THEN   SWAP 1 + SWAP
    REPEAT
    2SWAP 2DROP TRUE ;

\ For CP and EP, return CP EP and TRUE.
\ Instead of ``FORTRACK'' if we want no sync.
: FORTRACK-DUMMY TRUE ;

\ For CHARPOINTER and EXPRESSIONPOINTER :
\ return CHARPOINTER and EXPRESSIONPOINTER plus "the strings HAS been used up".
\ (Note: this is an end-check, to be done only when the expression ends with '$'.)
: CHECK$
\D DUP @ ABORT" CHECK$ compiled not at end of expression, system error"
    OVER AT-END? ;

\ Where the matched part of the string starts.
: STARTPOINTER    STRING-TABLE @ ;

\ For POINTER : "it POINTS into a word". start or end is considered "in a word".
: IN-WORD DUP IN-STRING? IF C@ \w IN-CHAR-SET ELSE DROP TRUE THEN ;
\ For POINTER : "it DOESNOT point into a word".
\ Start or end is considered "not in a word". (Too!).
: NOT-IN-WORD DUP IN-STRING? IF C@ \w IN-CHAR-SET 0= ELSE DROP TRUE THEN ;

\ For CHARPOINTER and EXPRESSIONPOINTER :
\ return CHARPOINTER and EXPRESSIONPOINTER plus "we ARE at the start of a word"
\ ``CHAR-POINTER'' must point into a string that is zero-ended at both ends
\ ( ``STRING-COPY'' ).
: CHECK< OVER   DUP 1- NOT-IN-WORD  SWAP IN-WORD AND ;

\ For CHARPOINTER and EXPRESSIONPOINTER :
\ return CHARPOINTER and EXPRESSIONPOINTER plus "we ARE at the end of a word"
: CHECK> OVER   DUP 1- IN-WORD  SWAP NOT-IN-WORD AND ;

\ For CHARPOINTER and EXPRESSIONPOINTER :
\ Remember this as the start or end of a substring.
\ Leave CHARPOINTER and leave the EXPRESSIONPOINTER after the substring number.
\ Plus "yeah, it IS okay"
\ In case you wonder, because the offset is known, during backtracking just
\ the last (and final) position is remembered.
: HANDLE() @+ >R   OVER R> REMEMBER() TRUE ;

\ If the following match xt (at ``EXPRESSIONPOINTER'' ) works out,
\ with one of the modifiers: * + ?
\ advance both past the remainder of the expression, else leave them as is.
\ Return CHARPOINTER and EXPRESSIONPOINTER and "there IS a match".
\ In a regular expression buffer each of those xt must be followed by the
\ xt of ADVANCE-CHAR.
: ADVANCE? OVER >R @+ EXECUTE DROP R> BACKTRACK ;


\ END OF TESTED FOR COMPILATION ONLY AREA
: ADVANCE* OVER >R   (ADVANCE*) R> BACKTRACK ;
: ADVANCE+ OVER >R   (ADVANCE*)
    \ For 0 or 1 char matches no backtracking.
    \ 1 char match is a + match. 0 char match is not.
    OVER R@ 2 + < IF OVER R> 1+ = EXIT THEN
    R> BACKTRACK ;

\ ---------------------------------------------------------------------------
\                    building the regexp
\ ---------------------------------------------------------------------------

\ The compiled expression.
CREATE RE-COMPILED MAX-RE CELLS ALLOT

\ Regular expressions are parsed using a simple recursive descent
\ parser.

\ Build up a string to be matched simply.
CREATE NORMAL-CHARS MAX-RE CELLS ALLOT
: !NORMAL-CHARS   0 NORMAL-CHARS ! ;

\ To where is the compiled expression filled.
VARIABLE RE-FILLED

\ Initialise ``RE-FILLED
: !RE-FILLED RE-COMPILED RE-FILLED ! ;

\ Add ITEM to the ``RE-EXPR''
: RE,   RE-FILLED @ ! 1 CELLS RE-FILLED +! ;

\ Add STRINGCONSTANT to the ``RE-EXPR''
: RE$,   DUP >R RE-FILLED @ $!   RE-FILLED @ CELL+ R> + ALIGNED RE-FILLED ! ;

\ Add CHARSET to the ``RE-EXPR''.
: RE-SET,   RE-FILLED @ COPY-SET   MAX-SET RE-FILLED +! ;

\ Make a hole in the ``RE-EXPR'' for a quantifier, and leave IT.
: MAKE-HOLE   MAX-SET CELL+ >R  RE-FILLED @ R@ -
    DUP DUP CELL+ R> MOVE
    1 CELLS RE-FILLED +! ;

\ FAILS THE MOST SIMPLE TEST !
\ Add the command to match the string in ``NORMAL-CHARS'' to the compiled
\ expression.
: HARVEST-NORMAL-CHARS NORMAL-CHARS @ IF
        'ADVANCE-EXACT RE,   NORMAL-CHARS $@ RE$,   !NORMAL-CHARS
    THEN
;

\    -    -    -   --    -    -   -    -    -   -    -    -   -

\ Build up a set to be matched.
CREATE SET-MATCHED ALLOT-CHAR-SET DROP
: !SET-MATCHED   \EMPTY SET-MATCHED COPY-SET ;


\ Add the command to match the set in ``SET-MATCHED'' to the compiled
\ expression.
: HARVEST-SET-MATCHED 'ADVANCE-CHAR RE,   SET-MATCHED RE-SET,  !SET-MATCHED  ;

\    -    -    -   --    -    -   -    -    -   -    -    -   -
\ For EP and CHAR : add the char to the simple match, or make it
\ a single character set, whatever is needed. Leave EP.
: ADD-TO-NORMAL OVER C@ QUANTIFIER? IF
    HARVEST-NORMAL-CHARS 'ADVANCE-CHAR RE, RE-FILLED @ \EMPTY RE-SET, SET-BIT
ELSE NORMAL-CHARS $C+ THEN ;

\    -    -    -   --    -    -   -    -    -   -    -    -   -

: GET-CHAR-SET CHAR-SET-SET WHERE-IN-SET
             DUP 0= ABORT" Illegal escaped char set, user error"
             CELL+ @ ;

\ EP is pointing to an '\' between '[  and ']'. Add the escaped
\ char (or set) to ``SET-MATCHED''
\ Leave EP incremented after the character consumed.
: ESCAPE[] 1+ C@+
    DUP GET-ESCAPE DUP IF SET-MATCHED SET-BIT DROP ELSE
        DROP GET-CHAR-SET SET-MATCHED OR-SET! THEN ;

\ EP is pointing to the first char of a range, between '[' and ']'.
\ Add the range to the ``SET-MATCHED''
\ CAN'T HANDLE ESCAPES, BUT WE ARE GOING TO DO THIS BY ELIMINATING
\ THE ESCAPES IN THE FIRST ROUND BY COPYING THE DATA TO A TEMPORARY
\ AREA, AND ADDING THE ZERO.
: SET-RANGE DUP C@ OVER 2 + C@ 1+ SWAP DO I SET-MATCHED SET-BIT LOOP 3 + ;

\ For EP (pointing between [ and ] ) add one item to ``SET-MATCHED''.
\ Leave EP pointing after the item.
: ADD[]-1  DUP C@
    DUP &. = IF DROP \. SET-MATCHED OR-SET! 1+ ELSE
    DUP &\ = IF DROP ESCAPE[] ELSE
    OVER 1+ C@ &- = IF DROP SET-RANGE ELSE
    SET-MATCHED SET-BIT 1+
    THEN THEN THEN
;

\ Build up the set between [ and ] into ``SET-MATCHED''.
\ EP points after the intial [ , leave IT pointing after the closing ].
: (PARSE[])
    BEGIN ADD[]-1 DUP C@ DUP 0= ABORT" Premature end of '[' character set" &] = UNTIL 1+
;

\ Compile a set between [ and ].
\ EP points after the intial [ , leave IT pointing after the closing ].
: PARSE[]
    DUP C@ &^ = IF 1+ (PARSE[]) SET-MATCHED INVERT-SET ELSE (PARSE[]) THEN
    HARVEST-SET-MATCHED  ;

\ Compile a set denoted by a \.
\ EP points after the intial \ , leave IT pointing after the set indicating character.
: PARSE\
    C@+ GET-CHAR-SET SET-MATCHED COPY-SET
    HARVEST-SET-MATCHED  ;

\    -    -    -   --    -    -   -    -    -   -    -    -   -

\ A copy of the start and end of the regular expression string.
VARIABLE RE-EXPR-START
VARIABLE RE-EXPR-END

\ Remember the limits of the EXPRESSION string. Leave IT.
: REMEMBER-START-RE OVER RE-EXPR-START ! 2DUP + RE-EXPR-END ! ;

\ Everything to be initialised for a build. Take EXPRESSION string, leave IT.
: INIT-BUILD   REMEMBER-START-RE !NORMAL-CHARS   !SET-MATCHED   !RE-FILLED   !ALLOCATOR
    'FORTRACK RE,   'HANDLE() RE, 2 RE, ;

\ Everything to be harvested after a build.
: EXIT-BUILD   HARVEST-NORMAL-CHARS   'HANDLE() RE, 3 RE,   0 RE,   ?ALLOCATOR ;

\    -    -    -   --    -    -   -    -    -   -    -    -   -

\ For EP and CHAR : EP plus "it IS one of ^ $ without its special meaning".
\ ``EP'' points after ``CHAR'' in the re, and is of course needed to
\ determine this.
: ^$? DUP &^ = IF DROP RE-EXPR-START @ 1+ OVER <> ELSE
    &$ = IF RE-EXPR-END @ OVER <> ELSE  FALSE THEN THEN ;

\ If the character at EP is to be treated normally, return incremented EP plus IT,
\ else EP plus FALSE. EP may be incremented past 2 char escapes!
: NORMAL-CHAR? C@+   >R
                     R@ SPECIAL? 0= IF R> EXIT THEN
                     R@ ^$? IF R> EXIT THEN
                     \ Escapes representing a character are okay too.
                     R@ &\ = IF DUP C@ GET-ESCAPE IF RDROP C@+ GET-ESCAPE EXIT THEN THEN
                     RDROP 1- FALSE ;

\ - - - - - - - - - - - - - - - - - - - - - - - -
\ Commands that get executed upon a special character
\ - - - - - - - - - - - - - - - - - - - - - - - -

\ Patch up the previous single character match with a quantifier.
: ADD*   MAKE-HOLE 'ADVANCE* SWAP ! ;
: ADD+   MAKE-HOLE 'ADVANCE+ SWAP ! ;
: ADD?   MAKE-HOLE 'ADVANCE? SWAP ! ;

\ Add sets, see also PARSE[] and PARSE\ .
: ADD.   'ADVANCE-CHAR RE, \. RE-SET, ;

\ Add specialties, more like markers.
: ADD<   'CHECK< RE, ;
: ADD>   'CHECK> RE, ;
: ADD(   'HANDLE() RE, ALLOCATE( RE, ;
: ADD)   'HANDLE() RE, ALLOCATE) RE, ;
: ADD^   'FORTRACK-DUMMY RE-COMPILED ! ;
: ADD$   'CHECK$ RE, ;

30 SET COMMAND-SET     COMMAND-SET !SET

: | COMMAND-SET 2SET+! ;    \ Shorthand, about to be hidden.
\ Parse thingies do an extra increment on the EP pointer.
&[ 'PARSE[] | &\ 'PARSE\ | &. 'ADD. |
&< 'ADD< |   &> 'ADD> | &( 'ADD( | &) 'ADD) |
&* 'ADD* |   &+ 'ADD+ |   &? 'ADD? |
&^ 'ADD^ |   &$ 'ADD$ |
'| HIDDEN

\ Execute the command that belongs to the abnormal CHARACTER.
: DO-ABNORMAL COMMAND-SET WHERE-IN-SET
             DUP 0= ABORT" Illegal escaped char for command, system error"
             HARVEST-NORMAL-CHARS CELL+ @ EXECUTE ;

\ Parse one element of re POINTER . Leave incremented POINTER.
: (RE-BUILD-ONE)
    NORMAL-CHAR? DUP IF ADD-TO-NORMAL ELSE DROP C@+ DO-ABNORMAL THEN ;

\ Parse one element of regular EXPRESSION ending at END.
\ Leave EXPRESSION incremented past parsed part and END as is.
\ Leave flag "The expression IS fully parsed".
: RE-BUILD-ONE    2DUP > ABORT" Premature end of regular expression"
        2DUP = IF TRUE ELSE >R (RE-BUILD-ONE) R> FALSE THEN ;

\ Parse the EXPRESSION string, put the result in the buffer
\ ``RE-COMPILED''. Leave a POINTER to that buffer.
: RE-BUILD INIT-BUILD OVER + BEGIN RE-BUILD-ONE UNTIL 2DROP EXIT-BUILD
   RE-COMPILED ;

\ Prepare the STRING to be matched.
\ Return a POINTER to the start of the string.
: STRING-BUILD OVER +   OVER STRING-TABLE 2! ;

\ For STRING and POINTER to compiled expression:
\ "there IS a match". \0 ..\9 are filled in.
: (RE-MATCH) >R STRING-BUILD R> (MATCH) >R 2DROP R> ;

\ For STRING and regular expression STRING:
\ "there IS a match". \0 ..\9 are been filled in.
: RE-MATCH RE-BUILD (RE-MATCH) ;

\ Compile "inline regular expression ending in '"' ":
\ compile code that leave a pointer to that expression compiled.
: RE-BUILD"    &" (PARSE) RE-BUILD RE-FILLED @ OVER -
        POSTPONE SKIP   $,   CELL+   POSTPONE LITERAL ;

\ Only to be used while compiling.
\ For STRING and "inline regular expression":
\ "there IS a match". \0 ..\9 are been filled in.
: RE-MATCH" RE-BUILD" POSTPONE (RE-MATCH) ; IMMEDIATE

\ Return remaining STRING of ``STRING-COPY'' after substring INDEX.
: REMAINING STRING[] CELL+ @   1 STRING[] CELL+ @ OVER - ;

\ Return STRING before the matched string.
: BEFORE\0   0 STRING[] @   1 STRING[] @   OVER - ;

\ Return STRING after the matched string.
: AFTER\0   1 STRING[] CELL+ @  0 STRING[] CELL+ @   OVER - ;

\ \ -----------------------------------------------------------------
\ \     Only used for awk-like facilities.
\ \ -----------------------------------------------------------------
\ \
\ \ \ Replace substring INDEX with a hole of LENGTH.
\ \ : MAKE-OF-SIZE   DUP >R DUP STRING[] @ R@ + SWAP REMAINDER   >R SWAP R> MOVE
\ \   R> STRING-TABLE CELL+ +! ;
\ \
\ \ \ Replace STRING for substring INDEX.
\ \ : (RE-REPLACE) 2DUP SWAP MAKE-OF-SIZE   2* CELLS STRING-TABLE + @ SWAP MOVE ;
\ \
\ \ \ Replace all substrings with STRING1 STRING2 .. STRINGN
\ \ : RE-REPLACE  ALLOCATOR @ 2/ 1- 1 DO (RE-REPLACE) -1 +LOOP ;

CREATE STRING-COPY MAX-RE CELLS ALLOT

\ CP points to a '\#' escape. Add the matched substring indicated by '#'
\ to the replaced string. Leave CP pointing after the escape.
: DO-ESCAPE 1+ C@+ &0 - 1+ STRING[] SE@-STRING STRING-COPY $+! ;

\ For the range to CP2 from CP1 : "It STARTS with a substring escape"
: ESCAPE? 2DUP - 1 > >R         \ At least two char's
          DUP C@+ &\ = >R       \ First char '\'
          C@ &0 &9 1+ WITHIN >R \ Second char a digit.
          2DROP
          R> R> R> AND AND ;

\ For a range to CP2 from CP1 add the first item to ``STRING-COPY''.
\ Leave CP2 and an incremented CP1.
: DO-ONE-CHAR 2DUP ESCAPE? IF DO-ESCAPE ELSE C@+ STRING-COPY $C+ THEN ;

\ Use the replacement STRING to replace the matched part for a recent call
\ of ``RE-MATCH''.
: RE-REPLACE
    BEFORE\0 STRING-COPY $!
    BOUNDS BEGIN 2DUP > WHILE DO-ONE-CHAR REPEAT 2DROP
    AFTER\0 STRING-COPY $+!
    STRING-COPY $@ ;
\D INCLUDE debug-re.frt
