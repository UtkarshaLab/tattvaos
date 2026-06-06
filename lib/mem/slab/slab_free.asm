; =============================================================================
; Tattva OS — lib/mem/slab/slab_free.asm
; =============================================================================
; Slab Allocator Freeing function stub (Subfeature 10.1).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_SLAB_SLAB_FREE_ASM
%define LIB_MEM_SLAB_SLAB_FREE_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; kmem_cache_free — returns an allocated object back to the slab cache
; Input:
;   RDI = pointer to cache descriptor (kmem_cache_t)
;   RSI = pointer to object memory to free
; Output: none
; -----------------------------------------------------------------------------
global kmem_cache_free
kmem_cache_free:
    ; Stub: no-op for initial cache definitions phase
    ret

%endif ; LIB_MEM_SLAB_SLAB_FREE_ASM
