; =============================================================================
; Tattva OS — kernel/entry/start.asm
; =============================================================================
; Kernel startup logic. Reloads segment registers, sets up the 16KB aligned
; kernel stack, and configures the GS base register for CPU-local storage.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; kernel_start — first instructions executed inside kernel_entry
; -----------------------------------------------------------------------------
    ; 1. Reload 64-bit data segment registers (SEL_DATA64 = 0x10)
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; 2. Set up the aligned kernel stack
    mov rsp, kernel_stack_top

    ; 3. Preserve the BootInfo pointer passed in RDI
    push rdi

    ; 4. Initialize GS base MSR to point to BSP's CPU-local structure
    mov ecx, 0xC0000101             ; MSR_GS_BASE
    mov rax, bsp_cpu_local          ; low 32 bits
    mov rdx, rax
    shr rdx, 32                     ; high 32 bits (EDX:EAX)
    wrmsr

    ; 5. Sanitize CPU general purpose registers (excluding RSP/RDI)
    call cpu_clear_gprs

    ; 6. Restore BootInfo pointer and jump to early initialization
    pop rdi
    jmp kernel_init

; -----------------------------------------------------------------------------
; CPU-local Data Structures
; -----------------------------------------------------------------------------
section .data
align 8
bsp_cpu_local:
    .self        dq bsp_cpu_local   ; pointer to self (standard GS self-reference)
    .cpu_id      dd 0               ; CPU ID 0 for BSP
    .reserved    dd 0               ; explicit alignment padding
    .stack_top   dq kernel_stack_top; kernel stack top address

; -----------------------------------------------------------------------------
; Kernel Stack allocation
; -----------------------------------------------------------------------------
section .bss
align 16
kernel_stack_bottom:
    resb 16384                      ; 16KB stack allocation
kernel_stack_top:
