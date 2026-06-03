; =============================================================================
; Tattva OS — lib/mem/virt/pf.asm
; =============================================================================
; Page Fault Handler entry and dispatching (Subfeature 6.1).
; Hooks Vector 14 (#PF) to intercept faults, read CR2 and the exception error
; code, and log diagnostic details.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PF_ASM
%define LIB_MEM_VIRT_PF_ASM

[BITS 64]

section .text

; External symbol from interrupts.asm for unhandled fallbacks
extern common_isr_handler
extern uart_print_str
extern uart_print_hex64

; -----------------------------------------------------------------------------
; page_fault_isr — Low-level assembly entry point for Vector 14 (#PF)
; -----------------------------------------------------------------------------
global page_fault_isr
page_fault_isr:
    ; Pushing GP registers
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    ; 1. Read CR2 (faulting virtual address)
    mov rdi, cr2                    ; RDI = faulting address (arg 1)

    ; 2. Read error code
    ; The error code is at: RSP + 120 (since we pushed 15 registers * 8 bytes = 120 bytes)
    mov rsi, [rsp + 120]            ; RSI = error code (arg 2)

    ; 3. Call high-level handler
    call virt_page_fault_handler    ; RAX = 1 if handled, 0 if unhandled

    test rax, rax
    jz .unhandled

    ; Handled: restore registers and return
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax

    ; Clean up error code from the stack
    add rsp, 8                      ; pop error code
    iretq

.unhandled:
    ; Restore registers and let common_isr_handler panic
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax

    ; Vector index 14
    push qword 14
    jmp common_isr_handler

; -----------------------------------------------------------------------------
; virt_page_fault_handler — parses error code and prints detailed debug logs
; Input:
;   RDI = faulting virtual address (from CR2)
;   RSI = exception error code
; Output:
;   RAX = 1 if handled, 0 if unhandled
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_page_fault_handler
virt_page_fault_handler:
    push rbx
    push r12
    push r13

    mov r12, rdi                    ; R12 = vaddr
    mov r13, rsi                    ; R13 = error_code

    ; Print "#PF: Page Fault at "
    mov rsi, msg_pf_prefix
    call uart_print_str

    ; Print faulting address in hex
    mov rax, r12
    call uart_print_hex64

    ; Print " (Error Code: "
    mov rsi, msg_pf_err_code
    call uart_print_str

    ; Print error code in hex
    mov rax, r13
    call uart_print_hex64

    ; Print details divider
    mov rsi, msg_pf_details_start
    call uart_print_str

    ; 1. Check Present (Bit 0)
    test r13, 1
    jnz .present_violation
    mov rsi, msg_pf_absent
    call uart_print_str
    jmp .check_write
.present_violation:
    mov rsi, msg_pf_present
    call uart_print_str

.check_write:
    mov rsi, msg_comma_space
    call uart_print_str

    ; 2. Check Write (Bit 1)
    test r13, 2
    jnz .write_fault
    mov rsi, msg_pf_read
    call uart_print_str
    jmp .check_user
.write_fault:
    mov rsi, msg_pf_write
    call uart_print_str

.check_user:
    mov rsi, msg_comma_space
    call uart_print_str

    ; 3. Check User (Bit 2)
    test r13, 4
    jnz .user_fault
    mov rsi, msg_pf_supervisor
    call uart_print_str
    jmp .check_instruction
.user_fault:
    mov rsi, msg_pf_user
    call uart_print_str

.check_instruction:
    mov rsi, msg_comma_space
    call uart_print_str

    ; 4. Check Instruction Fetch (Bit 4)
    test r13, 16
    jnz .instruction_fault
    mov rsi, msg_pf_data
    call uart_print_str
    jmp .details_done
.instruction_fault:
    mov rsi, msg_pf_instruction
    call uart_print_str

.details_done:
    mov rsi, msg_pf_details_end
    call uart_print_str

    ; Return 0 (unhandled) for Subfeature 6.1
    xor rax, rax

    pop r13
    pop r12
    pop rbx
    ret

section .data

msg_pf_prefix:          db "[#PF] Page Fault at ", 0
msg_pf_err_code:        db " (Error Code: ", 0
msg_pf_details_start:   db " - ", 0
msg_pf_absent:          db "Non-Present Page", 0
msg_pf_present:         db "Protection Violation", 0
msg_pf_read:            db "Read Access", 0
msg_pf_write:           db "Write Access", 0
msg_pf_supervisor:      db "Supervisor Mode", 0
msg_pf_user:            db "User Mode", 0
msg_pf_data:            db "Data Access", 0
msg_pf_instruction:     db "Instruction Fetch", 0
msg_comma_space:        db ", ", 0
msg_pf_details_end:     db ")", 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_PF_ASM
