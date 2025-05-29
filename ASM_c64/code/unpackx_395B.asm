// munpackerX, c64 version, kickAssembler syntax


.const mmchl = 4
.var zpvars = $c0  //$D9 
.var BSS =  $c6    //$3DD // putting bss to ZP makes code 14 bytes less
.var BSSbuffer = $3C5 	  // but needs caching to not destroy basic

*=BSS "BSS" virtual 
			// unpack data
ENDa:       .word  0 	
h:          .word  0
l:          .word  0
CNTbv:      .byte  0 	// order is important
CNTbits:    .byte  0, 0, 0, 0, 0, 0, 0, 0
DISTbv:     .byte  0
DISTbits:   .byte  0, 0, 0, 0, 0, 0, 0, 0
LIbv:		.byte  0
LIbits:		.byte  0, 0, 0, 0, 0, 0, 0, 0
Flags: 		.byte  0 	// 1: DIR, 2: NEGCHECK, 4: USELOOKUP
			// zp variables
tmp1:       .byte  0
tmp2:       .byte  0
tmpY2:      .byte  0
tmpY3: 		.byte  0
lut: 		.word  0
licnt:      .word  0
tbin:       .word  0
boend:      .word  0  		        // last out byte +1 (to compare)
bitbc:      .byte  0
BITBUFF:    .byte  0
bits:       .word  0
cnt:        .byte  0
outbits:    .word  0

			*=$0801 "basic startup"

			// basic start line
			.byte $0B, $08, $00, $00, $9E, $32, $30, $36, $31, $00, $00, $00

			*=* "main code"

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

			ldy #52
!loop:
			lda BSS,y
			pha
			lda BSSbuffer,y
			sta BSS,y 
			pla
			sta BSSbuffer,y
			dey
			bpl !loop-			
			rts

			*=* "zp data block"
