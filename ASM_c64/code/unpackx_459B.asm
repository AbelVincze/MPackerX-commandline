// munpackerX, c64 version, kickAssembler syntax


*=$03DD "BSS" virtual 
ENDa:       .word  0
dw:         .byte  0
h:          .word  0
l:          .word  0
CNTbv:      .byte  0 	// order is important
CNTbits:    .byte  0, 0, 0, 0, 0, 0, 0, 0
DISTbv:     .byte  0
DISTbits:   .byte  0, 0, 0, 0, 0, 0, 0, 0
LIbv:		.byte  0
LIbits:		.byte  0, 0, 0, 0, 0, 0, 0, 0
Flags: 		.byte  0 	// 1: DIR, 2: NEGCHECK, 4: USELOOKUP

			*=$0801 "basic startup"

			// basic start line
			.byte $0B, $08, $00, $00, $9E, $32, $30, $36, $31, $00, $00, $00

			*=* "main code"

.const mmchl = 4
.var zpvars = $D9




main:       
			//*
			sei

			lda #$3b		// graphix mode on
			sta $d011
			lda #$18
			sta $d018

			lda #$e6 		// set hires graphic color
			ldy #$00
!loop:   	sta $400,y
			sta $500,y
			sta $600,y
			sta $6E8,y
			dey
			bne !loop-

			jsr swapdata
			jsr UNPACKX        // do unpack
			jsr swapdata
			cli
			rts

swapdata:
			ldy #dataend-data-1
!loop:
			lda data,y
			pha
			lda zpvars,y
			sta data,y 
			pla
			sta zpvars,y
			dey
			bpl !loop-
			rts

			*=* "zp data block"
data:
.pseudopc zpvars {

//tmpY:        .byte 0
tmpY2:       .byte 0
tmpY3: 		 .byte 0
licnt:       .word 0
tbin:        .word 0
pbin:        .word packeddata        // packed binary input
bout:        .word $2000		        // binary output
boend:       .word 0  		        // last out byte +1 (to compare)
isStream:    .byte 1
bitbc:       .byte 0
BITBUFF:     .byte 0
bits:        .word 0
tmp:         .word 0
cnt:         .byte 0
outbits:     .word 0

}
dataend:
			*=* "unpack code"


UNPACKX:   // unpacking pakerX packages
	  
			// INIT unpack loop: isStream to true for starting
			// these are initialized by the swapdata
			// lda #1
			// sta isStream
			// lda #0              // inicializalas...
			// sta bitbc
			// sta l               // length = dw * h
			// sta l+1

			jsr getAbyte        // height
			sta h+1
			jsr getAbyte
			sta h

			jsr getAbyte        // read first byte of the packed data
			sta dw              // byte width
			tax

!loop:		lda l               // calc length (l*h)
			clc
			adc h
			sta l
			lda l+1
			adc h+1
			sta l+1
			dex
			bne !loop-      

			lda l               // calc end address (+1)
			clc
			adc bout
			sta boend
			lda l+1
			adc bout+1
			sta boend+1

				ldx #2          // 3 bitet olvasunk
				jsr pullnbits
				sta Flags
				and #$04
				beq skipli

				jsr getAbyte
				tax
				lda pbin
				sta LUT+1
				lda pbin+1
				sta LUT+2
				txa
				bne !skip+
				inc pbin+1 		// ha 0, akkor 256 !
!skip:						
				clc
				adc pbin
				sta pbin
				bcc !skip+
				inc pbin+1
!skip:
				lda #<LIbv
				ldx #>LIbv
				ldy #2
				jsr setupnv

skipli:
			//restore CNTbitdepths
			lda #<CNTbv
			ldx #>CNTbv
			ldy #3
			jsr setupnv

			//restore DISTbitdepths
			lda #<DISTbv
			ldx #>DISTbv
			ldy #3
			jsr setupnv

			// UNPACK data ------------------------------------------------------------------
			// unpack mainloop
unpackloop:
			lda bout+1 			// is finished?
			cmp boend+1
			bcc ulcont
			lda bout
			cmp boend
			bcc ulcont
			rts

ulcont:
			lda isStream
			beq Repeat

Stream:		// STREAM --------------------------------------------
			dec isStream 		// next block will be REPEAT
			jsr pullCNTbits 	// read data length

			sta licnt+1 		// a bits+1 van az akkuban!
			lda bits
			sta licnt

sloop:
				lda Flags
				and #$04 		// USELOOKUP?
				bne slcopy

			jsr getAbyte 		// copy from packed data
			jmp !skip+

slcopy:
				lda #<LIbv
				ldx #>LIbv
				jsr pulldatabits  // Rear variable lenght "byte"
				ldy bits
LUT:
				lda $FFFF,y 	// Address set up at LUT init
