; =============================================================================
; Tattva OS — lib/mem/slab/slab_alloc.asm
; =============================================================================
; Slab Allocator Allocation function stub (Subfeature 10.1).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_SLAB_SLAB_ALLOC_ASM
%define LIB_MEM_SLAB_SLAB_ALLOC_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; kmem_cache_alloc — allocates a single object from the slab cache
; Input:
;   RDI = pointer to cache descriptor (kmem_cache_t)
; Output:
;   RAX = pointer to allocated object, or 0 if OOM
; -----------------------------------------------------------------------------
global kmem_cache_alloc
kmem_cache_alloc:
    ; Stub: returns 0 (OOM) for initial cache definitions phase
    xor rax, rax
    ret

%endif ; LIB_MEM_SLAB_SLAB_ALLOC_ASM
