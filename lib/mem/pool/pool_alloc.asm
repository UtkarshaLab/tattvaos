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

    push rbx

    ; Load initial head and tag to expected registers RDX:RAX
    mov rax, [rdi + pool_t.free_head]
    mov rdx, [rdi + pool_t.free_tag]

.retry:
    test rax, rax
    jz .fail_pop                    ; if free_head is NULL, pool is exhausted

    ; Read next pointer from first 8 bytes of expected free slot
    mov rbx, [rax]                  ; RBX = new_head (next slot)

    ; Increment expected tag to form new tag
    mov rcx, rdx
    inc rcx                         ; RCX = new_tag = tag + 1

    ; Perform double-width Compare-And-Swap
    lock cmpxchg16b [rdi + pool_t.free_head]
    jnz .retry                      ; if ZF = 0, retry with updated RDX:RAX

    ; CAS succeeded! Increment used count atomically
    lock inc qword [rdi + pool_t.count]

    pop rbx
    ret

.fail_pop:
    pop rbx
.fail:
    xor rax, rax
    ret

%endif ; LIB_MEM_POOL_POOL_ALLOC_ASM
