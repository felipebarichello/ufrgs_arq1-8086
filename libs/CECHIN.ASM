; Funções do Cechin
;===================

;
;====================================================================
; printf("%s", string)
; printf("...")
;	- Escrever uma rotina para colocar o conte�do de um string na tela
;	- O ponteiro para o string entra em DS:BX
;	- Um string � uma seq��ncia de caracteres ASCII que termina com 00H (�\0�)
;====================================================================
;
; 		.model small
; 		.stack
		
; CR		equ		13
; LF		equ		10
		
; 		.data
; Texto1	db		"Texto numero 1",CR,LF,0
; Texto2	db		"Hello World",CR,LF,0

; 		.code
; 		.startup
	
; 		; printf("Texto numero 1\r\n")
; 		lea		bx,Texto1
; 		call	printf_s

; 		; printf("Hello World\r\n")
; 		lea		bx,Texto2
; 		call	printf_s
		
; 		.exit


;
;--------------------------------------------------------------------
;Fun��o: Escrever um string na tela
;
;void printf_s(char *s -> BX) {
;	While (*s!='\0') {
;		putchar(*s)
; 		++s;
;	}
;}
;--------------------------------------------------------------------
printf_s	proc	near

;	While (*s!='\0') {
	mov		dl,[bx]
	cmp		dl,0
	je		ps_1

;		putchar(*s)
	push	bx
	mov		ah,2
	int		21H
	pop		bx

;		++s;
	inc		bx
		
;	}
	jmp		printf_s
		
ps_1:
	ret
	
printf_s	endp


;
;====================================================================
;	- Escrever uma rotina para converter um n�mero com 16 bits em um string
;	- O valor de 16 bits entra no registrador AX
;	- O ponteiro para o string entra em DS:BX
;	- Um string � uma seq��ncia de caracteres ASCII que termina com 00H (�\0�)
;====================================================================
;

; 		.model small		
; 		.stack

; 		.data
; String	db		10 dup (?)
; H2D		db		10 dup (?)

; sw_n	dw	0
; sw_f	db	0
; sw_m	dw	0

; 		.code
; 		.startup

; 		; Chamada da rotina (para teste)
		
; 		; sprintf (String, "%d", 2943);
; 		mov		ax,2943
; 		lea		bx,String
; 		call	sprintf_w

; 		; printf("%s", String);
; 		lea		bx,String
; 		call	printf_s
		
; 		.exit

;
;--------------------------------------------------------------------
;Fun��o: Converte um inteiro (n) para (string)
;		 sprintf(string, "%d", n)
;
;void sprintf_w(char *string->BX, WORD n->AX) {
;	k=5;
;	m=10000;
;	f=0;
;	do {
;		quociente = n / m : resto = n % m;	// Usar instru��o DIV
;		if (quociente || f) {
;			*string++ = quociente+'0'
;			f = 1;
;		}
;		n = resto;
;		m = m/10;
;		--k;
;	} while(k);
;
;	if (!f)
;		*string++ = '0';
;	*string = '\0';
;}
;
;Associa��o de variaveis com registradores e mem�ria
;	string	-> bx
;	k		-> cx
;	m		-> sw_m dw
;	f		-> sw_f db
;	n		-> sw_n	dw
;--------------------------------------------------------------------

sprintf_w	proc	near

;void sprintf_w(char *string, WORD n) {
LOCAL       sw_n:   WORD
LOCAL       sw_f:   BYTE
LOCAL       sw_m:   WORD

	mov		sw_n,ax

;	k=5;
	mov		cx,5
	
;	m=10000;
	mov		sw_m,10000
	
;	f=0;
	mov		sw_f,0
	
;	do {
sw_do:

;		quociente = n / m : resto = n % m;	// Usar instru��o DIV
	mov		dx,0
	mov		ax,sw_n
	div		sw_m
	
;		if (quociente || f) {
;			*string++ = quociente+'0'
;			f = 1;
;		}
	cmp		al,0
	jne		sw_store
	cmp		sw_f,0
	je		sw_continue
sw_store:
	add		al,'0'
	mov		[bx],al
	inc		bx
	
	mov		sw_f,1
sw_continue:
	
;		n = resto;
	mov		sw_n,dx
	
;		m = m/10;
	mov		dx,0
	mov		ax,sw_m
	mov		bp,10
	div		bp
	mov		sw_m,ax
	
;		--k;
	dec		cx
	
;	} while(k);
	cmp		cx,0
	jnz		sw_do

;	if (!f)
;		*string++ = '0';
	cmp		sw_f,0
	jnz		sw_continua2
	mov		[bx],'0'
	inc		bx
sw_continua2:


;	*string = '\0';
	mov		byte ptr[bx],0
		
;}
	ret
		
sprintf_w	endp


