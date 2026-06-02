; =============================================================================
; Tattva OS — boot/stage2/a20/a20_kbd.asm
; =============================================================================
; Enable A20 line using the PS/2 Keyboard Controller (8042) Output Port.
; Highly compatible fallback for systems without Port 0x92 or BIOS support.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef A20_KBD_ASM
%define A20_KBD_ASM

[BITS 16]

; =============================================================================
; a20_kbd — enable A20 via keyboard controller output port
; Input:  none
; Output: none
; Clobbers: AX
; =============================================================================
a20_kbd:
    push ax

    ; 1. Disable keyboard and mouse interrupts/transmission to prevent corruption
    call a20_kbd_wait_input
    mov al, 0xAD                    ; command 0xAD: disable keyboard
    out 0x64, al

    call a20_kbd_wait_input
    mov al, 0xA7                    ; command 0xA7: disable mouse
    out 0x64, al

    ; 2. Read existing Output Port configuration
    call a20_kbd_wait_input
    mov al, 0xD0                    ; command 0xD0: read Output Port
    out 0x64, al

    call a20_kbd_wait_output
    in al, 0x60                     ; read output byte from data port
    push ax                         ; save it

    ; 3. Write Output Port with bit 1 set to enable A20
    call a20_kbd_wait_input
    mov al, 0xD1                    ; command 0xD1: write Output Port
    out 0x64, al

    call a20_kbd_wait_input
    pop ax                          ; restore output port byte
    or al, 0x02                     ; set bit 1 (A20 Enable)
    out 0x60, al

    ; 4. Re-enable keyboard and mouse
    call a20_kbd_wait_input
    mov al, 0xAE                    ; command 0xAE: enable keyboard
    out 0x64, al

    call a20_kbd_wait_input
    mov al, 0xA8                    ; command 0xA8: enable mouse
    out 0x64, al

    ; 5. Wait until input buffer is clear to confirm complete
    call a20_kbd_wait_input

    pop ax
    ret

; -----------------------------------------------------------------------------
; a20_kbd_wait_input — wait until input buffer (port 0x64 bit 1) is empty (0)
; -----------------------------------------------------------------------------
a20_kbd_wait_input:
    in al, 0x64
    test al, 0x02                   ; bit 1 set = input buffer full
    jnz a20_kbd_wait_input          ; wait until 0
    ret

; -----------------------------------------------------------------------------
; a20_kbd_wait_output — wait until output buffer (port 0x64 bit 0) is full (1)
; -----------------------------------------------------------------------------
a20_kbd_wait_output:
    in al, 0x64
    test al, 0x01                   ; bit 0 clear = output buffer empty
    jz a20_kbd_wait_output          ; wait until 1
    ret

%endif ; A20_KBD_ASM
