; *************************************************************************
;
;       Mindy Minimal Interpreter for the z80 
;
;       Ken Boak, John Hardy and craig Jones. 
;
;       GNU GENERAL PUBLIc LIcENSE                   Version 3, 29 June 2007
;
;       see the LIcENSE file in this repo for more information 
;
; *****************************************************************************
    FALSE       EQU 0
    TRUE        EQU -1	
    UNLIMITED   EQU -2		; for endless loops

    cTRL_C      equ 3       ; end of text
    cTRL_E      equ 5       ; edit
    cTRL_H      equ 8       ; backspace
    cTRL_J      equ 10      ; re-edit
    cTRL_L      equ 12      ; list
    cTRL_P      equ 16      ; print stack

    BSLASH      equ $5c

.macro LITDAT,len
    db len
.endm

.macro REPDAT,len,data			; compress the command tables
    
    db (len | $80)
    db data
.endm

.macro ENDDAT
    db 0
.endm

; **************************************************************************
; Page 0  Initialisation
; **************************************************************************		

	.ORG ROMSTART + $180		; 0+180 put Mindy code from here	

; **************************************************************************
; Macros must be written in Mindy and end with ; 
; this code must not span pages
; **************************************************************************
macros:

reedit_:
    db "/z/UE;"			; remembers last line edited

edit_:
    .cstr "`?`/K/UP/UE;"

list_:
    ; .cstr "/N26(/i65+/UE/k0>(/N))/UP;"

printStack_:
    .cstr "/US/UP;"        

