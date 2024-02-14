; Instruções emprestadas do computador Cesar
;============================================


_clr        MACRO   sym
    xor sym, sym
ENDM

_tst        MACRO   sym
    test sym, sym
ENDM
