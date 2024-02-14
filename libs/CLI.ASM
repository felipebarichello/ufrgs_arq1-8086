ARGS_SIZE   EQU     80h
ARGS_PTR    EQU     81h

get_args    PROC NEAR C, buffer:WORD
    ;Salvar segmentos
    push ds
    push es

    ;Trocar DS com ES para poder usa o `rep movsb`
    mov ax, ds 
    mov bx, es
    mov ds, bx
    mov es, ax

    ;Colocar o tamanho do string da linha de comando em `cx`, a fim de repetir `movsb` `cx` vezes
    mov si, ARGS_SIZE
    mov ch, 0
    mov cl, [si]
    mov ax, cx ;Retornar o tamanho do string em `ax`

    mov si, ARGS_PTR ; Inicializa o ponteiro de origem
    mov di, buffer ; Inicializa o ponteiro de destino
    rep movsb

    ;Restaurar segmentos
    pop es
    pop ds

    ret
get_args    ENDP
