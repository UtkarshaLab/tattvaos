; =============================================================================
; Tattva OS — lib/mem/pool/pool_alloc.asm
; =============================================================================
; Pool Allocation: Pops a free slot from the intrusive stack-based free list.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_POOL_POOL_ALLOC_ASM
%define LIB_MEM_POOL_POOL_ALLOC_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; pool_alloc — allocates a slot from the pool in O(1) time
; Input:
;   RDI = pointer to the pool (pool_t)
; Output:
;   RAX = pointer to the allocated slot, or 0 if exhausted or invalid pool
; Clobbers: none (preserves non-volatile registers)
; -----------------------------------------------------------------------------
global pool_alloc
pool_alloc:
    ; Validate pool pointer
    test rdi, rdi
    jz .fail

    ; Retrieve the head of the free list
    mov rax, [rdi + pool_t.free_head]
    test rax, rax
    jz .fail                        ; if free_head is NULL, pool is exhausted

    ; Pop the head slot from the free list
    ; Read the next free slot address from the first 8 bytes of the current free slot
    mov rdx, [rax]                  ; RDX = next free slot address
    mov [rdi + pool_t.free_head], rdx ; pool.free_head = next

    ; Increment the active count
    inc qword [rdi + pool_t.count]

    ret

.fail:
    xor rax, rax
    ret

%endif ; LIB_MEM_POOL_POOL_ALLOC_ASM