data:
.pseudopc zpvars {
			// not reusable data, it will be overwritten with actual values
pbin:        .word packeddata       // packed binary input
bout:        .word $2000		    // binary output
isStream:    .byte 1
tmp:         .byte 0, >BSS 			// store high byte for DIST/CNT/LIbv
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

			jsr getAbyte        // height Big endian
			sta h+1
			jsr getAbyte
			sta h
			jsr getAbyte        // read first byte of the packed data
			tax 				// we do not store dw (but maybe should) - 2 bytes

!loop:		lda l               // calc length (l*h)
			adc h 				// don't need clc, cause we start with C clear,
			sta l 				// and second add also clears - 1 Byte
			lda l+1
			adc h+1
			sta l+1
			dex
			bne !loop-      

			lda l               // calc end address (+1)
			adc bout			//clc - the previous addition left C clear -1 Byte
			sta boend
			lda l+1
			adc bout+1
			sta boend+1

			ldx #2          	// 3 bitet olvasunk
			jsr pullnbits
			sta Flags
			and #$04 			// USELOOKUP?
			beq skipli
								// set up LUT
			jsr getAbyte 		// LUT size 0-255 (0=256)
			ldx pbin 			// remove tax and use X to save A - 1 byte
			stx lut 			// using zp lut instead of code rewrite saves 3 bytes
			ldx pbin+1
			stx lut+1
			tax 				// need to set Z 
			beq !skipadd+ 		// ha 0, akkor 256 ! (bne-rol valtva a logika -> -2 byte)
			adc pbin 			// clc was cleared by getAbyte
			sta pbin
			bcc !skip+
!skipadd:
			inc pbin+1
!skip:
			lda #<LIbv
			ldx #2
			jsr setupnv
						
skipli:
			//restore CNTbitdepths
			ldx #3				// -0 byte, setupnv restores Y
			lda #<CNTbv 		// only need low byte
			jsr setupnv

			//restore DISTbitdepths
			lda #<DISTbv
			jsr setupnv

// UNPACK data ------------------------------------------------------------------
			
unpackloop:						// unpack mainloop
			lda bout+1 			// is finished?
			cmp boend+1
			bcc ulcont 			// bcc is failsafe... bne is strict
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
				and #$04 			// USELOOKUP?
				bne slcopy

				jsr getAbyte 		// copy from packed data
				bne !skip+ 			// utoljara inc pbin+1 volt, az meg ugye...
slcopy:
				lda #<LIbv
				jsr pulldatabits  	// Rear variable lenght "byte"
				ldy bits
				lda (lut),y 		// Address set up at LUT init
!skip:
				jsr setAbyte 		// the stream is packed

				lda licnt 			// * 16 bit arithmetic *
				bne ln0
				dec licnt+1
				bmi unpackloop 		// ?bne (+lda/dec) nem hiszem hogy 32767 byte-nal hosszabb stream lenne.		
ln0:        dec licnt
			jmp sloop

Repeat:		// REPEAT --------------------------------------------
			jsr pullbit
			rol isStream

			lda #<DISTbv
			jsr pulldatabits
			lda bout 			// * 16 bit arithmetic *
			sec
			sbc bits
			sta tbin
			lda bout+1
			sbc bits+1
			sta tbin+1

			jsr pullCNTbits 	// clc not needed, pulldatabits clears it - 1 byte
			lda bits 			// ezt a reszt modositjuk, hogy ne kelljen mar ennyit matekozni
			adc #mmchl
			tax 				// using x instead of bits - 2 bytes
			bcc r3
			inc bits+1
r3:			ldy #0
			sty tmp 			// tmp atszervezese - 1 byte
			
			lda Flags 			// NEGCHECK?
			and #$02
			beq repeatloop

			jsr pullbit 		// is NEG?
			bcc repeatloop
			dec tmp

repeatloop:			
				lda (tbin),y
				eor tmp
				sta (bout),y
				iny 				// * 16 bit arithmetic *
				bne r0
				inc tbin+1
				inc bout+1
r0:         	dex
				bne repeatloop
				dec bits+1 
				bpl repeatloop 		// csak akkor mukodik ha 32768-nal rovidebb...
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
			stx tmp1 			// using X instead of Y saves 2 bytes
			sta tmp
			ldx #2              // 3 bitet olvasunk
			jsr pullnbits
			ldy #0
			sta (tmp),y
			adc #1 				// pullnbits cleared C -1 byte
			sta tmp2
			ldx tmp1			// read 3/4 bits (dep input Y)
sloop1:
			iny 				// repositioning iny - 1 byte
			jsr pullnbits
			sta (tmp),y
	        cpy tmp2
			bne sloop1
			rts

getAbyte: 	// read a byte from the packed data - Y modified
			ldy #0
			lda (pbin),y
			inc pbin 			// * 16 bit arithmetic *
			bne end
			inc pbin+1
end:        rts   

setAbyte:	// write a byte to the target memory - Y modified
			ldy #0
			sta (bout),y
			inc bout 			// * 16 bit arithmetic *
			bne sbend
			inc bout+1
sbend:      rts   

pullbit: 	// pull a single bit from the packed data - X/Y saved, A modified
			sty tmpY2
			dec bitbc
			bpl next
			jsr getAbyte
			ldy #7
			sty bitbc
			sta BITBUFF
next:
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
			ldx tmpY3
			lda bits
			rts

pullCNTbits:                     // eredmeny bits-ben
			lda #<CNTbv

pulldatabits:
			sta tmp
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
			adc outbits 		// clc not needed, C is clear here (bcs)
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
			jsr pullnbits 		// bits in A already - 2 Bytes
			adc outbits  		// pullnbits cleared C -1 byte
			sta bits
			lda outbits+1
			adc bits+1
			sta bits+1 			// C is clear, no overflow here...
			rts

expH:       .byte >2, >4, >8, >16, >32, >64, >128, >256 //, >512, >1024, >2048, >4096, >8192, >16384, >32768
expL:       .byte <2, <4, <8, <16, <32, <64, <128, <256, <512, <1024, <2048, <4096, <8192, <16384, <32768
			// <2 = >512, <4 = >1024 etc... save 7 bytes

theend:

.print "munpackerX length "+(expH-UNPACKX)+" Bytes"	   
.print "total code length "+(theend-main)+" Bytes"	   
.print "BSS code length "+(Flags+1-BSS)+" Bytes"	   

packeddata:
.import binary "spiral_NL.pkx"
//.import binary "spiral_back_NL.pkx"


.print "packeddata length "+(*-packeddata)+" Bytes"	   
