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

; VMA Flags (matching virt.asm design)
VMA_READ        equ (1 << 0)
VMA_WRITE       equ (1 << 1)
VMA_EXEC        equ (1 << 2)
VMA_USER        equ (1 << 3)
VMA_COW         equ (1 << 4)
VMA_ZFOD        equ (1 << 5)
VMA_STACK       equ (1 << 6)
VMA_ONDEMAND    equ (1 << 7)

; Page Table Flags (from pgtable.asm)
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_NX         equ (1 << 63)

; External symbols
extern common_isr_handler
extern uart_print_str
extern uart_print_hex64
extern vma_find
extern phys_alloc_page
extern phys_free_page
extern memzero
extern memcpy
extern virt_map

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

    ; 1. Find VMA containing the address
    mov rdi, r12
    call vma_find                   ; RAX = VMA pointer, or 0 if not found
    test rax, rax
    jz .do_diagnostics              ; no VMA, invalid address -> panic

    mov rbx, [rax + 16]             ; RBX = vma->flags (VMA structure: start, end, flags)
                                    ; Wait, let's verify offset of .flags in vma_t:
                                    ; start (8 bytes), end (8 bytes) -> flags is at offset 16!

    ; 2. Check if it is an on-demand VMA
    test rbx, VMA_ONDEMAND
    jz .do_diagnostics              ; not on-demand VMA

    ; 3. Check if fault was Present violation (bit 0 = 1)
    test r13, 1                     ; Present bit set?
    jnz .do_diagnostics             ; protection fault -> not standard ZFOD/on-demand paging

    ; 4. Call handler for on-demand paging
    mov rdi, r12                    ; virtual address
    mov rsi, rax                    ; VMA pointer
    call virt_handle_ondemand
    test rax, rax
    jz .do_diagnostics              ; OOM during map -> panic

    ; Successfully handled!
    mov rax, 1
    jmp .exit

.do_diagnostics:
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

    ; Return 0 (unhandled)
    xor rax, rax

.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_handle_ondemand — allocates, mock-loads, and maps an on-demand page
; Input:
;   RDI = faulting virtual address
;   RSI = VMA pointer
; Output:
;   RAX = 1 on success, 0 on failure (OOM)
; -----------------------------------------------------------------------------
global virt_handle_ondemand
virt_handle_ondemand:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi                    ; R12 = virtual address
    mov r13, rsi                    ; R13 = VMA pointer

    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .oom
    mov r14, rax                    ; R14 = new physical page base

    ; 2. Zero-out the new page
    mov rdi, r14
    mov rsi, 4096
    call memzero

    ; 3. Write mock loaded file data
    mov rdi, r14
    mov rsi, msg_pf_mock_data
    mov rdx, 31                     ; length of msg_pf_mock_data
    call memcpy

    ; Write the virtual address at offset 32 to verify
    mov [r14 + 32], r12

    ; 4. Map the physical page with VMA permissions
    mov rdx, [r13 + 16]             ; RDX = vma->flags
    xor rbx, rbx                    ; RBX = mapping flags

    test rdx, VMA_WRITE
    jz .no_write
    or rbx, PAGE_WRITABLE
.no_write:

    test rdx, VMA_USER
    jz .no_user
    or rbx, PAGE_USER
.no_user:

    test rdx, VMA_EXEC
    jnz .is_exec
    mov rcx, PAGE_NX
    or rbx, rcx
.is_exec:

    mov rdi, r12
    and rdi, -4096                  ; align virtual address to page
    mov rsi, r14                    ; physical address
    mov rdx, rbx                    ; flags
    call virt_map
    test rax, rax
    jz .map_fail

    mov rax, 1                      ; return 1 (success)
    jmp .done

.map_fail:
    mov rdi, r14
    call phys_free_page
.oom:
    xor rax, rax                    ; return 0 (failure)
.done:
    pop r14
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

msg_pf_mock_data:       db "TATTVA_OS_ONDEMAND_PAGE_LOADED", 0

%endif ; LIB_MEM_VIRT_PF_ASM
