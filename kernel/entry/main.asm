; =============================================================================
; Tattva OS — kernel/entry/main.asm
; =============================================================================
; Kernel main entry point. Invoked after subsystem initialization completes.
; Prints the final kernel ready message and transitions to the CPU idle loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

; External VMM functions
extern vma_create
extern uart_print_str
extern uart_print_hex64

kernel_main:
    ; 1. Print kernel execution ready state
    mov rsi, msg_kernel_ready
    call uart_print_str

    ; 2. Run VMM Page Fault On-Demand Paging Test
    mov rsi, msg_test_start
    call uart_print_str

    ; Create a VMA: start=0x70000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_ONDEMAND (0x83)
    mov rdi, 0x70000000
    mov rsi, 4096
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .test_fail_vma

    mov rsi, msg_vma_ok
    call uart_print_str

    ; Access address to trigger page fault (read/write check)
    mov rdi, 0x70000000
    mov byte [rdi], 0x42            ; should trigger #PF and resume!

    ; Verification 1: Check if the written byte is present and correct
    mov al, [rdi]
    cmp al, 0x42
    jne .test_fail_val

    ; Verification 2: Print the mock loaded page content
    mov rsi, rdi
    call uart_print_str             ; should print "TATTVA_OS_ONDEMAND_PAGE_LOADED"
    mov rsi, msg_crlf
    call uart_print_str

    ; Verification 3: Check unique address written at offset 32
    mov rax, [rdi + 32]
    cmp rax, 0x70000000
    jne .test_fail_addr

    ; Test PASSED!
    mov rsi, msg_test_passed
    call uart_print_str
    jmp .idle

.test_fail_vma:
    mov rsi, msg_fail_vma_str
    call uart_print_str
    jmp .panic

.test_fail_val:
    mov rsi, msg_fail_val_str
    call uart_print_str
    jmp .panic

.test_fail_addr:
    mov rsi, msg_fail_addr_str
    call uart_print_str

.panic:
    mov rsi, msg_test_failed
    call uart_print_str
    cli
.hlt_loop:
    hlt
    jmp .hlt_loop

.idle:
    ; 3. Disable interrupts (no external interrupt handlers registered yet)
    cli

    ; 4. Enter CPU idle loop
.idle_loop:
    hlt                             ; halt the processor until next interrupt
    jmp .idle_loop                  ; jump back if an NMI or interrupt wakes us

; -----------------------------------------------------------------------------
; Messages
; -----------------------------------------------------------------------------
section .data

msg_kernel_ready:     db "Tattva Kernel Ready. Entering main execution.", 0x0D, 0x0A, 0
msg_test_start:       db "Running VMM On-Demand Paging Exception Test...", 0x0D, 0x0A, 0
msg_vma_ok:           db "VMA created at 0x70000000. Triggering read/write page fault...", 0x0D, 0x0A, 0
msg_crlf:             db 0x0D, 0x0A, 0
msg_test_passed:      db "VMM On-Demand Paging Test PASSED!", 0x0D, 0x0A, 0
msg_test_failed:      db "VMM On-Demand Paging Test FAILED! Halting.", 0x0D, 0x0A, 0

msg_fail_vma_str:     db "Failure: Could not create on-demand VMA.", 0x0D, 0x0A, 0
msg_fail_val_str:     db "Failure: Resumed byte value is incorrect.", 0x0D, 0x0A, 0
msg_fail_addr_str:    db "Failure: Unique address verification at offset 32 failed.", 0x0D, 0x0A, 0
