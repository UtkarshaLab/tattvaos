; =============================================================================
; Tattva OS — kernel/arch/x86_64/interrupts.asm
; =============================================================================
; Interrupt Descriptor Table (IDT) configuration and Exception Handling.
; Installs handlers for the 32 standard CPU exceptions, performs comprehensive
; register dumping on panic, and hooks into the survive warm-reload system.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef KERNEL_ARCH_X86_64_INTERRUPTS_ASM
%define KERNEL_ARCH_X86_64_INTERRUPTS_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; interrupts_init — configure early IDT and register exception handlers
; Input:  none
; Output: none
; Clobbers: none (preserves all)
; -----------------------------------------------------------------------------
interrupts_init:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; 1. Clear IDT space to zero (256 entries * 16 bytes = 4096 bytes)
    mov rdi, idt_start
    xor rax, rax
    mov rcx, 512                    ; 4096 / 8 = 512 quadwords
    cld
    rep stosq

    ; 2. Register first 32 CPU exception handlers
    xor rbx, rbx                    ; RBX = vector index
.loop_register:
    cmp rbx, 32
    jge .load_idt
    
    mov rdi, rbx                    ; vector index
    mov rsi, [isr_table + rbx * 8]  ; handler address
    
    ; Set IST index in RDX:
    ; 1 for vector 8 (#DF) -> IST 1
    ; 2 for vector 14 (#PF) -> IST 2
    ; 3 for vector 2 (NMI) -> IST 3
    ; 0 otherwise
    xor rdx, rdx
    cmp rbx, 8                      ; Double Fault
    je .set_df_ist
    cmp rbx, 14                     ; Page Fault
    je .set_pf_ist
    cmp rbx, 2                      ; NMI
    je .set_nmi_ist
    jmp .do_register
.set_df_ist:
    mov rdx, 1                      ; Use IST 1 (Double Fault Stack)
    jmp .do_register
.set_pf_ist:
    mov rdx, 2                      ; Use IST 2 (Page Fault Stack)
    jmp .do_register
.set_nmi_ist:
    mov rdx, 3                      ; Use IST 3 (NMI Stack)
.do_register:
    call register_idt_handler
    
    inc rbx
    jmp .loop_register

.load_idt:
    ; 2b. Register TLB shootdown ISR at vector 0xFB
    mov rdi, 0xFB                   ; vector 0xFB
    mov rsi, tlb_shootdown_isr      ; handler address
    xor rdx, rdx                    ; no IST
    call register_idt_handler

    ; 3. Load IDT limit/base structure
    lidt [idt_ptr]
    
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; register_idt_handler — write a 16-byte gate descriptor to the IDT
; Input:  RDI = vector index (0-255)
;         RSI = handler address (64-bit)
;         RDX = IST index (0-7)
; Output: nothing
; Clobbers: none
; -----------------------------------------------------------------------------
register_idt_handler:
    push rax
    push rbx
    push rcx
    push rsi

    ; Calculate descriptor address: idt_start + (RDI * 16)
    mov rbx, rdi
    shl rbx, 4                      ; RBX = index * 16
    add rbx, idt_start              ; RBX points to descriptor

    ; Write offset low (bits 0-15)
    mov ax, si                      ; AX = low 16 bits of RSI
    mov [rbx + 0], ax

    ; Write selector (SEL_CODE64 = 0x08)
    mov word [rbx + 2], 0x08

    ; Write IST (lower 3 bits written to byte 4)
    mov [rbx + 4], dl

    ; Write type_attr (0x8E: present, ring 0, 64-bit Interrupt Gate)
    mov byte [rbx + 5], 0x8E

    ; Write offset mid (bits 16-31)
    shr rsi, 16
    mov ax, si                      ; AX = bits 16-31 of RSI
    mov [rbx + 6], ax

    ; Write offset high (bits 32-63)
    shr rsi, 16                     ; ESI = bits 32-63 of RSI
    mov [rbx + 8], esi

    ; Write reserved field (0)
    mov dword [rbx + 12], 0

    pop rsi
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; kernel_panic — populate panic state and call survive recovery
; Input:  RDI = pointer to null-terminated panic reason string
;         RSI = crash RIP
; Output: never returns
; -----------------------------------------------------------------------------
kernel_panic:
    cli                             ; disable interrupts immediately

    ; 1. Store panic string pointer at 0x508
    mov [0x508], rdi

    ; 2. Store crash RIP at 0x510
    mov [0x510], rsi

    ; 3. Retrieve survive wakeup entry point from 0x500 (PANIC_VECTOR)
    mov rax, [0x500]
    test rax, rax
    jz .no_survive

    ; 4. Call survive recovery wakeup routine
    jmp rax

.no_survive:
    ; Fallback: print message and halt indefinitely
    mov rsi, msg_panic_fallback
    call uart_print_str
.halt:
    hlt
    jmp .halt

; -----------------------------------------------------------------------------
; ISR Common Handler
; Saves GP registers, dumps state to UART, and triggers kernel_panic.
; -----------------------------------------------------------------------------
common_isr_handler:
    ; Push GP registers in reverse order
    push rax                        ; RSP + 112
    push rbx                        ; RSP + 104
    push rcx                        ; RSP + 96
    push rdx                        ; RSP + 88
    push rsi                        ; RSP + 80
    push rdi                        ; RSP + 72
    push rbp                        ; RSP + 64
    push r8                         ; RSP + 56
    push r9                         ; RSP + 48
    push r10                        ; RSP + 40
    push r11                        ; RSP + 32
    push r12                        ; RSP + 24
    push r13                        ; RSP + 16
    push r14                        ; RSP + 8
    push r15                        ; RSP + 0

    ; 1. Print crash diagnostic banner
    mov rsi, msg_crash_banner
    call uart_print_str

    ; 2. Print exception name
    mov rsi, msg_exception_label
    call uart_print_str
    mov rbx, [rsp + 120]            ; load vector index
    cmp rbx, 32
    jl .get_name
    mov rsi, msg_unknown_exception
    jmp .print_name
.get_name:
    mov rsi, [exception_names_table + rbx * 8]
.print_name:
    call uart_print_str
    mov rsi, msg_crlf
    call uart_print_str

    ; 3. Print Error Code
    mov rsi, msg_err_code_label
    call uart_print_str
    mov rax, [rsp + 128]            ; error code
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 4. Print RIP
    mov rsi, msg_rip_label
    call uart_print_str
    mov rax, [rsp + 136]            ; faulting RIP
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 5. Print RSP
    mov rsi, msg_rsp_label
    call uart_print_str
    mov rax, [rsp + 160]            ; RSP at time of interrupt
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 6. Print general registers
    ; RAX & RBX
    mov rsi, msg_rax_rbx_label
    call uart_print_str
    mov rax, [rsp + 112]            ; RAX
    call uart_print_hex64
    mov rsi, msg_space
    call uart_print_str
    mov rax, [rsp + 104]            ; RBX
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; RCX & RDX
    mov rsi, msg_rcx_rdx_label
    call uart_print_str
    mov rax, [rsp + 96]             ; RCX
    call uart_print_hex64
    mov rsi, msg_space
    call uart_print_str
    mov rax, [rsp + 88]             ; RDX
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; RSI & RDI
    mov rsi, msg_rsi_rdi_label
    call uart_print_str
    mov rax, [rsp + 80]             ; RSI
    call uart_print_hex64
    mov rsi, msg_space
    call uart_print_str
    mov rax, [rsp + 72]             ; RDI
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; RBP
    mov rsi, msg_rbp_label
    call uart_print_str
    mov rax, [rsp + 64]             ; RBP
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; R8 & R9
    mov rsi, msg_r8_r9_label
    call uart_print_str
    mov rax, [rsp + 56]             ; R8
    call uart_print_hex64
    mov rsi, msg_space
    call uart_print_str
    mov rax, [rsp + 48]             ; R9
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; R10 & R11
    mov rsi, msg_r10_r11_label
    call uart_print_str
    mov rax, [rsp + 40]             ; R10
    call uart_print_hex64
    mov rsi, msg_space
    call uart_print_str
    mov rax, [rsp + 32]             ; R11
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; R12 & R13
    mov rsi, msg_r12_r13_label
    call uart_print_str
    mov rax, [rsp + 24]             ; R12
    call uart_print_hex64
    mov rsi, msg_space
    call uart_print_str
    mov rax, [rsp + 16]             ; R13
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; R14 & R15
    mov rsi, msg_r14_r15_label
    call uart_print_str
    mov rax, [rsp + 8]              ; R14
    call uart_print_hex64
    mov rsi, msg_space
    call uart_print_str
    mov rax, [rsp + 0]              ; R15
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; Control registers (CR2, CR3, CR4)
    mov rsi, msg_cr2_cr3_label
    call uart_print_str
    mov rax, cr2
    call uart_print_hex64
    mov rsi, msg_space
    call uart_print_str
    mov rax, cr3
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; Call stack trace walker to print backtrace (Subfeature 20.5)
    extern stack_trace_walk
    mov rdi, [rsp + 64]             ; RDI = RBP at exception entry
    call stack_trace_walk

    ; 7. Trigger the warm restart / survive log
    mov rbx, [rsp + 120]            ; vector
    cmp rbx, 32
    jl .get_panic_reason
    mov rdi, msg_unknown_exception
    jmp .panic
.get_panic_reason:
    mov rdi, [exception_names_table + rbx * 8]
.panic:
    mov rsi, [rsp + 136]            ; RIP
    call kernel_panic

    ; Halt if panic fallback executes
    cli
.halt:
    hlt
    jmp .halt

; -----------------------------------------------------------------------------
; Exception Vector Entry Points (ISRs 0 to 31)
; -----------------------------------------------------------------------------
%macro no_error_code_isr 1
isr_%1:
    push qword 0                    ; dummy error code
    push qword %1                   ; vector index
    jmp common_isr_handler
%endmacro

%macro error_code_isr 1
isr_%1:
    ; CPU automatically pushed the error code
    push qword %1                   ; vector index
    jmp common_isr_handler
%endmacro

no_error_code_isr 0
no_error_code_isr 1
no_error_code_isr 2
no_error_code_isr 3
no_error_code_isr 4
no_error_code_isr 5
no_error_code_isr 6
no_error_code_isr 7
error_code_isr    8
no_error_code_isr 9
error_code_isr    10
error_code_isr    11
error_code_isr    12
error_code_isr    13
error_code_isr    14
no_error_code_isr 15
no_error_code_isr 16
error_code_isr    17
no_error_code_isr 18
no_error_code_isr 19
no_error_code_isr 20
error_code_isr    21
no_error_code_isr 22
no_error_code_isr 23
no_error_code_isr 24
no_error_code_isr 25
no_error_code_isr 26
no_error_code_isr 27
no_error_code_isr 28
no_error_code_isr 29
error_code_isr    30
no_error_code_isr 31

; -----------------------------------------------------------------------------
; IDT Data & Names
; -----------------------------------------------------------------------------
section .data

align 8
idt_ptr:
    .limit  dw 4095                 ; 256 entries * 16 bytes - 1
    .base   dq idt_start            ; base pointer

align 8
isr_table:
    dq isr_0, isr_1, isr_2, isr_3, isr_4, isr_5, isr_6, isr_7
    dq isr_8, isr_9, isr_10, isr_11, isr_12, isr_13, page_fault_isr, isr_15
    dq isr_16, isr_17, isr_18, isr_19, isr_20, isr_21, isr_22, isr_23
    dq isr_24, isr_25, isr_26, isr_27, isr_28, isr_29, isr_30, isr_31

exception_name_0:  db "Division Error (#DE)", 0
exception_name_1:  db "Debug Exception (#DB)", 0
exception_name_2:  db "Non-Maskable Interrupt", 0
exception_name_3:  db "Breakpoint (#BP)", 0
exception_name_4:  db "Overflow (#OF)", 0
exception_name_5:  db "Bound Range Exceeded (#BR)", 0
exception_name_6:  db "Invalid Opcode (#UD)", 0
exception_name_7:  db "Device Not Available (#NM)", 0
exception_name_8:  db "Double Fault (#DF)", 0
exception_name_9:  db "Coprocessor Segment Overrun", 0
exception_name_10: db "Invalid TSS (#TS)", 0
exception_name_11: db "Segment Not Present (#NP)", 0
exception_name_12: db "Stack-Segment Fault (#SS)", 0
exception_name_13: db "General Protection Fault (#GP)", 0
exception_name_14: db "Page Fault (#PF)", 0
exception_name_15: db "Reserved Exception (15)", 0
exception_name_16: db "x87 Floating-Point Exception (#MF)", 0
exception_name_17: db "Alignment Check (#AC)", 0
exception_name_18: db "Machine Check (#MC)", 0
exception_name_19: db "SIMD Floating-Point Exception (#XM)", 0
exception_name_20: db "Virtualization Exception (#VE)", 0
exception_name_21: db "Control Protection Exception (#CP)", 0
exception_name_22: db "Reserved Exception (22)", 0
exception_name_23: db "Reserved Exception (23)", 0
exception_name_24: db "Reserved Exception (24)", 0
exception_name_25: db "Reserved Exception (25)", 0
exception_name_26: db "Reserved Exception (26)", 0
exception_name_27: db "Reserved Exception (27)", 0
exception_name_28: db "Hypervisor Injection Exception", 0
exception_name_29: db "VMM Communication Exception", 0
exception_name_30: db "Security Exception (#SX)", 0
exception_name_31: db "Reserved Exception (31)", 0

align 8
exception_names_table:
    dq exception_name_0, exception_name_1, exception_name_2, exception_name_3
    dq exception_name_4, exception_name_5, exception_name_6, exception_name_7
    dq exception_name_8, exception_name_9, exception_name_10, exception_name_11
    dq exception_name_12, exception_name_13, exception_name_14, exception_name_15
    dq exception_name_16, exception_name_17, exception_name_18, exception_name_19
    dq exception_name_20, exception_name_21, exception_name_22, exception_name_23
    dq exception_name_24, exception_name_25, exception_name_26, exception_name_27
    dq exception_name_28, exception_name_29, exception_name_30, exception_name_31

msg_crash_banner:      db 0x0D, 0x0A, "================================================", 0x0D, 0x0A
                       db "  KERNEL PANIC: EXCEPTION TRIGGERED", 0x0D, 0x0A
                       db "================================================", 0x0D, 0x0A, 0
msg_exception_label:   db "Exception:   ", 0
msg_err_code_label:    db "Error Code:  ", 0
msg_rip_label:         db "RIP:         ", 0
msg_rsp_label:         db "RSP:         ", 0
msg_rax_rbx_label:     db "RAX / RBX:   ", 0
msg_rcx_rdx_label:     db "RCX / RDX:   ", 0
msg_rsi_rdi_label:     db "RSI / RDI:   ", 0
msg_rbp_label:         db "RBP:         ", 0
msg_r8_r9_label:       db "R8  / R9:    ", 0
msg_r10_r11_label:     db "R10 / R11:   ", 0
msg_r12_r13_label:     db "R12 / R13:   ", 0
msg_r14_r15_label:     db "R14 / R15:   ", 0
msg_cr2_cr3_label:     db "CR2 / CR3:   ", 0
msg_unknown_exception: db "Unknown Exception", 0
msg_panic_fallback:    db "!!! FATAL PANIC: Survive system not available. Halting.", 0x0D, 0x0A, 0
msg_crlf:              db 0x0D, 0x0A, 0
msg_space:             db "   ", 0

; -----------------------------------------------------------------------------
; IDT Memory Space
; -----------------------------------------------------------------------------
section .bss
align 16
idt_start:
    resb 4096                       ; 256 descriptors * 16 bytes = 4096 bytes

%endif ; KERNEL_ARCH_X86_64_INTERRUPTS_ASM
