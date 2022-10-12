BasicUpstart2(main)

* = $0810

//.var unused = $FA           //
//.var unused = $FB           // 
.var screen_lsb = $FC         // screen address low .byte
.var screen_msb = $FD         // screen address high .byte
.var head_path_pointer_lsb = $FE   // head pointer low .byte
.var head_path_pointer_msb = $FF   // head pointer high .byte

.var bg_colour = $00    // background colour
.var brd_colour = $0b   // border colour
.var food_char = $3f    // character to be used for food.

main:
    lda #$FF  // maximum frequency value
    sta $D40E // voice 3 frequency low .byte
    sta $D40F // voice 3 frequency high .byte
    lda #$80  // noise waveform, gate bit off
    sta $D412 // voice 3 control register

    lda $d016           // set multicolour mode
    ora #%00010000
    sta $d016

    lda $D018           // set character memory to start from ram at $3000
    ora #$0c
    sta $d018

    lda #brd_colour     // set border colour
    sta $d020
    lda #bg_colour      // set background colour
    sta $d021
    lda #$04            // bg colour #1, stripes, start with magenta
    sta $d022
    lda #$0b            // bg colour #2, dark grey for shadow
    sta $d023

    jmp start_game

start_game:
    //  initiate variables
    lda #$00
    sta direction
    sta food_flag
    sta length_msb
    sta head_path_pointer_lsb

    lda #$01
    sta speed_setting

    lda #$0c
    sta head_path_pointer_msb

    lda #$0e
    sta snake_colour

    lda #$02
    sta length_lsb       // starting length

    lda #$09            //  default value for last key (to match default direction of up/$00)
    sta last_key

    // starting location in approximately screen centre
    lda #12             // $0C
    sta head_row
    lda #19             // $13
    sta head_column

    jsr clear_screen        // clear screen
    jsr spawn_food          // spawn initial piece of food

loop:
    jsr read_keyb           // read last keypress, ignore if invalid
    jsr step                // set direction, update head coordinate, reset if AOB
    jsr screen_address      // look up the screen address from coordinates
    jsr collision_check     // check if snake has collided with itself or food
    jsr draw                // draw the snake
    jsr spawn_food          // check if there is food, if not spawn one, if food has been eaten increment length
    jsr delay               // run the delay loop according to speed setting
    jmp loop

read_keyb:          // reads keyboard input
    ldx $c5         // read keyboard buffer
    lda direction   
    and #$00000001  // if direction is $01 or $03 then it's horizontal, AND gives 1 otherwise vertical, AND gives 0
    bne !horiz+
    // not horizontal so direction must be vertical
    txa
    cmp #$12
    beq update_key
    cmp #$0A
    beq update_key
    rts
!horiz:
    txa
    cmp #$09
    beq update_key
    cmp #$0D
    beq update_key
    rts
update_key:
    sta last_key
    rts


step:
    lda direction 
    sta prev_dir     // store the direction from the previous loop
    lda last_key
    cmp #$09  // 'w' = up
    beq !up+
    cmp #$12  // 'd' = right
    beq !right+
    cmp #$0D  // 's' = down
    beq !down+
    cmp #$0A  // 'a' = left
    beq !left+
    rts
!up:
    lda #$00
    sta direction
    dec head_row // decrement row
    lda head_row
    bmi reset
    rts
!right:
    lda #$01
    sta direction
    inc head_column // increment column
    lda head_column
    cmp #40
    beq reset
    rts
!down:
    lda #$02
    sta direction
    inc head_row // increment row
    lda head_row
    cmp #25
    beq reset
    rts
!left:
    lda #$03
    sta direction
    dec head_column // decrement column
    lda head_column
    bmi reset
    rts

reset:
    tsx
    inx
    inx
    txs
    jmp main

screen_address:                   // uses head_row and head_column value to set screen_lsb and screen_msb
    ldy head_row                  // to point at the screen location
    lda screen_table, y
    clc
    adc head_column
    sta screen_lsb
    lda screen_table +25, y
    adc #$00
    sta screen_msb
    rts

collision_check:
    ldy #$00
    lda (screen_lsb),y          // load head position in screen ram
    cmp #food_char              // check if that has food character
    beq fed
    cmp #$00                    // check for 'space' character
    bne reset
    rts
