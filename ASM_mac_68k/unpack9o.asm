; unpacker9o
;
; 68k ASM unpacking routine for 68k Mac by Abel Vincze 2017/08/29
; This source file is designed to test run in Tricky68k simulator

			public start    ; Make the entry point public
			org $2000       ; Place the origin at $2000

TTY:        equ $FFE000
mmchl:		equ	$4-1		; a constant used in the compressor, needed for decompressing



start:
			; set up variables, and pointer to packed/unpacked data ------------------------
			lea		locals(PC), a0			; access local variables with a0

			lea		data(PC),a1				; source and
			lea		OUT(PC),a2				; target address parameters
			bsr.b	UNPACK9O				; decompressing

			move.w	#exp-UNPACK9O, d7		; code length display...
			
			move.w	L(a0), d0				; and finally check the unpacked data
			subq.w	#1, d0					; fix counter
			lea		unpackeddata(PC),a2		; test original data address
			lea		OUT(PC),a1				; decompressed data address
			
.loop		cmp.b	(a1)+,(a2)+				; compare bytes..... why not. no mess with counter
			bne.b	errorloop				; if doesn't match, go to errorloop (to make it noticable)
			dbra	d0, .loop
okloop:									
			bra.b okloop					; All is OK
errorloop:									
			bra.b errorloop					; Unpack doesn't match original...


UNPACK9O:		
			; Unpack9o 68k ASM -------------------------------------------------------------
			; a0 - locals
			; a1 - packed data
			; a2 - output address
			; used; d0,d1,d2,d3,d4,d5,d6,d7/a3,a4
			
											; SETUP DATA
			move.w  (a1)+, d1
			move.w	d1, H(a0)				; data height	16bit
			moveq	#0, d0					; clear d0...
			move.b	(a1)+, d0				; data width	8bit
			move.b	d0, DW+1(a0)
			mulu.w	d0, d1					; adathosszusag kiszamolasa a DW es H-bol
			move.w	d1, L(a0)				; final data length
			
			add.l	a2, d1
			move.l	d1,(a0)					; set end address for finish comp

			moveq	#0, d5					; clear d5... BITBC!!!
			; restore CNTbitdepths
			lea		CNTbv(PC), a3
			bsr.b	setupVNV

			; restore DISTbitdepths
			lea 	DISTbv(PC), a3
			bsr.b	setupVNV
			
			; INIT unpack loop: isStream to true for starting
			;moveq	#1, d3					; isStream = 1	; nem kell kulon beallitani!
											; lehetne bra.b .isstream is, de d7-et jobb nullazni
			
			; UNPACK data ------------------------------------------------------------------
											; unpack mainloop
unpackloop:
			cmpa.l	(a0), a2				; compare data length
			bge.b	__rts__					; -> finish
			
			tst.b	d3						; isStream?
			beq.b	.isrepeat				; no -> then repeat
			
			
.isstream:
			; STREAM BLOCK
			bsr.b	pullCNTbits				; d1-ben az eredmeny
.copyloop:
			move.b	(a1)+, (a2)+			; copy the stream;
			dbra	d1, .copyloop
			moveq	#0,	d3					; nullazzuk a streamet
			bra.b	unpackloop
			
.isrepeat:	
			; REPEAT BLOCK 
			bsr.b	pullbit					; next?
			roxl.b	#1,d3					; set isStream true!
			
			bsr.b	pullDISTbits			; d1-ben az eredmeny pozicio
			movea.l	a2, a3
			suba.w	d1, a3					; a3-ban a masolas forrasa

			bsr.b	pullCNTbits				; d1-ben az eredmeny:	adathosszusag
			addq.w	#mmchl, d1				; javitjuk

			bsr.b	pullbit					; is neg?
			bcs.b	.repeatnegloop
			
.repeatloop:
			move.b	(a3)+, (a2)+			; copy the repeated stream;
			dbra	d1, .repeatloop
			bra.b	unpackloop

.repeatnegloop:
			move.b	(a3)+, (a2)				; copy and negate the repeated stream;
			not.b	(a2)+
			dbra	d1, .repeatnegloop
			bra.b	unpackloop

			; finish unpacking, here we need to rearrange bytes...

	
			; HELPER FUNCTIONS -------------------------------------------------------------
setupVNV:
			moveq	#2, d0
			bsr.b 	pullnbits				; d1-be vissza! d0,d2,d3 maradjon!
			move.w	d1,d3					; d3- counter
			move.b	d1, (a3)+			
.loop:
			moveq	#3, d0					; 4 bitet olvasunk
			bsr.b	pullnbits
			move.b	d1, (a3)+
			dbra	d3,	.loop
__rts__:	rts
			
pullnbits:									; unch input  d0 = n, used d6, out d1
			; pull N control bits
			moveq	#0, d1
.loop
			bsr.b	pullbit
			addx.w	d1,d1
			dbra	d0, .loop
			addq.w	#1, d0					; to clear w bits
			rts

pullbit:									; used global(!) d5/d4
			; pull 1 control bit
			tst.b	d5						; bit counter
			bne.b	.next
			moveq	#8, d5					; reset bitcounter
			move.b	(a1)+, d4				; if 0, get a new byte to the buffer
.next
			subq.b	#1, d5					; decrement counter
			roxl.b	d4	
			rts
			
pullCNTbits:
			; pull VNV 
			lea		CNTbv(PC), a4
			bra.b	pulldatabits			; continue
			
pullDISTbits:
			lea		DISTbv(PC), a4
			
