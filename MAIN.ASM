;Macros e constantes fixas
INCLUDE <LIBS\SYSCALL.ASM>
INCLUDE <LIBS\ASCII.ASM>
INCLUDE <LIBS\CESAR.ASM>

;Parâmetros do programa
STACK_SIZE  EQU 0800h ;(2 kb)
BUFFER_SIZE EQU 0400h ;(1 kb)

.MODEL small

.STACK      STACK_SIZE

.DATA
    ;Strings constantes de uso interno
    str_input_file_default    DB "a.in",0
    str_output_file_default   DB "a.out",0
    str_voltage_default       DB "127",0

    ;Strings constantes de relatório
    str_crlf                  DB CR,LF,0
    str_prtprm_i              DB "Arquivo de entrada: ",0
    str_prtprm_o              DB CR,LF,"Arquivo de saida: ",0
    str_prtprm_v              DB CR,LF,"Tensao esperada: ",0

    ;Strings constantes de erro
    str_error                 DB "ERRO: ",0
    str_invalid_argument_pre  DB "Argumento [",0
    str_invalid_argument_post DB "] invalido.",CR,LF,0
    str_missing_value_pre     DB "Opcao [",0
    str_missing_value_post    DB "] sem parametro.",CR,LF,0
    str_invalid_voltage       DB "Parametro da opcao [-v] deve ser 127 ou 220.",CR,LF,0
    str_error_ifopen          DB "Erro ao abrir arquivo de entrada.",CR,LF,0
    str_error_ifread          DB "Erro ao ler arquivo de entrada.",CR,LF,0
    str_error_not_found       DB "Arquivo nao encontrado.",CR,LF,0
    str_error_ifclose         DB "Erro ao fechar arquivo de entrada.",CR,LF,0

    ;Variáveis para a CLI
    command      DB 127 DUP(?)
    input_file   DW OFFSET str_input_file_default
    output_file  DW OFFSET str_output_file_default
    voltage      DB 127
    voltage_str  DW OFFSET str_voltage_default

    ;Variáveis para a leitura do arquivo
    fhandle          DW ?
    file_buffer   DW ?

dbg_read DB "Arquivo lido com sucesso",0

.CODE

;Bibliotecas de funções
INCLUDE <LIBS\STRING.ASM>
INCLUDE <LIBS\CECHIN.ASM>
INCLUDE <LIBS\CLI.ASM>

_print      MACRO   msg:REQ, copy:=<lea>
	copy bx, msg
	call printf_s
ENDM

_error       MACRO  cause:REQ, copy:=<lea>
    _print str_error
    _print cause, copy
ENDM

;Coloca um ponteiro para o valor da opção em `di` e verifica a sua validade.
;(CF == 1) <=> erro
option_value PROC NEAR
    mov si, di

option_value_loop:
    dec cx
    jz  missing_value

    call next_token
    cmp BYTE PTR [di], 0 ;Se o token for vazio, ignorar e ler o próximo
    je  option_value_loop

    ;Há argumentos após a opção. Verificar se é um valor.
    cmp BYTE PTR [di], '-' ;Se for uma opção, o valor não está presente
    je  missing_value

    clc
    ret

missing_value:
    _print str_missing_value_pre
    _print si, mov
    _print str_missing_value_post

    stc
    ret
option_value ENDP


.STARTUP
    INVOKE get_args, ADDR command

    ;Igualar o ES ao DS para facilitar a manipulação de strings
    mov ax, ds 
    mov es, ax

    ;Tokenizar a string de comando
    _tokenize command
    _tst cx
    jz cli_end ;Se não houver mais de um token, pular o CLI.

cli_read_option:
    call next_token ;Próximo argumento. Se for o primeiro, é apenas um espaço.
    mov ah, [di] ;Armazenar caractere atual

    _tst ah
    jz  cli_continue ;Se for um token vazio, era apenas um espaço. Ignorar.

    cmp ah, '-' ;Verificar se é uma opção
    je  cli_is_option ;É uma opção. Continuar lendo.