fed:
    lda #$00
    sta food_flag       // set food flag to 00 (no food)
    clc
    lda length_lsb      // add 1 to the length 
    adc #$01
    sta length_lsb
    lda length_msb
    adc #$00
    sta length_msb
    lda $d41b           // get random number
    and #%00000001      // check if odd or even
    beq stripes
    lda food_colour
    sta snake_colour    // change colour of snake (foreground)
    rts
stripes:                // change colour of stripes (background #1)
    lda food_colour
    and #%00000111      // can only be colours 0-8 because of multicolor mode
    sta $d022
    rts

draw:
    // draw head
    lda #$48                    // head character
    clc
    adc direction
    ldy #$00
    sta (screen_lsb),y

    lda screen_msb
    pha
    adc #$d4                    // move msb up to address colour ram
    sta screen_msb
    lda snake_colour
    sta (screen_lsb),y
    pla
    sta screen_msb

    // add this new head screen location and direction to the path
    lda screen_lsb
    sta (head_path_pointer_lsb), y

    lda head_path_pointer_msb
    pha                         // temporarily push the head pointer to the stack

    clc
    adc #$04                    // add 1024 ($0400) to point at the path msb
    sta head_path_pointer_msb
    lda screen_msb
    sta (head_path_pointer_lsb),y

    lda head_path_pointer_msb
    clc
    adc #$04                    // add another 1024 ($0400) to point at the path direction
    sta head_path_pointer_msb
    lda direction
    sta (head_path_pointer_lsb),y
    
    pla                         // retrieve head pointer from the stack
    sta head_path_pointer_msb

    // redraw body behind head
    lda #$01                    // load the path_offset with a vlaue one 1 for the space behind the head.
    sta path_offset + 0
    lda #$00
    sta path_offset + 1

    jsr path_lookup                // look up the screen location behind the head from the path
    jsr body_char                  // look up what character to draw based on the previous direction, puts in 'a' reg
    ldy #$00
    sta (screen_lsb),y

    // draw the tail
    sec
    lda length_lsb                 // subtract 1 from the length to find the tail space 
    sbc #$01
    sta path_offset + 0
    lda length_msb
    sbc #$00
    sta path_offset + 1

    jsr path_lookup
    lda #$4c                        // tail character
    clc
    adc tail_direction
    ldy #$00
    sta (screen_lsb),y    

    // remove the old tail (overwrite with a blank space)
    lda length_lsb
    sta path_offset + 0
    lda length_msb
    sta path_offset + 1

    jsr path_lookup
    ldy #$00
    lda #$00
    sta (screen_lsb),y

    lda food_flag       
    and #%00000001      // check if bit 0 is set (there is no food so the snake must have eaten this loop)
    bne !+              // 
    ora #%00000010      // if this is true then set the 1 bit to indicate.
    sta food_flag       // 

    // increment head_pointer
!:  clc
    lda head_path_pointer_lsb
    adc #$01
    sta head_path_pointer_lsb
    lda head_path_pointer_msb
    adc #$00
    sta head_path_pointer_msb
    cmp #$10                    // check if the path pointer should be wrapped back around.
    beq !+
    rts
!:  lda #$0c
    sta head_path_pointer_msb
    rts

    // looks up the screen location from the path_offset and places
    // it in the screen_msb / lsb locations
    // takes care of wrapping around when decrementing the head_pointer
    // to stay within the valid memory space.
    // restores the head_pointer afterwards.
path_lookup:
    lda head_path_pointer_msb        // backup head pointer to stack
    pha
    lda head_path_pointer_lsb
    pha

    sec                         // subtract the path_offset
    sbc path_offset + 0
    sta head_path_pointer_lsb
    lda head_path_pointer_msb
    sbc path_offset + 1
    sta head_path_pointer_msb
    cmp #$0c                    // check if this falls out the bottom of the path space
    bcs !+                      // and if so wrap around.
    adc #$04
    sta head_path_pointer_msb

!:  ldy #$00                    // retrieve the screen location from the path
    lda (head_path_pointer_lsb), y
    sta screen_lsb
    clc
    lda head_path_pointer_msb
    adc #$04
    sta head_path_pointer_msb
    lda (head_path_pointer_lsb), y
    sta screen_msb
    clc
    ldy #$01
    lda head_path_pointer_msb
    adc #$04
    sta head_path_pointer_msb
    lda (head_path_pointer_lsb), y
    sta tail_direction
        
    pla
    sta head_path_pointer_lsb        // restore head pointer from stack
    pla
    sta head_path_pointer_msb
    rts

