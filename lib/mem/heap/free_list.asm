; =============================================================================
; Tattva OS — lib/mem/heap/free_list.asm
; =============================================================================
; Doubly-linked free list heap allocator with block splitting and coalescing.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_HEAP_FREE_LIST_ASM
%define LIB_MEM_HEAP_FREE_LIST_ASM

[BITS 64]

struc heap_block_t
    .size       resq 1          ; Size of the block (excluding header)
    .flags      resq 1          ; Bit 0: 0 = free, 1 = used
    .next       resq 1          ; Pointer to next block in free list
    .prev       resq 1          ; Pointer to prev block in free list
endstruc

section .text

; -----------------------------------------------------------------------------
; free_list_init — initializes the free list heap allocator in a given region
; Input:
;   RDI = start address of heap region
;   RSI = size of heap region in bytes
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global free_list_init
free_list_init:
    ; Align start address to 16 bytes
    mov rax, rdi
    add rax, 15
    and rax, -16                    ; RAX = aligned start address
    
    ; Adjust size for alignment overhead
    mov rcx, rdi
    add rcx, rsi                    ; RCX = end address
    sub rcx, rax                    ; RCX = aligned size
    
    ; Verify that we have enough space for at least the header
    cmp rcx, heap_block_t_size
    jbe .done
    
    ; Create the initial free block at RAX
    sub rcx, heap_block_t_size      ; RCX = block size (excluding header)
    
    mov qword [rax + heap_block_t.size], rcx
    mov qword [rax + heap_block_t.flags], 0 ; mark as free
    mov qword [rax + heap_block_t.next], 0
    mov qword [rax + heap_block_t.prev], 0
    
    ; Set free list head to point to this block
    mov [free_list_head], rax
 
.done:
    ret

; -----------------------------------------------------------------------------
; free_list_alloc — allocates size bytes from the heap, 16-byte aligned
; Input:
;   RDI = size of allocation in bytes
; Output:
;   RAX = pointer to allocated memory, or 0 if OOM
; Clobbers: RAX, RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
global free_list_alloc
free_list_alloc:
    cmp rdi, 0
    je .oom
    
    ; Align size to 16 bytes
    mov rax, rdi
    add rax, 15
    and rax, -16                    ; RAX = aligned size
    mov r8, rax                     ; R8 = aligned size
    
    ; Traverse free list starting at free_list_head
    mov rsi, [free_list_head]       ; RSI = current block

.search_loop:
    test rsi, rsi
    jz .oom                         ; end of list, no block found (OOM)
    
    mov rcx, [rsi + heap_block_t.size]
    cmp rcx, r8
    jae .found_block
    
    mov rsi, [rsi + heap_block_t.next]
    jmp .search_loop

.found_block:
    ; Check if we can split: block->size >= aligned_size + heap_block_t_size + 16
    mov r9, r8
    add r9, heap_block_t_size
    add r9, 16                      ; R9 = minimum size required to split
    cmp rcx, r9
    jb .allocate_whole
    
    ; Split the block!
    ; Calculate new block address: rsi + heap_block_t_size + aligned_size
    mov rdi, rsi
    add rdi, heap_block_t_size
    add rdi, r8                     ; RDI = new block pointer
    
    ; Calculate new block size: old_size - aligned_size - heap_block_t_size
    mov r9, rcx
    sub r9, r8
    sub r9, heap_block_t_size       ; R9 = new block size
    
    ; Initialize new block header
    mov [rdi + heap_block_t.size], r9
    mov qword [rdi + heap_block_t.flags], 0 ; free
    
    ; Link new block in place of old block
    mov rdx, [rsi + heap_block_t.next]
    mov [rdi + heap_block_t.next], rdx
    mov rdx, [rsi + heap_block_t.prev]
    mov [rdi + heap_block_t.prev], rdx
    
    test rdx, rdx
    jz .update_head_split
    mov [rdx + heap_block_t.next], rdi
    jmp .update_next_split
.update_head_split:
    mov [free_list_head], rdi
.update_next_split:
    mov rdx, [rdi + heap_block_t.next]
    test rdx, rdx
    jz .split_done
    mov [rdx + heap_block_t.prev], rdi
.split_done:
    ; Update allocated block size and flags
    mov [rsi + heap_block_t.size], r8
    mov qword [rsi + heap_block_t.flags], 1 ; used
    
    ; Return pointer to block body
    mov rax, rsi
    add rax, heap_block_t_size
    ret

.allocate_whole:
    ; Remove block from free list
    mov rdx, [rsi + heap_block_t.prev]
    mov rcx, [rsi + heap_block_t.next]
    
    test rdx, rdx
    jz .update_head_whole
    mov [rdx + heap_block_t.next], rcx
    jmp .update_next_whole
.update_head_whole:
    mov [free_list_head], rcx
.update_next_whole:
    test rcx, rcx
    jz .whole_done
    mov [rcx + heap_block_t.prev], rdx
.whole_done:
    ; Mark as used
    mov qword [rsi + heap_block_t.flags], 1 ; used
    
    ; Return pointer to block body
    mov rax, rsi
    add rax, heap_block_t_size
    ret

.oom:
    xor rax, rax                    ; return 0 on OOM
    ret

