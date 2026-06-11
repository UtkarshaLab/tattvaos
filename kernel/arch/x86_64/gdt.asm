; =============================================================================
; Tattva OS — kernel/arch/x86_64/gdt.asm
; =============================================================================
; Global Descriptor Table (GDT) and Task State Segment (TSS) initialization.
; Sets up the kernel GDT and loads the TSS with an Emergency Stack for IST 1.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef KERNEL_ARCH_X86_64_GDT_ASM
%define KERNEL_ARCH_X86_64_GDT_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; gdt_init — load kernel GDT and initialize Task State Segment (TSS)
; Input:  none
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
gdt_init:
    push rax
    push rbx
    push rcx

    ; 1. Initialize TSS structure fields
    ; Clear TSS memory to 0
    mov rdi, kernel_tss
    xor rax, rax
    mov rcx, 13                     ; 104 / 8 = 13 quadwords
    cld
    rep stosq

    ; Set IST1 stack pointer (Double Fault)
    mov rax, double_fault_stack_top
    mov [kernel_tss + 36], rax       ; tss.ist1 (offset 36)

    ; Set IST2 stack pointer (Page Fault)
    mov rax, page_fault_stack_top
    mov [kernel_tss + 44], rax       ; tss.ist2 (offset 44)

    ; Set IST3 stack pointer (NMI)
    mov rax, nmi_stack_top
    mov [kernel_tss + 52], rax       ; tss.ist3 (offset 52)
    
    ; Set I/O map base to 104 (no I/O map)
    mov word [kernel_tss + 102], 104 ; tss.iomap_base (offset 102)

    ; 2. Initialize the 16-byte TSS descriptor in GDT dynamically
    ; TSS Descriptor Base = kernel_tss
    mov rax, kernel_tss
    mov rbx, kernel_gdt + 40        ; RBX points to TSS descriptor (selector 0x28)

    ; Limit = sizeof(tss) - 1 = 103
    mov word [rbx + 0], 103

    ; Base low (0-15)
    mov [rbx + 2], ax

    ; Base mid (16-23)
    shr rax, 16
    mov [rbx + 4], al

    ; Access byte (0x89: present, 64-bit available TSS, DPL=0)
    mov byte [rbx + 5], 0x89

    ; Limit high + flags (0x00: Limit 16-19 = 0, Granularity=0, L=0, AVL=0)
    mov byte [rbx + 6], 0x00

    ; Base mid-high (24-31)
    shr rax, 8
    mov [rbx + 7], al

    ; Base high (32-63)
    shr rax, 8
    mov [rbx + 8], eax

    ; Reserved (0)
    mov dword [rbx + 12], 0

    ; 3. Load the new GDT
    lgdt [gdt_ptr]

    ; 4. Reload segment registers to use new descriptors
    mov ax, 0x10                    ; Kernel Data selector (0x10)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; 5. Reload CS register via lretq (64-bit far return)
    push qword 0x08                 ; new CS selector (SEL_CODE64 = 0x08)
    lea rax, [rel .reload_cs]       ; reload destination address
    push rax
    lretq                           ; far return to reload CS
.reload_cs:

    ; 6. Load Task Register (TSS selector = 0x28)
    mov ax, 0x28
    ltr ax

    pop rcx
    pop rbx
    pop rax
    ret

section .data

align 8
gdt_ptr:
    .limit dw 55                    ; 5 descriptors * 8 + 1 TSS * 16 - 1 = 55 bytes
    .base  dq kernel_gdt

align 16
kernel_gdt:
    ; Descriptor 0: Null Descriptor
    dq 0
    ; Descriptor 1: Kernel Code 64 (0x08)
    dq 0x00209A0000000000           ; Access=0x9A (Execute/Read, DPL=0, Code), Flags=0x2 (L=1)
    ; Descriptor 2: Kernel Data 64 (0x10)
    dq 0x0000920000000000           ; Access=0x92 (Read/Write, DPL=0, Data)
    ; Descriptor 3: User Data 64 (0x18)
    dq 0x0000F20000000000           ; Access=0xF2 (Read/Write, DPL=3, Data)
    ; Descriptor 4: User Code 64 (0x20)
    dq 0x0020FA0000000000           ; Access=0xFA (Execute/Read, DPL=3, Code), Flags=0x2 (L=1)
    ; Descriptor 5-6: TSS Descriptor (0x28) (16 bytes, initialized dynamically)
    dq 0
    dq 0

section .bss

align 16
kernel_tss:
    resb 104                        ; 64-bit TSS structure space

align 16
double_fault_stack_bottom:
    resb 4096                       ; 4KB Emergency Stack for IST 1 (Double Fault)
double_fault_stack_top:

align 16
page_fault_stack_bottom:
    resb 4096                       ; 4KB Emergency Stack for IST 2 (Page Fault)
page_fault_stack_top:

align 16
nmi_stack_bottom:
    resb 4096                       ; 4KB Emergency Stack for IST 3 (NMI)
nmi_stack_top:

%endif ; KERNEL_ARCH_X86_64_GDT_ASM
