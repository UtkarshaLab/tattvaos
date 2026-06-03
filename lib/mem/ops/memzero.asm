; =============================================================================
; Tattva OS — lib/mem/ops/memzero.asm
; =============================================================================
; AVX2-optimized memzero implementation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_OPS_MEMZERO_ASM
%define LIB_MEM_OPS_MEMZERO_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; memzero — clears RSI bytes at RDI to 0 using AVX2 (256-bit SIMD)
; Input:
;   RDI = destination pointer
;   RSI = byte count
; Output:
;   RAX = destination pointer (RDI)
; Clobbers: R8, RCX, RSI, RDI, YMM0, XMM0
; -----------------------------------------------------------------------------
global memzero
memzero:
    mov rax, rdi                    ; RAX = destination pointer (return value)
    cmp rsi, 0
    je .done

    ; Clear YMM0 to all zeros
    vxorps ymm0, ymm0, ymm0

    ; Check if we have at least 32 bytes to zero
    cmp rsi, 32
    jb .zero_sub32

    mov rcx, rsi
    shr rcx, 5                      ; RCX = number of 32-byte blocks
    and rsi, 31                     ; RSI = remaining bytes

.loop32:
    vmovdqu [rdi], ymm0             ; store 32 bytes of zeros
    add rdi, 32
    dec rcx
    jnz .loop32

.zero_sub32:
    ; Zero remaining bytes (RSI < 32)
    ; Check for 16 bytes
    test rsi, 16
    jz .check_8
    vmovdqu [rdi], xmm0             ; store 16 bytes of zeros (lower 128-bits of YMM0)
    add rdi, 16

.check_8:
    test rsi, 8
    jz .check_4
    xor r8, r8
    mov [rdi], r8
    add rdi, 8

.check_4:
    test rsi, 4
    jz .check_2
    xor r8d, r8d
    mov [rdi], r8d
    add rdi, 4

.check_2:
    test rsi, 2
    jz .check_1
    xor r8w, r8w
    mov [rdi], r8w
    add rdi, 2

.check_1:
    test rsi, 1
    jz .done
    mov byte [rdi], 0

.done:
    ret

%endif ; LIB_MEM_OPS_MEMZERO_ASM
