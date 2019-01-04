; unpackerX
;
; 68k ASM unpacking routine for 68k Mac by Abel Vincze 2018/12/10
; This source file is designed to test run in Tricky68k simulator
;
; unpackerX is an extended version of the unpacker9o decompression routine.
; It reads and decompresses files compressed with MPackerX cmd/gui tool.

			code
			public start    ; Make the entry point public
			org $2000       ; Place the origin at $2000

TTY:        equ $FFE000
mmchl:		equ	$4-1		; a constant used in the compressor, needed for decompressing



start:
			; set up variables, and pointer to packed/unpacked data ------------------------
			lea		locals(PC), a0			; access local variables with a0

			lea		data(PC),a1				; source and
			lea		OUT(PC),a2				; target address parameters
			bsr.b	UNPACKX					; decompressing
			; finish unpacking, here we need to rearrange bytes...
			
			; CHECK START
			; from here, we only checks the decompressed data with the included original.
			; if you implement this routine, just skip this part
			move.w	#exp-UNPACKX, d7		; code length display...
			
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
			; CHECK END

UNPACKX:		
			; UnpackX 68k ASM --------------------------------------------------------------
			; a0 - locals
			; a1 - packed data
			; a2 - output address
			; used; d0,d1,d2,d3,d4,d5,d6,d7/a3,a4
			
											; SETUP DATA
			move.w  (a1)+, d1				; start reading the compressed data...
			move.w	d1, H(a0)				; data height	16bit
			moveq	#0, d0					; clear d0...
			move.b	(a1)+, d0				; data width	8bit
			move.b	d0, DW+1(a0)
			mulu.w	d0, d1					; uncompressed data lenght calculated from DW*H
			move.w	d1, L(a0)				; final data length
			
			add.l	a2, d1					; add lenght to OUR address to
			move.l	d1,(a0)					; set end address for finish comp
			
			moveq	#0, d5					; clear d5... BITBC (control bit counter in buffer)

				moveq	#2, d0					; 3 bits to read
				bsr		pullnbits				; read control bits and
				move.b	d1, FLAGS(a0)			; store in flags (USELOOKUP, NEGCHECK, DIR)
				btst	#2, d1					; USELOOKUP?
				beq.b	.skipli					; if we don't use LOOKUP table, just skip this part
				
				move.b	(a1)+, d1				; number of LUT entries
				move.l  a1, LUT(a0)				; save LUT addr
				adda	d1,a1					; skip LUT entries (as we direct read them later)
				; restore LIbitdepths
				moveq	#2, d6					; 3 bits to read
				lea		LIbv(PC), a3
				bsr.b	setupVNV				; read and store LIbitdepths entries
.skipli:
			moveq	#3, d6					; 4 bits to read
			; restore CNTbitdepths
			lea		CNTbv(PC), a3
			bsr.b	setupVNV				; read and store CNTbitdepths entries

			; restore DISTbitdepths
			lea 	DISTbv(PC), a3
			bsr.b	setupVNV				; read and store DISTbitdepths entries
			
			; INIT unpack loop: isStream to true for starting
			;moveq	#1, d3					; isStream = 1	; don't need to set up, as it is not zero
											; setupVNV has left it -1.W
			
			; UNPACK data ------------------------------------------------------------------
											; unpack mainloop
unpackloop:
			cmpa.l	(a0), a2				; compare data length
			bge.b	__rts__					; -> finish
			
			tst.b	d3						; isStream?
			bne.b	.isstream							
			
.isrepeat:	
			; REPEAT BLOCK 
			bsr.b	pullbit					; next block?
			roxl.b	#1,d3					; set the read bit in isStream  
			
			bsr.b	pullDISTbits			; read distance, and store in d1
			movea.l	a2, a3					; copy write address to a3
			suba.w	d1, a3					; substract distance, and save as source of copy in a3

			bsr.b	pullCNTbits				; read counter, result in d1
			addq.w	#mmchl, d1				; fix it

				btst	#1,Flags(PC)		; NEGCHECK (do the compressed data contains NEGCHK bits?)
				beq.b	.repeatloop			; if no, just skip to the copy part
				
			bsr.b	pullbit					; read bit: NEG
			bcs.b	.repeatnegloop			; if NEG is set, we have an inverted block, skip there
			
