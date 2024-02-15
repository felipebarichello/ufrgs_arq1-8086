;Macros e constantes fixas
INCLUDE <LIBS\SYSCALL.ASM>
INCLUDE <LIBS\ASCII.ASM>
INCLUDE <LIBS\CESAR.ASM>

;Parâmetros do programa
STACK_SIZE  EQU 0400h ;(1 kb)
BUFFER_SIZE EQU 2000h ;(16 kb)
MAX_VOLTAGE EQU 499

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
    str_invalid_measure1      DB "Linha [",0
    str_invalid_measure2      DB "] invalida: ",DQUOTE,0
    str_invalid_measure3      DB DQUOTE,CR,LF,0

    ;Variáveis para a CLI
    command     DB 127 DUP(?)
    input_file  DW OFFSET str_input_file_default
    output_file DW OFFSET str_output_file_default
    voltage     DW 127
    voltage_str DW OFFSET str_voltage_default

    ;Variáveis para manipulação de arquivos
    fhandle         DW ?
    file_buffer     DB BUFFER_SIZE DUP(?)
    bytes_read      DW ?
    
    ;Outras variáveis
    error_ocurred DB 0 ;Flag de erro para quando o erro não pode terminar o programa (por exemplo, enquanto um arquivo está aberto)
    phases        DW 3 DUP(?)
    needs_comma   DB 0 ;Flag que indica se é necessário uma vírgula agora para separar os valores
    int_buffer    DB 6 DUP(?) ;Buffer para conversão de inteiros para string. Espaço para 65535 + '\0'.        


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
    INVOKE get_args, OFFSET command

    ;Igualar o ES ao DS para facilitar a manipulação de strings
    mov ax, ds 
    mov es, ax

    cld ;Garantir que a string será lida da esquerda para a direita

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
    mov voltage, ax ;Armazenar valor da tensão

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
    ;Abrir arquivo
    _fopen input_file, FMODE_READ
    jnc measures_open_end

    ;Falha ao abrir arquivo. Tratar erro.
    ;`ax` contém o código do erro.
    mov cx, ax ;printf_s usa `ax`

    _error str_error_ifopen
    
    cmp cx, 2 ;Erro de arquivo não encontrado
    jne @F ;Outro erro

    ;Arquivo não encontrado
    _print str_error_not_found

@@:
    jmp exit_err

measures_open_end:
    mov fhandle, ax


measures_fread:
    mov si, OFFSET file_buffer ;Setar `si` para usar com instruções de string

    ;Ler arquivo para o buffer. São lidos no máximo BUFFER_SIZE bytes por vez.
    _fread fhandle, si, BUFFER_SIZE
    jnc measures_read_setup

    ;Falha ao ler arquivo. Tratar erro.
    inc error_ocurred
    _error str_error_ifread
    jmp measures_close

measures_read_setup:
    mov bytes_read, ax ;Armazenar quantidade de bytes lidos

    ;`ah` conta quantas fases foram lidas na medida atual
    ;(ah < 0) => (linha inválida)
    _clr ah
    mov cx, 1 ;`cx` marca a linha atual (o número de linhas do arquivo)
    mov di, si ;`di` marca o início da linha atual


;jmp aqui para ler o próximo caractere e parseá-lo
measures_read_lods:
    lodsb ;Carregar próximo byte em `al`

;jmp aqui se o próximo caractere já foi lido
measures_read_parse:
    ;Verificar se está abaixo ou acima dos números ASCII
    cmp al, '9'
    ja  measures_read_above
    cmp al, '0'
    jb  measures_read_below

    ;É um número ASCII. Transformar string em número se não houver uma vírgula faltando.
    ;Verificar ausência de vírgula
    cmp needs_comma, 0
    jne measures_read_invalid ;Se for necessário uma vírgula, não poderia haver um número

    inc ah ;Incrementar contador de fases
    cmp ah, 3 ;Verificar em que fase está
    ja  measures_read_invalid ;Se esta é a quarta fase fase, a linha é inválida
    
    inc needs_comma ;Marcar que é necessário uma vírgula para separar os valores

@@:
    lea bx, [si-1] ;Armazenar ponteiro para o início do número
    
@@:
    lodsb ;Procurar fim do número
    cmp al, '0'
    jb  @F
    cmp al, '9'
    jna @B

@@:
    ;Fim do número. `si` aponta para o segundo caractere que não faz parte do número.
    ;`al` é o valor do primeiro caractere que não faz parte do número.
    ;Salvar registradores
    push ax
    push cx

    mov dh, ah ;Salvar número da fase

    mov BYTE PTR [si-1], 0 ;Colocar um '\0' no fim do número. O caractere sobrescrito estará em `al` após um `pop ax`.
    call atoi ;Converter string para número

    ;Setar número da fase como offset
    _clr bh
    mov bl, dh

    ;Verificar se é um valor válido
    cmp ax, MAX_VOLTAGE
    ja  measures_read_invalid ;Tensão acima do valor máximo

    mov phases[bx], ax ;Armazenar valor da fase

    ;Restaurar registradores
    pop cx
    pop ax

    ;O caractere sobrescrito está em `al`. Restaurá-lo.
    mov BYTE PTR [si-1], al
    
    ;O caractere sobrescrito está em `al`. Continuar lendo a partir dele (não executar o `lodsb`).
    jmp measures_read_parse
    

