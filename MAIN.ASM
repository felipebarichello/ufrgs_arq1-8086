.MODEL small

;Macros e constantes
INCLUDE <LIBS\CONSTS.ASM>
INCLUDE <LIBS\SYSCALL.ASM>
INCLUDE <LIBS\CESAR.ASM>

.STACK

.DATA
    ;Strings constantes
    str_input_file_default    DB "a.in",0
    str_output_file_default   DB "a.out",0
    str_invalid_argument_pre  DB "Argumento [",0
    str_invalid_argument_post DB "] invalido.",CR,LF,0

    ;Variáveis para a CLI
    command_size DB ?
    command      DB 127 DUP(?)
    argc         DW ?
    input_file   DW OFFSET str_input_file_default
    output_file  DW OFFSET str_output_file_default
    voltage      DB 127

    ;Variáveis para a leitura do arquivo
    fhandle          DW ?
    volt_buffer_ptr  DW ?
    volt_buffer_size DW ?


.CODE

;Bibliotecas de funções
INCLUDE <LIBS\STRING.ASM>
INCLUDE <LIBS\CECHIN.ASM>
INCLUDE <LIBS\CLI.ASM>

.STARTUP
    INVOKE get_args, ADDR command

    ;Igualar o ES ao DS para facilitar a manipulação de strings
    mov ax, ds 
    mov es, ax

    ;Tokenizar a string de comando
    lea di, command
    mov al, ' '
    call tokenize

    mov argc, cx

cli_read_option:
    ; mov al, [si]
    ; jz  cli_end

    jmp dbg_just_print ;DBG

    ;Argumento inválido. Imprimir erro e sair.
    lea bx, str_invalid_argument_pre
    call printf_s

    mov bx, di
    call printf_s

    lea bx, str_invalid_argument_post
    call printf_s

    jmp end_program

cli_skip_invalid:
    ;TODO

dbg_just_print:
    mov bx, di
    call printf_s

cli_next_option:
    _next_token
    jnz cli_read_option

cli_end:
    jmp end_program ;DBG

    ;Abrir arquivo
    _fopen input_file, FMODE_READ

    ;Apenas os primeiros 16 kb são lidos.
    _fread fhandle, sp, 3FFFh
    mov volt_buffer_ptr, sp
    mov volt_buffer_size, ax ;Armazenar tamanho do buffer para desalocá-lo posteriormente
    sub sp, ax ;Reservar espaço utilizado pelo buffer
    _fclose fhandle

    mov di, volt_buffer_ptr
    mov al, ','
    _next_token

end_program:
    ;Fim do programa. Desalocar buffer.
    add sp, volt_buffer_size

.EXIT

END
