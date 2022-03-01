; this is where we define the ines header, this is not required for a real NES cartridge
; but you need this for an emulator for it to understand how to run your program correctly
.segment "HEADER"
.byte "NES" ; begining of iNES header
.byte $1a   ; signature of iNES header
.byte $02   ; 2 * 16KB PRG ROM
.byte $01   ; 1 * 8KB CHR ROM
.byte %00000000 ; mapper and mirroring (binary representation)
.byte $00
.byte $00
.byte $00
.byte $00
.byte $00, $00, $00, $00, $00 ; filler bytes

; location in memory that begins in memory offset zero and goes all the way to memory offset FF
.segment "ZEROPAGE"
background: .res 2 ; reserve 2 bytes in zeropage for background pointer variable

; where your code starts, defines where to define your code, and where your code lives in this file
.segment "STARTUP"
Reset: ; reset handler
	SEI ; disable all interrupts
	CLD ; disable decimal mode, the 6502 on the NES does not support this

	; Disable sound IRQ
	LDX #$40  ; load $40 into X the pound symbol means you are loading a value
	STX $4017 ; store X to the address $4017

	; Initialize the stack register
	LDX #$FF  ; load $FF into X because as you push data onto the stack it decrements the value
	TXS		  ; transfer X register to the stack register

	INX ; $FF + 1 = $00

	; Zero out the PPU registers
	STX $2000 ; Store value of X (0) into address 2000
	STX $2001 ; addresses 2000 and 2001 are PPU registers

	; disable PCM channel
	STX $4010

:
	; address $2002; PPUSTATUS, tells us if the PPU is currently drawing the screen
	; the BIT op-code tells us the value of bit 7 of $2002's returned byte if bit number
	; 7 is set to zero we are not currently waiting to draw the next screen if bit number 7
	; is one we have reached the period where we have drawn a full screen and we will continue on in the program
	BIT $2002
	; jump back to prev annonomous label if bit number 7 is set to zero (until the PPU is fully initialized, this takes around 30,000 CPU cycles)
	BPL :- 

	TXA ; transfer x register to a register

CLEARMEM:
	; the value of X will be stored in the first part before the comma resulting in the range $0000 -> $00FF 
	; so this will store A registers value in all those addresses, setting all those addresses values to 0
	STA $0000, X ; $0000 - > $00FF
	; as we can see that does not clear out all the memory so we will have to clear the rest out with the following
	STA $0100, X ; $0100 - > $01FF
	; Not clearing $0200 - > $02FF because we will store information about the sprite we will display on the screen in a range of memory
	; this area is picked for the sprite info for no particular reason, but it has to be initialized to something other than 0
	STA $0300, X ; $0300 - > $03FF
	STA $0400, X
	STA $0500, X
	STA $0600, X
	STA $0700, X

	LDA #$FF ; pound since we are loading it into A
	STA $0200, X ; %0200 - > $02FF sprite information will be initialized to $FF
	LDA #$00 ; load 0 back into A

	INX ; X + 1
	; BNE: Branch on Not Equal
	BNE CLEARMEM ; a little trick in assembly you can use the fact that FF rolls over to 0

; wait for vblank
:
	BIT $2002
	BPL :- 

	; this will be used to tell the PPU what range of memory the most signifigant byte starting with $02
	LDA #$02 ; load A with the value of $02 (address of our oam)
	STA $4014 ; OAMDMA register 
	NOP ; No Operation Burn a cycle, the PPU needs a moment to initiate a memory transfer from the range $0200 into its own memory

	LDA #$3F
	STA $2006 ; loading these values into the PPUADDR ($2006) tells the PPU that any following writes to PPUDATA ($2007) will be at $3F00
	LDA #$00
	STA $2006 ; the PPU now finds out we want to write to $3F00 which is the address of the first color of the first palette

	LDX #$00

; we will now write the palette data itself to the selected PPU memory address, write one byte of the data each incrementation
LoadPalettes:
	LDA PaletteData, X ; load A with address of PaletteData + X
	; address $2007 is the address of PPUDATA, we set the address of PPUDATA to $3F00 earlier buy setting PPUADDR($2006) to $3F00
	STA $2007 ; $3F00, %3F01, $3F02 ... $3F1F once we get to 3F1F it means we have updated all 32 bytes of memory for the pallete
	INX
	CPX #$20 ; compare X to $20
	BNE LoadPalettes ; loop until we have stored all palette data inside 2007

