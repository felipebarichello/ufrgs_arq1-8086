;Macros e constantes fixas
INCLUDE <LIBS\SYSCALL.ASM>
INCLUDE <LIBS\ASCII.ASM>
INCLUDE <LIBS\PSEUDO.ASM>

;Parâmetros do programa
STACK_SIZE  EQU 0400h ;(1 kb)
BUFFER_SIZE EQU 0C000h ;(60 kb)
MAX_VOLTAGE EQU 499

VOLTAGE_NONE EQU 0
VOLTAGE_BAD  EQU -1
VOLTAGE_GOOD EQU 1

VOLTAGE_NONE_THRESHOLD EQU 9
VOLTAGE_GOOD_RANGE     EQU 10

.MODEL small

.STACK      STACK_SIZE

.DATA
    ;Strings constantes defaults
    str_input_file_default    DB "a.in",0
    str_output_file_default   DB "a.out",0
    str_voltage_default       DB "127",0

    ;Strings constantes não relacionadas a erros
    str_crlf                  DB CR,LF,0
    str_prtprm_i              DB "Arquivo de entrada: ",0
    str_prtprm_o              DB CR,LF,"Arquivo de saida: ",0
    str_prtprm_v              DB CR,LF,"Tensao esperada: ",0
    str_measure_time          DB "Tempo de medida: ",0
    str_report_good           DB "Tempo de tensao adequada: ",0
    str_report_none           DB "Tempo sem tensao: ",0

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
    str_error_ofcreate        DB "Erro ao criar arquivo de saida.",CR,LF,0

    ;Variáveis para a CLI
    command                   DB 127 DUP(?) ;Comando que chamou o programa
    input_file_name_size      DW LENGTHOF str_input_file_default-1
    input_file                DW OFFSET str_input_file_default ;Arquivo de medidas
    output_file_name_size     DW LENGTHOF str_output_file_default-1
    output_file               DW OFFSET str_output_file_default ;Arquivo de relatório
    expected_voltage          DW 127 ;Tensão esperada nas medidas
    expected_voltage_str_size DW LENGTHOF str_voltage_default-1
    expected_voltage_str      DW OFFSET str_voltage_default ;String da tensão esperada

    ;Variáveis para manipulação de arquivos
    fhandle         DW ?
    file_buffer     DB BUFFER_SIZE DUP(?)

    ;Variáveis de leitura de arquivo de medidas
    bytes_read      DW ?
    needs_comma       DB 0 ;Flag que indica se é necessário uma vírgula agora para separar os valores
    voltage_quality   DB VOLTAGE_NONE ;Qualidade da tensão da medida
    voltage_time_good DW 0 ;Tempo total de tensão adequada
    voltage_time_none DW 0 ;Tempo total sem tensão

    ;Outras variáveis
    int_buffer    DB 6 DUP(?) ;Buffer para conversão de inteiros para string. Espaço para 65535 + '\0'.
    error_ocurred DB 0 ;Flag de erro para quando o erro não pode terminar o programa (por exemplo, enquanto um arquivo está aberto)
    clock_size    DW ? ;Tamanho utilizado do buffer de relógio
    clock_buffer  DB 9 DUP(?) ;Buffer para conversão de tempo para string. Espaço para "99:59:59" + '\0'.


.CODE

;Bibliotecas de funções
INCLUDE <LIBS\STRING.ASM>
INCLUDE <LIBS\CECHIN.ASM>
INCLUDE <LIBS\CLI.ASM>
INCLUDE <LIBS\CLOCK.ASM>

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
    
    ;Calcular tamanho do nome do arquivo
    push cx
    call strlen
    mov input_file_name_size, cx
    pop cx

    dec di ;Voltar para o separador para o próximo token
    jmp cli_continue

