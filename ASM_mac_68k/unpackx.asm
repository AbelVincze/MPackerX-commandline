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

			org $4000
	
data:
; __c64font2_packedx	mpackerx __c64font2 -dln -W 16 -M 96 -L 63 -vb
	dc.b $05, $40, $01, $AD, $25, $77, $EF, $DF, $BF, $F7, $7F, $57, $8F, $FF, $AF, $07
	dc.b $CF, $67, $6F, $9F, $D7, $0F, $5F, $37, $27, $3F, $1F, $B7, $C7, $87, $03, $E7
	dc.b $6B, $8B, $97, $5B, $9B, $AB, $4F, $BB, $F3, $2F, $24, $E0, $80, $01, $C5, $67
	dc.b $18, $88, $C1, $02, $95, $83, $6A, $2B, $3B, $64, $A5, $3B, $86, $DE, $F0, $2F
	dc.b $78, $1D, $3E, $2A, $FE, $25, $CB, $7F, $7F, $5E, $31, $41, $B9, $2F, $10, $0E
	dc.b $3A, $B1, $B9, $BB, $64, $83, $80, $99, $DB, $4C, $CD, $0A, $41, $F9, $35, $57
	dc.b $77, $75, $53, $88, $45, $D4, $CE, $66, $64, $CD, $5D, $2B, $3F, $7F, $F1, $79
	dc.b $EC, $FF, $55, $5A, $02, $E8, $5A, $E7, $40, $A2, $AF, $C0, $0A, $B5, $94, $8A
	dc.b $90, $96, $AE, $92, $83, $42, $3E, $19, $C5, $44, $7D, $23, $EB, $89, $12, $19
	dc.b $F5, $CB, $E3, $26, $AF, $73, $8B, $2F, $33, $A9, $29, $5A, $5A, $AB, $ED, $9A
	dc.b $B7, $48, $8C, $C2, $2A, $AF, $EF, $48, $8A, $51, $D5, $41, $61, $6D, $8F, $FE
	dc.b $23, $D7, $0B, $2E, $70, $19, $2E, $39, $04, $74, $34, $EE, $22, $48, $CC, $82
	dc.b $AD, $44, $7D, $89, $09, $2C, $C1, $64, $C7, $B7, $9E, $46, $6B, $39, $9D, $CC
	dc.b $B3, $E2, $3E, $94, $AA, $27, $23, $E2, $22, $0E, $89, $7B, $77, $F1, $BB, $BB
	dc.b $6D, $23, $35, $B1, $11, $0D, $36, $48, $0A, $EE, $8A, $52, $CE, $F3, $7E, $0A
	dc.b $32, $44, $9F, $88, $85, $3D, $45, $CE, $03, $6E, $DC, $F0, $00, $01, $13, $A8
	dc.b $9B, $49, $30, $C2, $5A, $D5, $C9, $09, $51, $17, $82, $CB, $EA, $18, $8A, $0A
	dc.b $2B, $B9, $8C, $25, $12, $CC, $21, $98, $80, $D3, $30, $F7, $35, $91, $6B, $8E
	dc.b $A2, $7F, $E3, $7E, $21, $45, $1B, $58, $59, $BB, $BE, $90, $43, $D0, $94, $EE
	dc.b $16, $EE, $E8, $49, $DB, $88, $4D, $52, $4D, $A6, $D1, $7A, $94, $50, $1F, $56
	dc.b $41, $14, $3E, $A2, $F6, $A8, $6F, $6C, $22, $16, $CE, $44, $D7, $E5, $05, $16
	dc.b $70, $75, $61, $23, $D0, $4E, $87, $F2, $81, $5A, $39, $84, $8A, $22, $18, $16
	dc.b $5D, $15, $12, $50, $42, $1C, $AD, $20, $8A, $E6, $35, $0B, $72, $45, $6E, $3C
	dc.b $BB, $20, $1A, $08, $03, $5E, $A5, $1C, $C5, $EA, $4A, $7B, $3F, $EA, $43, $84
	dc.b $06, $41, $9D, $E4, $9F, $0A, $05, $2B, $F7, $5A, $48, $42, $12, $BF, $07, $C3
	dc.b $A3, $39, $06, $27, $22, $50, $43, $CD, $CC, $CF, $B9, $E1, $01, $91, $99, $E1
	dc.b $23, $E8, $B7, $5D, $D8, $18, $1F, $E2, $57, $4F, $C2, $97, $20, $96, $1C, $58
	dc.b $32, $4E, $09, $71, $04, $10, $6C, $07, $39, $85, $BD, $40, $12, $EB, $EF, $15
	dc.b $01, $61, $C0, $52, $21, $21, $98, $B2, $02, $11, $F6, $01, $3A, $57, $CC, $37
	dc.b $B7, $50, $EC, $88, $07, $90, $84, $7F

dataend:

