; =============================================================================
; Tattva OS — kernel/kernel_stub.asm
; =============================================================================
; Minimal kernel stub for testing the full boot chain.
; Prints "Tattva Kernel OK" via UART (COM1) and halts.
;
; This is a raw binary — no ULF header yet.
; Placed at sector 17 (LBA) of boot.img by the Makefile.
; The bootloader loads it to 0x20000 via BIOS int 0x13 in real mode,
; then copies it to 0x100000 (1MB) in 64-bit long mode,
; then jumps to 0x100000.
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

[BITS 64]
[ORG 0x100000]

kernel_entry:
    ; -------------------------------------------------------------------------
    ; Print "Tattva Kernel OK" via UART (COM1 = 0x3F8)
    ; Same polling approach as the bootloader — port I/O works in long mode
    ; -------------------------------------------------------------------------
    mov rsi, .msg_kernel_ok

.print_loop:
    lodsb                           ; AL = [RSI], RSI++
    test al, al                     ; null terminator?
    jz .print_done
    call .uart_putc
    jmp .print_loop

.print_done:
    ; -------------------------------------------------------------------------
    ; Halt — kernel has no scheduler yet
    ; -------------------------------------------------------------------------
    cli
.halt:
    hlt
    jmp .halt

; =============================================================================
; .uart_putc — write a single character via COM1 (polling)
; Input:  AL = character to send
; Output: nothing
; =============================================================================
.uart_putc:
    push rdx
    push rax
    mov bl, al                      ; save character

.uart_wait:
    mov dx, 0x3F8 + 5              ; LSR (Line Status Register)
    in al, dx
    test al, 0x20                   ; Transmitter Holding Register Empty?
    jz .uart_wait

    mov al, bl                      ; restore character
    mov dx, 0x3F8                   ; THR (Transmit Holding Register)
    out dx, al

    pop rax
    pop rdx
    ret

; =============================================================================
; Data
; =============================================================================
.msg_kernel_ok:
    db "================================", 0x0D, 0x0A
    db "  Tattva Kernel OK", 0x0D, 0x0A
    db "================================", 0x0D, 0x0A, 0