;Não é uma opção. Imprimir erro e sair.
cli_invalid:
    _print str_invalid_argument_pre
    _print di, mov
    _print str_invalid_argument_post

    jmp exit_err

cli_is_option:
    mov ah, [di+2] ;Armazenar segundo caractere da opção (após o '-')
    _tst ah ;Se não for um '\0' (espaço tokenizado), é muito grande para ser qualquer uma das opções
    jnz cli_invalid

    mov ah, [di+1] ;Armazenar letra da opção
    cmp ah, 'a'
    jnb  @F ;Pula conversão se for letra minúscula

    ;É letra maiúscula (ou inválido). Converter para minúscula.
    add ah, ('a'-'A')

@@:
    sub ah, 'i' ;Verificar se é '-i'
    je  cli_i

    sub ah, 'o'-'i' ;Verificar se é '-o'
    je  cli_o

    sub ah, 'v'-'o' ;Verificar se é '-v'
    je  cli_v

    jmp cli_invalid ;Opção inválida. Imprimir erro e sair.

cli_i:
    ;Obter o valor da opção. Se não houver valor, terminar programa.
    call option_value
    jc  exit_err

    mov input_file, di ;Armazenar nome do arquivo de entrada
    
    mov bx, di

    jmp cli_continue

cli_o:
    ;Obter o valor da opção. Se não houver valor, terminar programa.
    call option_value
    jc  exit_err

    mov output_file, di ;Armazenar nome do arquivo de saída
    jmp cli_continue

cli_v:
    ;Obter o valor da opção. Se não houver valor, terminar programa.
    call option_value
    jc  exit_err

    ;Converter string para número
    mov bx, di
    call atoi

    ;Verificar se o número é válido
    cmp ax, 127
    je  cli_v_valid

    cmp ax, 220
    je cli_v_valid

    ;Número inválido. Imprimir erro e sair.
    _print str_invalid_voltage
    jmp exit_err

cli_v_valid:
    mov voltage_str, di ;Armazenar string do valor da tensão
    mov voltage, al ;Armazenar valor da tensão

cli_continue:
    dec cx
    jnz cli_read_option ;Se ainda houver tokens, continuar o loop.

cli_end:
    ;Imprimir parâmetros
    _print str_prtprm_i
    _print input_file, mov
    _print str_prtprm_o
    _print output_file, mov
    _print str_prtprm_v
    _print voltage_str, mov
    _print str_crlf

measures_open:
    ;Alocar espaço para o buffer
    sub sp, BUFFER_SIZE
    mov file_buffer, sp

    ;Abrir arquivo
    _fopen input_file, FMODE_READ
    jnc measures_read

    ;Falha ao abrir arquivo. Tratar erro.
    ;`ax` contém o código do erro.
    mov cx, ax ;printf_s usa `ax`

    _error str_error_ifopen
    
    cmp cx, 2 ;Erro de arquivo não encontrado
    jne @F

    ;Arquivo não encontrado
    _print str_error_not_found

@@:
    ;Outro erro
    jmp exit_err

measures_read:
    mov fhandle, ax

    ;Ler arquivo para o buffer. São lidos no máximo BUFFER_SIZE bytes por vez.
    _fread fhandle, sp, BUFFER_SIZE
    jnc measures_process

    ;Falha ao ler arquivo. Tratar erro.
    _print str_error_ifread
    jmp exit_err

measures_process:
    ;DBG
    _print dbg_read
    jmp measures_close


measures_close:
    _fclose fhandle
    jnc @F

    ;Falha ao fechar arquivo. Tratar erro.
    _print str_error_ifclose
    jmp exit_err

@@:
    ; mov di, file_buffer
    ; mov al, ','
    ; call next_token

    ;TODO: Relatório impresso
    ;TODO: Relatório arquivado

    jmp exit_ok

exit_err:
exit_ok:
end_program:
    ;Fim do programa. Desalocar buffer.
    add sp, BUFFER_SIZE

.EXIT

END
