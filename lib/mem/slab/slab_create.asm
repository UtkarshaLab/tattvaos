; =============================================================================
; Tattva OS — lib/mem/slab/slab_create.asm
; =============================================================================
; Slab Allocator Cache Creation functions (Subfeature 10.3).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_SLAB_SLAB_CREATE_ASM
%define LIB_MEM_SLAB_SLAB_CREATE_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern heap_alloc

; -----------------------------------------------------------------------------
; kmem_cache_create_in_place — initializes a pre-allocated cache descriptor
; Input:
;   RDI = cache descriptor pointer (kmem_cache_t)
;   RSI = pointer to name string (ASCIIZ)
;   RDX = object size in bytes
;   RCX = object alignment in bytes
;   R8  = constructor function pointer (optional, can be 0)
;   R9  = destructor function pointer (optional, can be 0)
; Output: none
; Clobbers: none (preserves all registers except scratch RAX)
; -----------------------------------------------------------------------------
global kmem_cache_create_in_place
kmem_cache_create_in_place:
    test rdi, rdi
    jz .done

    ; Align object size to alignment boundary
    mov rax, rdx
    dec rcx
    add rax, rcx
    not rcx
    and rax, rcx                    ; RAX = aligned obj_size
    inc rcx                         ; restore RCX (alignment)

    ; Set cache configuration
    mov [rdi + kmem_cache_t.name], rsi
    mov [rdi + kmem_cache_t.obj_size], rax
    mov [rdi + kmem_cache_t.align_size], rcx
    mov [rdi + kmem_cache_t.ctor], r8
    mov [rdi + kmem_cache_t.dtor], r9

    ; Initialize slab list heads to 0 (NULL)
    mov qword [rdi + kmem_cache_t.slabs_full], 0
    mov qword [rdi + kmem_cache_t.slabs_part], 0
    mov qword [rdi + kmem_cache_t.slabs_free], 0

    ; Clear spinlock
    mov qword [rdi + kmem_cache_t.lock], 0

.done:
    ret

; -----------------------------------------------------------------------------
; kmem_cache_create — dynamically creates and initializes a cache descriptor
; Input:
;   RDI = pointer to name string (ASCIIZ)
;   RSI = object size in bytes
;   RDX = object alignment in bytes
;   RCX = constructor function pointer (optional, can be 0)
;   R8  = destructor function pointer (optional, can be 0)
; Output:
;   RAX = pointer to new kmem_cache_t, or 0 if OOM
; -----------------------------------------------------------------------------
global kmem_cache_create
kmem_cache_create:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi                    ; R12 = name
    mov r13, rsi                    ; R13 = obj_size
    mov r14, rdx                    ; R14 = align_size
    
    push rcx                        ; push ctor to stack
    push r8                         ; push dtor to stack

    ; Allocate memory for the cache descriptor
    mov rdi, kmem_cache_t_size
    call heap_alloc                 ; RAX = allocated address
    
    pop r9                          ; R9 = dtor
    pop r8                          ; R8 = ctor

    test rax, rax
    jz .fail

    ; Initialize the descriptor in-place
    mov rdi, rax                    ; cache pointer
    mov rsi, r12                    ; name
    mov rdx, r13                    ; obj_size
    mov rcx, r14                    ; align_size
    call kmem_cache_create_in_place

    ; Return the cache descriptor address in RAX
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_SLAB_SLAB_CREATE_ASM
