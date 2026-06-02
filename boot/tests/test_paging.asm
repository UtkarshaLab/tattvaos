; =============================================================================
; Tattva OS — boot/tests/test_paging.asm
; =============================================================================
; Test assertions for PML4 and PDPT page table configuration.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef TEST_PAGING_ASM
%define TEST_PAGING_ASM

%include "paging_verify.asm"

[BITS 32]

; =============================================================================
; test_paging — verify page table mapping attributes
; =============================================================================
test_paging:
    push esi

    mov esi, msg_test_paging
    call uart_print_pm

    call paging_verify              ; verify page table structures
    jc .failed

    mov esi, msg_pass_pm
    call uart_print_pm
    jmp .done

.failed:
    mov esi, msg_fail_pm
    call uart_print_pm

.done:
    pop esi
    ret

; =============================================================================
; Data (in 32-bit section)
; =============================================================================
msg_test_paging:    db "TEST: Page directory table structures... ", 0
msg_pass_pm:        db "PASS", 0x0D, 0x0A, 0
msg_fail_pm:        db "FAIL", 0x0D, 0x0A, 0

[BITS 16]

%endif ; TEST_PAGING_ASM
