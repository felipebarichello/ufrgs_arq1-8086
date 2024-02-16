; Macros para syscalls
;======================

FMODE_READ  EQU    0
FMODE_WRITE EQU    1
FMODE_RW    EQU    2


DOS         EQU     21h
_syscall    MACRO   fncode:REQ, idreg:=<ah>
    mov idreg, fncode
    int DOS
ENDM


FCREATE     EQU     3Ch
_fcreate    MACRO   file_name:REQ
    mov dx, file_name
    _syscall FCREATE
ENDM

;Retorno:
;   `cf` <=> erro
;   `ax` = handle ou erro
FOPEN       EQU     3Dh
_fopen      MACRO   file_name:REQ, mode:REQ
    mov dx, file_name
    _syscall (FOPEN*100h+mode), ax ;ah = FOPEN, al = mode
ENDM

;Argumentos:
;   `file` - File handle
;   `buffer` - EA do buffer em DS
;   `size` - Número de bytes a serem lidos
;
;Retorno:
;   `cf` <=> erro
;   `ax` = número de bytes lidos
FREAD       EQU     3Fh
_fread      MACRO   file:REQ, buffer:REQ, size:REQ
    mov bx, file                      
    mov cx, size                      
    mov dx, buffer                    
    _syscall FREAD
ENDM

;Argumentos:
;   `bx` - File handle
;   `buffer` - EA do buffer em DS
;   `size` - Número de bytes a serem escritos
;
;Retorno:
;   `cf` <=> erro
;   `ax` = número de bytes escritos
FWRITE      EQU     40h
_fwrite     MACRO   buffer:REQ, size:REQ
    mov dx, buffer
    mov cx, size
    _syscall FWRITE
ENDM

;Argumentos:
;   `bx` - File handle
;   `msg` - EA do buffer em DS
;
;Retorno:
;   `cf` <=> erro
;   `ax` = número de bytes escritos
_fwrite_msg MACRO   msg:REQ
    mov dx, OFFSET msg                 
    mov cx, LENGTHOF msg-1
    _syscall FWRITE
ENDM

;Argumentos:
;   `file` - File handle
FCLOSE      EQU     3Eh
_fclose     MACRO   file
    mov bx, file         
    _syscall FCLOSE
ENDM
