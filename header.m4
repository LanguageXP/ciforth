dnl  $Id$  M4 file to handle the develish FIG headers.
dnl Copyright(2000): Albert van der Horst, HCC FIG Holland by GNU Public License
dnl
dnl _STRING : Lay down a string in memory.
dnl Take care of embedded double quotes by using single quotes.
dnl Note: this cannot be used in HEADER, because index must look in the real string,
dnl not on some variable that contains the string.
dnl The digression using _squote is needed because the single quote is used in m4.
define(_squote,')
define({_dbquoted},"{{$1}}")dnl
define({_sgquoted},'{{$1}}')dnl
define({_quoted},{ifelse( -1, index({$1},{"}),{_dbquoted},{_sgquoted})}({{$1}}))
define({_STRING},
{DC      len({$1})
        DSS      _quoted}({{$1}}))dnl
define({_sc},0)dnl
define({_STRINGINLINE},
{DC      SKIP
         DC      len({$1})
SB{}_sc: DSS      _quoted}({{$1}})
{       DC      LIT, SB{}_sc
        DC      LIT, len({$1})
define({_sc},{incr}(_sc))dnl })dnl
dnl
dnl _VOCLINKOLD is a m4 variable that generates a chain of vocabularies.
define({_VOCLINKOLD},0)dnl
define(_VOCLINK,
        {DC      DOVOC
        DC      _VOCLINKOLD{}define({_VOCLINKOLD},_LINKOLD)dnl
})dnl
dnl We lay down a nice square around the definition as a tribute to Thomas Newman
dnl _star(x) generates x stars
define({_star},{ifelse}(0,$1,,{*{_star}({decr}($1))}))
dnl _LINKOLD is a m4 variable that generates numbers in sequence.
define({_LINKOLD},0)dnl
dnl Lay down a header with forth name $1, assembler name $2 and code field $3
dnl and data field $4, flag field $5, link field $6.
dnl All except the assembler name are optional.
define(HEADER, {dnl
ifelse(0,len({$1}),,
;  ********_star(len({$1}))
;  *   {{$1}}   *
;  ********_star(len({$1}))
;
N_$2:   {_STRING}({{$1}}))
ifelse(0,len($2),,$2:)dnl
        DC    ifelse(0,len($3),0H,$3)
        DC    ifelse(0,len($4),$ + _CELLS(PH_OFFSET-D_HOFFSET),$4)
        DC    ifelse(0,len($5),0H,$5)
        DC    ifelse(0,len({$6}),dnl Only link in if there is no explicit link.
{_LINKOLD{}define({_LINKOLD},{$2-_CELLS(C_HOFFSET)})},dnl
$6)
        DC    ifelse(0,len({$1}),0,N_$2)
})dnl
dnl
dnl
dnl ------------------ to get dictionaries better under control -------------------------------------
dnl Remember! The assembler names denote the code field.
dnl The link etc. field of the word with assembler name $1
define({_DEA},{$1-_CELLS(C_HOFFSET)})dnl
define({_LINK_FIELD},{($1+_CELLS(L_HOFFSET-C_HOFFSET))})dnl
define({_CODE_FIELD},$1)dnl
define({_VAR_FIELD},{($1+_CELLS(PH_OFFSET-C_HOFFSET))})dnl
dnl     Handle Branching
define({_0BRANCH},dnl
{DC      ZBRAN
        DC      $1-$-CW})dnl
define({_BRANCH},dnl
{DC      BRAN
        DC      $1-$-CW})dnl
define({_DO},dnl
{DC     XDO
        DC      $1-$-CW})dnl
define({_QDO},dnl
{DC     XQDO
        DC      $1-$-CW})dnl
define({_LOOP},dnl
{DC     XLOOP
        DC      $1-$-CW})dnl
dnl The field where a pointer to the latest entry of a vocabulary resides.
define({CODE_HEADER},
{HEADER({$1},
{$2},
{$+_CELLS(PH_OFFSET-C_HOFFSET)},
{$+_CELLS(PH_OFFSET-D_HOFFSET)},
$5)})dnl
define({JMPHERE_FROM_PROT},{})dnl
define({JMPHERE_FROM_REAL},{})dnl
define({JMPFAR},{DB    0EAH})dnl
define({_CELLS},(CW*($1)))dnl
#
# Start of Intel dependant code part
# The 32 bit version may be used in the postlude to redefine
# _NEXT etc. to generate faster code.
#
# See definition of NEXT in glossary.
define({_NEXT},{JMP     NEXT})
define({_NEXT32},
        {LODSW                 ; NEXT
        JMP     _CELL_PTR[WR]  } )
# See definition of PUSH in glossary.
define({_PUSH},{JMP     APUSH})
define({_PUSH32},
        {PUSH    AX
        _NEXT32})
# Like PUSH but for two numbers.
define({_2PUSH},{JMP     DPUSH})
define({_2PUSH32},
        {PUSH    DX
        _PUSH32})
