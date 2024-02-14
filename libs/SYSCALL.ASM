; Macros para syscalls
;======================

FMODE_READ  EQU    0
FMODE_WRITE EQU    1
FMODE_RW    EQU    2

_syscall    MACRO   fncode:REQ, idreg:=<ah>
    mov idreg, fncode
    int 21h
ENDM

;Retorno:
;   `cf` <=> erro
;   `ax` = handle ou erro
_fopen      MACRO   file_name:REQ, mode:REQ
    mov dx, file_name
    _syscall (3D00h+mode), ax
ENDM

;Argumentos:
;   `file` - File handle
;   `buffer` - EA do buffer em DS
;   `size` - Número de bytes a serem lidos
;
;Retorno:
;   `cf` <=> erro
;   `ax` = número de bytes lidos
_fread      MACRO   file:REQ, buffer:REQ, size:REQ
    mov bx, file                      
    mov cx, size                      
    mov dx, buffer                    
    _syscall 3Fh
ENDM

;Argumentos:
;   `file` - File handle
_fclose     MACRO   file
    mov bx, file         
    _syscall 3Eh
ENDM
