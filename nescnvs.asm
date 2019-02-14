;; 16 byte iNES header specifies ROM info
  .inesprg 1            ; 1x 16KB PRG code
  .ineschr 1            ; 1X 8KB CHR data
  .inesmap 0            ; mapper 0 = NROM, no bank swapping
  .inesmir 1            ; background mirroring

;; Register interrupts
  .bank 1
  .org $FFFA            ; first of 3 special addresses starts here
  .dw MAINLOOP          ; jmp to NMI label on NMI interrupt
  .dw RESET             ; jmp to RESET label if startup or hw reset
  .dw 0                 ; ignore audio

;; Vars
  .rsset $0000          ; Start vars at ram location 0
;playerx           .rs 1 ; Xpos for player
;playery           .rs 1 ; Ypos for player
; TODO: Add vars here
logox      .rs 1
logoy      .rs 1

;; Reset
  .bank 0               ; NESASM arranges things into 8KB chunks, this is chunk 0
  .org $C000            ; Tells the assembler where to start in this 8kb chunk
RESET:
  SEI                   ; disable IRQs
  CLD                   ; disable decimal mode, meant to make decimal arithmetic "easier"
  LDX #$40
  STX $4017             ; disable APU frame IRQ
  LDX #$FF
  TXS                   ; Set up stack
  INX                   ; now X = 0
  STX $2000             ; disable NMI
  STX $2001             ; disable rendering
  STX $4010             ; disable DMC IRQs

vblankwait1:            ; First wait for vblank to make sure PPU is ready
  BIT $2002
  BPL vblankwait1

;; Helper to wipe memory
clrmem:
  LDA #$00
  STA $0000, x
  STA $0100, x
  STA $0300, x
  STA $0400, x
  STA $0500, x
  STA $0600, x
  STA $0700, x
  LDA #$FE
  STA $0200, x          ; move all sprites off screen
  INX
  BNE clrmem
   
vblankwait2:            ; Second wait for vblank, PPU is ready after this
  BIT $2002
  BPL vblankwait2

;  PPUCTRL ($2000)
;  76543210
;  | ||||||
;  | ||||++- Base nametable address
;  | ||||    (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
;  | |||+--- VRAM address increment per CPU read/write of PPUDATA
;  | |||     (0: increment by 1, going across; 1: increment by 32, going down)
;  | ||+---- Sprite pattern table address for 8x8 sprites (0: $0000; 1: $1000)
;  | |+----- Background pattern table address (0: $0000; 1: $1000)
;  | +------ Sprite size (0: 8x8; 1: 8x16)
;  |
;  +-------- Generate an NMI at the start of the
;            vertical blanking interval vblank (0: off; 1: on)              
  LDA #%10010000   ; enable NMI, sprites from Pattern Table 0, background from Pattern Table 1
  STA $2000

;  PPUMASK ($2001)
;  binary byte flags
;  76543210
;  ||||||||
;  |||||||+- Grayscale (0: normal color; 1: AND all palette entries
;  |||||||   with 0x30, effectively producing a monochrome display;
;  |||||||   note that colour emphasis STILL works when this is on!)
;  ||||||+-- Disable background clipping in leftmost 8 pixels of screen
;  |||||+--- Disable sprite clipping in leftmost 8 pixels of screen
;  ||||+---- Enable background rendering
;  |||+----- Enable sprite rendering
;  ||+------ Intensify reds (and darken other colors)
;  |+------- Intensify greens (and darken other colors)
;  +-------- Intensify blues (and darken other colors)
  LDA #%00011110   ; enable sprites, enable background, no clipping on left side
  STA $2001

;;;;;;;;;;;;;;;;;;;;;;
; Load game pallets
LoadPalettes:
  LDA $2002             ; read PPU status to reset the high/low latch
  LDA #$3F              ; max out 0011 1111
  STA $2006             ; write the high byte of $3F00 address
  LDA #$00
  STA $2006             ; write the low byte of $3F00 address
  LDX #$00              ; start out at 0
LoadPalettesLoop:
  LDA PaletteData, x    ; load data from address (palette + the value in x)
                          ; 1st time through loop it will load palette+0
                          ; 2nd time through loop it will load palette+1
                          ; 3rd time through loop it will load palette+2
                          ; etc
  STA $2007             ; write to PPU
  INX                   ; X = X + 1
  CPX #$20              ; Compare X to hex $20
  BNE LoadPalettesLoop  ; Branch to LoadPalettesLoop if compare was Not Equal to zero

;; END BOILERPLATE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InitializeState:
  LDA #$80
  STA logox
  STA logoy

;; Start forever loop. Interrrupted by NMI
Forever:
  JMP Forever

;; Main loop
MAINLOOP:
  ;; Load graphics into PPU from memory
  ;; Needs to be done every frame
  LDA #$00
  STA $2003
  LDA #$02
  STA $4014

  ;; Run draw logic first
  JSR Draw
  ;; Then run update logic
  JSR Update
  ;; Return from interrupt
  RTI

;; Main draw routine
Draw:
	JSR DrawLogo
	RTS

;  ;; Tile 0
;  LDA #$80
;  STA $0200
;  STA $0203
;  LDA #$41
;  STA $0201
;  LDA #$10
;  STA $0202

DrawLogo:
  LDX #$00
DrawLogoLoop:
  LDA logosprite, x
  STA $0200, x
  INX
  CPX #$0B
  BNE DrawLogoLoop

  RTS

;; Main update routine
Update:
RTS

;; Pallet and sprite data defs
  .bank 1
  .org $E000
PaletteData:
  ;; Background Pallets (0-3)
  ;; Random pallets that I just took from YY-CHR
  .db $0F,$30,$26,$05, $0F,$13,$23,$33, $0F,$1C,$2B,$39, $0F,$06,$15,$36
  ;; Character Palletes (0-3)
  .db $0F,$30,$26,$05, $0F,$13,$23,$33, $0F,$1C,$2B,$39, $0F,$06,$15,$36

logosprite:
; 1st byte encodes the y position
; 2nd byte encodes the tile index loaded into the PPU 
; 3rd byte encodes any sprite attributes
;  76543210
;  |||   ||
;  |||   ++- Color Palette of sprite.  Choose which set of 4 from the 16 colors to use
;  |||
;  ||+------ Priority (0: in front of background; 1: behind background)
;  |+------- Flip sprite horizontally
;  +-------- Flip sprite vertically
; 4th byte encodes the x position

;; Logo is 6x6 sprites, 36 total

     ;vert tile attr horiz
  .db $80, $00, $00, $80
  .db $80, $01, $00, $88
  .db $80, $02, $00, $90
  .db $80, $03, $00, $98
  .db $80, $04, $00, $A0
  .db $80, $05, $00, $A8

  .db $88, $10, $00, $80
  .db $88, $11, $00, $88
  .db $88, $12, $00, $90
  .db $88, $13, $00, $98
  .db $88, $14, $00, $A0
  .db $88, $15, $00, $A8

;;; BANK 2 AND OUR PICTURE DATA
  ;; Bank 2 will be starting at $0000 and in it we will include our picture data for backgrounds and sprites
  .bank 2                       ; Change to bank 2
  .org $0000                    ; start at $0000
  .incbin "cnvs.chr"           ; INClude BINary