pulldatabits:								; get the number with the selected format (CNT/DIST bits)
											; change: d0,d1/a4 (uses: d0,d1,d2,d6,d7/a4
			moveq	#0, d6					; clear for safety
			move.b	(a4)+,d6				; d6 length of bit table, a4 bit table
			moveq	#0, d2					; d2 index in the table vbit
			moveq	#0, d7		 			; fix = 0
			bra.b	.loopin					; enter point of the loop
.loop						
			bsr.b	pullbit					; is num here?
			bcs.b	.read					; -> yes, then read it and return...
			add.w	d0, d0					; rol.w	#1, d0, azaz x2
			add.w	exp(PC,d0),d7			; fix += Math.pow( 2, actbits ); read from exp table
			addq.w	#1, d2					; vbit++
.loopin
			move.b	(a4,d2), d0				; d0 actbits			
			dbra	d6, .loop				; kovetkezo bit;
.read
			bsr.b	pullnbits				; d0-ban actbits, d1-ben eredmeny
			add.w	d7, d1
			rts

exp:		dc.w	2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768			
	
	
			; LOCAL variables
			; org $21d0
	
locals:
ENDa:		dc.l	0	; saved 4 bytes by making this var first...
dw:			dc.w	0
h:			dc.w	0
l:			dc.w	0
CNTbv:		dc.b	0							; fontos az elrendezes!!!
CNTbits:	dc.b	0, 0, 0, 0, 0, 0, 0, 0
DISTbv:		dc.b	0
DISTbits:	dc.b	0, 0, 0, 0, 0, 0, 0, 0

DW:			equ		dw		-locals
H:			equ		h		-locals
L:			equ		l		-locals
ENDA:		equ		ENDa	-locals
CNTBITS:	equ		CNTbits	-locals
DISTBITS:	equ		DISTbits-locals
CNTBV:		equ		CNTbv	-locals
DISTBV:		equ		DISTbv	-locals

			org $3000
	
data:
; __c64font2_packed9o
	dc.b $01, $00, $10, $62, $26, $B5, $41, $A6, $68, $BE, $C3, $99, $91, $91, $9F, $9D
	dc.b $C3, $FF, $83, $99, $99, $83, $9F, $9F, $9F, $FF, $0A, $1B, $C3, $99, $91, $89
	dc.b $99, $99, $C3, $42, $2E, $00, $00, $2D, $4C, $FC, $1A, $98, $FF, $2C, $4A, $E0
	dc.b $E0, $E7, $E7, $E7, $B9, $66, $42, $3F, $9D, $C3, $FF, $FF, $18, $1C, $2F, $8E
	dc.b $06, $F2, $28, $CE, $50, $66, $7A, $18, $E7, $C3, $99, $81, $99, $99, $99, $FF
	dc.b $C3, $99, $99, $99, $99, $C3, $F1, $FF, $E7, $E7, $E7, $E7, $FF, $FF, $E7, $FF
	dc.b $E7, $E7, $C7, $E7, $E7, $E7, $81, $FF, $F7, $E3, $C1, $80, $80, $E3, $C1, $FF
	dc.b $FF, $C3, $81, $81, $81, $81, $C3, $FF, $0F, $C1, $EC, $E7, $E7, $E7, $11, $5A
	dc.b $A8, $49, $2E, $FF, $FF, $C3, $F9, $C1, $99, $C1, $FF, $FF, $FF, $C1, $99, $99
	dc.b $C1, $F9, $F9, $2F, $8A, $06, $F1, $31, $0D, $71, $4D, $A3, $45, $99, $99, $83
	dc.b $3E, $A6, $87, $93, $99, $FF, $99, $99, $99, $8A, $7D, $CD, $F9, $F3, $CF, $9F
	dc.b $81, $FF, $E7, $83, $D2, $FF, $28, $42, $EE, $FF, $FF, $27, $A5, $00, $00, $E7
	dc.b $E7, $E7, $09, $38, $FF, $9F, $9F, $5F, $54, $53, $E8, $C2, $9F, $9F, $9F, $F8
	dc.b $A8, $6F, $14, $50, $D3, $25, $C3, $A4, $17, $99, $C3, $FF, $C3, $99, $9F, $C3
	dc.b $F9, $99, $C3, $FF, $99, $99, $00, $99, $00, $8A, $9D, $5A, $F9, $E3, $F9, $31
	dc.b $F3, $88, $46, $C9, $80, $80, $80, $C1, $E3, $F7, $FF, $00, $60, $E4, $E7, $E7
	dc.b $E7, $07, $07, $A1, $3D, $63, $FF, $FF, $C3, $9F, $9F, $9F, $53, $42, $0B, $C1
	dc.b $9F, $C3, $F9, $83, $E2, $A1, $BC, $4D, $43, $59, $08, $87, $93, $99, $99, $99
	dc.b $93, $87, $FF, $81, $A4, $BD, $26, $E7, $2D, $10, $E7, $FF, $F9, $F1, $E1, $99
	dc.b $80, $F9, $F9, $8A, $66, $A4, $9F, $9F, $9F, $9F, $9F, $8E, $BE, $CA, $00, $3F
	dc.b $83, $D4, $24, $E8, $FF, $F9, $F9, $C6, $F1, $A6, $FF, $FF, $E7, $04, $41, $F1
	dc.b $7C, $54, $37, $8A, $28, $69, $21, $81, $9F, $9F, $87, $9F, $9F, $81, $FF, $99
	dc.b $83, $46, $23, $C3, $FF, $9D, $99, $F3, $E7, $CF, $99, $B9, $FF, $81, $9F, $83
	dc.b $F9, $F9, $99, $C3, $19, $29, $E2, $FF, $FF, $FF, $F8, $F0, $E3, $E7, $E7, $1B
	dc.b $22, $20, $1F, $F1, $09, $30, $95, $11, $02, $81, $9F, $54, $7B, $F8, $82, $C1
	dc.b $F8, $A8, $6F, $14, $10, $D2, $3F, $A6, $35, $B7, $13, $99, $99, $C3, $E7, $FF
	dc.b $C3, $99, $C3, $C7, $98, $99, $C0, $8C, $9D, $1E, $83, $99, $99, $C3, $39, $AA
	dc.b $88, $E1, $3C, $18, $81, $C3, $C3, $81, $18, $3C, $33, $33, $6C, $F8, $41, $EA
	dc.b $12, $78, $FF, $F1, $E7, $C1, $79, $DC, $17, $C6, $83, $78, $A2, $86, $9F, $C3
	dc.b $99, $9F, $91, $0C, $4D, $04, $61, $9C, $9C, $9C, $94, $80, $88, $9C, $FF, $F9
	dc.b $F3, $0A, $73, $42, $81, $99, $F3, $A4, $D4, $CF, $C1, $E2, $08, $FF, $C3, $81
	dc.b $99, $99, $81, $C3, $FF, $FC, $3C, $15, $55, $04, $24, $C2, $9B, $73, $8B, $83
	dc.b $FF, $FF, $9C, $94, $80, $C1, $C9, $E2, $A1, $BC, $4D, $43, $5D, $99, $99, $06
	dc.b $3E, $C8, $A7, $70, $48, $C3, $99, $99, $FF, $F3, $E7, $CF, $CF, $CF, $E7, $F3
	dc.b $19, $3A, $30, $E2, $E0, $FF, $F3, $F2, $85, $E7, $E7, $99, $99, $E7, $E7, $4E
	dc.b $C8, $A8, $51, $88, $00, $00, $00, $53, $05, $3E, $C8, $5B, $28, $E2, $99, $C3
	dc.b $E7, $C3, $F8, $B0, $6F, $13, $50, $D7, $21, $C3, $87, $EA, $05, $C3, $BC, $C8
	dc.b $A5, $D1, $22, $E7, $15, $C4, $CF, $87, $4E, $89, $C1, $0A, $7D, $CB, $1F, $0F
	dc.b $C7, $E7, $E7, $F9, $83, $CE, $00, $01, $03, $07, $0F, $1F, $3F, $7F, $0C, $8E
	dc.b $8A, $12, $56, $FF, $E7, $FF, $C7, $E7, $E7, $39, $F7, $61, $C1, $F3, $87, $7C
	dc.b $4D, $27, $8A, $EA, $33, $66, $15, $83, $23, $B2, $84, $79, $E1, $14, $7E, $1A
	dc.b $93, $C7, $FF, $81, $F9, $F3, $E7, $1C, $BA, $14, $FF, $99, $C3, $00, $C3, $99
	dc.b $6B, $E6, $1D, $2C, $E7, $E3, $F0, $F8, $FF, $FF, $01, $1A, $B0, $C1, $E3, $F7
	dc.b $63, $E5, $06, $04, $4D, $09, $3A, $FF, $F9, $FF, $24, $CC, $30, $C3, $FF, $FF
	dc.b $81, $F3, $E7, $CF, $BE, $2C, $1B, $C5, $11, $AF, $90, $F4, $FE, $FC, $F9, $93
	dc.b $87, $8F, $9F, $FF, $24, $F8, $99, $93, $87, $8F, $01, $B4, $48, $C3, $E4, $F5
	dc.b $21, $C3, $C5, $E3, $44, $81, $E7, $E7, $3E, $43, $43, $E7, $CF, $E7, $E7, $C7
	dc.b $0F, $1F, $97, $65, $00, $00, $80, $25, $E5, $E0, $E0, $00, $27, $70, $05, $2A
	dc.b $28, $49, $E2, $FF, $9F, $9F, $93, $F8, $00, $1B, $DC, $43, $DC, $38, $B6, $10
	dc.b $81, $FF, $F3, $ED, $CF, $83, $CF, $9D, $03, $80, $0D, $A1, $E1, $CF, $F1, $E7
	dc.b $CF, $9F, $CF, $E7, $F1, $6B, $B9, $51, $00, $00, $3F, $3F, $CF, $CF, $20, $06
	dc.b $BF, $00, $24, $24, $80, $DA, $E2, $84, $9A, $FF, $C7, $1A, $FB, $05, $F1, $C0
	dc.b $DE, $45, $0F, $24, $01, $9C, $88, $80, $94, $9C, $9C, $9C, $FF, $C3, $09, $EA
	dc.b $08, $5D, $52, $81, $08, $87, $93, $81, $26, $88, $60, $3F, $1F, $8F, $C7, $E3
	dc.b $F1, $F8, $FC, $E7, $B2, $80, $E0, $E0, $4F, $91, $42, $7A, $8B, $FF, $FF, $99
	dc.b $80, $80, $94, $E3, $C1, $BD, $C0, $2C, $65, $50, $D2, $90, $99, $89, $81, $81
	dc.b $91, $33, $28, $D0, $E7, $C3, $81, $32, $65, $00, $40, $E7, $E7, $FF, $8F, $E7
	dc.b $F3, $F9, $F3, $E7, $8F, $FF, $FC, $F8, $F1, $E3, $C7, $8F, $1F, $3F, $FF, $FF
	dc.b $FC, $C1, $89, $C9, $C9, $AB, $D0, $02, $36, $A8, $22, $34, $42, $FF, $13, $C0
	dc.b $A6, $D4, $2F, $8F, $86, $F2, $01, $ED, $93, $43, $4C, $C3, $80, $9B, $71, $10
	dc.b $FF, $EF, $CF, $80, $80, $CF, $EF, $FF, $FF, $FC, $44, $7A, $82, $1F, $52, $40
	dc.b $E7, $FF, $E7, $FF, $00, $8A, $39, $C1, $00, $80, $C0, $E0, $F0, $F8, $FC, $FE
	dc.b $BD, $12, $05, $46, $80, $2A, $54, $D0, $93, $85, $FF, $FF, $C3, $F0, $05, $37
	dc.b $91, $50, $CC, $66, $B6, $86, $9F, $AA
	
dataend:

unpackeddata:
; __c64font2_unpacked9o
	dc.b $C3, $99, $91, $91, $9F, $9D, $C3, $FF, $83, $99, $99, $83, $9F, $9F, $9F, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $C3, $99, $91, $89, $99, $99, $C3, $FF
	dc.b $FF, $FF, $FF, $00, $00, $FF, $FF, $FF, $00, $00, $FC, $FC, $FC, $FC, $FC, $FC
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $E0, $E0, $E7, $E7, $E7
	dc.b $3C, $66, $6E, $6E, $60, $66, $3C, $00, $7C, $66, $66, $7C, $60, $60, $60, $00
	dc.b $00, $00, $00, $00, $00, $00, $00, $00, $3C, $66, $6E, $76, $66, $66, $3C, $00
	dc.b $00, $00, $00, $FF, $FF, $00, $00, $00, $FF, $FF, $03, $03, $03, $03, $03, $03
	dc.b $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $1F, $1F, $18, $18, $18
	dc.b $C3, $99, $91, $91, $9F, $9D, $C3, $FF, $FF, $FF, $83, $99, $99, $83, $9F, $9F
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $C3, $99, $91, $89, $99, $99, $C3, $FF
	dc.b $FF, $FF, $FF, $00, $00, $FF, $FF, $FF, $83, $99, $99, $83, $9F, $9F, $9F, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $E0, $E0, $E7, $E7, $E7
	dc.b $3C, $66, $6E, $6E, $60, $66, $3C, $00, $00, $00, $7C, $66, $66, $7C, $60, $60
	dc.b $00, $00, $00, $00, $00, $00, $00, $00, $3C, $66, $6E, $76, $66, $66, $3C, $00
	dc.b $00, $00, $00, $FF, $FF, $00, $00, $00, $7C, $66, $66, $7C, $60, $60, $60, $00
	dc.b $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $1F, $1F, $18, $18, $18
	dc.b $E7, $C3, $99, $81, $99, $99, $99, $FF, $C3, $99, $99, $99, $99, $C3, $F1, $FF
	dc.b $E7, $E7, $E7, $E7, $FF, $FF, $E7, $FF, $E7, $E7, $C7, $E7, $E7, $E7, $81, $FF
	dc.b $F7, $E3, $C1, $80, $80, $E3, $C1, $FF, $FF, $C3, $81, $81, $81, $81, $C3, $FF
	dc.b $0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F, $E7, $E7, $E7, $00, $00, $FF, $FF, $FF
	dc.b $18, $3C, $66, $7E, $66, $66, $66, $00, $3C, $66, $66, $66, $66, $3C, $0E, $00
	dc.b $18, $18, $18, $18, $00, $00, $18, $00, $18, $18, $38, $18, $18, $18, $7E, $00
	dc.b $08, $1C, $3E, $7F, $7F, $1C, $3E, $00, $00, $3C, $7E, $7E, $7E, $7E, $3C, $00
	dc.b $F0, $F0, $F0, $F0, $F0, $F0, $F0, $F0, $18, $18, $18, $FF, $FF, $00, $00, $00
	dc.b $FF, $FF, $C3, $F9, $C1, $99, $C1, $FF, $FF, $FF, $C1, $99, $99, $C1, $F9, $F9
	dc.b $E7, $E7, $E7, $E7, $FF, $FF, $E7, $FF, $E7, $E7, $C7, $E7, $E7, $E7, $81, $FF
	dc.b $E7, $C3, $99, $81, $99, $99, $99, $FF, $C3, $99, $99, $99, $99, $C3, $F1, $FF
	dc.b $0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F, $E7, $E7, $E7, $00, $00, $FF, $FF, $FF
	dc.b $00, $00, $3C, $06, $3E, $66, $3E, $00, $00, $00, $3E, $66, $66, $3E, $06, $06
	dc.b $18, $18, $18, $18, $00, $00, $18, $00, $18, $18, $38, $18, $18, $18, $7E, $00
	dc.b $18, $3C, $66, $7E, $66, $66, $66, $00, $3C, $66, $66, $66, $66, $3C, $0E, $00
	dc.b $F0, $F0, $F0, $F0, $F0, $F0, $F0, $F0, $18, $18, $18, $FF, $FF, $00, $00, $00
	dc.b $83, $99, $99, $83, $99, $99, $83, $FF, $83, $99, $99, $83, $87, $93, $99, $FF
	dc.b $99, $99, $99, $FF, $FF, $FF, $FF, $FF, $C3, $99, $F9, $F3, $CF, $9F, $81, $FF
	dc.b $E7, $E7, $E7, $E7, $E7, $E7, $E7, $E7, $FF, $FF, $FF, $FF, $FF, $00, $00, $FF
	dc.b $FF, $FF, $FF, $FF, $00, $00, $00, $00, $FF, $FF, $FF, $00, $00, $E7, $E7, $E7
	dc.b $7C, $66, $66, $7C, $66, $66, $7C, $00, $7C, $66, $66, $7C, $78, $6C, $66, $00
	dc.b $66, $66, $66, $00, $00, $00, $00, $00, $3C, $66, $06, $0C, $30, $60, $7E, $00
	dc.b $18, $18, $18, $18, $18, $18, $18, $18, $00, $00, $00, $00, $00, $FF, $FF, $00
	dc.b $00, $00, $00, $00, $FF, $FF, $FF, $FF, $00, $00, $00, $FF, $FF, $18, $18, $18
	dc.b $FF, $9F, $9F, $83, $99, $99, $83, $FF, $FF, $FF, $83, $99, $9F, $9F, $9F, $FF
	dc.b $99, $99, $99, $FF, $FF, $FF, $FF, $FF, $C3, $99, $F9, $F3, $CF, $9F, $81, $FF
	dc.b $83, $99, $99, $83, $99, $99, $83, $FF, $83, $99, $99, $83, $87, $93, $99, $FF
	dc.b $FF, $FF, $FF, $FF, $00, $00, $00, $00, $FF, $FF, $FF, $00, $00, $E7, $E7, $E7
	dc.b $00, $60, $60, $7C, $66, $66, $7C, $00, $00, $00, $7C, $66, $60, $60, $60, $00
	dc.b $66, $66, $66, $00, $00, $00, $00, $00, $3C, $66, $06, $0C, $30, $60, $7E, $00
	dc.b $7C, $66, $66, $7C, $66, $66, $7C, $00, $7C, $66, $66, $7C, $78, $6C, $66, $00
	dc.b $00, $00, $00, $00, $FF, $FF, $FF, $FF, $00, $00, $00, $FF, $FF, $18, $18, $18
	dc.b $C3, $99, $9F, $9F, $9F, $99, $C3, $FF, $C3, $99, $9F, $C3, $F9, $99, $C3, $FF
	dc.b $99, $99, $00, $99, $00, $99, $99, $FF, $C3, $99, $F9, $E3, $F9, $99, $C3, $FF
	dc.b $FF, $FF, $FF, $00, $00, $FF, $FF, $FF, $C9, $80, $80, $80, $C1, $E3, $F7, $FF
	dc.b $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $E7, $E7, $E7, $07, $07, $E7, $E7, $E7
	dc.b $3C, $66, $60, $60, $60, $66, $3C, $00, $3C, $66, $60, $3C, $06, $66, $3C, $00
	dc.b $66, $66, $FF, $66, $FF, $66, $66, $00, $3C, $66, $06, $1C, $06, $66, $3C, $00
	dc.b $00, $00, $00, $FF, $FF, $00, $00, $00, $36, $7F, $7F, $7F, $3E, $1C, $08, $00
	dc.b $FF, $00, $00, $00, $00, $00, $00, $00, $18, $18, $18, $F8, $F8, $18, $18, $18
	dc.b $FF, $FF, $C3, $9F, $9F, $9F, $C3, $FF, $FF, $FF, $C1, $9F, $C3, $F9, $83, $FF
	dc.b $99, $99, $00, $99, $00, $99, $99, $FF, $C3, $99, $F9, $E3, $F9, $99, $C3, $FF
	dc.b $C3, $99, $9F, $9F, $9F, $99, $C3, $FF, $C3, $99, $9F, $C3, $F9, $99, $C3, $FF
	dc.b $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $E7, $E7, $E7, $07, $07, $E7, $E7, $E7
	dc.b $00, $00, $3C, $60, $60, $60, $3C, $00, $00, $00, $3E, $60, $3C, $06, $7C, $00
	dc.b $66, $66, $FF, $66, $FF, $66, $66, $00, $3C, $66, $06, $1C, $06, $66, $3C, $00
	dc.b $3C, $66, $60, $60, $60, $66, $3C, $00, $3C, $66, $60, $3C, $06, $66, $3C, $00
	dc.b $FF, $00, $00, $00, $00, $00, $00, $00, $18, $18, $18, $F8, $F8, $18, $18, $18
	dc.b $87, $93, $99, $99, $99, $93, $87, $FF, $81, $E7, $E7, $E7, $E7, $E7, $E7, $FF
	dc.b $E7, $C1, $9F, $C3, $F9, $83, $E7, $FF, $F9, $F1, $E1, $99, $80, $F9, $F9, $FF
	dc.b $FF, $FF, $00, $00, $FF, $FF, $FF, $FF, $9F, $9F, $9F, $9F, $9F, $9F, $9F, $9F
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F
	dc.b $78, $6C, $66, $66, $66, $6C, $78, $00, $7E, $18, $18, $18, $18, $18, $18, $00
	dc.b $18, $3E, $60, $3C, $06, $7C, $18, $00, $06, $0E, $1E, $66, $7F, $06, $06, $00
	dc.b $00, $00, $FF, $FF, $00, $00, $00, $00, $60, $60, $60, $60, $60, $60, $60, $60
	dc.b $00, $00, $00, $00, $00, $00, $00, $FF, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0
	dc.b $FF, $F9, $F9, $C1, $99, $99, $C1, $FF, $FF, $E7, $81, $E7, $E7, $E7, $F1, $FF
	dc.b $E7, $C1, $9F, $C3, $F9, $83, $E7, $FF, $F9, $F1, $E1, $99, $80, $F9, $F9, $FF
	dc.b $87, $93, $99, $99, $99, $93, $87, $FF, $81, $E7, $E7, $E7, $E7, $E7, $E7, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F
	dc.b $00, $06, $06, $3E, $66, $66, $3E, $00, $00, $18, $7E, $18, $18, $18, $0E, $00
	dc.b $18, $3E, $60, $3C, $06, $7C, $18, $00, $06, $0E, $1E, $66, $7F, $06, $06, $00
	dc.b $78, $6C, $66, $66, $66, $6C, $78, $00, $7E, $18, $18, $18, $18, $18, $18, $00
	dc.b $00, $00, $00, $00, $00, $00, $00, $FF, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0
	dc.b $81, $9F, $9F, $87, $9F, $9F, $81, $FF, $99, $99, $99, $99, $99, $99, $C3, $FF
	dc.b $9D, $99, $F3, $E7, $CF, $99, $B9, $FF, $81, $9F, $83, $F9, $F9, $99, $C3, $FF
	dc.b $FF, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $F8, $F0, $E3, $E7, $E7
	dc.b $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $1F, $1F, $1F, $1F, $1F, $1F, $1F, $1F
	dc.b $7E, $60, $60, $78, $60, $60, $7E, $00, $66, $66, $66, $66, $66, $66, $3C, $00
	dc.b $62, $66, $0C, $18, $30, $66, $46, $00, $7E, $60, $7C, $06, $06, $66, $3C, $00
	dc.b $00, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $07, $0F, $1C, $18, $18
	dc.b $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0
	dc.b $FF, $FF, $C3, $99, $81, $9F, $C3, $FF, $FF, $FF, $99, $99, $99, $99, $C1, $FF
	dc.b $9D, $99, $F3, $E7, $CF, $99, $B9, $FF, $81, $9F, $83, $F9, $F9, $99, $C3, $FF
	dc.b $81, $9F, $9F, $87, $9F, $9F, $81, $FF, $99, $99, $99, $99, $99, $99, $C3, $FF
	dc.b $3F, $3F, $3F, $3F, $3F, $3F, $3F, $3F, $1F, $1F, $1F, $1F, $1F, $1F, $1F, $1F
	dc.b $00, $00, $3C, $66, $7E, $60, $3C, $00, $00, $00, $66, $66, $66, $66, $3E, $00
	dc.b $62, $66, $0C, $18, $30, $66, $46, $00, $7E, $60, $7C, $06, $06, $66, $3C, $00
	dc.b $7E, $60, $60, $78, $60, $60, $7E, $00, $66, $66, $66, $66, $66, $66, $3C, $00
	dc.b $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0
	dc.b $81, $9F, $9F, $87, $9F, $9F, $9F, $FF, $99, $99, $99, $99, $99, $C3, $E7, $FF
	dc.b $C3, $99, $C3, $C7, $98, $99, $C0, $FF, $C3, $99, $9F, $83, $99, $99, $C3, $FF
	dc.b $FF, $FF, $FF, $FF, $00, $00, $FF, $FF, $3C, $18, $81, $C3, $C3, $81, $18, $3C
	dc.b $33, $33, $CC, $CC, $33, $33, $CC, $CC, $F8, $F8, $F8, $F8, $F8, $F8, $F8, $F8
	dc.b $7E, $60, $60, $78, $60, $60, $60, $00, $66, $66, $66, $66, $66, $3C, $18, $00
	dc.b $3C, $66, $3C, $38, $67, $66, $3F, $00, $3C, $66, $60, $7C, $66, $66, $3C, $00
	dc.b $00, $00, $00, $00, $FF, $FF, $00, $00, $C3, $E7, $7E, $3C, $3C, $7E, $E7, $C3
	dc.b $CC, $CC, $33, $33, $CC, $CC, $33, $33, $07, $07, $07, $07, $07, $07, $07, $07
	dc.b $FF, $F1, $E7, $C1, $E7, $E7, $E7, $FF, $FF, $FF, $99, $99, $99, $C3, $E7, $FF
	dc.b $C3, $99, $C3, $C7, $98, $99, $C0, $FF, $C3, $99, $9F, $83, $99, $99, $C3, $FF
	dc.b $81, $9F, $9F, $87, $9F, $9F, $9F, $FF, $99, $99, $99, $99, $99, $C3, $E7, $FF
	dc.b $33, $33, $CC, $CC, $33, $33, $CC, $CC, $F8, $F8, $F8, $F8, $F8, $F8, $F8, $F8
	dc.b $00, $0E, $18, $3E, $18, $18, $18, $00, $00, $00, $66, $66, $66, $3C, $18, $00
	dc.b $3C, $66, $3C, $38, $67, $66, $3F, $00, $3C, $66, $60, $7C, $66, $66, $3C, $00
	dc.b $7E, $60, $60, $78, $60, $60, $60, $00, $66, $66, $66, $66, $66, $3C, $18, $00
	dc.b $CC, $CC, $33, $33, $CC, $CC, $33, $33, $07, $07, $07, $07, $07, $07, $07, $07
	dc.b $C3, $99, $9F, $91, $99, $99, $C3, $FF, $9C, $9C, $9C, $94, $80, $88, $9C, $FF
	dc.b $F9, $F3, $E7, $FF, $FF, $FF, $FF, $FF, $81, $99, $F3, $E7, $E7, $E7, $E7, $FF
	dc.b $CF, $CF, $CF, $CF, $CF, $CF, $CF, $CF, $FF, $C3, $81, $99, $99, $81, $C3, $FF
	dc.b $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF
	dc.b $3C, $66, $60, $6E, $66, $66, $3C, $00, $63, $63, $63, $6B, $7F, $77, $63, $00
	dc.b $06, $0C, $18, $00, $00, $00, $00, $00, $7E, $66, $0C, $18, $18, $18, $18, $00
	dc.b $30, $30, $30, $30, $30, $30, $30, $30, $00, $3C, $7E, $66, $66, $7E, $3C, $00
	dc.b $03, $03, $03, $03, $03, $03, $03, $03, $FF, $FF, $00, $00, $00, $00, $00, $00
	dc.b $FF, $FF, $C1, $99, $99, $C1, $F9, $83, $FF, $FF, $9C, $94, $80, $C1, $C9, $FF
	dc.b $F9, $F3, $E7, $FF, $FF, $FF, $FF, $FF, $81, $99, $F3, $E7, $E7, $E7, $E7, $FF
	dc.b $C3, $99, $9F, $91, $99, $99, $C3, $FF, $9C, $9C, $9C, $94, $80, $88, $9C, $FF
	dc.b $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF
	dc.b $00, $00, $3E, $66, $66, $3E, $06, $7C, $00, $00, $63, $6B, $7F, $3E, $36, $00
	dc.b $06, $0C, $18, $00, $00, $00, $00, $00, $7E, $66, $0C, $18, $18, $18, $18, $00
	dc.b $3C, $66, $60, $6E, $66, $66, $3C, $00, $63, $63, $63, $6B, $7F, $77, $63, $00
	dc.b $03, $03, $03, $03, $03, $03, $03, $03, $FF, $FF, $00, $00, $00, $00, $00, $00
	dc.b $99, $99, $99, $81, $99, $99, $99, $FF, $99, $99, $C3, $E7, $C3, $99, $99, $FF
	dc.b $F3, $E7, $CF, $CF, $CF, $E7, $F3, $FF, $C3, $99, $99, $C3, $99, $99, $C3, $FF
	dc.b $F3, $F3, $F3, $F3, $F3, $F3, $F3, $F3, $E7, $E7, $99, $99, $E7, $E7, $C3, $FF
	dc.b $FF, $FF, $FF, $FF, $33, $33, $CC, $CC, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
	dc.b $66, $66, $66, $7E, $66, $66, $66, $00, $66, $66, $3C, $18, $3C, $66, $66, $00
	dc.b $0C, $18, $30, $30, $30, $18, $0C, $00, $3C, $66, $66, $3C, $66, $66, $3C, $00
	dc.b $0C, $0C, $0C, $0C, $0C, $0C, $0C, $0C, $18, $18, $66, $66, $18, $18, $3C, $00
	dc.b $00, $00, $00, $00, $CC, $CC, $33, $33, $FF, $FF, $FF, $00, $00, $00, $00, $00
	dc.b $FF, $9F, $9F, $83, $99, $99, $99, $FF, $FF, $FF, $99, $C3, $E7, $C3, $99, $FF
	dc.b $F3, $E7, $CF, $CF, $CF, $E7, $F3, $FF, $C3, $99, $99, $C3, $99, $99, $C3, $FF
	dc.b $99, $99, $99, $81, $99, $99, $99, $FF, $99, $99, $C3, $E7, $C3, $99, $99, $FF
	dc.b $FF, $FF, $FF, $FF, $33, $33, $CC, $CC, $00, $00, $00, $FF, $FF, $FF, $FF, $FF
	dc.b $00, $60, $60, $7C, $66, $66, $66, $00, $00, $00, $66, $3C, $18, $3C, $66, $00
	dc.b $0C, $18, $30, $30, $30, $18, $0C, $00, $3C, $66, $66, $3C, $66, $66, $3C, $00
	dc.b $66, $66, $66, $7E, $66, $66, $66, $00, $66, $66, $3C, $18, $3C, $66, $66, $00
	dc.b $00, $00, $00, $00, $CC, $CC, $33, $33, $FF, $FF, $FF, $00, $00, $00, $00, $00
	dc.b $C3, $E7, $E7, $E7, $E7, $E7, $C3, $FF, $99, $99, $99, $C3, $E7, $E7, $E7, $FF
	dc.b $CF, $E7, $F3, $F3, $F3, $E7, $CF, $FF, $C3, $99, $99, $C1, $F9, $99, $C3, $FF
	dc.b $FF, $FF, $FF, $1F, $0F, $C7, $E7, $E7, $F9, $F9, $F9, $F9, $F9, $F9, $F9, $F9
	dc.b $00, $01, $03, $07, $0F, $1F, $3F, $7F, $FF, $FF, $FF, $FF, $FF, $00, $00, $00
	dc.b $3C, $18, $18, $18, $18, $18, $3C, $00, $66, $66, $66, $3C, $18, $18, $18, $00
	dc.b $30, $18, $0C, $0C, $0C, $18, $30, $00, $3C, $66, $66, $3E, $06, $66, $3C, $00
	dc.b $00, $00, $00, $E0, $F0, $38, $18, $18, $06, $06, $06, $06, $06, $06, $06, $06
	dc.b $FF, $FE, $FC, $F8, $F0, $E0, $C0, $80, $00, $00, $00, $00, $00, $FF, $FF, $FF
	dc.b $FF, $E7, $FF, $C7, $E7, $E7, $C3, $FF, $FF, $FF, $99, $99, $99, $C1, $F3, $87
	dc.b $CF, $E7, $F3, $F3, $F3, $E7, $CF, $FF, $C3, $99, $99, $C1, $F9, $99, $C3, $FF
	dc.b $C3, $E7, $E7, $E7, $E7, $E7, $C3, $FF, $99, $99, $99, $C3, $E7, $E7, $E7, $FF
	dc.b $33, $66, $CC, $99, $33, $66, $CC, $99, $FF, $FF, $FF, $FF, $FF, $00, $00, $00
	dc.b $00, $18, $00, $38, $18, $18, $3C, $00, $00, $00, $66, $66, $66, $3E, $0C, $78
	dc.b $30, $18, $0C, $0C, $0C, $18, $30, $00, $3C, $66, $66, $3E, $06, $66, $3C, $00
	dc.b $3C, $18, $18, $18, $18, $18, $3C, $00, $66, $66, $66, $3C, $18, $18, $18, $00
	dc.b $CC, $99, $33, $66, $CC, $99, $33, $66, $00, $00, $00, $00, $00, $FF, $FF, $FF
	dc.b $E1, $F3, $F3, $F3, $F3, $93, $C7, $FF, $81, $F9, $F3, $E7, $CF, $9F, $81, $FF
	dc.b $FF, $99, $C3, $00, $C3, $99, $FF, $FF, $FF, $FF, $E7, $FF, $FF, $E7, $FF, $FF
	dc.b $E7, $E7, $E3, $F0, $F8, $FF, $FF, $FF, $F7, $E3, $C1, $80, $C1, $E3, $F7, $FF
	dc.b $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $00, $00
	dc.b $1E, $0C, $0C, $0C, $0C, $6C, $38, $00, $7E, $06, $0C, $18, $30, $60, $7E, $00
	dc.b $00, $66, $3C, $FF, $3C, $66, $00, $00, $00, $00, $18, $00, $00, $18, $00, $00
	dc.b $18, $18, $1C, $0F, $07, $00, $00, $00, $08, $1C, $3E, $7F, $3E, $1C, $08, $00
	dc.b $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $FF, $FF
	dc.b $FF, $F9, $FF, $F9, $F9, $F9, $F9, $C3, $FF, $FF, $81, $F3, $E7, $CF, $81, $FF
	dc.b $FF, $99, $C3, $00, $C3, $99, $FF, $FF, $FF, $FF, $E7, $FF, $FF, $E7, $FF, $FF
	dc.b $E1, $F3, $F3, $F3, $F3, $93, $C7, $FF, $81, $F9, $F3, $E7, $CF, $9F, $81, $FF
	dc.b $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FC, $FE, $FC, $F9, $93, $87, $8F, $9F, $FF
	dc.b $00, $06, $00, $06, $06, $06, $06, $3C, $00, $00, $7E, $0C, $18, $30, $7E, $00
	dc.b $00, $66, $3C, $FF, $3C, $66, $00, $00, $00, $00, $18, $00, $00, $18, $00, $00
	dc.b $1E, $0C, $0C, $0C, $0C, $6C, $38, $00, $7E, $06, $0C, $18, $30, $60, $7E, $00
	dc.b $03, $03, $03, $03, $03, $03, $03, $03, $01, $03, $06, $6C, $78, $70, $60, $00
	dc.b $99, $93, $87, $8F, $87, $93, $99, $FF, $C3, $CF, $CF, $CF, $CF, $CF, $C3, $FF
	dc.b $FF, $E7, $E7, $81, $E7, $E7, $FF, $FF, $FF, $FF, $E7, $FF, $FF, $E7, $E7, $CF
	dc.b $E7, $E7, $C7, $0F, $1F, $FF, $FF, $FF, $E7, $E7, $E7, $00, $00, $E7, $E7, $E7
	dc.b $E7, $E7, $E7, $E0, $E0, $E7, $E7, $E7, $FF, $FF, $FF, $FF, $0F, $0F, $0F, $0F
	dc.b $66, $6C, $78, $70, $78, $6C, $66, $00, $3C, $30, $30, $30, $30, $30, $3C, $00
	dc.b $00, $18, $18, $7E, $18, $18, $00, $00, $00, $00, $18, $00, $00, $18, $18, $30
	dc.b $18, $18, $38, $F0, $E0, $00, $00, $00, $18, $18, $18, $FF, $FF, $18, $18, $18
	dc.b $18, $18, $18, $1F, $1F, $18, $18, $18, $00, $00, $00, $00, $F0, $F0, $F0, $F0
	dc.b $FF, $9F, $9F, $93, $87, $93, $99, $FF, $C3, $CF, $CF, $CF, $CF, $CF, $C3, $FF
	dc.b $FF, $E7, $E7, $81, $E7, $E7, $FF, $FF, $FF, $FF, $E7, $FF, $FF, $E7, $E7, $CF
	dc.b $99, $93, $87, $8F, $87, $93, $99, $FF, $E7, $E7, $E7, $00, $00, $E7, $E7, $E7
	dc.b $E7, $E7, $E7, $E0, $E0, $E7, $E7, $E7, $FF, $FF, $FF, $FF, $0F, $0F, $0F, $0F
	dc.b $00, $60, $60, $6C, $78, $6C, $66, $00, $3C, $30, $30, $30, $30, $30, $3C, $00
	dc.b $00, $18, $18, $7E, $18, $18, $00, $00, $00, $00, $18, $00, $00, $18, $18, $30
	dc.b $66, $6C, $78, $70, $78, $6C, $66, $00, $18, $18, $18, $FF, $FF, $18, $18, $18
	dc.b $18, $18, $18, $1F, $1F, $18, $18, $18, $00, $00, $00, $00, $F0, $F0, $F0, $F0
	dc.b $9F, $9F, $9F, $9F, $9F, $9F, $81, $FF, $F3, $ED, $CF, $83, $CF, $9D, $03, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $E7, $E7, $CF, $F1, $E7, $CF, $9F, $CF, $E7, $F1, $FF
	dc.b $3F, $3F, $3F, $3F, $3F, $3F, $00, $00, $3F, $3F, $CF, $CF, $3F, $3F, $CF, $CF
	dc.b $FF, $FF, $FF, $FF, $F0, $F0, $F0, $F0, $F0, $F0, $F0, $F0, $FF, $FF, $FF, $FF
	dc.b $60, $60, $60, $60, $60, $60, $7E, $00, $0C, $12, $30, $7C, $30, $62, $FC, $00
	dc.b $00, $00, $00, $00, $00, $18, $18, $30, $0E, $18, $30, $60, $30, $18, $0E, $00
	dc.b $C0, $C0, $C0, $C0, $C0, $C0, $FF, $FF, $C0, $C0, $30, $30, $C0, $C0, $30, $30
	dc.b $00, $00, $00, $00, $0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F, $00, $00, $00, $00
	dc.b $FF, $C7, $E7, $E7, $E7, $E7, $C3, $FF, $F3, $ED, $CF, $83, $CF, $9D, $03, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $E7, $E7, $CF, $F1, $E7, $CF, $9F, $CF, $E7, $F1, $FF
	dc.b $9F, $9F, $9F, $9F, $9F, $9F, $81, $FF, $3F, $3F, $CF, $CF, $3F, $3F, $CF, $CF
	dc.b $FF, $FF, $FF, $FF, $F0, $F0, $F0, $F0, $F0, $F0, $F0, $F0, $FF, $FF, $FF, $FF
	dc.b $00, $38, $18, $18, $18, $18, $3C, $00, $0C, $12, $30, $7C, $30, $62, $FC, $00
	dc.b $00, $00, $00, $00, $00, $18, $18, $30, $0E, $18, $30, $60, $30, $18, $0E, $00
	dc.b $60, $60, $60, $60, $60, $60, $7E, $00, $C0, $C0, $30, $30, $C0, $C0, $30, $30
	dc.b $00, $00, $00, $00, $0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F, $00, $00, $00, $00
	dc.b $9C, $88, $80, $94, $9C, $9C, $9C, $FF, $C3, $F3, $F3, $F3, $F3, $F3, $C3, $FF
	dc.b $FF, $FF, $FF, $81, $FF, $FF, $FF, $FF, $FF, $FF, $81, $FF, $81, $FF, $FF, $FF
	dc.b $3F, $1F, $8F, $C7, $E3, $F1, $F8, $FC, $E7, $E7, $E7, $E7, $E7, $E7, $E7, $E7
	dc.b $E7, $E7, $E7, $E0, $E0, $FF, $FF, $FF, $E7, $E7, $E7, $07, $07, $FF, $FF, $FF
	dc.b $63, $77, $7F, $6B, $63, $63, $63, $00, $3C, $0C, $0C, $0C, $0C, $0C, $3C, $00
	dc.b $00, $00, $00, $7E, $00, $00, $00, $00, $00, $00, $7E, $00, $7E, $00, $00, $00
	dc.b $C0, $E0, $70, $38, $1C, $0E, $07, $03, $18, $18, $18, $18, $18, $18, $18, $18
	dc.b $18, $18, $18, $1F, $1F, $00, $00, $00, $18, $18, $18, $F8, $F8, $00, $00, $00
	dc.b $FF, $FF, $99, $80, $80, $94, $9C, $FF, $C3, $F3, $F3, $F3, $F3, $F3, $C3, $FF
	dc.b $FF, $FF, $FF, $81, $FF, $FF, $FF, $FF, $FF, $FF, $81, $FF, $81, $FF, $FF, $FF
	dc.b $9C, $88, $80, $94, $9C, $9C, $9C, $FF, $E7, $E7, $E7, $E7, $E7, $E7, $E7, $E7
	dc.b $E7, $E7, $E7, $E0, $E0, $FF, $FF, $FF, $E7, $E7, $E7, $07, $07, $FF, $FF, $FF
	dc.b $00, $00, $66, $7F, $7F, $6B, $63, $00, $3C, $0C, $0C, $0C, $0C, $0C, $3C, $00
	dc.b $00, $00, $00, $7E, $00, $00, $00, $00, $00, $00, $7E, $00, $7E, $00, $00, $00
	dc.b $63, $77, $7F, $6B, $63, $63, $63, $00, $18, $18, $18, $18, $18, $18, $18, $18
	dc.b $18, $18, $18, $1F, $1F, $00, $00, $00, $18, $18, $18, $F8, $F8, $00, $00, $00
	dc.b $99, $89, $81, $81, $91, $99, $99, $FF, $FF, $E7, $C3, $81, $E7, $E7, $E7, $E7
	dc.b $FF, $FF, $FF, $FF, $FF, $E7, $E7, $FF, $8F, $E7, $F3, $F9, $F3, $E7, $8F, $FF
	dc.b $FC, $F8, $F1, $E3, $C7, $8F, $1F, $3F, $FF, $FF, $FC, $C1, $89, $C9, $C9, $FF
	dc.b $FF, $FF, $FF, $07, $07, $E7, $E7, $E7, $0F, $0F, $0F, $0F, $FF, $FF, $FF, $FF
	dc.b $66, $76, $7E, $7E, $6E, $66, $66, $00, $00, $18, $3C, $7E, $18, $18, $18, $18
	dc.b $00, $00, $00, $00, $00, $18, $18, $00, $70, $18, $0C, $06, $0C, $18, $70, $00
	dc.b $03, $07, $0E, $1C, $38, $70, $E0, $C0, $00, $00, $03, $3E, $76, $36, $36, $00
	dc.b $00, $00, $00, $F8, $F8, $18, $18, $18, $F0, $F0, $F0, $F0, $00, $00, $00, $00
	dc.b $FF, $FF, $83, $99, $99, $99, $99, $FF, $FF, $E7, $C3, $81, $E7, $E7, $E7, $E7
	dc.b $FF, $FF, $FF, $FF, $FF, $E7, $E7, $FF, $8F, $E7, $F3, $F9, $F3, $E7, $8F, $FF
	dc.b $99, $89, $81, $81, $91, $99, $99, $FF, $CC, $CC, $33, $33, $CC, $CC, $33, $33
	dc.b $FF, $FF, $FF, $07, $07, $E7, $E7, $E7, $0F, $0F, $0F, $0F, $FF, $FF, $FF, $FF
	dc.b $00, $00, $7C, $66, $66, $66, $66, $00, $00, $18, $3C, $7E, $18, $18, $18, $18
	dc.b $00, $00, $00, $00, $00, $18, $18, $00, $70, $18, $0C, $06, $0C, $18, $70, $00
	dc.b $66, $76, $7E, $7E, $6E, $66, $66, $00, $33, $33, $CC, $CC, $33, $33, $CC, $CC
	dc.b $00, $00, $00, $F8, $F8, $18, $18, $18, $F0, $F0, $F0, $F0, $00, $00, $00, $00
	dc.b $C3, $99, $99, $99, $99, $99, $C3, $FF, $FF, $EF, $CF, $80, $80, $CF, $EF, $FF
	dc.b $FF, $FC, $F9, $F3, $E7, $CF, $9F, $FF, $C3, $99, $F9, $F3, $E7, $FF, $E7, $FF
	dc.b $00, $00, $3F, $3F, $3F, $3F, $3F, $3F, $00, $80, $C0, $E0, $F0, $F8, $FC, $FE
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $0F, $0F, $0F, $0F, $F0, $F0, $F0, $F0
	dc.b $3C, $66, $66, $66, $66, $66, $3C, $00, $00, $10, $30, $7F, $7F, $30, $10, $00
	dc.b $00, $03, $06, $0C, $18, $30, $60, $00, $3C, $66, $06, $0C, $18, $00, $18, $00
	dc.b $FF, $FF, $C0, $C0, $C0, $C0, $C0, $C0, $FF, $7F, $3F, $1F, $0F, $07, $03, $01
	dc.b $00, $00, $00, $00, $00, $00, $FF, $FF, $F0, $F0, $F0, $F0, $0F, $0F, $0F, $0F
	dc.b $FF, $FF, $C3, $99, $99, $99, $C3, $FF, $FF, $EF, $CF, $80, $80, $CF, $EF, $FF
	dc.b $FF, $FC, $F9, $F3, $E7, $CF, $9F, $FF, $C3, $99, $F9, $F3, $E7, $FF, $E7, $FF
	dc.b $C3, $99, $99, $99, $99, $99, $C3, $FF, $CC, $66, $33, $99, $CC, $66, $33, $99
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $0F, $0F, $0F, $0F, $F0, $F0, $F0, $F0
	dc.b $00, $00, $3C, $66, $66, $66, $3C, $00, $00, $10, $30, $7F, $7F, $30, $10, $00
	dc.b $00, $03, $06, $0C, $18, $30, $60, $00, $3C, $66, $06, $0C, $18, $00, $18, $00
	dc.b $3C, $66, $66, $66, $66, $66, $3C, $00, $33, $99, $CC, $66, $33, $99, $CC, $66
	dc.b $00, $00, $00, $00, $00, $00, $FF, $FF, $F0, $F0, $F0, $F0, $0F, $0F, $0F, $0F
; -----------------------------------------------------------------------------------------


		org	$A000
OUT:	ds.b $A000

;	This compression is optimized for 1 bit graphics data, and small data sizes <64K
;
;	Unpacking mechanism
;
;	Source data (compressed) is read by bytes in linear order forward -> 0, 1, 2, 3,... n-1, n.
;	Target data (decompressed) is also reproduced in linear order forward. The written data is
;	composed of BLOCKs, that can be either STREAMs or REPEATs. STREAMs are series of uncompressed
;	bytes copied from the Source data, and REPEATs are copies of the previously written data,
;	optionally inverted (NEG).
;
;	3 types of informations are stored in the compressed data (source data):
;	- setup data:		byte and bit informations how to handle compressed data.
;	- data bytes:		original content to be copied.
;	- control bits:		an array of bit, containing unpacking flow, they describes the BLOCKs
;
;	While data bytes are unchanged part of the original content, control bits holds informations
;	how to read/write data. These control bits (one or more) are the following:
;	- STREAM FOLLOWS	1 bit:		1: the next BLOCK is a STREAM, 0: next BLOCK is a REPEAT
;	- NEG REPEAT		1 bit:		1: the repeated bytes are inverted, 0: normal repeat
;	- CNTbits			1-x bits:	Counter value stored with variable bitlength*
;	- DISTbits			1-x bits:	Offset values stored with variable bitlenght*
;	- n BIT VALUE		n bits:		binary value
;
;	To allow linear read of source data bytes while variable bitlength data needs to be inserted
;	in the data flow, the control bits are always read by bytes, 8 at a time, and cached. When
;	the cache runs out of bits, a new byte is read into it.
;
;	* Some words about the variable bitlength values (VBV)
;	A VBV type is composed from 0 or more SELECTOR bits, and 1 or more VALUE bits (X)
;	Here are some examples:
;
;	(A)												(B)
;	SELECTOR/VALUEBITS	VALUE	FINAL VALUE			SELECTOR/VALUEBITS	VALUE	FINAL VALUE
;	1XX			3 bits	0-3		0-3					1XXX		4 bits	0-7		0-7
;	01XXX		5 bits	0-7		4-11				01XXXXXX	8 bits	0-63	8-71
;	001XXXX		7 bits	0-15	12-27				00XXXXXXXX 10 bits	0-255	72-327
;	000XXXXX	8 bits	0-31	28-59
;
;	(C)
;	SELECTOR/VALUEBITS	VALUE	FINAL VALUE
;	XXXX		4 bits	0-15		0-15
;
;	The configuration of the VBV can varie depending on the compressed data, so it is stored in
;	the setup data, by the following way:
;	- BV	3bit: the number of different bit length variation-1
;	- BITS	4 bits each: an array of the bit lengths used-1 
;
;	The compressed data structure:
;	(compressed data are read as data bytes (DB), or control bits (Cb)
;
;	Setup data:
;	2 DB:	Uncompressed Height
;	1 DB:	Uncompressed Byte width	(total uncompressed bytes = Height x Byte width)
;	3 Cb:	3 bit:	CNTBV
;	x4 Cb:	4 bit x (CNTBV+1)	-> CNTVBITS array
;	3 Cb:	3 bit:	DISTBV
;	x4 Cb:	4 bit x (DISTBV+1)	-> DISTVBITS array
;
;	Compressed data:
;	Always start with STREAM, and STREAM is always followed by a REPEAT
;
;	STREAM:
;	VBV Cb:	CNTbits, length of the STREAM bytes -1
;	x DB:	STREAM bytes x = CNTbits+1
;
;	REPEAT:
;	1 Cb:	STREAM FOLLOWS, the next block is a stream if set (1)
;	VBV Cb:	DISTbits, offset of the repeat source: source = destination-DISTbits
;	VBV Cb: CNTbits, number of the repeated bytes -4
;	1 Cb:	NEG: the repeated bytes are inverted if set
;
;	The decompression:
;	After all setup bytes/bites are read, and processed, we start with a STREAM.
;	STREAM data is read, then copied to the target.
;	then a REPEAT data is read processed: target is written by copying from its previously
;	written location.
;	then continue with a STREAM or another REPEAT depending on the STREAM FOLLOWS bit.
;	before start writing a BLOCK, check if the total uncompressed bytes are reached or not.
;
;	That's all.
;
;	The code above does all of these in 188 bytes (79 instr.) of 68k assembly (relocatable)...
;	(UNPACK9O byte count without local variables, and exp table)
;
;	A small check loop is included, if the decompression was successfull, the code ends with okloop:
;	Compression tool used: http://iparigrafika.hu/hoh_proto/serialize/serialize_c.html




