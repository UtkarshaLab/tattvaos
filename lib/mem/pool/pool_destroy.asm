; =============================================================================
; Tattva OS — lib/mem/pool/pool_destroy.asm
; =============================================================================
; Pool Destroyer: Walks the block list, reclaiming physical pages and the initial
; heap allocation before freeing the pool descriptor.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_POOL_POOL_DESTROY_ASM
%define LIB_MEM_POOL_POOL_DESTROY_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern heap_free
extern phys_free_page

; -----------------------------------------------------------------------------
; pool_destroy — completely destroys a pool allocator and frees all memory
; Input:
;   RDI = pointer to the pool descriptor (pool_t)
; Output: none
; Clobbers: none (preserves non-volatile registers)
; -----------------------------------------------------------------------------
global pool_destroy
pool_destroy:
    test rdi, rdi
    jz .exit

    push rbx
    push r12

    mov rbx, rdi                    ; RBX = pool descriptor

    ; Fetch the start of the block list: pool.memory - 16
    mov r12, [rbx + pool_t.memory]
    test r12, r12
    jz .free_desc
    sub r12, 16                     ; R12 = first block (allocated via heap_alloc)

    ; Save the next block pointer before freeing the first block
    mov rdi, [r12]                  ; RDI = second block pointer

    ; Free the first block using heap_free
    push rdi
    mov rdi, r12
    call heap_free
    pop r12                         ; R12 = second block pointer

.free_loop:
    test r12, r12
    jz .free_desc                   ; End of list

    ; Save next block pointer
    mov rdi, [r12]                  ; RDI = next block pointer
    push rdi

    ; Free the current block using phys_free_page
    mov rdi, r12
    call phys_free_page

    pop r12                         ; R12 = next block
    jmp .free_loop

.free_desc:
    ; Free the pool descriptor itself
    mov rdi, rbx
    call heap_free

.exit:
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_POOL_POOL_DESTROY_ASM