iOpcodes:
    LITDAT 15
    db    lsb(bang_)        ;    !            
    db    lsb(dquote_)      ;    "
    db    lsb(hash_)        ;    #
    db    lsb(dollar_)      ;    $            
    db    lsb(percent_)     ;    %            
    db    lsb(amper_)       ;    &
    db    lsb(quote_)       ;    '
    db    lsb(lparen_)      ;    (        
    db    lsb(rparen_)      ;    )
    db    lsb(star_)        ;    *            
    db    lsb(plus_)        ;    +
    db    lsb(comma_)       ;    ,            
    db    lsb(minus_)       ;    -
    db    lsb(dot_)         ;    .
    db    lsb(slash_)       ;    /	;/MOD

    REPDAT 10, lsb(num_)		; 10 x repeat lsb of add to the num routine 

    LITDAT 7
    db    lsb(colon_)       ;    :        
    db    lsb(semi_)        ;    ;
    db    lsb(lt_)          ;    <
    db    lsb(eq_)          ;    =            
    db    lsb(gt_)          ;    >            
    db    lsb(question_)    ;    ?   ( -- val )  read a char from input
    db    lsb(at_)          ;    @    

    REPDAT 26, lsb(call_)	; call a command A, B ....z

    LITDAT 6
    db    lsb(lbrack_)      ;    [
    db    lsb(bslash_)      ;    \
    db    lsb(rbrack_)      ;    ]
    db    lsb(caret_)       ;    ^
    db    lsb(underscore_)  ;    _   
    db    lsb(grave_)       ;    `   ; for printing `hello`        

    REPDAT 26, lsb(var_)	; a b c .....z

    LITDAT 4
    db    lsb(lbrace_)      ;    {
    db    lsb(pipe_)        ;    |            
    db    lsb(rbrace_)      ;    }            
    db    lsb(tilde_)       ;    ~ ( a b c -- b c a ) rotate            

iAltcodes:
    LITDAT 24
    db     lsb(aNop_)       ;A
    db     lsb(bmode_)      ;B      toggle byte mode
    db     lsb(aNop_)       ;C
    db     lsb(aNop_)       ;D      
    db     lsb(emit_)       ;E      emit a char
    db     lsb(aNop_)       ;F      false
    db     lsb(go_)         ;G      execute Mindy code
    db     lsb(aNop_)       ;H      toggle hex mode
    db     lsb(inPort_)     ;I      input from port
    db     lsb(aNop_)       ;J      loop variable    
    db     lsb(key_)        ;K      input char
    db     lsb(shl_)        ;L
    db     lsb(aNop_)       ;M
    db     lsb(newln_)      ;N      prints a newline to output
    db     lsb(outPort_)    ;O      output to port
    db     lsb(aNop_)       ;P      print Mindy prompt
    db     lsb(aNop_)       ;Q
    db     lsb(shr_)        ;R
    db     lsb(arrSize_)    ;S      array size
    db     lsb(aNop_)       ;T      true
    db     lsb(utility_)    ;U      
    db     lsb(aNop_)       ;V      
    db     lsb(while_)      ;W      word mode 
    db     lsb(exec_)       ;X      execute machine code 
    
    REPDAT 3, lsb(aNop_)
                            ;Y
                            ;Z

    ENDDAT 

backSpace:
    ld a,c
    or b
    jr z, interpret2
    dec bc
    call printStr
    .cstr "\b \b"
    jr interpret2
    
start:
    ld SP,DSTACK		; start of Mindy
    call init		    ; setups
    call printStr		; prog count to stack, put code line 235 on stack then call print
    .cstr "Mindy 0.1\r\n"

interpret:
    call prompt

    ld bc,0                 ; load bc with offset into TIb, decide char into tib or execute or control         
    ld (vTIBPtr),bc

interpret2:                     ; calc nesting (a macro might have changed it)
    ld e,0                  ; initilize nesting value
    push bc                 ; save offset into TIb, 
                            ; bc is also the count of chars in TIB
    ld hl,TIB               ; hl is start of TIB
    jr interpret4

interpret3:
    ld a,(hl)               ; A = char in TIB
    inc hl                  ; inc pointer into TIB
    dec bc                  ; dec count of chars in TIB
    call nesting            ; update nesting value

interpret4:
    ld a,c                  ; is count zero?
    or B
    jr nz, interpret3       ; if not loop
    pop bc                  ; restore offset into TIB

waitchar:   
    call getchar            ; loop around waiting for character from serial port
    cp $20			; compare to space
    jr nc,waitchar1		; if >= space, if below 20 set cary flag
    cp $0                   ; is it end of string? null end of string
    jr z,waitchar4
    cp '\r'                 ; carriage return? ascii 13
    jr z,waitchar3		; if anything else its macro/control 
    cp cTRL_H
    jr z,backSpace
    ld d,msb(macros)
    cp cTRL_E
    ld e,lsb(edit_)
    jr z,macro
    cp cTRL_J
    ld e,lsb(reedit_)
    jr z,macro
    cp cTRL_L
    ld e,lsb(list_)
    jr z,macro
    cp cTRL_P
    ld e,lsb(printStack_)
    jr z,macro
    jr interpret2

macro:                          
    ld (vTIBPtr),bc
    push de
    call ENTER		;Mindy go operation and jump to it
    .cstr "/G"
    ld bc,(vTIBPtr)
    jr interpret2

waitchar1:
    ld hl,TIB
    add hl,bc
    ld (hl),A               ; store the character in textbuf
    inc bc
    call putchar            ; echo character to screen
    call nesting
    jr  waitchar            ; wait for next character

waitchar3:
    ld hl,TIB
    add hl,bc
    ld (hl),"\r"            ; store the crlf in textbuf
    inc hl
    ld (hl),"\n"            
    inc hl                  ; ????
    inc bc
    inc bc
    call crlf               ; echo character to screen
    ld a,E                  ; if zero nesting append and ETX after \r
    or A
    jr nz,waitchar
    ld (hl),$03             ; store end of text ETX in text buffer 
    inc bc

waitchar4:    
    ld (vTIBPtr),bc
    ld bc,TIB               ; Instructions stored on heap at address HERe, we pressed enter
    dec bc

next:                           ;      
    inc bc                      ;       Increment the IP
    ld a, (bc)                  ;       Get the next character and dispatch
    or a                        ; is it NUL?       
    jr z,exit
    cp cTRL_c
    jr z,etx
    sub "!"
    jr c,NexT
    ld L,A                      ;       Index into table
    ld H,msb(opcodes)           ;       Start address of jump table         
    ld L,(hl)                   ;       get low jump address
    ld H,msb(page4)             ;       Load H with the 1st page address
    jp (hl)                     ;       Jump to routine

exit:
    inc bc			; store offests into a table of bytes, smaller
    ld de,bc                
    call rpop               ; Restore Instruction pointer
    ld bc,hl
    ex de,hl
    jp (hl)

etx:                                
    ld hl,-DSTACK               ; check if stack pointer is underwater
    add hl,SP
    jr nc,etx1
    ld SP,DSTACK
etx1:
    jp interpret

init:                           
    ld ix,RSTACK
    ld iy,NexT		            ; iy provides a faster jump to NexT

    ld hl,altVars               ; init altVars to 0 
    ld b,26 * 2
init1:
    ld (hl),0
    inc hl
    djnz init1
    ld hl,TRUE                  ; hl = TRUE
    ld (vTrue),hl
    dec hl                      ; hl = Unlimited
    ld (vUnlimited),hl
    ld hl,DSTACK
    ld (vS0),hl
    ld hl,65
    ld (vLastDef),hl
    ld hl,hEAP
    ld (vHeapPtr),hl
    ld hl,VARS                  ; init namespaces to 0 using LDIR
    ld de,hl
    inc de
    ld (hl),0
    ld bc,VARS_SIZE
    LDIR

initOps:
    ld hl, iOpcodes
    ld de, opcodes
    ld bc, 256

initOps1:
    ld a,(hl)
    inc hl
    SLA A                     
    ret z
    jr c, initOps2
    SRL A
    ld c,A
    ld b,0
    LDIR
    jr initOps1
    
initOps2:        
    SRL A
    ld b,A
    ld a,(hl)
    inc hl
initOps2a:
    ld (de),A
    inc de
    DJnz initOps2a
    jr initOps1

lookup:
    sub "A"
    jr lookup2 
lookup1:
    sub "a" - 26
lookup2:
    add A,A
    ld hl,VARS
    add A,l
    ld l,a
    ld a,0
    adc a,h
    ld h,a
    xor a
    or E                        ; sets z flag if A-z
    ret

printhex:                           
                                ; Display hl as a 16-bit number in hex.
    push bc                     ; preserve the IP
    ld a,h
    call printhex2
    ld a,l
    call printhex2
    pop bc
    ret
printhex2:		                    
    ld	c,A
	RRA 
	RRA 
	RRA 
	RRA 
    call printhex3
    ld a,c
printhex3:		
    and	0x0F
	add	A,0x90
	DAA
	ADc	A,0x40
	DAA
	jp putchar

editDef:                        ; lookup up def based on number
    pop hl                      ; pop ret address
    ex (SP),hl                  ; swap with TOS                  
    ld a,l
    ex AF,AF'
    ld a,l
    call lookup
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,D
    or E
    ld hl,TIB
    jr z,editDef3
    ld a,":"
    call writechar
    ex AF,AF'
    call writechar
    jr editDef2
editDef1:
    inc de
editDef2:        
    ld a,(de)
    call writechar
    cp ";"
    jr nz,editDef1
editDef3:        
    ld de,TIB
    or A
    sbc hl,de
    ld (vTIBPtr),hl
    jp (iy)

; **************************************************************************             
; calculate nesting value
; A is char to be tested, 
; E is the nesting value (initially 0)
; E is increased by ( and [ 
; E is decreased by ) and ]
; E has its bit 7 toggled by `
; limited to 127 levels
; **************************************************************************             

