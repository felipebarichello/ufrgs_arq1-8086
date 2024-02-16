SIXTY       DB 60

s2hms       PROC    NEAR
    div SIXTY ;Dividir os segundos totais por 60 para obter os minutos totais
    mov dx, ax ;Agora, `dl` contém os minutos totais, e `dh` contém os segundos mod 60
    cbw ;Converter `al` para `ax`. Agora `ax` contém os minutos totais
    div SIXTY ;Dividir os minutos totais por 60 para obter as horas

    ;dh: segundos mod 60
    ;ah: minutos mod 60
    ;al: horas totais
    ret
s2hms       ENDP


;Executar `s2hms` antes. `bx` deve conter o endereço do buffer de destino
hms2str     PROC    NEAR
    _tst ax ;Testar se chegou a um minuto.
    jz  no_minutes

    ;Chegou a um minuto.
    push dx ;Salvar segundos
    _tst al ;Testar se chegou a uma hora.
    jz  no_hours

    ;Chegou a uma hora.
    push ax ;Salvar minutos
    cbw ;Converter horas para WORD
    call sprintf_w ;Converter horas para string
    mov BYTE PTR [bx], ':' ;Inserir ':' ao fim das horas
    inc bx ;Avançar para o próximo caractere
    pop ax ;Restaurar minutos

no_hours:
    mov al, ah
    cbw ;Converter minutos para WORD
    call sprintf_w ;Converter minutos para string
    mov BYTE PTR [bx], ':' ;Inserir ':' ao fim dos minutos
    inc bx ;Avançar para o próximo caractere
    pop dx ;Restaurar segundos

no_minutes:
    mov al, dh
    cbw ;Converter segundos para WORD
    call sprintf_w ;Converter segundos para string
    mov BYTE PTR [bx], 0 ;Inserir '\0'
    ret
hms2str     ENDP