!skip:
				jsr setAbyte 	// the stream is packed

			lda licnt 			// * 16 bit arithmetic *
			bne ln0
			lda licnt+1
			beq unpackloop
			dec licnt+1
ln0:        dec licnt
			jmp sloop


Repeat:		// REPEAT --------------------------------------------
			jsr pullbit
			lda #0
			adc #0
			sta isStream

			lda #<DISTbv
			ldx #>DISTbv
			jsr pulldatabits
			lda bout 			// * 16 bit arithmetic *
			sec
			sbc bits
			sta tbin
			lda bout+1
			sbc bits+1
			sta tbin+1

			jsr pullCNTbits
			clc 				// * 16 bit arithmetic *
			lda bits 			// ezt a reszt modositjuk, hogy ne kelljen mar ennyit matekozni
			adc #mmchl
			sta bits
			bcc r3
			inc bits+1
r3:			ldy #0
			
				lda Flags 		// NEGCHECK?
				and #$02
				beq r1

			jsr pullbit
			lda #0
			bcc r1
			lda #$ff
r1:         sta tmp
repeatloop:
			
			lda (tbin),y
			eor tmp
			sta (bout),y
			iny 				// * 16 bit arithmetic *
			bne r0
			inc tbin+1
			inc bout+1
r0:         cpy bits
			bne repeatloop
			dec bits+1
			bpl repeatloop
			tya
			clc 				// * 16 bit arithmetic *
			adc bout
			sta bout
			bcc r2
			inc bout+1
r2:
			jmp unpackloop

			//---------------------------------------------------------------------
			// HELPER FUNCTIONS
setupnv:
			sty snvx+1
			sta tmp
			stx tmp+1
			ldx #2              // 3 bitet olvasunk
			jsr pullnbits
			ldy #0
			sta (tmp),y
			clc
			adc #2
			sta schk+1
			iny
snvx:		ldx #$00			// read 3/4 bits (dep input Y)
sloop1:
			jsr pullnbits
			sta (tmp),y
			iny
schk:       cpy #0
			bne sloop1
			rts

getAbyte: 	// read a byte from the packed data
			//sty tmpY       		// save y
			ldy #0
			lda (pbin),y
			inc pbin 			// * 16 bit arithmetic *
			bne end
			inc pbin+1
end:        //ldy tmpY
			rts   

setAbyte:	// write a byte to the target memory 
			//sty tmpY        	// save y
			ldy #0
			sta (bout),y
			inc bout 			// * 16 bit arithmetic *
			bne sbend
			inc bout+1
sbend:      //ldy tmpY
			rts   

pullbit: 	// pull a single bit from the packed data
			sty tmpY2
			ldy bitbc
			bne next
			jsr getAbyte
			ldy #8
			sta BITBUFF
next:
			dey
			sty bitbc
			ldy tmpY2
			rol BITBUFF
			rts
 
pullnbits:  // pull N bits from the packed data
			// x-ben a bitek szama
			stx tmpY3          // save X, no need to save Y
			lda #0
			sta bits
			sta bits+1
loop:       jsr pullbit
			rol bits
			rol bits+1
			dex
			bpl loop
			lda bits
end2:       ldx tmpY3
			rts

pullCNTbits:                     // eredmeny bits-ben
			lda #<CNTbv
			ldx #>CNTbv

pulldatabits:
			sta tmp
			stx tmp+1            //tmp fog mutatni tablazatra
			ldy #0
			sty outbits
			sty outbits+1
			lda (tmp),y
			iny
			sta cnt              // max bitv         
			bne pdloopin

pdloop:
			jsr pullbit
			bcs read

			lda expL,x
			clc
			adc outbits
			sta outbits
			lda expH,x
			adc outbits+1
			sta outbits+1

pdloopin:
			lda (tmp),y
			iny
			tax
			dec cnt
			bpl pdloop

read:
			jsr pullnbits
			lda outbits
			clc
			adc bits
			sta bits
			lda outbits+1
			adc bits+1
			sta bits+1
			rts

expL:       .byte <2, <4, <8, <16, <32, <64, <128, <256, <512, <1024, <2048, <4096, <8192, <16384, <32768
expH:       .byte >2, >4, >8, >16, >32, >64, >128, >256, >512, >1024, >2048, >4096, >8192, >16384, >32768



theend:

.print "munpackerX length "+(expL-UNPACKX)+" Bytes"	   
.print "total code length "+(theend-main)+" Bytes"	   
//.print "BSS code length "+(theend-ENDa)+" Bytes"	   

packeddata:
//.import binary "spiral_NL.pkx"
.import binary "spiral_back.pkx"


.print "packeddata length "+(*-packeddata)+" Bytes"	   
