; =============================================================================
; Tattva OS — lib/mem/slab/slab_reap.asm
; =============================================================================
; Slab Allocator Reclaim function (Subfeature 10.4).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_SLAB_SLAB_REAP_ASM
%define LIB_MEM_SLAB_SLAB_REAP_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern kmem_slab_unlink
extern heap_free

; -----------------------------------------------------------------------------
; kmem_cache_reap — reclaims/frees all empty slabs in the cache to the heap
; Input:
;   RDI = pointer to cache descriptor (kmem_cache_t)
;   If a destructor is defined, it runs on all objects of each empty slab.
; Output:
;   RAX = count of pages/slabs reclaimed
; -----------------------------------------------------------------------------
global kmem_cache_reap
kmem_cache_reap:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = cache descriptor (kmem_cache_t)
    xor r15, r15                    ; R15 = count of reclaimed slabs

.reap_loop:
    ; Get first slab in slabs_free list
    mov r13, [r12 + kmem_cache_t.slabs_free]
    test r13, r13
    jz .done                        ; If no more empty slabs, we are done

    ; 1. Check if destructor is defined
    mov rax, [r12 + kmem_cache_t.dtor]
    test rax, rax
    jz .skip_dtor

    ; Run destructor on all objects in this empty slab
    mov r14, [r13 + slab_t.mem_start] ; R14 = current object pointer
    xor rbx, rbx                    ; RBX = current object index
    mov rbp, [r13 + slab_t.obj_count] ; RBP = total objects in slab

.dtor_loop:
    cmp rbx, rbp
    jae .skip_dtor

    ; Call destructor: dtor(obj_ptr, cache_ptr)
    mov rdi, r14                    ; RDI = object pointer
    mov rsi, r12                    ; RSI = cache pointer
    mov rax, [r12 + kmem_cache_t.dtor]
    call rax

    ; Advance to next object
    mov rcx, [r12 + kmem_cache_t.obj_size]
    add r14, rcx
    inc rbx
    jmp .dtor_loop

.skip_dtor:
    ; 2. Unlink slab from slabs_free list
    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r13
    call kmem_slab_unlink

    ; 3. Free the slab page
    mov rdi, r13
    call heap_free

    inc r15                         ; Increment reclaimed count
    jmp .reap_loop

.done:
    mov rax, r15                    ; Return reclaimed count
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_SLAB_SLAB_REAP_ASM
