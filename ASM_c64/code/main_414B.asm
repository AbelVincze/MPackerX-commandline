;!to "build/depacker9o.prg",cbm    ; output file

;===================================
; main.asm triggers all subroutines 
; and runs the Interrupt Routine
;===================================

           ; *=$80E

tbin        = $8E
pbin        = $90        ; packed binary input
bout        = $92        ; binary output
boend       = $94        ; last out byte +1 (to compare)
isStream    = $96
bitbc       = $97
BITBUFF     = $98
bits        = $9A
tmp         = $9C
cnt         = $9E
outbits     = $9F

main:
            sei
            lda #$3b
            sta $d011
            lda #$18
            sta $d018

            ;rts

            lda #$20
            ldy #$00
.clsloop:   sta $400,y      ;clear screen
            sta $500,y
            sta $600,y
            sta $6D0,y
            dey
            bne .clsloop

            lda #<packeddata
            ldx #>packeddata
            sta pbin
            stx pbin+1
            lda #<$2000
            ldx #>$2000
            sta bout
            stx bout+1

            jsr UNPACK9O        ; do unpack

            lda #<exp
            sec
            sbc #<UNPACK9O
            sta $07ff
            lda #>exp
            sbc #>UNPACK9O
            sta $07fe

            cli
            rts


UNPACK9O:   ; unpacking paker9o packages
      
            ; INIT unpack loop: isStream to true for starting
            lda #1
            sta isStream
            lda #0              ; inicializalas...
            sta bitbc

            jsr getAbyte        ; read first byte of the packed data
            sta dw              ; byte width
            tax
            jsr getAbyte        ; height
            sta h
            jsr getAbyte
            sta h+1

            lda #0              ; length = dw * h
            sta l
            sta l+1

.mloop:     lda l               ; calc length
            clc
            adc h
            sta l
            lda l+1
            adc h+1
            sta l+1
            dex
            bne .mloop      

            lda l               ; calc end address (+1)
            clc
            adc bout
            sta boend
            lda l+1
            adc bout+1
            sta boend+1

            ;restore CNTbitdepths
            ldx #2              ; 3 bitet olvasunk
            jsr pullnbits
            sta CNTbv
            tay
            iny
            sty .c0+1          ; counter
            ldy #0
            inx                 ; 4 bitet olvasunk
.mloop2:
            jsr pullnbits
            sta CNTbits,y
            iny
.c0:        cpy #0
            bne .mloop2

            ;restore DISTbitdepths
            ldx #2              ; 3 bitet olvasunk
            jsr pullnbits
            sta DISTbv
            tay
            iny
            sty .c1+1           ; counter
            ldy #0
            inx                 ; 4 bitet olvasunk
.mloop3:
            jsr pullnbits
            sta DISTbits,y
            iny
.c1:        cpy #0
            bne .mloop3


            ; UNPACK data ------------------------------------------------------------------
            ; unpack mainloop
unpackloop:

            ; is finished?
            lda bout
            cmp boend
            bne .ulcont
            lda bout+1
            cmp boend+1
            bne .ulcont
            rts

.ulcont:
            lda isStream
            beq .isRepeat
.isStream:
            dec isStream
            jsr pullCNTbits
.sloop:
            jsr getAbyte
            jsr setAbyte

            lda bits
            bne .n0
            lda bits+1
            beq unpackloop
            dec bits+1
.n0:        dec bits
            jmp .sloop

.isRepeat:

            ;rts
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
            adc #4
            sta bits
            lda bits+1
            adc #0
            sta bits+1

            ldy #0
            jsr pullbit
            lda #0
            bcc .r1
            eor #$ff
.r1:        sta tmp
.repeatloop:
            
            lda (tbin),y
            eor tmp
            sta (bout),y
            iny
            bne .r0
            inc tbin+1
            inc bout+1
.r0:        cpy bits
            bne .repeatloop
            dec bits+1
            bpl .repeatloop
            tya
            clc
            adc bout
            sta bout
            lda bout+1
            adc #0
            sta bout+1
            jmp unpackloop



getAbyte:   sty .end+1        ; save y
            ldy #0
            lda (pbin),y
            inc pbin
            bne .end
            inc pbin+1
.end:       ldy #0
            rts   

setAbyte:   sty .sbend+1        ; save y
            ldy #0
            sta (bout),y
            inc bout
            bne .sbend
            inc bout+1
.sbend:     ldy #0
            rts   

pullbit:
            sty .p+1
            ldy bitbc
            bne .next
            ldy #8
            jsr getAbyte
            sta BITBUFF
.next:
            dey
            sty bitbc
.p          ldy #0
            rol BITBUFF
            rts
 
pullnbits:
            ; x-ben a bitek szama
            stx .end2+1        ; save x
            tya
            pha
            lda #0
            sta bits
            sta bits+1
.loop:      jsr pullbit
            rol bits
            rol bits+1
            dex
            bpl .loop
            pla 
            tay
            lda bits
.end2:      ldx #0
            rts

pullCNTbits:                  ; eredmeny bits-ben
            lda #<CNTbv
            ldx #>CNTbv
            bne pulldatabits
pullDISTbits:
            lda #<DISTbv
            ldx #>DISTbv
pulldatabits:
            sta tmp
            stx tmp+1            ;tmp fog mutatni tablazatra
            ldy #0
            sty outbits
            sty outbits+1
            lda (tmp),y
            iny
            sta cnt              ; max bitv         
            jmp .pdloopin

.pdloop:
            jsr pullbit
            bcs .read

            lda exp,x
            clc
            adc outbits
            sta outbits
            lda expH,x
            adc outbits+1
            sta outbits+1

.pdloopin:
            lda (tmp),y
            iny
            tax
            dec cnt
            bpl .pdloop

.read
            jsr pullnbits
            lda outbits
            clc
            adc bits
            sta bits
            lda outbits+1
            adc bits+1
            sta bits+1

            rts



exp         !byte <2, <4, <8, <16, <32, <64, <128, <256, <512, <1024, <2048, <4096, <8192, <16384, <32768
expH        !byte >2, >4, >8, >16, >32, >64, >128, >256, >512, >1024, >2048, >4096, >8192, >16384, >32768

ENDa        !word  0
dw          !byte  0
h           !word  0
l           !word  0
CNTbv       !byte  0
CNTbits     !byte  0, 0, 0, 0, 0, 0, 0, 0
DISTbv      !byte  0
DISTbits    !byte  0, 0, 0, 0, 0, 0, 0, 0
           

