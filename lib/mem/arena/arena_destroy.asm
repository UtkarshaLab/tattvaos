; =============================================================================
; Tattva OS — lib/mem/arena/arena_destroy.asm
; =============================================================================
; Arena Destroy: Releases the entire memory block of the arena to the heap.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_ARENA_ARENA_DESTROY_ASM
%define LIB_MEM_ARENA_ARENA_DESTROY_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern heap_free

; -----------------------------------------------------------------------------
; arena_destroy — destroys the arena and returns its memory to the heap
; Input:
;   RDI = pointer to the arena (arena_t)
; Output: none
; Clobbers: none (preserves all registers except volatile scratch registers)
; -----------------------------------------------------------------------------
global arena_destroy
arena_destroy:
    test rdi, rdi
    jz .exit

    ; Since the arena structure lives at the start of the allocated block,
    ; we simply pass the arena pointer itself to heap_free.
    call heap_free

.exit:
    ret

%endif ; LIB_MEM_ARENA_ARENA_DESTROY_ASM