.repeatloop:
			move.b	(a3)+, (a2)+			; copy the repeated stream
			dbra	d1, .repeatloop			; (read from the already decompressed data)
			bra.b	unpackloop

.repeatnegloop:
			move.b	(a3)+, (a2)				; copy and negate the repeated stream;
			not.b	(a2)+
			dbra	d1, .repeatnegloop
			bra.b	unpackloop

			
.isstream:
			; STREAM BLOCK
			bsr.b		pullCNTbits			; read counter, result in d1
				btst	#2,Flags(PC)			; USELOOKUP?
				bne.b	.lcopy			
.copyloop:
			move.b	(a1)+, (a2)+			; copy the stream;
			dbra	d1, .copyloop
			bra.b	.copyend				; d3 nulla, tehat nem stream a kovetkezo
.lcopy
				move.w	d1, d3					; LOOKUP table is used, store counter in d3
				move.l	Lut(PC), a3				; get LOOKUP table address, and store in a3
.lcopyloop:
				bsr.b	pullLIbits				; read LOOKUP table index
				move.b	(a3,d1), (a2)+			; read byte from LOOKUP table and 
				dbra	d3, .lcopyloop			; repeat until counter=-1
.copyend:				
				moveq	#0,	d3					; set next block as repeat!
				bra.b	unpackloop				

	
			; HELPER FUNCTIONS -------------------------------------------------------------
setupVNV:									; input d6 = bitlength of the entries
											; a3 = address of the bitdepths array
			moveq	#2, d0					; setup bitdepths table 
			bsr.b 	pullnbits				; 3 bits to read, result in d1 (number of bitdepths entries)
			move.w	d1,d3					; save as counter for the read loop
			move.b	d1, (a3)+				; store also in the first entry of our array
.loop:
			move.w	d6, d0					; bits to read
			bsr.b	pullnbits				; get that number of bits
			move.b	d1, (a3)+				; store in the array
			dbra	d3,	.loop
__rts__:	rts
			
pullbit:									; used global(!) d5/d4 (Bitcounter, buffer)
											; pull 1 control bit
			tst.b	d5						; bit counter
			bne.b	.next
			moveq	#8, d5					; reset bitcounter
			move.b	(a1)+, d4				; if 0, get a new byte to the buffer
.next
			subq.b	#1, d5					; decrement counter
			roxl.b	d4						; read a bit from the buffer
			rts								; result in X/C

pullDISTbits:
			lea		DISTbv(PC), a4			; address of the DISTbitdepths array in a4
			bra.b	pulldatabits			; continue
			
pullCNTbits:
			lea		CNTbv(PC), a4			; address of the CNTbitdepths array in a4
				bra.b	pulldatabits			; continue

pullnbits:									; inputd0 = n, used d6, out d1
											; pull N number of control bits
			moveq	#0, d1					; clear result reg
.loop
			bsr.b	pullbit					; pull a bit from buffer
			addx.w	d1,d1					; push it to the result
			dbra	d0, .loop
			addq.w	#1, d0					; to clear w bits
			rts

			
pullLIbits:
				lea		LIbv(PC), a4		; address of the LIbitdepths array in a4	
