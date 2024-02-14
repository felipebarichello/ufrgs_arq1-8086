; Instruções emprestadas do computador Cesar, em forma de macros
;================================================================


_clr        MACRO   sym
    xor sym, sym
ENDM

_tst        MACRO   sym
    test sym, sym
ENDM
