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

; =============================================================================
; survive_wakeup_entry — entry point when kernel triggers panic
; =============================================================================
survive_wakeup_entry:
    cli                             ; disable interrupts immediately
    cld                             ; Clear direction flag for robust execution

    ; 1. Save all registers to SURVIVE_PAGE + 0xA00 (crash snapshot)
    mov [SURVIVE_PAGE + 0xA00], rax
    mov [SURVIVE_PAGE + 0xA08], rbx
    mov [SURVIVE_PAGE + 0xA10], rcx
    mov [SURVIVE_PAGE + 0xA18], rdx
    mov [SURVIVE_PAGE + 0xA20], rsi
    mov [SURVIVE_PAGE + 0xA28], rdi
    mov [SURVIVE_PAGE + 0xA30], rbp
    mov [SURVIVE_PAGE + 0xA38], rsp
    mov [SURVIVE_PAGE + 0xA40], r8
    mov [SURVIVE_PAGE + 0xA48], r9
    mov [SURVIVE_PAGE + 0xA50], r10
    mov [SURVIVE_PAGE + 0xA58], r11
    mov [SURVIVE_PAGE + 0xA60], r12
    mov [SURVIVE_PAGE + 0xA68], r13
    mov [SURVIVE_PAGE + 0xA70], r14
    mov [SURVIVE_PAGE + 0xA78], r15

    ; Save control registers
    mov rax, cr0
    mov [SURVIVE_PAGE + 0xA80], rax
    mov rax, cr2
    mov [SURVIVE_PAGE + 0xA88], rax
    mov rax, cr3
    mov [SURVIVE_PAGE + 0xA90], rax
    mov rax, cr4
    mov [SURVIVE_PAGE + 0xA98], rax

    ; Save segment selectors
    xor rax, rax
    mov ax, cs
    mov [SURVIVE_PAGE + 0xAA0], rax
    mov ax, ds
    mov [SURVIVE_PAGE + 0xAA8], rax
    mov ax, es
    mov [SURVIVE_PAGE + 0xAB0], rax
    mov ax, fs
    mov [SURVIVE_PAGE + 0xAB8], rax
    mov ax, gs
    mov [SURVIVE_PAGE + 0xAC0], rax
    mov ax, ss
    mov [SURVIVE_PAGE + 0xAC8], rax

    ; Save RFLAGS
    pushfq
    pop qword [SURVIVE_PAGE + 0xAD0]

    ; Save RIP from 0x510
    mov rax, [0x510]
    mov [SURVIVE_PAGE + 0xAD8], rax

    ; 2. Set up a temporary safe stack for recovery execution
    mov rsp, STACK_LONG

    ; 3. Log the panic string and RIP to SURVIVE_PAGE + 0x800 (SURVIVE_PAGE + 0x800)
    mov rcx, [0x508]                ; RCX = panic string pointer
    mov rdx, [0x510]                ; RDX = crash RIP
    call survive_log_panic

    ; 4. Output panic message to COM1 serial port
    lea rsi, [msg_panic_prefix]
    call uart_print_64
    
    mov rsi, SURVIVE_PAGE + 0x808   ; address of copied panic message
    call uart_print_64
    
    lea rsi, [msg_panic_at]
    call uart_print_64
    
    mov rax, [SURVIVE_PAGE + 0x800] ; crash RIP
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
msg_checksum_ok:    db "Snapshot checksum valid. Initiating warm recovery...", 0x0D, 0x0A, 0
msg_checksum_fail:  db "Snapshot checksum INVALID (corrupted). Triggering hard reset...", 0x0D, 0x0A, 0

%endif ; SURVIVE_WAKEUP_ASM
