; =============================================================================
; Tattva OS — kernel/entry/init.asm
; =============================================================================
; Kernel early initialization sequence. Saves the BootInfo pointer, verifies
; CPU-local storage (GS base), and sequentially calls initialization stubs for
; core kernel subsystems.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

kernel_init:
    ; 1. Save BootInfo pointer in a global variable
    mov [boot_info_ptr], rdi

    ; 2. Print initial boot message
    mov rsi, msg_kernel_boot
    call uart_print_str

    ; 3. Print BootInfo physical address
    mov rsi, msg_boot_info_loc
    call uart_print_str
    mov rax, rdi
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 4. Verify GS Base initialization at runtime
    mov ecx, 0xC0000101             ; MSR_GS_BASE
    rdmsr                           ; EDX:EAX = GS Base
    shl rdx, 32
    or rax, rdx                     ; RAX = full 64-bit GS base
    
    mov rsi, msg_gs_base_loc
    call uart_print_str
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 4b. Initialize Exception Handlers (IDT)
    mov rsi, msg_init_idt
    call uart_print_str
    call interrupts_init
    mov rsi, msg_ok
    call uart_print_str

    ; 5. Initialize Memory Management
    mov rsi, msg_init_mm
    call uart_print_str
    call mm_init
    mov rsi, msg_ok
    call uart_print_str

    ; 6. Initialize Scheduler
    mov rsi, msg_init_sched
    call uart_print_str
    call sched_init
    mov rsi, msg_ok
    call uart_print_str

    ; 7. Initialize Device Drivers
    mov rsi, msg_init_drivers
    call uart_print_str
    call drivers_init
    mov rsi, msg_ok
    call uart_print_str

    ; 8. Initialize System Services
    mov rsi, msg_init_serve
    call uart_print_str
    call serve_init
    mov rsi, msg_ok
    call uart_print_str

    ; 9. Jump to the main kernel loop
    jmp kernel_main

; -----------------------------------------------------------------------------
; Subsystem Initialization Stubs
; (To be replaced by actual implementations in subsequent milestones)
; -----------------------------------------------------------------------------
mm_init:
    ; TODO: Implement physical page allocator E820 parsing under lib/mem/
    ret

sched_init:
    ; TODO: Implement task scheduler
    ret

drivers_init:
    ; TODO: Implement hardware drivers (keyboard, disk, network, etc.)
    ret

serve_init:
    ; TODO: Implement system security/serving layers
    ret

; -----------------------------------------------------------------------------
; Messages & Global Data
; -----------------------------------------------------------------------------
section .data

align 8
global boot_info_ptr
boot_info_ptr:      dq 0

msg_kernel_boot:     db "Tattva Kernel Booting...", 0x0D, 0x0A, 0
msg_boot_info_loc:   db "BootInfo Pointer: ", 0
msg_gs_base_loc:     db "GS Base register: ", 0
msg_init_idt:        db "Initializing Exception Handlers (IDT)... ", 0
msg_init_mm:         db "Initializing MM (Physical Allocator)... ", 0
msg_init_sched:      db "Initializing Scheduler... ", 0
msg_init_drivers:    db "Initializing Device Drivers... ", 0
msg_init_serve:      db "Initializing Services... ", 0
msg_ok:              db "OK", 0x0D, 0x0A, 0
msg_crlf:            db 0x0D, 0x0A, 0
