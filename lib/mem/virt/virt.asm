; =============================================================================
; Tattva OS — lib/mem/virt/virt.asm
; =============================================================================
; Virtual memory manager entry. Handles Virtual Memory Areas (VMAs).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_VIRT_ASM
%define LIB_MEM_VIRT_VIRT_ASM

[BITS 64]

struc vma_t
    .start      resq 1          ; Start virtual address (page-aligned)
    .end        resq 1          ; End virtual address (page-aligned, exclusive)
    .flags      resq 1          ; VMA flags
    .next       resq 1          ; Pointer to next VMA in the list
endstruc

section .text

; -----------------------------------------------------------------------------
; vma_init — initializes the VMA allocator
; Input: none
; Output: none
; -----------------------------------------------------------------------------
global vma_init
vma_init:
    mov qword [vma_list_head], 0
    ret

; -----------------------------------------------------------------------------
; vma_create — creates a non-overlapping Virtual Memory Area (VMA)
; Input:
;   RDI = start virtual address
;   RSI = size in bytes
;   RDX = VMA flags
; Output:
;   RAX = pointer to the created VMA structure, or 0 if overlap/OOM
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9
; -----------------------------------------------------------------------------
global vma_create
vma_create:
    push rbx
    push r12
    push r13
    push r14

    ; Page-align the start address down
    mov rbx, rdi
    and rbx, -4096                  ; RBX = aligned start address
    
    ; Page-align the size up
    mov r12, rsi
    add r12, 4095
    and r12, -4096                  ; R12 = aligned size
    
    ; Calculate end address (start + size)
    mov r13, rbx
    add r13, r12                    ; R13 = end address (exclusive)
    
    mov r14, rdx                    ; R14 = flags

    ; 1. Check for overlap with existing VMAs
    mov rsi, [vma_list_head]
.overlap_loop:
    test rsi, rsi
    jz .no_overlap
    
    ; Check: start < vma->end && end > vma->start
    mov rcx, [rsi + vma_t.start]
    mov rdx, [rsi + vma_t.end]
    
    cmp rbx, rdx
    jae .next_overlap
    cmp r13, rcx
    jbe .next_overlap
    
    ; Overlap detected!
    jmp .error_overlap

.next_overlap:
    mov rsi, [rsi + vma_t.next]
    jmp .overlap_loop

.no_overlap:
    ; 2. Allocate VMA node from the heap
    mov rdi, vma_t_size
    call heap_alloc
    test rax, rax
    jz .error_oom
    
    ; Populate the VMA structure
    mov [rax + vma_t.start], rbx
    mov [rax + vma_t.end], r13
    mov [rax + vma_t.flags], r14
    mov qword [rax + vma_t.next], 0

    ; 3. Insert VMA into ascending address-sorted list
    mov rdx, [vma_list_head]
    test rdx, rdx
    jz .insert_head_empty
    
    cmp rbx, [rdx + vma_t.start]
    jb .insert_head
    
    ; Search for insertion spot (node before VMA)
    mov rsi, rdx
.insert_search:
    mov rcx, [rsi + vma_t.next]
    test rcx, rcx
    jz .insert_after
    
    cmp rbx, [rcx + vma_t.start]
    jb .insert_after
    
    mov rsi, rcx
    jmp .insert_search

.insert_after:
    mov rcx, [rsi + vma_t.next]
    mov [rax + vma_t.next], rcx
    mov [rsi + vma_t.next], rax
    jmp .done

.insert_head:
    mov [rax + vma_t.next], rdx
    mov [vma_list_head], rax
    jmp .done

.insert_head_empty:
    mov [vma_list_head], rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.error_overlap:
.error_oom:
    xor rax, rax                    ; return 0 on error
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; vma_find — finds the VMA containing a given virtual address
; Input:
;   RDI = virtual address
; Output:
;   RAX = pointer to VMA structure, or 0 if not found
; -----------------------------------------------------------------------------
global vma_find
vma_find:
    mov rax, [vma_list_head]
.loop:
    test rax, rax
    jz .not_found
    
    mov rcx, [rax + vma_t.start]
    mov rdx, [rax + vma_t.end]
    
    cmp rdi, rcx
    jb .next
    cmp rdi, rdx
    jb .found                       ; if start <= addr < end, found!
    
.next:
    mov rax, [rax + vma_t.next]
    jmp .loop

.found:
    ret

.not_found:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; vma_destroy — removes and frees a VMA
; Input:
;   RDI = pointer to VMA structure to destroy
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI
; -----------------------------------------------------------------------------
global vma_destroy
vma_destroy:
    test rdi, rdi
    jz .done
    
    push rbx
    mov rbx, rdi                    ; RBX = target VMA to destroy
    
    ; Find and remove VMA from list
    mov rsi, [vma_list_head]
    test rsi, rsi
    jz .pop_done
    
    cmp rsi, rbx
    je .remove_head
    
.search_loop:
    mov rcx, [rsi + vma_t.next]
    test rcx, rcx
    jz .pop_done
    
    cmp rcx, rbx
    je .remove_next
    
    mov rsi, rcx
    jmp .search_loop

.remove_next:
    mov rdx, [rbx + vma_t.next]
    mov [rsi + vma_t.next], rdx
    jmp .free_node

.remove_head:
    mov rdx, [rbx + vma_t.next]
    mov [vma_list_head], rdx

.free_node:
    ; Free VMA structure back to heap
    mov rdi, rbx
    call heap_free

.pop_done:
    pop rbx
.done:
    ret

section .data

align 8
global vma_list_head
vma_list_head: dq 0

%endif ; LIB_MEM_VIRT_VIRT_ASM