nesting:                        
    cp '`'
    jr nz,nesting1
    ld a,$80
    xor e
    ld e,a
    ret
nesting1:
    cp ':'
    jr z,nesting2
    cp '['
    jr z,nesting2
    cp '{'
    jr z,nesting2
    cp '('
    jr nz,nesting3
nesting2:
    inc E
    ret
nesting3:
    cp ';'
    jr z,nesting4
    cp ']'
    jr z,nesting4
    cp '}'
    jr z,nesting4
    cp ')'
    ret nz
nesting4:
    dec E
    ret 

prompt:                             
    call printStr
    .cstr "\r\n> "
    ret

crlf:                               
    call printStr
    .cstr "\r\n"
    ret

printStr:                           
    ex (SP),hl		                ; swap			
    call putStr		
    inc hl			                ; inc past null
    ex (SP),hl		                ; put it back	
    ret

putStr0:                            
    call putchar
    inc hl
putStr:
    ld a,(hl)
    or A
    jr nz,putStr0
    ret

rpush:                              
    dec ix                  
    ld (ix+0),h
    dec ix
    ld (ix+0),l
    ret

rpop:                               
    ld L,(ix+0)         
    inc ix              
    ld H,(ix+0)
    inc ix                  
rpop2:
    ret

writechar:                          
    ld (hl),A
    inc hl
    jp putchar