measures_read_below:
    ;Vírgulas separam as fases de uma mesma medida
    cmp al, ','
    je  measures_comma

    ;Pular ' ' e '\t'
    cmp al, ' '
    je  measures_read_lods
    cmp al, TAB
    je  measures_read_lods
    
    ;'\r', '\n', "\r\n" ou "\n\r" separam as medidas no tempo
    cmp al, CR
    je  measures_line_break
    cmp al, LF
    je  measures_line_break

    ;Não é um caractere válido
    jmp measures_read_invalid


measures_read_above:
    ;Testar se é "fim" (case insensitive)
    cmp al, 'f'
    je  @F
    cmp al, 'F'
    jne measures_read_invalid

@@:
    lodsb
    cmp al, 'i'
    je  @F
    cmp al, 'I'
    jne measures_read_invalid

@@:
    lodsb
    cmp al, 'm'
    je  measures_read_end
    cmp al, 'M'
    je  measures_read_end
    jmp measures_read_invalid

measures_comma:
    ;Verificar se é necessário uma vírgula
    cmp needs_comma, 0
    je  measures_read_invalid ;Não era necessário uma vírgula. Erro.

    ;Era necessário uma vírgula. Resetar flag.
    mov needs_comma, 0
    jmp measures_read_lods


;Quebra de linha ('\r', '\n', "\r\n" ou "\n\r")
measures_line_break:
    ;Verificar se a linha é válida
    cmp ah, 3 ;Verificar se foram lidas 3 fases
    je  measures_line_ok

    ;Se foram lidas um número de fases diferente de 3,
    ;ou caso a linha já tenha sido marcada como inválida, tratar erro
    
    ;Salvar o caractere atual na stack
    push ax ;Caractere atual de quebra de linha

    ;Linha inválida 
    inc error_ocurred ;Marcar erro para quando o arquivo for fechado
    
    _print str_invalid_measure1 ;Imprimir o começo da mensagem de erro
    mov ax, cx ;Número da linha
    mov bx, OFFSET int_buffer ;Carregar buffer
    call sprintf_w ;Transformar o número da linha em string
    _print int_buffer ;Imprimir número da linha
    _print str_invalid_measure2 ;Imprimir o meio da mensagem de erro

    mov BYTE PTR [si-1], 0 ;Colocar um '\0' no fim da linha
    _print di, mov ;Imprimir todo o conteúdo da linha antes da quebra de linha
    _print str_invalid_measure3 ;Imprimir quebra de linha

    pop ax ;Restaurar caractere atual de quebra de linha

measures_line_ok:
    _clr ah
    mov needs_comma, 0 ;Resetar flag de vírgula
    inc cx ;Incrementar contador de linhas
    mov di, si ;Salvar início da nova linha. `si` aponta para o caractere após a quebra de linha

    ;Linha válida ou já tratada
    ;Verificar se o próximo caractere é um caractere de quebra de linha diferente
    mov bl, al
    lodsb

    cmp al, CR
    je  measures_check_double_line_break
    cmp al, LF
    jne measures_read_parse

measures_check_double_line_break:
    ;Há uma nova linha se e somente se os dois caracteres forem iguais
    cmp al, bl
    je  @F
    
    ;Os dois caracteres são diferentes. É um "\r\n" ou "\n\r". A nova linha está então no próximo caractere.
    inc di
    jmp measures_read_lods

@@:
    ;Os dois caracteres são iguais. Há uma nova linha.
    jmp measures_line_break


;A linha não é válida. Imprimir erro e continuar a partir da próxima linha.
measures_read_invalid:
    mov ah, -1 ;Marcar linha como inválida

measures_skip_line_loop:
    ;Encontrar próxima linha
    cmp al, CR
    je  measures_line_break
    cmp al, LF
    je  measures_line_break
    lodsb
    jmp measures_skip_line_loop

measures_read_end:
    ;Se o buffer estiver cheio, o arquivo pode não ter sido lido até o fim. Continuar lendo.
    cmp bytes_read, BUFFER_SIZE
    je  measures_fread

measures_close:
    _fclose fhandle
    jnc @F

    ;Falha ao fechar arquivo. Tratar erro.
    _print str_error_ifclose
    jmp exit_err

@@:
    cmp error_ocurred, 0
    jne exit_err

    ; mov di, file_buffer
    ; mov al, ','
    ; call next_token

    ;TODO: Relatório impresso
    ;TODO: Relatório arquivado

    jmp exit_ok

exit_err:
exit_ok:
end_program:

.EXIT

END