; -----------------------------------------------------------------------------
; free_list_free — frees a previously allocated memory block
; Input:
;   RDI = pointer to memory block to free
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI
; -----------------------------------------------------------------------------
global free_list_free
free_list_free:
    test rdi, rdi
    jz .done
    
    ; Get pointer to block header
    sub rdi, heap_block_t_size      ; RDI = block header pointer
    mov qword [rdi + heap_block_t.flags], 0 ; mark as free
    
    ; Find correct spot in address-sorted free list
    mov rsi, [free_list_head]       ; RSI = current list node
    xor rdx, rdx                    ; RDX = previous list node (initially null)

.find_loop:
    test rsi, rsi
    jz .insert_end
    
    cmp rsi, rdi
    ja .insert_before               ; if current node address > block address, insert before
    
    mov rdx, rsi
    mov rsi, [rsi + heap_block_t.next]
    jmp .find_loop

.insert_before:
    ; Link block between rdx and rsi
    mov [rdi + heap_block_t.next], rsi
    mov [rdi + heap_block_t.prev], rdx
    mov [rsi + heap_block_t.prev], rdi
    test rdx, rdx
    jz .update_head
    mov [rdx + heap_block_t.next], rdi
    jmp .coalesce
.update_head:
    mov [free_list_head], rdi
    jmp .coalesce

.insert_end:
    ; Link block at the end (after rdx)
    mov qword [rdi + heap_block_t.next], 0
    mov [rdi + heap_block_t.prev], rdx
    test rdx, rdx
    jz .update_head_empty
    mov [rdx + heap_block_t.next], rdi
    jmp .coalesce
.update_head_empty:
    mov [free_list_head], rdi

.coalesce:
    ; 1. Try to merge RDI with RDI->next
    mov rsi, [rdi + heap_block_t.next]
    test rsi, rsi
    jz .coalesce_prev
    
    ; Check if RDI and RSI are physically contiguous: rdi + heap_block_t_size + rdi->size == rsi
    mov rax, rdi
    add rax, heap_block_t_size
    add rax, [rdi + heap_block_t.size]
    cmp rax, rsi
    jne .coalesce_prev
    
    ; Merge RSI into RDI
    mov rcx, [rsi + heap_block_t.size]
    add rcx, heap_block_t_size
    add [rdi + heap_block_t.size], rcx
    
    mov rcx, [rsi + heap_block_t.next]
    mov [rdi + heap_block_t.next], rcx
    test rcx, rcx
    jz .coalesce_prev
    mov [rcx + heap_block_t.prev], rdi

.coalesce_prev:
    ; 2. Try to merge RDI->prev with RDI
    mov rsi, [rdi + heap_block_t.prev]
    test rsi, rsi
    jz .done
    
    ; Check if RSI and RDI are physically contiguous: rsi + heap_block_t_size + rsi->size == rdi
    mov rax, rsi
    add rax, heap_block_t_size
    add rax, [rsi + heap_block_t.size]
    cmp rax, rdi
    jne .done
    
    ; Merge RDI into RSI
    mov rcx, [rdi + heap_block_t.size]
    add rcx, heap_block_t_size
    add [rsi + heap_block_t.size], rcx
    
    mov rcx, [rdi + heap_block_t.next]
    mov [rsi + heap_block_t.next], rcx
    test rcx, rcx
    jz .done
    mov [rcx + heap_block_t.prev], rsi

.done:
    ret

; -----------------------------------------------------------------------------
; free_list_realloc — resizes a previously allocated memory block
; Input:
;   RDI = pointer to memory block (can be 0)
;   RSI = new size in bytes
; Output:
;   RAX = pointer to new memory block, or 0 if OOM
; -----------------------------------------------------------------------------
global free_list_realloc
free_list_realloc:
    test rdi, rdi
    jz .do_alloc
    test rsi, rsi
    jz .do_free
    
    ; Retrieve old block size
    mov r8, rdi
    sub r8, heap_block_t_size      ; R8 = block header pointer
    mov r9, [r8 + heap_block_t.size] ; R9 = old block size
    
    cmp r9, rsi
    jae .shrink_or_equal            ; if old size >= new size, just return it
    
    ; Allocate new region
    push rdi
    push rsi
    push r9
    
    mov rdi, rsi
    call free_list_alloc            ; RAX = new block pointer
    
    pop r9
    pop rsi
    pop rdi
    
    test rax, rax
    jz .oom
    
    ; Copy old data to new location
    push rdi                        ; push old pointer
    push r9                         ; push old size
    push rax                        ; push new pointer
    
    mov rdi, rax                    ; dest = new pointer
    mov rsi, [rsp + 16]             ; source = old pointer
    mov rdx, [rsp + 8]              ; count = old size
    extern memcpy
    call memcpy
    
    pop rax                         ; rax = new pointer
    pop r9
    pop rdi                         ; rdi = old pointer
    
    ; Free old block
    push rax
    call free_list_free
    pop rax
    ret

.shrink_or_equal:
    mov rax, rdi                    ; just return the same block
    ret

.do_alloc:
    mov rdi, rsi
    jmp free_list_alloc

.do_free:
    call free_list_free
    xor rax, rax
    ret

.oom:
    xor rax, rax
    ret

section .data

align 8
global free_list_head
free_list_head: dq 0

%endif ; LIB_MEM_HEAP_FREE_LIST_ASM