enter:                              
    ld hl,bc
    call rpush                      ; save Instruction Pointer
    pop bc
    dec bc
    jp (iy)                    

loopVar:    
    ld h,0
    ld d,ixh
    ld e,ixl
    add hl,de
    jp var1

; **********************************************************************			 
; Page 4 primitive routines 
; **********************************************************************
    .align $100
page4:

dquote_:        
question_:
lbrace_:   
rbrace_:   
underscore_: 
    jp (iy)

amper_:        
and_:
    pop     de          ;     bitwise and the top 2 elements of the stack
    pop     hl          ;    
    ld      A,E         ;   
    and     L           ;   
    ld      L,A         ;   
    ld      A,D         ;   
    and     H           ;   
and1:
    ld      H,A         ;   
    push    hl          ;    
    jp (iy)             ;   
    
                         
pipe_: 		 
or_:
    pop     de             ; bitwise or the top 2 elements of the stack
    pop     hl
    ld      A,E
    or      L
    ld      L,A
    ld      A,D
    or      H
    jr and1

caret_:		 
xor_:
    pop     de              ; bitwise xor the top 2 elements of the stack
    pop     hl
    ld      A,E
    xor     L
    ld      L,A
    ld      A,D
    xor     H
    jr and1

plus_:                           ; add the top 2 members of the stack
add_:
    pop     de                 
    pop     hl                 
    add     hl,de              
    push    hl                 
    jp carry              
                             
call_:
    ld a,(bc)
    call lookup
    ld e,(hl)
    inc hl
    ld d,(hl)
    jp go1

dot_:       
    pop hl
    call printDec
dot2:
    ld a,' '           
    call putchar
    jp (iy)

comma_:                          ; print hexadecimal
hdot_:
    pop     hl
    call printhex
    jr   dot2

bslash_:
drop_:
    pop     hl
    jp (iy)

hash_:
dup_:
    pop     hl              ; Duplicate the top member of the stack
    push    hl
    push    hl
    jp (iy)

; $ swap                        ; a b -- b a Swap the top 2 elements of the stack
dollar_:        
swap_:
    pop hl
    ex (SP),hl
    push hl
    jp (iy)

percent_:  
over_:
    pop hl              ; Duplicate 2nd element of the stack
    pop de
    push de
    push hl
    push de              ; and push it to top of stack
    jp (iy)        

semi_:
ret_:
    call rpop               ; Restore Instruction pointer
    ld bc,hl                
    jp (iy)             

tilde_:                               
not:
    pop hl
    ld a,l
    cpl
    ld l,a
    ld a,h
    cpl
    ld h,a
    push hl
    jp (iy)

bang_:                         ; Store the value at the address placed on the top of the stack
store_:
assign:
    pop de                      ; discard last accessed value
    pop de                      ; de = new value
assign0:
    ld hl,(vPointer)            ; hl = pointer
assign1:
    ld (hl),e                   ; ignore byte mode to allow assigning to vByteMode           
    inc hl    
    ld (hl),d
    jp (iy) 

minus_:       		    ; Subtract the value 2nd on stack from top of stack 
sub_:
    inc bc              ; check if sign of a number
    ld a,(bc)
    dec bc
    cp "0"
    jr c,sub1
    cp "9"+1
    jp c,num    
