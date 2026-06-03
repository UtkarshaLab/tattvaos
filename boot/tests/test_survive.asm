; =============================================================================
; Tattva OS — boot/tests/test_survive.asm
; =============================================================================
; Test assertion for survive/ panic snapshot and CRC32 verification.
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef TEST_SURVIVE_ASM
%define TEST_SURVIVE_ASM

[BITS 64]

; =============================================================================
; test_survive — verify survive snapshot saving and CRC32 verification
; =============================================================================
test_survive:
    push rsi
    push rax

    mov rsi, msg_test_survive
    call uart_print_64

    ; Save hardware state to SURVIVE_PAGE
    call survive_snapshot_save

    ; Verify snapshot checksum
    call survive_checksum_verify
    cmp rax, 1
    jne .failed

    mov rsi, msg_pass_survive
    call uart_print_64
    jmp .done

.failed:
    mov rsi, msg_fail_survive
    call uart_print_64

.done:
    pop rax
    pop rsi
    ret

; =============================================================================
; Data (64-bit)
; =============================================================================
msg_test_survive:  db "TEST: Survive snapshot checksum validation... ", 0
msg_pass_survive:  db "PASS", 0x0D, 0x0A, 0
msg_fail_survive:  db "FAIL", 0x0D, 0x0A, 0

[BITS 16]

%endif ; TEST_SURVIVE_ASM
