; Procedimentos relacionados a strings
;======================================

;Calcula o tamanho de uma string
;`di` deve apontar para o início da string
;Ao fim da execução, `cx` contém o tamanho da string
strlen      PROC    NEAR
    mov cx, -1
    _clr al ;Procurar por '\0'
    repne scasb
    not cx ;(not n) <=> (neg n+1) para n < 0
    dec cx ;Descontar o '\0'
    ret
strlen      ENDP

;Substitui todas as instâncias do separador por '\0', transformando uma string em uma sequência de tokens.
tokenize    PROC    NEAR
    _clr bx
    _clr cx ;Número de tokens - 1
    
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

_tokenize   MACRO   string:REQ, separator:=<' '>, copy:=<lea>
    copy di, string
    mov al, separator
    call tokenize
ENDM


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
