; =============================================================================
; Tattva OS — kernel/arch/x86_64/cpu.asm
; =============================================================================
; CPU feature verification and validation.
; Verifies SSE3, AVX, AVX2, and FMA support required for the umath GEMM stack.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef KERNEL_ARCH_X86_64_CPU_ASM
%define KERNEL_ARCH_X86_64_CPU_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; cpu_verify_features — check for mandatory SIMD/AVX2 instruction sets
; Input:  none
; Output: none (halts on failure)
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
cpu_verify_features:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    ; 1. Query CPUID Leaf 1 (Feature Information)
    mov eax, 1
    cpuid                           ; clobbers EAX, EBX, ECX, EDX

    ; Check SSE3: ECX bit 0
    test ecx, 1 << 0
    jz .err_sse3

    ; Check FMA3: ECX bit 12
    test ecx, 1 << 12
    jz .err_fma

    ; Check AVX: ECX bit 28
    test ecx, 1 << 28
    jz .err_avx

    ; 2. Query CPUID Leaf 7, Sub-leaf 0 (Extended Features)
    mov eax, 7
    xor ecx, ecx
    cpuid                           ; clobbers EAX, EBX, ECX, EDX

    ; Check AVX2: EBX bit 5
    test ebx, 1 << 5
    jz .err_avx2

    ; 3. If all checks pass, print confirmation and return
    mov rsi, .msg_cpu_ok
    call uart_print_str

    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; cpu_get_local — get the base address of the current CPU-local structure
; Input:  none
; Output: RAX = pointer to CPU-local structure
; Clobbers: none (preserves all other registers)
; -----------------------------------------------------------------------------
cpu_get_local:
    mov rax, [gs:0]                 ; offset 0 is .self pointer
    ret

; -----------------------------------------------------------------------------
; cpu_get_id — get the CPU ID of the running processor
; Input:  none
; Output: EAX = CPU ID
; Clobbers: none
; -----------------------------------------------------------------------------
cpu_get_id:
    mov eax, [gs:8]                 ; offset 8 is .cpu_id
    ret

; -----------------------------------------------------------------------------
; cpu_get_stack_top — get the kernel stack top of the running processor
; Input:  none
; Output: RAX = stack top address
; Clobbers: none
; -----------------------------------------------------------------------------
cpu_get_stack_top:
    mov rax, [gs:16]                ; offset 16 is .stack_top
    ret

.err_sse3:
    mov rsi, .msg_err_sse3
    jmp .panic
.err_fma:
    mov rsi, .msg_err_fma
    jmp .panic
.err_avx:
    mov rsi, .msg_err_avx
    jmp .panic
.err_avx2:
    mov rsi, .msg_err_avx2
    jmp .panic

.panic:
    call uart_print_str
    cli
.halt:
    hlt
    jmp .halt

section .data
.msg_cpu_ok:    db "CPU features verified (SSE3, AVX, AVX2, FMA).", 0x0D, 0x0A, 0
.msg_err_sse3:  db "!!! KERNEL PANIC: Missing CPU feature: SSE3 required !!!", 0x0D, 0x0A, 0
.msg_err_fma:   db "!!! KERNEL PANIC: Missing CPU feature: FMA3 required !!!", 0x0D, 0x0A, 0
.msg_err_avx:   db "!!! KERNEL PANIC: Missing CPU feature: AVX required !!!", 0x0D, 0x0A, 0
.msg_err_avx2:  db "!!! KERNEL PANIC: Missing CPU feature: AVX2 required !!!", 0x0D, 0x0A, 0

%endif ; KERNEL_ARCH_X86_64_CPU_ASM
