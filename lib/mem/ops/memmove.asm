; =============================================================================
; Tattva OS — lib/mem/ops/memmove.asm
; =============================================================================
; AVX2-optimized memmove implementation, safe for overlapping memory regions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_OPS_MEMMOVE_ASM
%define LIB_MEM_OPS_MEMMOVE_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; memmove — copies RDX bytes from RSI to RDI, handling overlaps safely
; Input:
;   RDI = destination pointer
;   RSI = source pointer
;   RDX = byte count
; Output:
;   RAX = destination pointer (RDI)
; Clobbers: R8, RCX, RDX, RSI, RDI, YMM0
; -----------------------------------------------------------------------------
global memmove
memmove:
    mov rax, rdi                    ; RAX = destination pointer (return value)
    cmp rdx, 0
    je .done
    cmp rsi, rdi
    je .done                        ; src == dest, nothing to do

    ; Detect overlap requiring reverse copy:
    ; if (dest > src && dest < src + count) we must copy in reverse
    cmp rdi, rsi
    jbe .forward_copy               ; dest <= src, safe for forward copy
    
    mov r8, rsi
    add r8, rdx                     ; R8 = src + count
    cmp rdi, r8
    jae .forward_copy               ; dest >= src + count, safe for forward copy

    ; -------------------------------------------------------------------------
    ; Reverse Copy (overlapping)
    ; -------------------------------------------------------------------------
    add rsi, rdx                    ; point to the end of source
    add rdi, rdx                    ; point to the end of destination

    cmp rdx, 32
    jb .copy_sub32_rev

    mov rcx, rdx
    shr rcx, 5                      ; RCX = number of 32-byte blocks
    and rdx, 31                     ; RDX = remaining bytes

.loop32_rev:
    sub rsi, 32
    sub rdi, 32
    vmovdqu ymm0, [rsi]             ; load 32 bytes (unaligned)
    vmovdqu [rdi], ymm0             ; store 32 bytes (unaligned)
    dec rcx
    jnz .loop32_rev

.copy_sub32_rev:
    test rdx, rdx
    jz .done

.sub32_loop_rev:
    dec rsi
    dec rdi
    mov r8b, [rsi]
    mov [rdi], r8b
    dec rdx
    jnz .sub32_loop_rev
    jmp .done

    ; -------------------------------------------------------------------------
    ; Forward Copy (non-overlapping)
    ; -------------------------------------------------------------------------
.forward_copy:
    call memcpy                     ; use optimized forward memcpy

.done:
    ret

%endif ; LIB_MEM_OPS_MEMMOVE_ASM