spawn_food:              // spawns a food in a random location
    lda food_flag        // load food flag
    and #%00000001       // check if the zero bit is set
    bne !skip+           // if so, there is already food, skip spawning.

    //temporarily backup the snakes head row to the stack so the screen_row_address routine can be used again
    lda head_row
    pha
    lda head_column
    pha
    
rand_row:
    lda $D41B           // get random 8 bit (0 - 255) number from SID
    and #%00011111      // mask to 5 bit (0-31)
    cmp #3              // lower bound
    bmi rand_row
    cmp #24             // upper bound  compare to see if is in range
    bcs rand_row        // if the number is too large, try again
    sta head_row
rand_col:               // generate a random number between 0-39 for column
    lda $D41B           // get random 8 bit (0 - 255) number from SID
    and #$00111111      // mask to 6 bit (0 - 63)
    cmp #03             // lower bound
    bmi rand_col
    cmp #37             // upper bound  compare to see if is in range
    bcs rand_col        // if the number is too large, try again
    sta head_column
    jsr screen_address
    ldy #$00           
    lda (screen_lsb),y  // load screen position
    cmp #$00            // see if it's a suitably blank location
    bne rand_row        // if it's not blank try again!!

!:  lda $D41B           // get random number from sid
    and #%00000111
    cmp #bg_colour      // check this isn't the same as the background colour
    beq !-              // if it is, try again
    ora #%00001000      // set multicolour mode
    sta food_colour
    lda screen_msb      // backup msb to stack
    pha
    clc
    adc #$d4            // to address color ram
    sta screen_msb
    lda food_colour
    sta (screen_lsb),y
    pla
    sta screen_msb      // restore msb

    lda #food_char      // food character
    sta (screen_lsb),y  // spawn food
    lda food_flag       // load food flag
    ora #%00000001      // set bit 0 to 1 (there is a food on the board)
    sta food_flag       
    pla
    sta head_column     // put the head column back
    pla
    sta head_row        // put the head row back
!skip:
    rts
  
body_char:              // works out which body character needs to be drawn, puts it in the 'a' register.
    lda direction
    cmp prev_dir
    bne !corner+        // if the previous direction was different proceed to corner logic
    lda food_flag
    and #%00000010      // check if the 1 bit is set (snake has fed on prev loop)
    bne !fat_body+
    lda #$40            // body character
    clc
    adc prev_dir
    rts
!fat_body:
    lda food_flag
    and #%00000001      // reset the 1 bit
    sta food_flag
    lda #$50            // use the fat body character
    clc
    adc prev_dir 
    rts
!corner:  cmp #$00
    beq !up+
    cmp #$01
    beq !right+
    cmp #$02
    beq !down+
    lda prev_dir
    cmp #$00
    bne !+
    lda #$45            // ne_corner character
    rts
!:  lda #$46            // se_corner character
    rts
!up:
    lda prev_dir
    cmp #$01
    bne !+
    lda #$46            // se_corner character
    rts
!:  lda #$47            // sw_corner character
    rts
!right:
    lda prev_dir
    cmp #$00
    bne !+  
    lda #$44            // nw_corner character
    rts
!:  lda #$47            // sw_corner character
    rts
!down:
    lda prev_dir
    cmp #$01
    bne !+
    lda #$45            // ne_corner character
    rts
!:  lda #$44           // nw_corner character
    rts

delay:
    txa                 // backup x
    pha
    tya                 // backup y
    pha
    ldx #$FF
    lda speed_setting   // load speed setting
    cmp #$01
    beq med_speed
    bcs high_speed
    ldy #$55
delay_loop:
    dex
    bne delay_loop
    dey
    bne delay_loop
    pla
    tay                 // restore y
    pla
    tax                 // restore x
    rts
med_speed:
    ldy #$3a
    jmp delay_loop
high_speed:
    ldy #$20
    jmp delay_loop


clear_screen:   // fill screen with space characters $0400 - $07FF
    ldx #$00
    lda #$00    // space character
cls_loop:
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    dex
    bne cls_loop
    rts

