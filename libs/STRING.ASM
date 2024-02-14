; Procedimentos relacionados a strings
;======================================

strcpy      PROC    NEAR
    _clr bx

strcpy_loop:
    mov ax, [si]
    mov [di], ax
    _tst ax
    jz  strcpy_end

    inc bx
    jmp strcpy_loop

strcpy_end:
    ret
strcpy      ENDP             


;Substitui todas as instâncias do separador por '\0', transformando uma string em uma sequência de tokens.
tokenize    PROC    NEAR
    _clr bx
    mov cx, 1 ;Número de tokens. Começa em 1, pois se não houver separadores, há um token.
    
tokenize_loop:
    mov ah, [di+bx]
    _tst ah
    jz  tokenize_end

    inc bx
    cmp ah, al
    jne tokenize_loop

    ;Encontrou o separador. `di+bx` aponta para o caractere após o separador.
    inc cx
    mov BYTE PTR [di+bx-1], 0
    jmp tokenize_loop

tokenize_end:
    ret
tokenize    ENDP


;Retorna o próximo token de uma sequência de tokens
;Só funciona corretamente se (DF == 0)
;`di` deve apontar para um token
;Ao fim da execução, o próximo token começa em `di`
;`si` não é alterado
;(ZF == 1) <=> (cx == 0) <=> (não há mais tokens)
next_token  PROC    NEAR USES cx
    mov cx, -1
    _clr al ;Prepara para procurar por '\0'
    repne scasb ;Procura por '\0'
    ;`di` aponta para o primeiro caractere do próximo token

    ret
next_token  ENDP

_next_token MACRO   counter:=<cx>
    call next_token
    dec counter ;Decrementa o contador de tokens
ENDM 