cli_o:
    ;Obter o valor da opção. Se não houver valor, terminar programa.
    call option_value
    jc  exit_err

    mov output_file, di ;Armazenar nome do arquivo de saída

    ;Calcular tamanho do nome do arquivo
    push cx
    call strlen
    mov output_file_name_size, cx
    pop cx

    dec di ;Voltar para o separador para o próximo token
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
    mov expected_voltage, ax ;Armazenar valor da tensão
    mov expected_voltage_str, di ;Armazenar string do valor da tensão

    ;Calcular tamanho da string do valor da tensão
    push cx
    call strlen
    mov expected_voltage_str_size, cx
    pop cx

    dec di ;Voltar para o separador para o próximo token

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
    _print expected_voltage_str, mov
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

    ;Ler arquivo para o buffer. São lidos no máximo BUFFER_SIZE bytes.
    ;Eu tinha feito uma boa parte do código pra ler o arquivo em partes menores,
    ;mas como este foi um semestre de quatro meses, às 10 horas de sexta-feira,
    ;eu dei um `git reset --hard` e me contentei com um buffer grande.
    ;Não está pedindo nas especificações, de qualquer forma.
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
    _clr cx ;`cx` conta as linhas lidas
    mov di, si ;`di` marca o início da linha atual
    mov voltage_quality, VOLTAGE_NONE ;Inicializar qualidade da tensão


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

    ;Verificar se é um valor válido
    cmp ax, MAX_VOLTAGE
    jna @F

    ;Tensão acima da máxima. Tratar erro.
    ;Restaurar estado do programa
    pop cx
    pop ax
    mov BYTE PTR [si-1], al ;O caractere sobrescrito está em `al`. Restaurá-lo.
    jmp measures_read_invalid ;Linha inválida

@@:
    ;Verificar a qualidade da tensão até então
    cmp voltage_quality, VOLTAGE_NONE

    ;Ruim: Pelo menos uma das fases medidas não estava nem "sem tensão" nem com tensão "boa".
    ;Não importa a qualidade da tensão de nenhuma das outras fases, a qualidade da tensão da medida é "ruim".
    js  measures_voltage_end

    ;Bom: Até agora, todas as fases estavam com tensão "boa".
    ;A qualidade da tensão é "boa" se e somente se cada uma das fases tiverem tensão "boa".
    ;Portanto a qualidade da tensão da medida então é setada para a qualidade da tensão da fase atual.
    jne measures_voltage_set

    ;Sem tensão: Até agora, todas as fases medidas estavam sem tensão, ou esta é a primeira fase.
    ;A qualidade da tensão é "sem tensão" se e somente se cada uma das fases forem "sem tensão"

    ;Se a tensão for menor ou igual a VOLTAGE_NONE_THRESHOLD, a qualidade da tensão é "sem tensão",
    ;e portanto não é necessário alterar a qualidade da tensão.
    ;Se for maior que isso, a qualidade da tensão da medida não pode ser "sem tensão".
    cmp ax, VOLTAGE_NONE_THRESHOLD
    jbe measures_voltage_end

measures_voltage_set:
    ;A tensão não é "sem tensão"
    ;A qualidade da tensão da medida então é setada para a qualidade da tensão da fase atual
    sub ax, expected_voltage ;Obter a diferença entre a tensão esperada e a tensão medida
    _abs ax ;Obter o módulo da diferença
    cmp ax, VOLTAGE_GOOD_RANGE ;Verificar se a diferença é menor ou igual a VOLTAGE_GOOD_RANGE
    jbe @F

    ;Se não for, a qualidade da tensão é "ruim"
    mov voltage_quality, VOLTAGE_BAD
    jmp measures_voltage_end

@@:
    ;Se for, a qualidade da tensão da medida é boa se e somente se esta for a primeira fase
    cmp dh, 1
    je  @F

    ;Não é a primeira fase, o que significa que uma das fases anteriores já teve uma qualidade de tensão "sem tensão"
    mov voltage_quality, VOLTAGE_BAD;Logo, a qualidade da tensão da medida é "ruim"

@@:
    ;É a primeira fase
    mov voltage_quality, VOLTAGE_GOOD

measures_voltage_end:
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
    inc cx ;Incrementar contador de linhas

    ;Verificar se a linha é válida
    cmp ah, 3 ;Verificar se foram lidas 3 fases
    je  measures_line_end

    ;Se foram lidas um número de fases diferente de 3,
    ;ou caso a linha já tenha sido marcada como inválida, tratar erro
    
    ;Salvar o caractere atual na stack
    push ax ;Caractere atual de quebra de linha

    ;Linha inválida 
    inc error_ocurred ;Marcar erro para quando o arquivo for fechado
    
    _print str_invalid_measure1 ;Imprimir o começo da mensagem de erro
    mov ax, cx ;Número da linha
    mov bx, OFFSET int_buffer ;Carregar buffer
    push cx
    call sprintf_w ;Transformar o número da linha em string
    pop cx
    _print int_buffer ;Imprimir número da linha
    _print str_invalid_measure2 ;Imprimir o meio da mensagem de erro

    mov BYTE PTR [si-1], 0 ;Colocar um '\0' no fim da linha
    _print di, mov ;Imprimir todo o conteúdo da linha antes da quebra de linha
    _print str_invalid_measure3 ;Imprimir quebra de linha

    pop ax ;Restaurar caractere atual de quebra de linha

