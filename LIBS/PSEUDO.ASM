; Pseudoinstruções para facilitar a leitura, em forma de macros
;=====================================================


;Instruções do Cesar

_clr        MACRO   sym
    xor sym, sym
ENDM

_tst        MACRO   sym
    test sym, sym
ENDM


;Obter o módulo de um valor recém calculado
_abs       MACRO   sym
    jns @F
    neg sym
@@:
ENDM
