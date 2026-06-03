; =============================================================================
; Tattva OS — boot/survive/wakeup.asm
; =============================================================================
; Wakeup entry point for the survive panic recovery vector.
; Captures the crash state, logs the panic, verifies checksums, and launches
; either warm recovery or hard reboot.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode)
; =============================================================================

%ifndef SURVIVE_WAKEUP_ASM
%define SURVIVE_WAKEUP_ASM

%include "config.asm"

[BITS 64]

global survive_wakeup_entry
extern survive_log_panic
extern survive_diff
extern survive_checksum_verify
extern survive_recover
extern survive_reset
extern uart_print_64
extern uart_print_hex64

; =============================================================================
; survive_wakeup_entry — entry point when kernel triggers panic
; =============================================================================
survive_wakeup_entry:
    cli                             ; disable interrupts immediately
    cld                             ; Clear direction flag for robust execution

    ; 1. Save all registers to 0x9A00 (crash snapshot)
    mov [0x9A00], rax
    mov [0x9A08], rbx
    mov [0x9A10], rcx
    mov [0x9A18], rdx
    mov [0x9A20], rsi
    mov [0x9A28], rdi
    mov [0x9A30], rbp
    mov [0x9A38], rsp
    mov [0x9A40], r8
    mov [0x9A48], r9
    mov [0x9A50], r10
    mov [0x9A58], r11
    mov [0x9A60], r12
    mov [0x9A68], r13
    mov [0x9A70], r14
    mov [0x9A78], r15

    ; Save control registers
    mov rax, cr0
    mov [0x9A80], rax
    mov rax, cr2
    mov [0x9A88], rax
    mov rax, cr3
    mov [0x9A90], rax
    mov rax, cr4
    mov [0x9A98], rax

    ; Save segment selectors
    xor rax, rax
    mov ax, cs
    mov [0x9AA0], rax
    mov ax, ds
    mov [0x9AA8], rax
    mov ax, es
    mov [0x9AB0], rax
    mov ax, fs
    mov [0x9AB8], rax
    mov ax, gs
    mov [0x9AC0], rax
    mov ax, ss
    mov [0x9AC8], rax

    ; Save RFLAGS
    pushfq
    pop qword [0x9AD0]

    ; Save RIP from 0x510
    mov rax, [0x510]
    mov [0x9AD8], rax

    ; 2. Set up a temporary safe stack for recovery execution
    mov rsp, 0x9C000                ; STACK_LONG

    ; 3. Log the panic string and RIP to SURVIVE_PAGE + 0x800 (0x9800)
    mov rcx, [0x508]                ; RCX = panic string pointer
    mov rdx, [0x510]                ; RDX = crash RIP
    call survive_log_panic

    ; 4. Output panic message to COM1 serial port
    lea rsi, [msg_panic_prefix]
    call uart_print_64
    
    mov rsi, 0x9808                 ; address of copied panic message
    call uart_print_64
    
    lea rsi, [msg_panic_at]
    call uart_print_64
    
    mov rax, [0x9800]               ; crash RIP
    call uart_print_hex64
    
    lea rsi, [msg_crlf]
    call uart_print_64

    ; 5. Print register diff diagnostics
    call survive_diff

    ; 6. Verify checksum of pristine snapshot
    call survive_checksum_verify
    test rax, rax
    jz .checksum_invalid

    ; Checksum matches! Proceed to reload and warm recovery
    lea rsi, [msg_checksum_ok]
    call uart_print_64
    call survive_recover
    jmp .halt

.checksum_invalid:
    ; Checksum fails, snapshot is corrupt. Trigger hard reboot
    lea rsi, [msg_checksum_fail]
    call uart_print_64
    call survive_reset

.halt:
    cli
    hlt
    jmp .halt

; =============================================================================
; 64-bit strings
; =============================================================================
msg_panic_prefix:   db 0x0D, 0x0A, "!!! KERNEL PANIC !!!", 0x0D, 0x0A, "Reason: ", 0
msg_panic_at:       db 0x0D, 0x0A, "RIP: 0x", 0
msg_crlf:           db 0x0D, 0x0A, 0
msg_checksum_ok:    db "Snapshot checksum valid. Initiating warm recovery...", 0x0D, 0x0A, 0
msg_checksum_fail:  db "Snapshot checksum INVALID (corrupted). Triggering hard reset...", 0x0D, 0x0A, 0

%endif ; SURVIVE_WAKEUP_ASM