last_key:           .byte 0      // last key pressed
food_flag:          .byte 0      // 1 if there is food currently on the board otherwise 0
direction:          .byte 0
prev_dir:           .byte 0
head_row:           .byte 0      // y-coordinate, zero being top
head_column:        .byte 0      // x-coordinate, zero being left
length_lsb:         .byte 0      // snake length low .byte
length_msb:         .byte 0      // snake length high .byte
path_offset:        .word $0000  // 16 bit offset to be applied when looking up screen locations from the path.
tail_direction:     .byte 0
snake_colour:       .byte 0
food_colour:        .byte 0
speed_setting:      .byte 0

screen_table:   .lohifill 25, $0400 + [i * 40]     // table of the memory locations for the first column in each row

* = $0c00                   // locations for 'path' (history of previous screen locations)
path_lo:  .fill 1024, 0     // screen location low bytes
path_hi:  .fill 1024, 0     // screen location high bytes
path_dir: .fill 1024, 0     // directions (needed to draw correct tail)

*=$3000
    .byte	$00, $00, $00, $00, $00, $00, $00, $00          // space
	.byte	$18, $3C, $66, $7E, $66, $66, $66, $00          //A
	.byte	$7C, $66, $66, $7C, $66, $66, $7C, $00          //B
	.byte	$3C, $66, $60, $60, $60, $66, $3C, $00          //C
	.byte	$78, $6C, $66, $66, $66, $6C, $78, $00          //D
	.byte	$7E, $60, $60, $78, $60, $60, $7E, $00          //E
	.byte	$7E, $60, $60, $78, $60, $60, $60, $00          //F
	.byte	$3C, $66, $60, $6E, $66, $66, $3C, $00          //G
	.byte	$66, $66, $66, $7E, $66, $66, $66, $00          //H
	.byte	$3C, $18, $18, $18, $18, $18, $3C, $00          //I
	.byte	$1E, $0C, $0C, $0C, $0C, $6C, $38, $00          //J
	.byte	$66, $6C, $78, $70, $78, $6C, $66, $00          //K
	.byte	$60, $60, $60, $60, $60, $60, $7E, $00          //L
	.byte	$63, $77, $7F, $6B, $63, $63, $63, $00          //M
	.byte	$66, $76, $7E, $7E, $6E, $66, $66, $00          //N
	.byte	$3C, $66, $66, $66, $66, $66, $3C, $00          //O
	.byte	$7C, $66, $66, $7C, $60, $60, $60, $00          //P
	.byte	$3C, $66, $66, $66, $66, $3C, $0E, $00          //Q
	.byte	$7C, $66, $66, $7C, $78, $6C, $66, $00          //R
	.byte	$3C, $66, $60, $3C, $06, $66, $3C, $00          //S
	.byte	$7E, $18, $18, $18, $18, $18, $18, $00          //T
	.byte	$66, $66, $66, $66, $66, $66, $3C, $00          //U
	.byte	$66, $66, $66, $66, $66, $3C, $18, $00          //V
	.byte	$63, $63, $63, $6B, $7F, $77, $63, $00          //W
	.byte	$66, $66, $3C, $18, $3C, $66, $66, $00          //X
	.byte	$66, $66, $66, $3C, $18, $18, $18, $00          //Y
	.byte	$7E, $06, $0C, $18, $30, $60, $7E, $00          //Z
	.byte	$66, $66, $FF, $66, $FF, $66, $66, $00          //#
	.byte	$00, $00, $7E, $00, $7E, $00, $00, $00          //=
	.byte	$00, $00, $00, $00, $00, $18, $18, $00          //.
	.byte	$FF, $FF, $FF, $00, $00, $00, $00, $00          // bar across top
	.byte	$00, $00, $00, $00, $00, $FF, $FF, $FF          // bar across bottom
	.byte	$07, $07, $07, $07, $07, $07, $07, $07          // bar on right
	.byte	$E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0          // bar on left
	.byte	$E7, $E7, $E7, $E7, $E7, $E7, $E7, $E7          // bar both sides vertical
	.byte	$FF, $FF, $FF, $00, $00, $FF, $FF, $FF          // bar both sides horizontal
	.byte	$07, $07, $07, $00, $00, $E7, $E7, $E7          // inside corner, lower right
	.byte	$E0, $E0, $E0, $00, $00, $E7, $E7, $E7          // inside corner, lower left
	.byte	$E7, $E7, $E7, $00, $00, $00, $00, $00          // bar cross top with central divide
	.byte	$00, $00, $00, $00, $00, $07, $07, $07          // lower right outside corner
	.byte	$00, $00, $00, $00, $00, $E0, $E0, $E0          // lower left outside corner
	.byte	$07, $07, $07, $00, $00, $00, $00, $00          // upper right outside corner
	.byte	$E0, $E0, $E0, $00, $00, $00, $00, $00          // upper left outside corner
	.byte	$9C, $9C, $9C, $94, $80, $88, $9C, $FF          // inverted W
	.byte	$E7, $C3, $99, $81, $99, $99, $99, $FF          // inverted A
	.byte	$C3, $99, $9F, $C3, $F9, $99, $C3, $FF          // inverted S
	.byte	$87, $93, $99, $99, $99, $93, $87, $FF          // inverted D
	.byte	$00, $00, $00, $00, $00, $00, $00, $00          
	.byte	$3C, $66, $6E, $76, $66, $66, $3C, $00          // 0
	.byte	$18, $18, $38, $18, $18, $18, $7E, $00          // 1
	.byte	$3C, $66, $06, $0C, $30, $60, $7E, $00          // 2
	.byte	$3C, $66, $06, $1C, $06, $66, $3C, $00          // 3
	.byte	$06, $0E, $1E, $66, $7F, $06, $06, $00          // 4
	.byte	$7E, $60, $7C, $06, $06, $66, $3C, $00          // 5
	.byte	$3C, $66, $60, $7C, $66, $66, $3C, $00          // 6
	.byte	$7E, $66, $0C, $18, $18, $18, $18, $00          // 7
	.byte	$3C, $66, $66, $3C, $66, $66, $3C, $00          // 8
	.byte	$3C, $66, $66, $3E, $06, $66, $3C, $00          // 9
	.byte	$00, $00, $00, $00, $00, $00, $00, $00          
	.byte	$00, $00, $00, $00, $00, $00, $00, $00
	.byte	$00, $00, $00, $00, $00, $00, $00, $00
	.byte	$00, $00, $00, $00, $00, $00, $00, $00
	.byte	$00, $00, $00, $00, $00, $00, $00, $00
	.byte	$3C, $B7, $F7, $FF, $FF, $BF, $BC, $28          // food
	.byte	$B4, $B4, $94, $94, $9C, $9C, $BC, $BC          // body up
	.byte	$00, $00, $D7, $D7, $F5, $F5, $AA, $AA          // body right
	.byte	$BC, $BC, $B4, $B4, $94, $94, $9C, $9C          // body down
	.byte	$00, $00, $5F, $5F, $D7, $D7, $AA, $AA          // body left
	.byte	$00, $00, $03, $07, $17, $35, $3D, $BE          // corner lower left
	.byte	$00, $00, $C0, $D0, $D0, $D4, $DC, $BC          // corner lower right
	.byte	$BC, $FC, $5C, $D4, $D4, $D0, $80, $00          // corner upper left
	.byte	$BC, $9F, $9F, $97, $97, $A7, $2A, $0A          // corner upper right
	.byte	$34, $34, $94, $D7, $9E, $5F, $BC, $BC          // head up
	.byte	$10, $AC, $D7, $D7, $F5, $F5, $AC, $B0          // head right
	.byte	$BC, $BE, $F5, $B6, $D7, $94, $9C, $1C          // head down
	.byte	$0C, $3A, $5F, $5F, $D7, $D7, $BA, $26          // head left
	.byte	$B4, $B4, $94, $94, $90, $90, $B0, $20          // tail up
	.byte	$00, $00, $DF, $97, $25, $09, $02, $00          // tail right
	.byte	$0C, $0C, $24, $24, $14, $94, $9C, $9C          // tail down
	.byte	$00, $00, $40, $50, $DC, $D7, $A8, $00          // tail left
    .byte	$B4, $B4, $D7, $D7, $5F, $5F, $BC, $BC          // fat body up
	.byte	$00, $1C, $D7, $D7, $F5, $F5, $BE, $AA          // fat body right
	.byte	$BC, $BC, $F5, $F5, $D7, $D7, $9C, $9C          // fat body down
	.byte	$00, $3C, $5F, $5F, $D7, $D7, $B6, $AA          // fat body left
