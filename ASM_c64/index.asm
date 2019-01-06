;============================================================
; Depacker9o
; Code by Abel Vincze
; (c) 2017 http://iparigrafika.hu
;
;============================================================
; This is the index file which loads all code and resources
;============================================================

;------------------------------------------------------------
;                         START                             
;------------------------------------------------------------

!cpu 6502
!to "build/depacker9o.prg",cbm    ; output file

;============================================================
; resourcefiles like character sets, music or sprite shapes
; are usually explicitly loaded to a specific location in
; memory. The addresses and loading is handled here
;============================================================

;!source "code/config_resources.asm"

;============================================================
; a BASIC loader will help us RUN the intro when loaded
; into the C64 as opposed to manually type SYS49152
;============================================================

* = $0801                               ; BASIC start address (#2049)
!byte $0b,$08,$e1,$07,$9e	  			; BASIC loader to start at $c000...
!byte "2","0","6","1"
!byte $00,$00,$00         			    ; puts BASIC line 2017 SYS 2061


;============================================================
;  main routine with our custom interrupt
;============================================================
!source "code/main.asm"

;============================================================
; any data like strings of text or tables of information
;============================================================

*=$b00
!source "code/examplepackeddata.asm"
!source "code/exampleunpackeddata.asm"

;------------------------------------------------------------
;                         THE END                             
;------------------------------------------------------------








