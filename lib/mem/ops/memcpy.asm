; =============================================================================
; Tattva OS — lib/mem/ops/memcpy.asm
; =============================================================================
; AVX2-optimized memcpy implementation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_OPS_MEMCPY_ASM
%define LIB_MEM_OPS_MEMCPY_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; memcpy — copies RDX bytes from RSI to RDI using AVX2 (256-bit SIMD)
; Input:
;   RDI = destination pointer
;   RSI = source pointer
;   RDX = byte count
; Output:
;   RAX = destination pointer (RDI)
; Clobbers: R8, RCX, RDX, RSI, RDI, YMM0
; -----------------------------------------------------------------------------
global memcpy
memcpy:
    mov rax, rdi                    ; RAX = destination pointer (return value)
    cmp rdx, 0
    je .done

    ; Check if we have at least 32 bytes to copy
    cmp rdx, 32
    jb .copy_sub32

    ; Loop to copy 32-byte blocks
    mov rcx, rdx
    shr rcx, 5                      ; RCX = number of 32-byte blocks (count / 32)
    and rdx, 31                     ; RDX = remaining bytes (count % 32)

.loop32:
    vmovdqu ymm0, [rsi]             ; load 32 bytes (unaligned)
    vmovdqu [rdi], ymm0             ; store 32 bytes (unaligned)
    add rsi, 32
    add rdi, 32
    dec rcx
    jnz .loop32

.copy_sub32:
    ; Copy remaining bytes (RDX < 32)
    ; Check for 16 bytes
    test rdx, 16
    jz .check_8
    vmovdqu xmm0, [rsi]
    vmovdqu [rdi], xmm0
    add rsi, 16
    add rdi, 16

.check_8:
    test rdx, 8
    jz .check_4
    mov r8, [rsi]
    mov [rdi], r8
    add rsi, 8
    add rdi, 8

.check_4:
    test rdx, 4
    jz .check_2
    mov r8d, [rsi]
    mov [rdi], r8d
    add rsi, 4
    add rdi, 4

.check_2:
    test rdx, 2
    jz .check_1
    mov r8w, [rsi]
    mov [rdi], r8w
    add rsi, 2
    add rdi, 2

.check_1:
    test rdx, 1
    jz .done
    mov r8b, [rsi]
    mov [rdi], r8b

.done:
    ret

%endif ; LIB_MEM_OPS_MEMCPY_ASM
