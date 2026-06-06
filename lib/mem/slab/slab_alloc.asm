; =============================================================================
; Tattva OS — lib/mem/slab/slab_alloc.asm
; =============================================================================
; Slab Allocator Allocation & Tracking routines (Subfeature 10.3).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_SLAB_SLAB_ALLOC_ASM
%define LIB_MEM_SLAB_SLAB_ALLOC_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern heap_alloc
extern heap_free

; -----------------------------------------------------------------------------
; kmem_slab_link — inserts a slab at the head of a cache's slab list
; Input:
;   RDI = pointer to cache descriptor (kmem_cache_t)
;   RSI = offset of list head in kmem_cache_t (e.g. kmem_cache_t.slabs_free)
;   RDX = pointer to slab to insert (slab_t)
; Output: none
; Clobbers: none (preserves all registers except scratch RAX)
; -----------------------------------------------------------------------------
global kmem_slab_link
kmem_slab_link:
    push rbx
    
    ; Calculate address of list head variable: RDI + RSI
    mov rbx, rdi
    add rbx, rsi                    ; RBX = list head address (e.g. &cache->slabs_free)

    mov rax, [rbx]                  ; RAX = current first slab in list
    mov [rdx + slab_t.next], rax    ; slab->next = first_slab
    mov qword [rdx + slab_t.prev], 0 ; slab->prev = 0

    test rax, rax
    jz .set_head
    mov [rax + slab_t.prev], rdx    ; first_slab->prev = slab

.set_head:
    mov [rbx], rdx                  ; list_head = slab

    pop rbx
    ret

; -----------------------------------------------------------------------------
; kmem_slab_unlink — removes a slab from its current doubly-linked list
; Input:
;   RDI = pointer to cache descriptor (kmem_cache_t)
;   RSI = offset of list head in kmem_cache_t
;   RDX = pointer to slab to remove (slab_t)
; Output: none
; Clobbers: none (preserves all registers except scratch RAX)
; -----------------------------------------------------------------------------
global kmem_slab_unlink
kmem_slab_unlink:
    push rbx
    push rcx
    push r8

    ; Calculate address of list head variable: RDI + RSI
    mov rbx, rdi
    add rbx, rsi                    ; RBX = list head address

    mov rcx, [rdx + slab_t.next]    ; RCX = slab->next
    mov r8, [rdx + slab_t.prev]     ; R8 = slab->prev

    test r8, r8
    jz .update_head
    mov [r8 + slab_t.next], rcx     ; prev_slab->next = next_slab
    jmp .update_next

.update_head:
    mov [rbx], rcx                  ; list_head = next_slab

.update_next:
    test rcx, rcx
    jz .clear_links
    mov [rcx + slab_t.prev], r8     ; next_slab->prev = prev_slab

.clear_links:
    mov qword [rdx + slab_t.next], 0
    mov qword [rdx + slab_t.prev], 0

    pop r8
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; kmem_slab_grow — allocates a new slab and initializes it in the empty list
; Input:
;   RDI = pointer to cache descriptor (kmem_cache_t)
; Output:
;   RAX = pointer to new slab_t, or 0 if OOM
; -----------------------------------------------------------------------------
global kmem_slab_grow
kmem_slab_grow:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = pointer to kmem_cache_t

    ; 1. Allocate a 4KB chunk from the heap
    mov rdi, 4096
    call heap_alloc                 ; RAX = slab address (4KB page-like block)
    test rax, rax
    jz .oom
    mov r13, rax                    ; R13 = slab pointer

    ; 2. Initialize slab_t fields
    mov qword [r13 + slab_t.magic], 0x51AB51AB
    mov qword [r13 + slab_t.next], 0
    mov qword [r13 + slab_t.prev], 0
    mov qword [r13 + slab_t.used_count], 0

    ; 3. Calculate mem_start aligned to align_size
    ; mem_start = (r13 + slab_t_size + align - 1) & ~(align - 1)
    mov rdx, [r12 + kmem_cache_t.align_size]
    mov rcx, rdx
    dec rcx                         ; RCX = align - 1

    mov rax, r13
    add rax, slab_t_size            ; RAX = r13 + 56
    add rax, rcx                    ; RAX = r13 + 56 + align - 1
    not rcx
    and rax, rcx                    ; RAX = aligned mem_start
    mov [r13 + slab_t.mem_start], rax
    mov r14, rax                    ; R14 = mem_start

    ; 4. Calculate obj_count capacity
    ; obj_count = (r13 + 4096 - mem_start) / obj_size
    mov rax, r13
    add rax, 4096                   ; RAX = slab end address
    sub rax, r14                    ; RAX = space left for objects
    
    xor rdx, rdx
    mov rcx, [r12 + kmem_cache_t.obj_size]
    div rcx                         ; RAX = capacity (obj_count)
    mov [r13 + slab_t.obj_count], rax
    mov r15, rax                    ; R15 = obj_count

    ; Verify capacity is at least 1 object
    test r15, r15
    jz .grow_fail

    ; 5. Partition memory into singly-linked free objects list
    ; Start from mem_start (R14) and link next objects
    mov rdi, r14                    ; RDI = current object
    xor rdx, rdx                    ; RDX = loop index (0 to obj_count - 1)
    mov rsi, [r12 + kmem_cache_t.obj_size] ; RSI = obj_size

.link_loop:
    mov rax, rdx
    inc rax
    cmp rax, r15
    jae .last_obj                   ; if next index >= obj_count, this is the last object

    ; Link current object to next object: [RDI] = RDI + obj_size
    mov rbx, rdi
    add rbx, rsi                    ; RBX = next object address
    mov [rdi], rbx                  ; store in current object

    mov rdi, rbx                    ; RDI = next object
    inc rdx
    jmp .link_loop

.last_obj:
    mov qword [rdi], 0              ; last object points to NULL (0)

    ; Set slab's free_head
    mov [r13 + slab_t.free_head], r14

    ; --- 5b. Run Constructor if defined ---
    mov r8, [r12 + kmem_cache_t.ctor]
    test r8, r8
    jz .skip_ctor                   ; if constructor is null, skip loop

    ; Loop over all objects in the slab and call ctor(obj_ptr, cache_ptr)
    mov r14, [r13 + slab_t.mem_start] ; R14 = current object pointer
    xor rdx, rdx                    ; RDX = loop index (0 to obj_count - 1)
    mov rsi, [r12 + kmem_cache_t.obj_size] ; RSI = obj_size

.ctor_loop:
    cmp rdx, r15                    ; compare index with obj_count (R15)
    jae .skip_ctor

    ; Save loop registers before calling ctor
    push r12
    push r13
    push r14
    push r15
    push rdx
    push rsi
    push r8

    ; Call constructor: ctor(RDI = obj_ptr, RSI = cache_ptr)
    mov rdi, r14                    ; object pointer
    mov rsi, r12                    ; cache pointer
    call r8

    pop r8
    pop rsi
    pop rdx
    pop r15
    pop r14
    pop r13
    pop r12

    ; Advance to next object
    add r14, rsi                    ; R14 = next object address
    inc rdx
    jmp .ctor_loop

.skip_ctor:
    ; 6. Link the slab to the cache's slabs_free list
    mov rdi, r12                    ; RDI = cache descriptor
    mov rsi, kmem_cache_t.slabs_free ; RSI = offset of slabs_free
    mov rdx, r13                    ; RDX = slab pointer
    call kmem_slab_link

    ; Return slab pointer in RAX
    mov rax, r13
    jmp .done

.grow_fail:
    ; Free allocated page if formatting fails
    mov rdi, r13
    call heap_free
.oom:
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

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