measures_line_end:
    _clr ah
    mov needs_comma, 0 ;Resetar flag de vírgula
    mov di, si ;Salvar início da nova linha. `si` aponta para o caractere após a quebra de linha

    ;
    cmp voltage_quality, VOLTAGE_NONE
    js  measures_inc_quality_bad ;Tensão ruim
    jne  measures_inc_quality_good ;Tensão adequada
    inc voltage_time_none ;Sem tensão. Incrementar tempo sem tensão

measures_inc_quality_good:
    inc voltage_time_good ;Incrementar tempo de tensão adequada
    jmp measures_check_double_line_break

measures_inc_quality_bad:
    mov voltage_quality, VOLTAGE_NONE ;Resetar qualidade da tensão

measures_check_double_line_break:
    ;Linha válida ou já tratada
    ;Verificar se o próximo caractere é um caractere de quebra de linha diferente
    mov bl, al
    lodsb

    cmp al, CR
    je  @F
    cmp al, LF
    jne measures_read_parse

@@:
    ;Há uma nova linha se e somente se os dois caracteres forem iguais
    cmp al, bl
    je  measures_line_break ;Os dois caracteres são iguais. São duas quebras de linha.
    
    ;Os dois caracteres são diferentes. É um "\r\n" ou "\n\r". Não há nova linha.
    inc di ;Pular o segundo caractere da quebra de linha para fins de armazenar o início da próxima linha
    jmp measures_read_lods


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
measures_close:
    _fclose fhandle
    jnc @F

    ;Falha ao fechar arquivo. Tratar erro.
    _print str_error_ifclose
    jmp exit_err

@@:
    cmp error_ocurred, 0
    jne exit_err


    ;Não houve erro. Imprimir tempo de medida.
    mov ax, cx ;Segundos
    mov bx, OFFSET clock_buffer ;Buffer
    call s2hms ;Segundos para horas, minutos, segundos
    call hms2str ;Horas, minutos, segundos para string
    sub bx, OFFSET clock_buffer
    mov clock_size, bx
    _print str_measure_time
    _print clock_buffer
    _print str_crlf

    ;Criar arquivo de relatório
    _fcreate output_file
    jnc @F

    ;Falha ao criar arquivo de relatório. Tratar erro.
    _error str_error_ofcreate
    jmp exit_err

@@:
    mov fhandle, ax
    
    ;Escrever relatório
    ;Escrever informações dos parâmetros
    mov bx, ax ;Carregar handle do arquivo de relatório
    _fwrite_msg str_prtprm_i
    _fwrite input_file, input_file_name_size
    _fwrite_msg str_prtprm_o
    _fwrite output_file, output_file_name_size
    _fwrite_msg str_prtprm_v
    _fwrite expected_voltage_str, expected_voltage_str_size
    _fwrite_msg str_crlf
    _fwrite_msg str_crlf

    ;Escrever tempo total de medida
    _fwrite_msg str_measure_time
    mov dx, OFFSET clock_buffer ;Não dá pra usar a macro aqui
    mov cx, clock_size          ;
    _syscall FWRITE             ;
    _fwrite_msg str_crlf

    ;Calcular tempo de tensão adequada
    _fwrite_msg str_report_good
    mov ax, voltage_time_good ;Segundos
    mov bx, OFFSET clock_buffer ;Buffer
    call s2hms ;Segundos para horas, minutos, segundos
    call hms2str ;Horas, minutos, segundos para string

    ;Escrever tempo de tensão adequada
    mov dx, OFFSET clock_buffer
    ; lea cx, [bx - OFFSET clock_buffer] ;Não funciona por algum motivo
    mov cx, bx
    sub cx, OFFSET clock_buffer
    mov bx, fhandle
    _syscall FWRITE
    _fwrite_msg str_crlf

    ;Calcular tempo sem tensão
    _fwrite_msg str_report_none
    mov ax, voltage_time_none ;Segundos
    mov bx, OFFSET clock_buffer ;Buffer
    call s2hms ;Segundos para horas, minutos, segundos
    call hms2str ;Horas, minutos, segundos para string

    ;Escrever tempo sem tensão
    mov dx, OFFSET clock_buffer
    ; lea cx, [bx - OFFSET clock_buffer] ;Não funciona por algum motivo
    mov cx, bx
    sub cx, OFFSET clock_buffer
    mov bx, fhandle
    _syscall FWRITE
    _fwrite_msg str_crlf


    ;Fechar arquivo
    _fclose fhandle

    jmp exit_ok

exit_err:
exit_ok:
end_program:

.EXIT

END
