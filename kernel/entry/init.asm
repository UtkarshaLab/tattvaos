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

%include "lib/mem/mem.inc"

section .text

kernel_init:
    ; 1. Save BootInfo pointer in a global variable
    mov [boot_info_ptr], rdi

    ; 1b. Load SMP active cores count from BootInfo structure (offset 80)
    mov eax, [rdi + 80]             ; load core count
    test eax, eax                   ; check if 0
    jnz .store_cores
    mov eax, 1                      ; default to 1 core
.store_cores:
    mov [smp_active_cores], eax

    ; 2. Initialize Kernel GDT & TSS (with IST stack overflow protection)
    call gdt_init

    ; 3. Print initial boot message
    mov rsi, msg_kernel_boot
    call uart_print_str

    ; 3b. Print GDT/TSS init status
    mov rsi, msg_init_gdt
    call uart_print_str
    mov rsi, msg_ok
    call uart_print_str

    ; 4. Print BootInfo physical address
    mov rsi, msg_boot_info_loc
    call uart_print_str
    mov rax, rdi
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 5. Verify GS Base initialization at runtime
    mov ecx, 0xC0000101             ; MSR_GS_BASE
    rdmsr                           ; EDX:EAX = GS Base
    shl rdx, 32
    or rax, rdx                     ; RAX = full 64-bit GS base
    
    mov rsi, msg_gs_base_loc
    call uart_print_str
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 5a. Test CPU-local GS Segment Accessors
    mov rsi, msg_gs_api_test
    call uart_print_str
    call cpu_get_id                 ; EAX = cpu_id
    call uart_print_dec
    mov al, '/'                     ; separator
    call uart_putc
    call cpu_get_stack_top          ; RAX = stack_top
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 5b. Initialize early CPU hardware and verify mandatory vector features
    mov rsi, msg_init_cpu
    call uart_print_str
    call cpu_init_hardware

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
    call phys_init

    ; 1. Mark kernel code/data as global (1MB to kernel_end)
    mov rdi, 0x100000               ; kernel start: 1MB
    mov rsi, kernel_end
    sub rsi, 0x100000               ; kernel size
    call virt_mark_global_range

    ; 2. Mark physical allocator bitmap as global
    mov rdi, [phys_state + phys_state_t.bitmap_addr]
    mov rsi, [phys_state + phys_state_t.bitmap_size]
    call virt_mark_global_range

    ; 3. Allocate 1024 pages (4MB) for kernel early bump heap
    mov rdi, 1024
    call phys_alloc_pages
    test rax, rax
    jz .error

    ; Save heap start address
    push rax

    ; 4. Mark early heap as global
    mov rdi, rax
    mov rsi, 1024 * 4096            ; 4MB size
    call virt_mark_global_range

    pop rax                         ; restore heap start address

    mov rdi, rax
    mov rsi, 1024 * 4096            ; 4MB size
    call heap_init
    call page_list_init
    call swap_init
    call kswapd_init
    call heap_transition
    call kmem_cache_init_all
    ret


.error:
    cli
    hlt
    jmp .error

sched_init:
    ; TODO: Implement task scheduler
    ret

drivers_init:
    ; TODO: Implement hardware drivers (keyboard, disk, network, etc.)
    ret

serve_init:
    ; TODO: Implement system security/serving layers
    ret

sys_handler:
    ; stub system call handler for syscall interface
    sysretq

; -----------------------------------------------------------------------------
; Messages & Global Data
; -----------------------------------------------------------------------------
section .data

align 8
global boot_info_ptr
boot_info_ptr:      dq 0

msg_kernel_boot:     db "Tattva Kernel Booting...", 0x0D, 0x0A, 0
msg_init_gdt:        db "Initializing Kernel GDT/TSS... ", 0
msg_boot_info_loc:   db "BootInfo Pointer: ", 0
msg_gs_base_loc:     db "GS Base register: ", 0
msg_gs_api_test:     db "GS Accessor Test (CPU/Stack): ", 0
msg_init_cpu:        db "Initializing CPU hardware & features... ", 0
msg_init_idt:        db "Initializing Exception Handlers (IDT)... ", 0
msg_init_mm:         db "Initializing MM (Physical Allocator)... ", 0
msg_init_sched:      db "Initializing Scheduler... ", 0
msg_init_drivers:    db "Initializing Device Drivers... ", 0
msg_init_serve:      db "Initializing Services... ", 0
msg_ok:              db "OK", 0x0D, 0x0A, 0
msg_crlf:            db 0x0D, 0x0A, 0