pulldatabits:								; get the number with the selected format (CNT/DIST bits)
											; change: d0,d1/a4 (uses: d0,d1,d2,d6,d7/a4
			moveq	#0, d6					; clear for safety
			move.b	(a4)+,d6				; d6 length of bitdepths array, a4 bitdepths array (first entry is the length)
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
			dbra	d6, .loop				; next bit
.read
			bsr.b	pullnbits				; d0-ban actbits, d1-ben eredmeny
			add.w	d7, d1
			rts
			
			; table for quick fix
exp:		dc.w	2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768			
	
	
			; LOCAL variables
			;org $2200
	
locals:
ENDa:		dc.l	0	; saved 4 bytes by making this var first...
Lut:		dc.l	0
dw:			dc.w	0
h:			dc.w	0
l:			dc.w	0
CNTbv:		dc.b	0						; order is important
CNTbits:	dc.b	0, 0, 0, 0, 0, 0, 0, 0
DISTbv:		dc.b	0
DISTbits:	dc.b	0, 0, 0, 0, 0, 0, 0, 0
LIbv:		dc.b	0
LIbits:		dc.b	0, 0, 0, 0, 0, 0, 0, 0
Flags:		dc.b	0	; 0: DIR	, 1: NEGCHECK	, 2: USELOOKUP

DW:			equ		dw		-locals
H:			equ		h		-locals
L:			equ		l		-locals
ENDA:		equ		ENDa	-locals
CNTBV:		equ		CNTbv	-locals
CNTBITS:	equ		CNTbits	-locals
DISTBV:		equ		DISTbv	-locals
DISTBITS:	equ		DISTbits-locals

LIBV:		equ		LIbv	-locals
LIBITS:		equ		LIbits	-locals
FLAGS:		equ		Flags	-locals
LUT:		equ		Lut		-locals

			org $3000
	
data:
; __c64font2_packedx	mpackerx __c64font2 -dln -W 16 -M 96 -L 63 -vb
	dc.b $01, $00, $10, $F4, $32, $FF, $E7, $99, $C3, $9F, $81, $F9, $00, $F3, $CF, $C1
	dc.b $80, $0F, $83, $E3, $FC, $9C, $C7, $3F, $F1, $87, $93, $07, $E0, $1F, $8F, $F8
	dc.b $CC, $91, $33, $C9, $9D, $94, $F7, $89, $F0, $66, $FE, $03, $C0, $18, $E1, $88
	dc.b $EF, $3C, $01, $B9, $98, $ED, $7F, $A4, $93, $A0, $46, $82, $09, $41, $0A, $FC
	dc.b $10, $10, $80, $BF, $09, $D8, $94, $21, $13, $05, $46, $7C, $10, $1D, $B7, $4B
	dc.b $98, $55, $31, $6B, $2D, $07, $70, $AC, $C9, $05, $8B, $B6, $D7, $80, $14, $17
	dc.b $05, $B4, $50, $04, $48, $D4, $78, $94, $9F, $68, $F4, $38, $8D, $AF, $C9, $DB
	dc.b $4F, $B6, $DC, $F9, $6D, $B2, $59, $69, $B6, $D4, $C0, $D2, $9C, $F7, $94, $E9
	dc.b $3A, $52, $94, $F8, $46, $0A, $48, $B6, $8B, $7A, $0D, $2B, $27, $53, $B3, $A4
	dc.b $8E, $D9, $CA, $51, $12, $8F, $12, $90, $3A, $7D, $04, $ED, $87, $29, $8B, $12
	dc.b $20, $4E, $8D, $97, $06, $37, $E5, $31, $A8, $4C, $0E, $B2, $48, $D1, $C2, $23
	dc.b $A5, $89, $D4, $B5, $DB, $68, $35, $11, $08, $AE, $C9, $09, $C8, $42, $08, $9C
	dc.b $78, $94, $81, $D3, $F7, $F6, $A5, $F7, $9F, $23, $AB, $79, $B2, $F2, $F6, $AB
	dc.b $14, $A1, $3A, $39, $09, $20, $53, $DE, $F7, $14, $1B, $3F, $73, $64, $96, $D1
	dc.b $42, $A8, $1A, $E4, $E8, $42, $3A, $2A, $9C, $8E, $A2, $48, $9C, $78, $94, $81
	dc.b $D3, $EF, $10, $27, $6C, $24, $44, $4D, $C1, $DC, $B0, $BC, $8D, $8A, $3C, $0B
	dc.b $9E, $A5, $49, $30, $AA, $24, $42, $0A, $5F, $E9, $EB, $39, $05, $2A, $0D, $7C
	dc.b $52, $9D, $B3, $A4, $B0, $16, $3C, $89, $C7, $89, $48, $1D, $3E, $E4, $A1, $02
	dc.b $10, $84, $CD, $83, $8C, $78, $17, $99, $5B, $81, $51, $28, $25, $4A, $DE, $44
	dc.b $2B, $82, $82, $87, $07, $95, $6F, $C2, $B0, $C4, $14, $A8, $35, $D2, $7C, $94
	dc.b $79, $20, $3C, $E2, $27, $1E, $25, $20, $64, $FF, $02, $32, $38, $11, $29, $EC
	dc.b $FB, $9A, $0B, $C0, $39, $F2, $09, $70, $A8, $33, $0A, $BC, $10, $04, $4F, $E9
	dc.b $02, $02, $02, $42, $70, $91, $87, $20, $A5, $41, $AE, $87, $D7, $5B, $64, $00
	dc.b $A4, $56, $3C, $4A, $40, $E9, $F4, $FC, $80, $8E, $8A, $F3, $0C, $30, $31, $E0
	dc.b $63, $22, $99, $15, $57, $22, $73, $2C, $B5, $9B, $82, $93, $A7, $4E, $C9, $F0
	dc.b $BC, $14, $B5, $AF, $9F, $52, $83, $4A, $48, $ED, $9C, $A2, $64, $30, $31, $EE
	dc.b $0A, $22, $71, $E2, $52, $07, $4F, $88, $36, $C9, $DB, $4D, $BD, $FB, $46, $56
	dc.b $B5, $B5, $93, $ED, $87, $38, $CC, $14, $99, $6E, $D6, $FF, $4E, $A0, $90, $91
	dc.b $E3, $D6, $69, $D0, $6A, $62, $10, $4D, $5E, $43, $E4, $4E, $3C, $4A, $40, $E9
	dc.b $FF, $D4, $18, $D1, $F2, $E3, $63, $6B, $18, $CA, $DA, $A9, $72, $B7, $E3, $AB
	dc.b $18, $41, $B6, $AB, $05, $26, $AC, $12, $02, $14, $40, $C3, $81, $BF, $BD, $0B
	dc.b $5A, $E8, $35, $32, $C3, $6A, $D2, $02, $A1, $CC, $10, $44, $B3, $C4, $B8, $48
	dc.b $01, $09, $12, $07, $5C, $D0, $15, $8C, $63, $04, $9B, $12, $A6, $56, $A1, $32
	dc.b $6E, $BF, $BD, $EB, $86, $81, $5A, $50, $78, $E9, $20, $69, $4E, $7B, $8A, $0D
	dc.b $85, $A0, $BD, $40, $49, $C5, $45, $29, $4A, $F2, $25, $95, $A4, $52, $3C, $4B
	dc.b $F4, $AB, $40, $25, $A8, $48, $81, $A8, $94, $1A, $FC, $24, $40, $D1, $02, $74
	dc.b $ED, $C1, $8D, $F2, $5A, $9B, $69, $56, $56, $DA, $69, $03, $33, $A2, $AD, $5A
	dc.b $EE, $0E, $40, $B1, $77, $89, $04, $90, $41, $04, $50, $6A, $62, $10, $24, $8F
	dc.b $47, $95, $20, $74, $5F, $23, $07, $39, $31, $80, $C6, $92, $D0, $B0, $12, $BD
	dc.b $F8, $EE, $3E, $B5, $0D, $A7, $C3, $B0, $72, $D6, $B3, $8E, $6B, $51, $22, $FC
	dc.b $78, $88, $31, $32, $50, $6B, $21, $B6, $DB, $C8, $DC, $79, $52, $07, $45, $EF
	dc.b $30, $0C, $F0, $C3, $0C, $32, $76, $60, $CB, $E9, $D9, $30, $68, $C9, $C9, $CE
	dc.b $38, $60, $D3, $4A, $3C, $71, $77, $05, $87, $8B, $17, $24, $B6, $8A, $15, $40
	dc.b $D7, $26, $7B, $C3, $08, $E4, $79, $52, $07, $45, $E4, $70, $72, $52, $11, $B4
	dc.b $97, $A5, $76, $FD, $F3, $F6, $C1, $B5, $8A, $65, $1B, $0B, $1C, $79, $46, $8D
	dc.b $18, $74, $85, $B8, $38, $28, $2B, $7A, $38, $50, $AB, $69, $04, $10, $42, $6C
	dc.b $A0, $D5, $48, $4E, $C4, $77, $3C, $AE, $3C, $7A, $12, $24, $0E, $9F, $BF, $F5
	dc.b $11, $EF, $20, $1D, $AF, $7B, $40, $F2, $16, $A6, $56, $A2, $7C, $A6, $59, $62
	dc.b $D6, $76, $0E, $6A, $DE, $03, $16, $1E, $38, $B0, $0C, $F7, $44, $5A, $CA, $A2
	dc.b $5A, $0D, $E4, $00, $A4, $73, $3C, $AE, $3C, $00, $84, $89, $03, $A7, $C0

dataend:

unpackeddata:
; __c64font2_unpacked (reordered for now)
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
;	Unpacking mechanism 9o
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




