; =============================================================================
; Tattva OS — boot/tests/test_a20.asm
; =============================================================================
; Test assertion for the A20 gate address line verification.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef TEST_A20_ASM
%define TEST_A20_ASM

%include "a20_verify.asm"

[BITS 16]

; =============================================================================
; test_a20 — verify A20 status and print diagnostic result
; =============================================================================
test_a20:
    push si

    mov si, msg_test_a20
    call uart_print

    call a20_verify                 ; verify A20 line status
    jc .failed

    mov si, msg_pass
    call uart_println
    jmp .done

.failed:
    mov si, msg_fail
    call uart_println

.done:
    pop si
    ret

; =============================================================================
; Data
; =============================================================================
msg_test_a20:   db "TEST: A20 gate address wrap-around... ", 0
msg_pass:       db "PASS", 0
msg_fail:       db "FAIL", 0

%endif ; TEST_A20_ASM