;
;====================================================================
; ReadString
;	- Escrever uma rotina para ler um string do teclado
;	- O ponteiro para o string entra em DS:BX
;	- O n�mero m�ximo de caracteres a serem lidos (e colocados
;		no buffer do string) entra em CX
;	- Deve considerar o CR (0x0D) como final da entrada do string
;	- Deve processar BS (back space), c�digo ASCII 0x08
;	- Quando chegar ao final do string, ignorar qualquer nova 
;		tecla digitada
;	- Um string � uma seq��ncia de caracteres ASCII que termina
;		com 00H (�\0�)
;====================================================================
;
; 		.model	small
; 		.stack

; 		.data
; BufferTec	db	100 dup (?)

; 		.code
; 		.startup

; 		; Chamada da rotina (para teste)
		
; 		;ReadString(bx=BufferTec, cx=10)	// limita em 10 caracteres
; 		mov		cx,10
; 		lea		bx,BufferTec
; 		call	ReadString
		
; 		.exit


;
;--------------------------------------------------------------------
;Fun��o: L� um string do teclado
;Entra: (S) -> DS:BX -> Ponteiro para o string
;	    (M) -> CX -> numero maximo de caracteres aceitos
;Algoritmo:
;	Pos = 0
;	while(1) {
;		al = Int21(7)	// Espera pelo teclado
;		if (al==CR) {
;			*S = '\0'
;			return
;		}
;		if (al==BS) {
;			if (Pos==0) continue;
;			Print (BS, SPACE, BS)	// Coloca 3 caracteres na tela
;			--S
;			++M
;			--Pos
;		}
;		if (M==0) continue
;		if (al>=SPACE) {
;			*S = al
;			++S
;			--M
;			++Pos
;			Int21 (s, AL)	// Coloca AL na tela
;		}
;	}
;--------------------------------------------------------------------
ReadString	proc	near

		;Pos = 0
		mov		dx,0

RDSTR_1:
		;while(1) {
		;	al = Int21(7)		// Espera pelo teclado
		mov		ah,7
		int		21H

		;	if (al==CR) {
		cmp		al,0DH
		jne		RDSTR_A

		;		*S = '\0'
		mov		byte ptr[bx],0
		;		return
		ret
		;	}

RDSTR_A:
		;	if (al==BS) {
		cmp		al,08H
		jne		RDSTR_B

		;		if (Pos==0) continue;
		cmp		dx,0
		jz		RDSTR_1

		;		Print (BS, SPACE, BS)
		push	dx
		
		mov		dl,08H
		mov		ah,2
		int		21H
		
		mov		dl,' '
		mov		ah,2
		int		21H
		
		mov		dl,08H
		mov		ah,2
		int		21H
		
		pop		dx

		;		--s
		dec		bx
		;		++M
		inc		cx
		;		--Pos
		dec		dx
		
		;	}
		jmp		RDSTR_1

RDSTR_B:
		;	if (M==0) continue
		cmp		cx,0
		je		RDSTR_1

		;	if (al>=SPACE) {
		cmp		al,' '
		jl		RDSTR_1

		;		*S = al
		mov		[bx],al

		;		++S
		inc		bx
		;		--M
		dec		cx
		;		++Pos
		inc		dx

		;		Int21 (s, AL)
		push	dx
		mov		dl,al
		mov		ah,2
		int		21H
		pop		dx

		;	}
		;}
		jmp		RDSTR_1

ReadString	endp


;
;====================================================================
; atoi
;	- Escrever uma rotina para converter um string em um número
;		de 16 bits
;	- O ponteiro para o string entra em DS:BX
;	- O resultado (com 16 bits) deve ser retornado em AX
;	- Um string é uma sequência de caracteres ASCII que termina
;		com 00H ('\0')
;====================================================================
;
; 		.model small
; 		.stack

; 		.data
; String1	db	"100",0
; String2	db	"4096",0
; String3	db	"65535",0

; 		.code
; 		.startup

; 		; Chamada da rotina (para teste)
		
; 		; ax = atoi(String1)
; 		lea		bx,String1
; 		call	atoi

; 		lea		bx,String2
; 		call	atoi

; 		lea		bx,String3
; 		call	atoi

; 		.exit


;
;--------------------------------------------------------------------
;Fun��o:Converte um ASCII-DECIMAL para HEXA
;Entra: (S) -> DS:BX -> Ponteiro para o string de origem
;Sai:	(A) -> AX -> Valor "Hex" resultante
;Algoritmo:
;	A = 0;
;	while (*S!='\0') {
;		A = 10 * A + (*S - '0')
;		++S;
;	}
;	return
;--------------------------------------------------------------------
atoi	proc near

		; A = 0;
		mov		ax,0
		
atoi_2:
		; while (*S!='\0') {
		cmp		byte ptr[bx], 0
		jz		atoi_1

		; 	A = 10 * A
		mov		cx,10
		mul		cx

		; 	A = A + *S
		mov		ch,0
		mov		cl,[bx]
		add		ax,cx

		; 	A = A - '0'
		sub		ax,'0'

		; 	++S
		inc		bx
		
		;}
		jmp		atoi_2

atoi_1:
		; return
		ret

atoi	endp
