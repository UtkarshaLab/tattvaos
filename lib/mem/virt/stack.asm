; =============================================================================
; Tattva OS — lib/mem/virt/stack.asm
; =============================================================================
; Thread Stack Page Allocator (Subfeature 20.1).
; Allocates page-aligned stack frames for newly spawned tasks.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_STACK_ASM
%define LIB_MEM_VIRT_STACK_ASM

[BITS 64]

; Local Constants
%ifndef VMA_READ
    %define VMA_READ    (1 << 0)
%endif
%ifndef VMA_WRITE
    %define VMA_WRITE   (1 << 1)
%endif
%ifndef VMA_STACK
    %define VMA_STACK   (1 << 6)
%endif

STACK_VIRT_START equ 0x700000000000

section .text

; External symbols
extern vma_list_head
extern vma_create
extern vma_find
extern vma_destroy
extern phys_alloc_page
extern phys_free_page
extern virt_map
extern virt_unmap
extern virt_translate

; -----------------------------------------------------------------------------
; virt_find_free_range — finds a free virtual address range of a given size
; Input:
;   RDI = size in bytes (page-aligned)
;   RSI = base address to start searching from
; Output:
;   RAX = start virtual address of the free range, or 0 if not found
; Clobbers: RAX, RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
global virt_find_free_range
virt_find_free_range:
    mov r8, rsi                     ; R8 = current candidate address
    mov r9, [vma_list_head]         ; R9 = current VMA node
    
.loop:
    test r9, r9
    jz .end_of_list                 ; no more VMAs, candidate is valid
    
    mov rax, [r9 + vma_t.start]
    mov rdx, [r9 + vma_t.end]
    
    ; If the VMA is completely below our current candidate, skip it
    cmp rdx, r8
    jbe .next_vma
    
    ; If there is a gap between r8 and the start of this VMA
    cmp rax, r8
    jbe .no_gap                     ; VMA starts at or below candidate (overlap)
    
    ; Check if the gap is large enough: rax - r8 >= RDI (requested size)
    mov rcx, rax
    sub rcx, r8
    cmp rcx, rdi
    jae .found                      ; gap is large enough!
    
.no_gap:
    ; Candidate overlaps or gap is too small. Move candidate to end of this VMA
    mov r8, rdx
    
.next_vma:
    mov r9, [r9 + vma_t.next]
    jmp .loop
    
.end_of_list:
    ; Check if candidate + size exceeds canonical address space limit (0x00007FFFFFFFFFFF)
    mov rcx, r8
    add rcx, rdi
    mov rax, 0x00007FFFFFFFFFFF
    cmp rcx, rax
    ja .error
    
.found:
    mov rax, r8
    ret
    
.error:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; thread_stack_alloc — allocates a page-aligned virtual stack frame
; Input:
;   RDI = size of stack in bytes (must be page-aligned, e.g. 16384)
; Output:
;   RAX = virtual address of the TOP of the stack (initial RSP value),
;         or 0 on failure
; -----------------------------------------------------------------------------
global thread_stack_alloc
thread_stack_alloc:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; 1. Page-align size just to be safe
    mov rbx, rdi                    ; RBX = requested size
    add rbx, 4095
    and rbx, -4096                  ; RBX = aligned size
    
    ; 2. Find a free virtual range
    mov rdi, rbx
    mov rsi, STACK_VIRT_START
    call virt_find_free_range
    test rax, rax
    jz .fail
    
    mov r12, rax                    ; R12 = start virtual address of stack
    
    ; 3. Create VMA for this range
    mov rdi, r12
    mov rsi, rbx
    mov rdx, (VMA_STACK | VMA_READ | VMA_WRITE)
    call vma_create
    test rax, rax
    jz .fail
    
    mov r15, rax                    ; R15 = VMA pointer
    
    ; 4. Allocate and map physical pages
    mov r13, r12                    ; R13 = current virtual address cursor
    mov r14, r12
    add r14, rbx                    ; R14 = end virtual address of stack (top)
    
.map_loop:
    cmp r13, r14
    jae .map_success
    
    ; Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .oom_cleanup
    
    ; Map virtual page to physical frame
    mov rdi, r13                    ; virtual address
    mov rsi, rax                    ; physical address
    mov rdx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_NX)
    call virt_map
    
    add r13, 4096
    jmp .map_loop
    
.map_success:
    ; Return the TOP of the stack (R14)
    mov rax, r14
    
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.oom_cleanup:
    ; Clean up previously mapped pages
    ; Loop from R12 to R13 (exclusive)
    mov r12, r12
.cleanup_loop:
    cmp r12, r13
    jae .destroy_vma
    
    ; Get mapped physical address to free it
    mov rdi, r12
    call virt_translate
    test rax, rax
    jz .skip_free
    
    mov rdi, rax
    call phys_free_page
.skip_free:
    ; Unmap virtual address
    mov rdi, r12
    call virt_unmap
    
    add r12, 4096
    jmp .cleanup_loop

.destroy_vma:
    mov rdi, r15
    call vma_destroy
    
.fail:
    xor rax, rax
    jmp .exit

; -----------------------------------------------------------------------------
; thread_stack_free — frees a previously allocated thread stack frame
; Input:
;   RDI = virtual address of the TOP of the stack (exclusive, returned by alloc)
;   RSI = size of the stack in bytes
; Output: none
; -----------------------------------------------------------------------------
global thread_stack_free
thread_stack_free:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = top of stack (exclusive)
    mov r12, rsi                    ; R12 = stack size
    
    ; Calculate start address (start = top - size)
    mov r13, rbx
    sub r13, r12                    ; R13 = start address (page-aligned)
    
    ; Find the VMA corresponding to the start address to destroy it later
    mov rdi, r13
    call vma_find
    mov r14, rax                    ; R14 = VMA pointer (or 0)
    
    ; Free all physical pages and unmap virtual space
    mov rcx, r13                    ; RCX = current virtual address cursor
.free_loop:
    cmp rcx, rbx
    jae .free_vma
    
    push rcx
    
    ; Translate to physical address
    mov rdi, rcx
    call virt_translate
    test rax, rax
    jz .skip_phys_free
    
    ; Free the physical page frame
    mov rdi, rax
    call phys_free_page
    
.skip_phys_free:
    ; Unmap the virtual page
    pop rcx
    push rcx
    mov rdi, rcx
    call virt_unmap
    
    pop rcx
    add rcx, 4096
    jmp .free_loop

.free_vma:
    ; Destroy the VMA if found
    test r14, r14
    jz .exit
    
    mov rdi, r14
    call vma_destroy

.exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_STACK_ASM
