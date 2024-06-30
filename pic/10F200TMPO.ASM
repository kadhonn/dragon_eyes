;**********************************************************************
;   This file is a basic code template for assembly code generation   *
;   on the PIC10F200. This file contains the basic code               *
;   building blocks to build upon.                                    *
;                                                                     *
;   Refer to the MPASM User's Guide for additional information on     *
;   features of the assembler (Document DS33014).                     *
;                                                                     *
;   Refer to the respective PIC data sheet for additional             *
;   information on the instruction set.                               *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Filename:	    xxx.asm                                           *
;    Date:                                                            *
;    File Version:                                                    *
;                                                                     *
;    Author:                                                          *
;    Company:                                                         *
;                                                                     * 
;                                                                     *
;**********************************************************************
;                                                                     *
;    Files Required: P10F200.INC                                      *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Notes:                                                           *
;                                                                     *
;**********************************************************************

	list      p=10F200            ; list directive to define processor
	#include <p10F200.inc>        ; processor specific variable definitions

	__CONFIG   _MCLRE_ON & _CP_OFF & _WDT_OFF

; '__CONFIG' directive is used to embed configuration word within .asm file.
; The lables following the directive are located in the respective .inc file. 
; See respective data sheet for additional information on configuration word.




;***** VARIABLE DEFINITIONS
FLAGS	EQU     0x10        ;flags
BRIGHTNESS EQU 0x11			;current brightness value used in the pwm loop
WANTED_BRIGHTNESS EQU 0x12	;wanted brightness set by update_logic routine
UPDATE_DELAY_COUNTER EQU 0x13; ;counter to 8 to get about 60 updates per second for logic
WAIT_TILL_TIMER_VAR EQU 0x14	;for wait_till_timer_value the time to wait

;***** FLAGS DEFINITIONS
OUT_FLAG	EQU		0x01	;UNUSED



;**********************************************************************
	ORG     0xFF             ; processor reset vector

; Internal RC calibration value is placed at location 0xFF by Microchip
; as a movlw k, where the k is a literal value.

	ORG     0x000             ; coding begins here
	movwf   OSCCAL            ; update register with factory cal value 




init
	clrwdt
	movlw	B'00000010'		;enable GPPU & GPWU, assign prescaler to Timer0 and set ratio to 1:8
	option					;load options
	clrf 	GPIO			;set all output to low
	movlw	B'00001110'		;setup only gpio0 to output
	tris 	6				;load gpio options
	clrf TMR0				;reset timer

	movlw 0x8				
	movwf UPDATE_DELAY_COUNTER ; init UPDATE_DELAY_COUNTER to 8	
	movlw 0x0	
	movwf BRIGHTNESS 
	movwf WANTED_BRIGHTNESS

	;bsf GPIO, GP0			;turn on led
	;bcf GPIO, GP0			;turn off led

pwm_loop
	;load wanted_brightness into brightness
	;loading sets Z flag and storing does not affect it, so we can use it to check for 0 brightness afterwards
	movf WANTED_BRIGHTNESS, 0
	movwf BRIGHTNESS
	btfss STATUS, Z ;if Z is set we have zero brightness, so skip the skip
	goto brightness_non_zero

zero_brightness
	call update_logic
	goto end_pwm_loop

brightness_non_zero
	bsf GPIO, GP0			;turn on led
	btfsc BRIGHTNESS, 7 	;test the first bit of brightness, if it is 0 we want brightness is low, so skip the next goto
	goto brightness_high

brightness_low
	call wait_till_timer_brightness
	bcf GPIO, GP0			;turn off led
	call update_logic
	goto end_pwm_loop

brightness_high
	call update_logic
	call wait_till_timer_brightness
	bcf GPIO, GP0			;turn off led

end_pwm_loop
	;load 255 as max value and wait till timer reaches it/aka end of pwm cycle
	movlw 0xff
	call wait_till_timer_value
	goto pwm_loop



wait_till_timer_brightness
	movf BRIGHTNESS, 0 ;load brightness

wait_till_timer_value
	movwf WAIT_TILL_TIMER_VAR ;store W into our own tmp var

wait_till_timer_value_loop
	movf TMR0, 0			;load time
	xorwf WAIT_TILL_TIMER_VAR,0 ;xor with wanted value, that means if they are the same W == 0 which means the Z flag is set
	btfss STATUS, Z			;if Z is set we are done and skip the goto
	goto wait_till_timer_value_loop
	
	retlw 0 ;return from wait_till_timer_value


update_logic
	decfsz UPDATE_DELAY_COUNTER, 1 ;dec UPDATE_DELAY_COUNTER and save it back there. if we reach zero we skip the return
	retlw 0

	;here we have the actual update_logic which is called every 8th time, meaning about 60fps
	movlw 0x8				
	movwf UPDATE_DELAY_COUNTER ;reset to 8

	incf WANTED_BRIGHTNESS, 1 ;inc WANTED_BRIGHTNESS as only logic for now



	END                       ; directive 'end of program'

