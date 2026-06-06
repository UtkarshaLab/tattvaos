; =============================================================================
; Tattva OS — lib/mem/arena/arena_reset.asm
; =============================================================================
; Arena Reset: Resets the bump pointer back to start (Subfeature 12.2: O(1) Bulk Deallocations).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_ARENA_ARENA_RESET_ASM
%define LIB_MEM_ARENA_ARENA_RESET_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; arena_reset — resets the arena current pointer back to start (bulk free)
; Input:
;   RDI = pointer to the arena (arena_t)
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
global arena_reset
arena_reset:
    test rdi, rdi
    jz .exit

    ; Reset current bump pointer to the start address
    mov rax, [rdi + arena_t.start]
    mov [rdi + arena_t.current], rax

.exit:
    ret

%endif ; LIB_MEM_ARENA_ARENA_RESET_ASM
