; =============================================================================
; Tattva OS — lib/mem/ops/memset.asm
; =============================================================================
; AVX2-optimized memset implementation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_OPS_MEMSET_ASM
%define LIB_MEM_OPS_MEMSET_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; memset — fills RDX bytes at RDI with byte value in RSI
; Input:
;   RDI = destination pointer
;   RSI = byte value to fill (only lowest 8 bits SIL are used)
;   RDX = byte count
; Output:
;   RAX = destination pointer (RDI)
; Clobbers: R8, R9, RCX, RDX, RDI, YMM0, XMM0
; -----------------------------------------------------------------------------
global memset
memset:
    mov rax, rdi                    ; RAX = destination pointer (return value)
    cmp rdx, 0
    je .done

    ; Broadcast the byte value in RSI (SIL) to R8 (64-bit register filled with SIL)
    movzx r8, sil
    mov r9, 0x0101010101010101
    imul r8, r9                     ; R8 = SIL repeated 8 times

    ; Initialize XMM0 with the broadcasted byte
    vmovq xmm0, r8
    vpbroadcastb xmm0, xmm0

    ; Check if we have at least 32 bytes to fill
    cmp rdx, 32
    jb .fill_sub32

    ; Initialize YMM0 for the 32-byte loop
    vpbroadcastb ymm0, xmm0

    mov rcx, rdx
    shr rcx, 5                      ; RCX = number of 32-byte blocks
    and rdx, 31                     ; RDX = remaining bytes

.loop32:
    vmovdqu [rdi], ymm0             ; store 32 bytes
    add rdi, 32
    dec rcx
    jnz .loop32

.fill_sub32:
    ; Fill remaining bytes (RDX < 32)
    ; Check for 16 bytes
    test rdx, 16
    jz .check_8
    vmovdqu [rdi], xmm0
    add rdi, 16

.check_8:
    test rdx, 8
    jz .check_4
    mov [rdi], r8
    add rdi, 8

.check_4:
    test rdx, 4
    jz .check_2
    mov [rdi], r8d
    add rdi, 4

.check_2:
    test rdx, 2
    jz .check_1
    mov [rdi], r8w
    add rdi, 2

.check_1:
    test rdx, 1
    jz .done
    mov [rdi], r8b

.done:
    ret

%endif ; LIB_MEM_OPS_MEMSET_ASM