; Initialize world to point to world data
LDA #<BackgroundData ; Load a with the value of the low byte of WorldData ( '<' gets the low byte of a label)
STA background		; Store value of A in the world variable (occupy low byte of world)
LDA #>BackgroundData ; Load a with the value of the high byte of WorldData
STA background+1		; Store the high byte of WorldData in our world variable 
	                ; ( the +1 means store it to the address that world refrences but add one to the address; populate second byte of variable)
; World now store an address to WorldData

; setup address in PPU for nametable data
BIT $2002	; read from 2002, this resets PPU to know the next value you write to 2006 is the first byte of the address (BIT is fast that is why its used)
LDA #$20	; load high byte
STA $2006
LDA #$00	; load low byte
STA $2006	; set the PPUDATA to point to the address $2000

LDX #$00
LDY #$00

; we will now load the background into PPUDATA ($2000) one byte at a time
LoadBackground:
	; We have to loop until 960 (until whole background is loaded) so we will use 16-bit math
	; 960 in Hex is 03C0 so we need the X register to have a value of 03 and the Y register have a value of C0
	LDA (background), Y ; load a with world address + y
	STA $2007	   ; store in PPU memory
	INY
	CPX #$03
	BNE :+		   ; if x is not equal we do not have ot check Y so we branch (branch to unamed label ahead)
	CPY #$C0
	BEQ DoneLoadingBackground ; if X and Y have hit 960 (03C0) we are dont loading the world

: 
	CPY #$00	   ; if Y has rolled over (255 + 1 = 0)
	BNE LoadBackground
	INX			   ; keep track how many elements we have interated over (or how much times Y has rolled over)
	INC background+1	   ; get to next chunk of data we want to load into PPU high byte

	JMP LoadBackground

DoneLoadingBackground:
	LDX #$00

SetAttributes:
	LDA #$55	  ; point to palette we loaded previously into PPU
	STA $2007
	INX
	CPX #$40
	BNE SetAttributes

	LDX #$00
	LDY #$00

LoadSprites:
	LDA SpriteData, X
	STA $0200, X ; store the sprite data into the memory we have mentioned earlier we will use for it
	INX
	CPX #$20
	BNE LoadSprites 
 
; Enable Interupts
CLI ; Clear Interupt

; Bit 7 tells the PPU we want to be interupted when the VBlank is occuring through the NMI, so when and interupt occurs the CPU will bring us to NMI
; change background to use second chr set of tiles ($1000)
LDA #%10010000
STA $2000
; Enabling sprites and background for left-most 8 pixels
; Enabling sprites and background
LDA #%00011110
STA $2001

LDA #$12
STA $0200

LDA #$0

Loop:  ; loop forever
	JMP Loop

NMI:   ; non maskable interupt handler
	LDA #$02 ; copy sprite data from $0200 -> PPU memory for display
	STA $4014
	RTI ; return from interupt

PaletteData:
  .byte $22,$29,$1A,$0F,$22,$36,$17,$0f,$22,$30,$21,$0f,$22,$27,$17,$0F  ; background palette data
  .byte $22,$16,$27,$18,$22,$1A,$30,$27,$22,$16,$30,$27,$22,$0F,$36,$17  ; sprite palette data

BackgroundData:
	.incbin "world.bin"

SpriteData: ; OAM, Object Attribute Memory
   ; Y Offset, SpriteNum, Palette (here we use first palette), X Offset
  .byte $08, $00, $00, $08
  .byte $08, $01, $00, $10
  .byte $10, $02, $00, $08
  .byte $10, $03, $00, $10
  .byte $18, $04, $00, $08
  .byte $18, $05, $00, $10
  .byte $20, $06, $00, $08
  .byte $20, $07, $00, $10


; defines special addresses that the 6502 needs to operate
.segment "VECTORS"
	.word NMI	; define Non Maskable Interupt time between image on the screen and being refreshed again by electron gun
	.word Reset ; what happens when someone press's the reset button
	
; where we tell the assembler where to find the graphical data
.segment "CHARS"
	.incbin "hellomario.chr"
