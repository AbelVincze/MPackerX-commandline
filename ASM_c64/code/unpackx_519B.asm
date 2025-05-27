// munpackerX, c64 version, kickAssembler syntax

			*=$0801 "basic startup"

			// basic start line
			.byte $0B, $08, $00, $00, $9E, $32, $30, $36, $31, $00, $00, $00

			*=* "main code"

.const mmchl = 4

.var licnt       = $8C
.var tbin        = $8E
.var pbin        = $90       // packed binary input
.var bout        = $92        // binary output
.var boend       = $94        // last out byte +1 (to compare)
.var isStream    = $96
.var bitbc       = $97
.var BITBUFF     = $98
.var bits        = $9A
.var tmp         = $9C
.var cnt         = $9E
.var outbits     = $9F



main:       
			//*
			sei
			lda #$3b
			sta $d011
			lda #$18
			sta $d018

			lda #$e6
			ldy #$00
!loop:   	sta $400,y      //clear screen
			sta $500,y
			sta $600,y
			sta $6E8,y
			dey
			bne !loop-
			//*/
			lda #<packeddata
			ldx #>packeddata
			sta pbin
			stx pbin+1
			lda #<$2000
			ldx #>$2000
			sta bout
			stx bout+1

			//rts
			jsr UNPACKX        // do unpack

			lda #<exp
			sec
			sbc #<UNPACKX
			sta $07ff
			lda #>exp
			sbc #>UNPACKX
			sta $07fe

			cli
			rts


UNPACKX:   // unpacking pakerX packages
	  
			// INIT unpack loop: isStream to true for starting
			lda #1
			sta isStream
			lda #0              // inicializalas...
			sta bitbc
			sta l               // length = dw * h
			sta l+1

			jsr getAbyte        // height
			sta h+1
			jsr getAbyte
			sta h

			jsr getAbyte        // read first byte of the packed data
			sta dw              // byte width
			tax

mloop:		lda l               // calc length
			clc
			adc h
			sta l
			lda l+1
			adc h+1
			sta l+1
			dex
			bne mloop      

			lda l               // calc end address (+1)
			clc
			adc bout
			sta boend
			lda l+1
			adc bout+1
			sta boend+1

				ldx #2          // 3 bitet olvasunk
				jsr pullnbits
				//and #%00000111
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
				clc
				adc pbin
				sta pbin
				lda #0
				cpx #0
				bne !skip+
				lda #1
!skip:			
				adc pbin+1
				sta pbin+1
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

			// is finished?
			lda bout+1
			cmp boend+1
			bcc ulcont
			lda bout
			cmp boend
			bcc ulcont
			rts

ulcont:
			lda isStream
			beq Repeat
Stream:
			dec isStream // next block will be REPEAT
			jsr pullCNTbits
				lda Flags
				and #$04
				bne slcopy
sloop:
			jsr getAbyte
			jsr setAbyte

			lda bits
			bne n0
			lda bits+1
			beq unpackloop
			dec bits+1
n0:         dec bits
			jmp sloop

slcopy:
			lda bits
			sta licnt
			lda bits+1
			sta licnt+1

slloop:
				jsr pullLIbits
				ldy bits


			// pullLIbits
			// slcopyloop:
			// 		read byte from lookup table
			// counter decrement, bne slcopyloop
			// 
LUT:
				lda $FFFF,y
				jsr setAbyte

			lda licnt
			bne ln0
			lda licnt+1
			beq unpackloop
			dec licnt+1
ln0:        dec licnt
			jmp slloop


Repeat:

			//rts
			jsr pullbit
			lda #0
			adc #0
			sta isStream

			jsr pullDISTbits
			lda bout
			sec
			sbc bits
			sta tbin
			lda bout+1
			sbc bits+1
			sta tbin+1

			jsr pullCNTbits
			clc
			lda bits
			adc #mmchl
			sta bits
			lda bits+1
			adc #0
			sta bits+1
			ldy #0
			
				lda Flags
				and #$02
				beq r1

			jsr pullbit
			lda #0
			bcc r1
			eor #$ff

r1:        sta tmp
repeatloop:
			
			lda (tbin),y
			eor tmp
			sta (bout),y
			iny
			bne r0
			inc tbin+1
			inc bout+1
r0:        cpy bits
			bne repeatloop
			dec bits+1
			bpl repeatloop
			tya
			clc
			adc bout
			sta bout
			lda bout+1
			adc #0
			sta bout+1
			jmp unpackloop

			//---------------------------------------------------------------------
			// HELPER FUNCTIONS
// setupLInv:		// ugly to be optimized later
// 				sta tmp
// 				stx tmp+1
// 				ldx #2              // 3 bitet olvasunk
// 				jsr pullnbits
// 				ldy #0
// 				sta (tmp),y
// 				clc
// 				adc #2
// 				sta schk+1
// 				iny
// 				bne sloop1 	    // read 3 bits (inx)

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

getAbyte:   sty end+1        // save y
			ldy #0
			lda (pbin),y
			inc pbin
			bne end
			inc pbin+1
end:        ldy #0
			rts   

setAbyte:   sty sbend+1        // save y
			ldy #0
			sta (bout),y
			inc bout
			bne sbend
			inc bout+1
sbend:      ldy #0
			rts   

pullbit:
			sty p+1
			ldy bitbc
			bne next
			ldy #8
			jsr getAbyte
			sta BITBUFF
next:
			dey
			sty bitbc
p:          ldy #0
			rol BITBUFF
			rts
 
pullnbits:
			// x-ben a bitek szama
			stx end2+1        // save x
			tya
			pha
			lda #0
			sta bits
			sta bits+1
loop:       jsr pullbit
			rol bits
			rol bits+1
			dex
			bpl loop
			pla 
			tay
			lda bits
end2:       ldx #0
			rts

pullLIbits:
			lda #<LIbv
			ldx #>LIbv
			bne pulldatabits
pullCNTbits:                  // eredmeny bits-ben
			lda #<CNTbv
			ldx #>CNTbv
			bne pulldatabits
pullDISTbits:
			lda #<DISTbv
			ldx #>DISTbv
pulldatabits:
			sta tmp
			stx tmp+1            //tmp fog mutatni tablazatra
			ldy #0
			sty outbits
			sty outbits+1
			lda (tmp),y
			iny
			sta cnt              // max bitv         
			jmp pdloopin

pdloop:
			jsr pullbit
			bcs read

			lda exp,x
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




exp:        .byte <2, <4, <8, <16, <32, <64, <128, <256, <512, <1024, <2048, <4096, <8192, <16384, <32768
expH:       .byte >2, >4, >8, >16, >32, >64, >128, >256, >512, >1024, >2048, >4096, >8192, >16384, >32768

ENDa:       .word  0
//LUT: 		.word  0
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


.print "munpackerX length "+(exp-UNPACKX)+" Bytes"	   

packeddata:
.import binary "spiral.pkx"


.print "packeddata length "+(*-packeddata)+" Bytes"	   
