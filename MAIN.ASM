.MODEL small

;Macros e constantes
INCLUDE <LIBS\CONSTS.ASM>
INCLUDE <LIBS\SYSCALL.ASM>
INCLUDE <LIBS\CESAR.ASM>

.STACK

.DATA
    ;Strings constantes de uso interno
    str_input_file_default    DB "a.in",0
    str_output_file_default   DB "a.out",0
    str_voltage_default       DB "127",0

    ;Strings constantes de informação
    str_prtprm_i              DB "Arquivo de entrada: ",0
    str_prtprm_o              DB CR,LF,"Arquivo de saida: ",0
    str_prtprm_v              DB CR,LF,"Tensao esperada: ",0
    str_ptrprm_end            DB CR,LF,0

    ;Strings constantes de erro
    str_invalid_argument_pre  DB "Argumento [",0
    str_invalid_argument_post DB "] invalido.",CR,LF,0
    str_missing_value_pre     DB "Opcao [",0
    str_missing_value_post    DB "] sem parametro.",CR,LF,0
    str_invalid_voltage       DB "Parametro da opcao [-v] deve ser 127 ou 220.",CR,LF,0
    str_error_fopen           DB "Erro ao abrir arquivo.",CR,LF,0

    ;Variáveis para a CLI
    command      DB 127 DUP(?)
    input_file   DW OFFSET str_input_file_default
    output_file  DW OFFSET str_output_file_default
    voltage      DB 127
    voltage_str  DW OFFSET str_voltage_default

    ;Variáveis para a leitura do arquivo
    fhandle          DW ?
    volt_buffer_ptr  DW ?
    volt_buffer_size DW ?


.CODE

;Bibliotecas de funções
INCLUDE <LIBS\STRING.ASM>
INCLUDE <LIBS\CECHIN.ASM>
INCLUDE <LIBS\CLI.ASM>

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

    jmp end_program

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
    jc  end_program

    mov input_file, di ;Armazenar nome do arquivo de entrada
    
    mov bx, di

    jmp cli_continue

cli_o:
    ;Obter o valor da opção. Se não houver valor, terminar programa.
    call option_value
    jc  end_program

    mov output_file, di ;Armazenar nome do arquivo de saída
    jmp cli_continue

cli_v:
    ;Obter o valor da opção. Se não houver valor, terminar programa.
    call option_value
    jc  end_program

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
    jmp end_program

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
    _print str_ptrprm_end

    ; ;Abrir arquivo
    ; _fopen input_file, FMODE_READ
    ; jnc @F

    ; ;Tratar erro, se houver
    ; _print str_error_fopen
    ; jmp end_program

@@:
    ; ;Apenas os primeiros 16 kb são lidos.
    ; _fread fhandle, sp, 3FFFh
    ; mov volt_buffer_ptr, sp
    ; mov volt_buffer_size, ax ;Armazenar tamanho do buffer para desalocá-lo posteriormente
    ; sub sp, ax ;Reservar espaço utilizado pelo buffer
    ; _fclose fhandle

    ; mov di, volt_buffer_ptr
    ; mov al, ','
    ; _next_token

end_program:
    ;Fim do programa. Desalocar buffer.
    add sp, volt_buffer_size

.EXIT

END
