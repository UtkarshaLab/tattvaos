; =============================================================================
; Tattva OS — boot/tests/test_e820.asm
; =============================================================================
; Test assertions for E820 memory map parsing and validation.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef TEST_E820_ASM
%define TEST_E820_ASM

[BITS 16]

; =============================================================================
; test_e820 — verify memory map parser results
; =============================================================================
test_e820:
    push si
    push eax

    mov si, msg_test_e820
    call uart_print

    ; Verify total memory reported is non-zero (implies successful BIOS query & parse)
    mov eax, [e820_total_mb]
    test eax, eax
    jz .failed

    mov si, msg_pass_e820
    call uart_println
    jmp .done

.failed:
    mov si, msg_fail_e820
    call uart_println

.done:
    pop eax
    pop si
    ret

; =============================================================================
; Data
; =============================================================================
msg_test_e820:   db "TEST: E820 system memory map parsing... ", 0
msg_pass_e820:   db "PASS", 0
msg_fail_e820:   db "FAIL", 0

%endif ; TEST_E820_ASM
