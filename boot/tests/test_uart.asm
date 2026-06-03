; =============================================================================
; Tattva OS — boot/tests/test_uart.asm
; =============================================================================
; Test assertion for the UART serial driver functions.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef TEST_UART_ASM
%define TEST_UART_ASM

[BITS 16]

; =============================================================================
; test_uart — verify UART works by testing status register
; =============================================================================
test_uart:
    push si
    push ax
    push dx

    mov si, msg_test_uart
    call uart_print

    ; Verify COM1 line status register (LSR)
    mov dx, UART_COM1 + 5           ; LSR port
    in al, dx
    test al, 0x20                   ; Transmitter Holding Register Empty (THRE)?
    jz .failed

    mov si, msg_pass_uart
    call uart_println
    jmp .done

.failed:
    mov si, msg_fail_uart
    call uart_println

.done:
    pop dx
    pop ax
    pop si
    ret

; =============================================================================
; Data
; =============================================================================
msg_test_uart:  db "TEST: UART COM1 initialization and status... ", 0
msg_pass_uart:  db "PASS", 0
msg_fail_uart:  db "FAIL", 0

%endif ; TEST_UART_ASM
