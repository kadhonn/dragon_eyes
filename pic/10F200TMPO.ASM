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
MODE EQU 0x15				;current mode, aka which sample is running
MODE_TMP EQU 0x16				;tmp var for the switch
BUTTON_DEBOUNCE_COUNTER EQU 0x17		;button debounce counter

MODE_1 EQU 0x1A		;vars for modes to use
MODE_2 EQU 0x1B
MODE_3 EQU 0x1C
MODE_4 EQU 0x1D
MODE_5 EQU 0x1E
MODE_6 EQU 0x1F

;***** specific var names for modes
UPPER_POS EQU MODE_1	;upper and lower values for pos (aka 16 bit var)
LOWER_POS EQU MODE_2
UPPER_SPEED EQU MODE_3	;upper and lower values for speed (aka 16 bit var)
LOWER_SPEED EQU MODE_4
ACC EQU MODE_5			;acceleration for speed


;***** FLAGS DEFINITIONS
MODE_NEEDS_INIT	EQU		0x00	;if the mode needs to initialize, aka button was pressed and mode switched
MODE_FLAG_1 EQU 0x04	;flags for modes to use
MODE_FLAG_2 EQU 0x05
MODE_FLAG_3 EQU 0x06
MODE_FLAG_4 EQU 0x07


;***** specific flag names for modes
ACC_UP EQU MODE_FLAG_1

;***** CONSTANTS
MODES_COUNT EQU 0x03		;how many modes we have, mode 0 means sleep




;**********************************************************************
	ORG     0xFF             ; processor reset vector

; Internal RC calibration value is placed at location 0xFF by Microchip
; as a movlw k, where the k is a literal value.

	ORG     0x000             ; coding begins here
	movwf   OSCCAL            ; update register with factory cal value 




init
	clrwdt
	movlw	B'01000010'		;enable GPWU, assign prescaler to Timer0 and set ratio to 1:8
	option					;load options
	clrf 	GPIO			;set all output to low
	movlw	B'00001110'		;setup only gpio0 to output
	tris 	6				;load gpio options
	clrf TMR0				;reset timer

	;init all vars
	movlw 0x8				
	movwf UPDATE_DELAY_COUNTER

	movlw 0x0	
	movwf BRIGHTNESS 
	movwf WANTED_BRIGHTNESS
	movwf BUTTON_DEBOUNCE_COUNTER

	movlw MODES_COUNT
	movwf MODE				;mode is MODES_COUNT because we will need to call button_detected which will decrease it to a valid value


	btfss STATUS, GPWUF		;skip sleep if GPWUF is set, because that means we woke up due to button
	sleep
	call button_detected


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
	call detect_button
	call update_logic
	goto end_pwm_loop

brightness_high
	call detect_button
	call update_logic
	call wait_till_timer_brightness
	bcf GPIO, GP0			;turn off led

end_pwm_loop
	;load 255 as max value and wait till timer reaches it/aka end of pwm cycle
	movlw 0xff
	call wait_till_timer_value
	goto pwm_loop



; only methods below this point



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
	
	movf MODE, 0			;load current mode
	movwf MODE_TMP			;save current mode into mode_tmp so we can modify it

	decf MODE_TMP, 1		;dec mode, if now 0 we know it has to be mode_1
	btfsc STATUS, Z			;skip the next goto if we have not reached 0
	goto mode_1

	decf MODE_TMP, 1		;dec mode, if now 0 we know it has to be mode_2
	btfsc STATUS, Z			;skip the next goto if we have not reached 0
	goto mode_2
	
	retlw 0					;unknown mode, return

mode_1 ;fast pulse
	movlw .16
	goto generic_pulse
mode_2 ;slow pulse
	movlw .4
	;goto generic_pulse

generic_pulse
	movwf ACC
	btfss FLAGS, MODE_NEEDS_INIT ;if MODE_NEEDS_INIT is set, we skip the skip
	goto generic_pulse_after_init
	
	;initialize mode
	movlw 0
	movwf LOWER_POS
	movwf UPPER_SPEED
	movwf LOWER_SPEED
	movlw .40
	movwf UPPER_POS
	bcf FLAGS, MODE_NEEDS_INIT ;reset MODE_NEEDS_INIT flag
generic_pulse_after_init
	movf ACC, 0 ;load acc to w, should be preserved throught the if below
	btfss UPPER_POS, 7 ;test the most significant bit of UPPER_POS, if set we want to slow down
	goto generic_pulse_speed_up
	;goto generic_pulse_slow_down
generic_pulse_slow_down
	subwf LOWER_SPEED, 1
	btfss STATUS, C ;if C is set we DO NOT need to carry, since borrow is negated...
	decf UPPER_SPEED, 1
	goto generic_pulse_move
generic_pulse_speed_up
	addwf LOWER_SPEED, 1
	btfsc STATUS, C ;if C is set we need to carry
	incf UPPER_SPEED, 1 
generic_pulse_move
	movf LOWER_SPEED, 0 ;load lower_speed to w 
	addwf LOWER_POS, 1 ;add to lower_pos and store
	btfsc STATUS, C ;if C is set we need to carry
	incf UPPER_POS, 1
	movf UPPER_SPEED, 0 ;load upper_speed to w
	addwf UPPER_POS, 1 ;add to upper_pos and store
generic_pulse_end
	movf UPPER_POS, 0	;now use UPPER_POS as wanted_brightness
	movwf WANTED_BRIGHTNESS
	retlw 0



detect_button
	btfsc GPIO, GP1		;we skip the return if we read a 0 because button is active-low
	retlw 0

button_detected
	bcf GPIO, GP0			;turn off led
	bsf FLAGS, MODE_NEEDS_INIT ;tell modes to init themselves

	;debounce here
	;delay function
	movlw 0x255
	call wait_till_timer_value
	decfsz BUTTON_DEBOUNCE_COUNTER, 1	;exit the loop when we reach 0
	goto $-3

	btfss GPIO, GP1		;we loop until we read a 1, which means button is let go
	goto $-1


	;delay function
	movlw 0x255
	call wait_till_timer_value
	decfsz BUTTON_DEBOUNCE_COUNTER, 1	;exit the loop when we reach 0
	goto $-3

	;debounce done
	decfsz MODE,1		;dec mode, skip return if we reach 0 == sleep
	retlw 0
	sleep				;we reached mode 0, so go to sleep for now


	END                       ; directive 'end of program'