unpackeddata:
; __c64font2_unpacked (reordered for now)
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $DF, $DF, $DF, $DF, $DF, $DF, $FF, $DF, $FF, $FF, $FF, $FF, $FF, $FF, $AF
	dc.b $AF, $AF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $D7, $D7, $03
	dc.b $D7, $D7, $03, $AF, $AF, $FF, $FF, $FF, $FF, $FF, $DF, $8F, $57, $5F, $9F, $CF
	dc.b $D7, $57, $8F, $DF, $FF, $FF, $FF, $FF, $FF, $BB, $5B, $57, $AF, $D7, $AB, $6B
	dc.b $77, $FF, $FF, $FF, $FF, $FF, $FF, $9F, $6F, $7F, $BF, $5F, $6B, $77, $8B, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $EF, $EF, $EF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $FF, $F7, $EF, $DF, $DF, $BF, $BF, $BF, $BF, $DF, $DF, $EF, $F7, $FF, $FF
	dc.b $BF, $DF, $EF, $EF, $F7, $F7, $F7, $F7, $EF, $EF, $DF, $BF, $FF, $FF, $FF, $DF
	dc.b $57, $8F, $8F, $57, $DF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
	dc.b $DF, $DF, $07, $DF, $DF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $CF, $CF, $EF, $DF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $07, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $CF, $CF, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $F7, $F7, $EF, $EF, $DF, $DF, $BF, $BF, $FF, $FF
	dc.b $FF, $FF, $FF, $8F, $77, $67, $57, $37, $77, $77, $8F, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $DF, $9F, $5F, $DF, $DF, $DF, $DF, $07, $FF, $FF, $FF, $FF, $FF, $FF, $8F
	dc.b $77, $F7, $EF, $DF, $BF, $7F, $07, $FF, $FF, $FF, $FF, $FF, $FF, $8F, $77, $F7
	dc.b $CF, $F7, $F7, $77, $8F, $FF, $FF, $FF, $FF, $FF, $FF, $EF, $CF, $AF, $6F, $07
	dc.b $EF, $EF, $EF, $FF, $FF, $FF, $FF, $FF, $FF, $07, $7F, $7F, $0F, $77, $F7, $F7
	dc.b $0F, $FF, $FF, $FF, $FF, $FF, $FF, $CF, $BF, $7F, $0F, $77, $77, $77, $8F, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $07, $77, $F7, $EF, $EF, $DF, $DF, $DF, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $8F, $77, $77, $8F, $77, $77, $77, $8F, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $8F, $77, $77, $77, $87, $F7, $EF, $9F, $FF, $FF, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $CF, $CF, $FF, $FF, $CF, $CF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $CF
	dc.b $CF, $FF, $FF, $CF, $CF, $EF, $DF, $FF, $FF, $FF, $FF, $FF, $FF, $F7, $EF, $DF
	dc.b $BF, $DF, $EF, $F7, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $07, $FF, $07
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $BF, $DF, $EF, $F7, $EF, $DF, $BF
	dc.b $FF, $FF, $FF, $FF, $FF, $8F, $77, $F7, $EF, $DF, $DF, $FF, $DF, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $CF, $B7, $67, $57, $57, $67, $BF, $C7, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $DF, $DF, $DF, $AF, $AF, $07, $77, $77, $FF, $FF, $FF, $FF, $FF, $FF, $0F
	dc.b $77, $77, $0F, $77, $77, $77, $0F, $FF, $FF, $FF, $FF, $FF, $FF, $8F, $77, $7F
	dc.b $7F, $7F, $7F, $77, $8F, $FF, $FF, $FF, $FF, $FF, $FF, $1F, $6F, $77, $77, $77
	dc.b $77, $6F, $1F, $FF, $FF, $FF, $FF, $FF, $FF, $07, $7F, $7F, $0F, $7F, $7F, $7F
	dc.b $07, $FF, $FF, $FF, $FF, $FF, $FF, $07, $7F, $7F, $0F, $7F, $7F, $7F, $7F, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $8F, $77, $7F, $7F, $67, $77, $77, $8F, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $77, $77, $77, $07, $77, $77, $77, $77, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $8F, $DF, $DF, $DF, $DF, $DF, $DF, $8F, $FF, $FF, $FF, $FF, $FF, $FF, $87
	dc.b $F7, $F7, $F7, $F7, $77, $77, $8F, $FF, $FF, $FF, $FF, $FF, $FF, $77, $6F, $5F
	dc.b $3F, $3F, $5F, $6F, $77, $FF, $FF, $FF, $FF, $FF, $FF, $7F, $7F, $7F, $7F, $7F
	dc.b $7F, $7F, $07, $FF, $FF, $FF, $FF, $FF, $FF, $77, $27, $27, $57, $77, $77, $77
	dc.b $77, $FF, $FF, $FF, $FF, $FF, $FF, $77, $37, $37, $57, $57, $67, $67, $77, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $8F, $77, $77, $77, $77, $77, $77, $8F, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $0F, $77, $77, $77, $0F, $7F, $7F, $7F, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $8F, $77, $77, $77, $77, $77, $77, $8F, $EF, $F3, $FF, $FF, $FF, $FF, $0F
	dc.b $77, $77, $77, $0F, $5F, $6F, $77, $FF, $FF, $FF, $FF, $FF, $FF, $8F, $77, $7F
	dc.b $8F, $F7, $F7, $77, $8F, $FF, $FF, $FF, $FF, $FF, $FF, $07, $DF, $DF, $DF, $DF
	dc.b $DF, $DF, $DF, $FF, $FF, $FF, $FF, $FF, $FF, $77, $77, $77, $77, $77, $77, $77
	dc.b $8F, $FF, $FF, $FF, $FF, $FF, $FF, $77, $77, $77, $77, $AF, $AF, $DF, $DF, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $77, $77, $57, $57, $57, $AF, $AF, $AF, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $77, $77, $AF, $DF, $DF, $AF, $77, $77, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $77, $77, $AF, $AF, $DF, $DF, $DF, $DF, $FF, $FF, $FF, $FF, $FF, $FF, $07
	dc.b $F7, $EF, $DF, $DF, $BF, $7F, $07, $FF, $FF, $FF, $FF, $FF, $FF, $C7, $DF, $DF
	dc.b $DF, $DF, $DF, $DF, $DF, $DF, $DF, $C7, $FF, $FF, $FF, $FF, $BF, $BF, $DF, $DF
	dc.b $EF, $EF, $F7, $F7, $FF, $FF, $FF, $FF, $FF, $8F, $EF, $EF, $EF, $EF, $EF, $EF
	dc.b $EF, $EF, $EF, $8F, $FF, $FF, $FF, $DF, $DF, $AF, $AF, $77, $FF, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $07, $FF, $FF
	dc.b $FF, $FF, $FF, $FF, $DF, $EF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $87, $77, $77, $77, $67, $97, $FF, $FF, $FF, $FF, $FF, $FF, $7F
	dc.b $7F, $4F, $37, $77, $77, $77, $0F, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $8F
	dc.b $77, $7F, $7F, $77, $8F, $FF, $FF, $FF, $FF, $FF, $FF, $F7, $F7, $87, $77, $77
	dc.b $77, $67, $97, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $8F, $77, $07, $7F, $77
	dc.b $8F, $FF, $FF, $FF, $FF, $FF, $FF, $CF, $BF, $0F, $BF, $BF, $BF, $BF, $BF, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $87, $77, $77, $77, $67, $97, $F7, $8F, $FF
	dc.b $FF, $FF, $FF, $7F, $7F, $4F, $37, $77, $77, $77, $77, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $DF, $FF, $9F, $DF, $DF, $DF, $DF, $CF, $FF, $FF, $FF, $FF, $FF, $FF, $EF
	dc.b $FF, $8F, $EF, $EF, $EF, $EF, $EF, $EF, $1F, $FF, $FF, $FF, $FF, $7F, $7F, $6F
	dc.b $5F, $3F, $5F, $6F, $77, $FF, $FF, $FF, $FF, $FF, $FF, $DF, $DF, $DF, $DF, $DF
	dc.b $DF, $DF, $CF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $2F, $57, $57, $57, $57
	dc.b $57, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $4F, $37, $77, $77, $77, $77, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $8F, $77, $77, $77, $77, $8F, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $4F, $37, $77, $77, $77, $0F, $7F, $7F, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $87, $77, $77, $77, $67, $97, $F7, $F7, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $27, $9F, $BF, $BF, $BF, $1F, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $8F
	dc.b $77, $9F, $EF, $77, $8F, $FF, $FF, $FF, $FF, $FF, $FF, $BF, $BF, $0F, $BF, $BF
	dc.b $BF, $B7, $CF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $77, $77, $77, $77, $67
	dc.b $97, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $77, $77, $AF, $AF, $DF, $DF, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $77, $77, $57, $57, $FF, $FF, $FF, $FF, $FF
	dc.b $8F, $77, $7F, $7F, $67, $77, $AF, $DF, $DF, $AF, $77, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $77, $77, $AF, $AF, $DF, $DF, $BF, $7F, $FF, $FF, $FF, $FF, $FF
	dc.b $FF, $07, $EF, $DF, $BF, $7F, $07, $FF, $FF, $FF, $FF, $FF, $FF, $E7, $DF, $DF
	dc.b $DF, $DF, $3F, $DF, $DF, $DF, $DF, $E7, $FF, $FF, $DF, $DF, $DF, $DF, $DF, $DF
	dc.b $DF, $DF, $DF, $DF, $FF, $FF, $FF, $FF, $FF, $3F, $DF, $DF, $DF, $DF, $E7, $DF
	dc.b $DF, $DF, $DF, $3F, $FF, $FF, $FF, $FF, $FF, $FF, $9B, $67, $FF, $FF, $FF, $FF
	dc.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
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