sub1:
    pop de              ;    
    pop hl              ;      Entry point for INVert
sub2:   
    and A               ;      Entry point for NEGate
    sbc hl,de           ; 
    push hl             ;    
    jp carry               
                            ; 5  
eq_:    
    pop hl
    pop de
    or a               ; reset the carry flag
    sbc hl,de          ; only equality sets hl=0 here
    jr z,true_
false_:
    ld hl,FALSE
    push hl
    jp (iy)

true_:
    ld hl,TRUE
    push hl
    jp (iy)

gt_:    
    pop hl
    pop de
    jr lt1_
lt_:    
    pop de
    pop hl
lt1_:   
    or a                ; reset the carry flag
    sbc hl,de           ; only equality sets hl=0 here
    jr c,true_
    jr false_

var_:
    ld a,(bc)
    call lookup1
var1:
    ld (vPointer),hl
    ld d,0
    ld e,(hl)
    ld a,(vByteMode)                   
    inc a                       ; is it byte?
    jr z,var2
    inc hl
    ld d,(hl)
var2:
    push de
    jp (iy)

grave_:                         
str:                                                      
    inc bc
    
str1:            
    ld a, (bc)
    inc bc
    cp "`"                      ; ` is the string terminator
    jr z,str2
    call putchar
    jr str1
str2:  
    dec bc
    jp   (iy) 

lbrack_:
arrDef:                         
    ld hl,0
    add hl,sp                   ; save 
    call rpush
    jp (iy)

at_:                         
arrAccess:
    pop hl                              ; hl = index  
    pop de                              ; de = array
    ld a,(vByteMode)                   ; a = data width
    inc a
    jr z,arrAccess1
arrAccess0:
    add hl,hl                           ; if data width = 2 then double 
arrAccess1:
    add hl,de                           ; add addr
    jp var1

lparen_: 
    jp begin
rparen_: 		
    jp again

num_: 
    jp num
colon_: 
    jp def
rbrack_:
    jp arrEnd

quote_:                          ; Discard the top member of the stack
    jr hex
star_: 
    jr mul      
slash_: 
    ; jr div

;*******************************************************************
; Page 5 primitive routines 
;*******************************************************************
    ;falls through 
slash:                      
    inc bc
    ld a,(bc)
    cp "/"
    jp z,comment
    cp "a"
    jr c,alt1
    cp "z"+1
    jr nc,alt2
    cp "i"
    ld l,0
    jp z,loopVar
    cp "j"
    ld l,8
    jp z,loopVar
    sub "a" 
    add A,A
    ld hl,altVars
    add a,l
    ld l,a
    jp var1
alt1:
    cp "A"
    jr c,alt2
    cp "Z"+1
    jr nc,alt2
    ld hl,altcodes
    sub "A"
    add a,l
    ld l,a
    ld a,(hl)                   ;       get low jump address
    ld h,msb(page6)
    ld L,A                      
    jp (hl)                     ;       Jump to routine
alt2:
    dec bc
    jr div

hex:
    ld hl,0	    		    ; clear hl to accept the number
hex1:
    inc bc
    ld a,(bc)		    ; Get the character which is a numeral
    bit 6,A                     ; is it uppercase alpha?
    jr z, hex2                  ; no a decimal
    SUB 7                       ; sub 7  to make $A - $F
hex2:
    SUB $30                     ; Form decimal digit
    jp c,num2
    cp $0F+1
    jp nc,num2
    add hl,hl                   ; 2X ; Multiply digit(s) in hl by 16
    add hl,hl                   ; 4X
    add hl,hl                   ; 8X
    add hl,hl                   ; 16X     
    add A,l                     ; add into bottom of hl
    ld  L,A                        
    jr  hex1

mul:                                
    pop  de                     ; de = 2nd factor 
    pop  hl
    push bc                     ; Preserve the IP
    ld b,h                      ; bc = 2nd value
    ld c,l
    ld hl,0
    ld A,16
mul2:
    add hl,hl
    rl e
    rl d
    jr nc,$+6
    add hl,bc
    jr nc,$+3
    inc de
    dec A
    jr nz,mul2
	pop bc			            ; Restore the IP
	push hl                     ; Put the product on the stack - stack bug fixed 2/12/21
	ld (vRemain),de
	jp (iy)

div:
    ld hl,bc                    ; hl = IP
    pop bc                      ; bc = denominator
    ex (sp),hl                  ; save IP, hl = numerator  
    ld a,h
    xor b
    push af
    xor b
    jp p,absbc
;abshl
    xor a  
    sub l  
    ld l,a
    sbc a,a  
    sub h  
    ld h,a
absbc:
    xor b
    jp p,$+9
    xor a  
    sub c  
    ld c,a
    sbc a,a  
    sub b  
    ld b,a
    add hl,hl
    ld a,15
    ld de,0
    ex de,hl
    jr jumpin
Loop1:
    add hl,bc   ;--
Loop2:
    dec a       ;4
    jr z,EndSDiv ;12|7
jumpin:
    sla e       ;8
    rl d        ;8
    adc hl,hl   ;15
    sbc hl,bc   ;15
    jr c,loop1  ;23-2b
    inc e       ;--
    jr Loop2    ;--
EndSDiv:
    pop af  
    jp p,div10
    xor a  
    sub e  
    ld e,a
    sbc a,a  
    sub d  
    ld d,a
div10:
    pop bc
    push de                     ; quotient
    ld (vRemain),hl          ; remainder
    jp (iy)

arrEnd:                       
    ld (vTemp1),bc              ; save IP
    call rpop
    ld (vTemp2),hl              ; save old SP
    ld de,hl                    ; de = hl = old SP
    or a 
    sbc hl,sp                   ; hl = array count (items on stack)
    srl h                       ; num items = num bytes / 2
    rr l                        
    ld bc,hl                    ; bc = count
    ld hl,(vHeapPtr)            ; hl = array[-4]
    ld (hl),c                   ; write num items in length word
    inc hl
    ld (hl),b
    inc hl                      ; hl = array[0], bc = count
                                ; de = old SP, hl = array[0], bc = count
    jr arrayEnd2
arrayEnd1:                        
    dec bc                      ; dec items count
    dec de
    dec de
    ld a,(de)                   ; a = lsb of stack item
    ld (hl),a                   ; write lsb of array item
    inc hl                      ; move to msb of array item
    ld a,(vByteMode)            ; vByteMode=1? 
    inc a
    jr z,arrayEnd2
    inc de
    ld a,(de)                   ; a = msb of stack item
    dec de
    ld (hl),a                   ; write msb of array item
    inc hl                      ; move to next word in array
arrayEnd2:
    ld a,c                      ; if not zero loop
    or b
    jr nz,arrayEnd1
    ex de,hl                    ; de = end of array 
    ld hl,(vTemp2)
    ld sp,hl                    ; SP = old SP
    ld hl,(vHeapPtr)            ; de = array[-2]
    inc hl
    inc hl
    push hl                     ; return array[0]
    ld (vHeapPtr),de            ; move heap* to end of array
    ld bc,(vTemp1)              ; restore IP
    jp (iy)

; **************************************************************************
; Page 6 Alt primitives
; **************************************************************************
    .align $100
page6:


arrSize_:
arrSize:
    pop hl
    dec hl                      ; msb size 
    ld d,(hl)
    dec hl                      ; lsb size 
    ld e,(hl)
    push de
anop_:
    jp (iy)

bmode_:
    ld a,(vByteMode)
    cpl
    ld (vByteMode),a
    ld (vByteMode+1),a
    jp (iy)

emit_:
    pop hl
    ld a,l
    call putchar
    jp (iy)

exec_:
    call exec1
    jp (iy)
exec1:
    pop hl
    ex (SP),hl
    jp (hl)

key_:
    call getchar
    ld H,0
    ld L,A
    push hl
    jp (iy)

go_:				    ;\^
    pop de
go1:
    ld a,D                      ; skip if destination address is null
    or E
    jr z,go3
    ld hl,bc
    inc bc                      ; read next char from source
    ld a,(bc)                   ; if ; to tail call optimise
    cp ";"                      ; by jumping to rather than calling destination
    jr z,go2
    call rpush                  ; save Instruction Pointer
go2:
    ld bc,de
    dec bc
go3:
    jp (iy)                     

inPort_:			    ; \<
    pop hl
    ld a,c
    ld c,l
    IN L,(c)
    ld H,0
    ld c,A
    push hl
    jp (iy)        

newln_:
    call crlf
    jp (iy)        

outPort_:
    pop hl
    ld e,c
    ld c,l
    pop hl
    OUT (c),l
    ld c,E
    jp (iy)        

; shiftLeft                     
; value count            
shl_:
shiftLeft:
    pop de                  ; de = count
    pop hl                  ; hl = value
    push bc                 ; save IP
    ld a,e
    or a
    jr z,shiftLeft2
    ld b,e
shiftLeft1:   
    add hl,hl               ; left shift hl
    djnz shiftLeft1
shiftLeft2:   
    pop bc
    push hl                 ; restore IP
    jp (iy)

shr_:
    pop de                  ; de = count
    pop hl                  ; hl = value
    push bc                 ; save IP
    ld a,e
    or a
    jr z,shiftRight2
    ld b,e
shiftRight1:   
    srl h
    rr l
    djnz shiftRight1
shiftRight2:   
    pop bc
    push hl                 ; restore IP
    jp (iy)

;/D -> /UD depth            depth
;/L -> /UE edit def         editDef
;/P -> /UP prompt           prompt
;/T -> /US print stack      printStk
utility_:
utility:
    inc bc
    ld a,(bc)
    cp "D"
    jr nz,utility1
; depth:
    ld hl,0
    add hl,SP
    ex de,hl
    ld hl,DSTACK
    or A
    sbc hl,de
    srl h
    rr l
    push hl
    jp (iy)                 ;   
utility1:
    cp "E"
    jp editDef
    cp "P"
    jr nz,utility2
    call prompt
    jp (iy)
    cp "S"
    jr nz,utility3
utility2:    
; printStk:                           
    call ENTER
    .cstr "`=> `/s2-/UD1-(#,2-)\\/N"             
utility3:
    jp (iy)

while_:
while:
    pop hl
    ld a,l
    or h
    jr nz,while2
    ld c,(ix+6)                 ; IP = )
    ld b,(ix+7)
    ; inc bc                      ; IP = one after )
    jp loopEnd4
while2:
    jp (iy)

;*******************************************************************
; Page 5 primitive routines continued
;*******************************************************************

def:                            ; create a colon definition
    inc bc
    ld  A,(bc)                  ; Get the next character
    cp ":"                      ; is it anonymouse
    jr nz,def0
    inc bc
    ld de,(vHeapPtr)            ; return start of definition
    push de
    jr def1
def0:    
    ld (vLastDef),A
    call lookup
    ld de,(vHeapPtr)            ; start of defintion
    ld (hl),E                   ; Save low byte of address in cFA
    inc hl              
    ld (hl),D                   ; Save high byte of address in cFA+1
    inc bc
def1:                           ; Skip to end of definition   
    ld a,(bc)                   ; Get the next character
    inc bc                      ; Point to next character
    ld (de),A
    inc de
    cp ";"                      ; Is it a semicolon 
    jr z, def2                  ; end the definition
    jr  def1                    ; get the next element
def2:    
    dec bc
def3:
    ld (vHeapPtr),de            ; bump heap ptr to after definiton
    jp (iy)       

num:
	ld hl,$0000				    ; clear hl to accept the number
	ld a,(bc)				    ; Get numeral or -
    cp '-'
    jr nz,num0
    inc bc                      ; move to next char, no flags affected
num0:
    ex af,af'                   ; save zero flag = 0 for later
num1:
    ld a,(bc)                   ; read digit    
    sub "0"                     ; less than 0?
    jr c, num2                  ; not a digit, exit loop 
    cp 10                       ; greater that 9?
    jr nc, num2                 ; not a digit, exit loop
    inc bc                      ; inc IP
    ld de,hl                    ; multiply hl * 10
    add hl,hl    
    add hl,hl    
    add hl,de    
    add hl,hl    
    add a,l                     ; add digit in a to hl
    ld l,a
    ld a,0
    adc a,h
    ld h,a
    jr num1 
num2:
    dec bc
    ex af,af'                   ; restore zero flag
    jr nz, num3
    ex de,hl                    ; negate the value of hl
    ld hl,0
    or a                        ; jump to sub2
    sbc hl,de    
num3:
    push hl                     ; Put the number on the stack
    jp (iy)                     ; and process the next character

;*******************************************************************
; Subroutines
;*******************************************************************

; hl = value
printDec:    
    bit 7,h
    jr z,printDec2
    ld a,'-'
    call putchar
    xor a  
    sub l  
    ld l,a
    sbc a,a  
    sub h  
    ld h,a
printDec2:        
    push bc
    ld c,0                      ; leading zeros flag = false
    ld de,-10000
    call printDec4
    ld de,-1000
    call printDec4
    ld de,-100
    call printDec4
    ld e,-10
    call printDec4
    inc c                       ; flag = true for at least digit
    ld e,-1
    call printDec4
    pop bc
    ret
printDec4:
    ld b,'0'-1
printDec5:	    
    inc b
    add hl,de
    jr c,printDec5
    sbc hl,de
    ld a,'0'
    cp b
    jr nz,printDec6
    xor a
    or c
    ret z
    jr printDec7
printDec6:	    
    inc c
printDec7:	    
    ld a,b
    jp putchar

; (val -- )
begin:
loopStart:
    ld (vTemp1),bc              ; save start
    ld e,1                      ; skip to loop end, nesting = 1
loopStart1:
    inc bc
    ld a,(bc)
    call nesting                ; affects zero flag
    jr nz,loopStart1
    pop de                      ; de = limit
    ld a,e                      ; is it zero?
    or d
    jr nz,loopStart2
    dec de                      ; de = TRUE
    ld (vElse),de
    jr loopStart4               ; yes continue after skip    
loopStart2:
    ld a,2                      ; is it TRUE
    add a,e
    add a,d
    jr nz,loopStart3                
    ld de,1                     ; yes make it 1
loopStart3:    
    ld hl,bc
    call rpush                  ; rpush loop end
    dec bc                      ; IP points to ")"
    ld hl,(vTemp1)              ; restore start
    call rpush                  ; rpush start
    ex de,hl                    ; hl = limit
    call rpush                  ; rpush limit
    ld hl,-1                    ; hl = count = -1 
    call rpush                  ; rpush count
loopstart4:    
    jp (iy)

again:
loopEnd:    
    ld e,(ix+2)                 ; de = limit
    ld d,(ix+3)
    ld a,e                      ; a = lsb(limit)
    or d                        ; if limit 0 exit loop
    jr z,loopEnd4                  
    inc de                      ; is limit -2
    inc de
    ld a,e                      ; a = lsb(limit)
    or d                        ; if limit 0 exit loop
    jr z,loopEnd2               ; yes, loop again
    dec de
    dec de
    dec de
    ld (ix+2),e                  
    ld (ix+3),d
loopEnd2:
    ld e,(ix+0)                 ; inc counter
    ld d,(ix+1)
    inc de
    ld (ix+0),e                  
    ld (ix+1),d
loopEnd3:
    ld de,FALSE                 ; if clause ran then vElse = FALSE    
    ld (vElse),de
    ld c,(ix+4)                 ; IP = start
    ld b,(ix+5)
    jp (iy)
loopEnd4:    
    ld de,2*4                   ; rpop frame
    add ix,de
    jp (iy)

carry:                              
    ld hl,0
    rl l
    ld (vcarry),hl
    jp (iy)              

comment:
    inc bc                      ; point to next char
    ld a,(bc)
    cp "\r"                     ; terminate at cr 
    jr nz,comment
    dec bc
    jp   (iy) 


; 0 1 count
; 2 3 limit
; 4 5 start
; 6 7 end
