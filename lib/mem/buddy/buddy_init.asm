; =============================================================================
; Tattva OS — lib/mem/buddy/buddy_init.asm
; =============================================================================
; Buddy Allocator Initialization (Subfeature 11.1).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_BUDDY_BUDDY_INIT_ASM
%define LIB_MEM_BUDDY_BUDDY_INIT_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern heap_alloc
extern memset
extern buddy_free_heads
extern buddy_start_addr
extern buddy_end_addr
extern buddy_metadata
extern buddy_save_context
extern buddy_load_context
extern buddy_nodes
extern buddy_node_count
extern buddy_active_node_index

; -----------------------------------------------------------------------------
; buddy_link_block — links a block into the free list of a specific order
; Input:
;   RDI = pointer to block (buddy_block_t)
;   RSI = order (0 to 11)
; Clobbers: none (preserves all registers except scratch RAX/RBX/RDX)
; -----------------------------------------------------------------------------
global buddy_link_block
buddy_link_block:
    push rbx
    push rdx

    mov [rdi + buddy_block_t.order], rsi

    shl rsi, 3                      ; rsi = order * 8
    lea rbx, [buddy_free_heads]
    add rbx, rsi                    ; RBX = &buddy_free_heads[order]

    mov rdx, [rbx]                  ; RDX = current head of list
    mov [rdi + buddy_block_t.next], rdx
    mov qword [rdi + buddy_block_t.prev], 0

    test rdx, rdx
    jz .set_head
    mov [rdx + buddy_block_t.prev], rdi

.set_head:
    mov [rbx], rdi

    pop rdx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; buddy_unlink_block — unlinks a block from the free list of a specific order
; Input:
;   RDI = pointer to block (buddy_block_t)
;   RSI = order (0 to 11)
; Clobbers: none (preserves all registers except scratch RAX/RBX/RCX/RDX)
; -----------------------------------------------------------------------------
global buddy_unlink_block
buddy_unlink_block:
    push rbx
    push rcx
    push rdx

    shl rsi, 3                      ; rsi = order * 8
    lea rbx, [buddy_free_heads]
    add rbx, rsi                    ; RBX = &buddy_free_heads[order]

    mov rcx, [rdi + buddy_block_t.next]
    mov rdx, [rdi + buddy_block_t.prev]

    test rdx, rdx
    jz .update_head
    mov [rdx + buddy_block_t.next], rcx
    jmp .update_next

.update_head:
    mov [rbx], rcx

.update_next:
    test rcx, rcx
    jz .clear_links
    mov [rcx + buddy_block_t.prev], rdx

.clear_links:
    mov qword [rdi + buddy_block_t.next], 0
    mov qword [rdi + buddy_block_t.prev], 0

    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; buddy_init — initializes the buddy allocator with a memory region
; Input:
;   RDI = start address of managed memory region (4KB aligned)
;   RSI = size of region in bytes
; Output: none
; -----------------------------------------------------------------------------
global buddy_init
buddy_init:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = start_addr
    mov r13, rsi                    ; R13 = size

    ; Store configuration
    mov [buddy_start_addr], r12
    mov rax, r12
    add rax, r13
    mov [buddy_end_addr], rax       ; end_addr = start_addr + size

    ; Clear free lists
    lea rdi, [buddy_free_heads]
    mov rcx, 12                     ; 12 list heads
    xor rax, rax
    cld
    rep stosq                       ; zero buddy_free_heads

    ; Calculate number of pages: N = size / 4096
    mov rax, r13
    shr rax, 12                     ; RAX = N (page count)
    mov r14, rax                    ; R14 = N

    ; Allocate metadata array: R14 bytes
    mov rdi, r14
    call heap_alloc
    test rax, rax
    jz .done                        ; If heap_alloc fails, we halt or return (OOM)
    mov [buddy_metadata], rax       ; R15 = pointer to metadata array
    mov r15, rax

    ; Zero out metadata array
    mov rdi, r15
    xor rsi, rsi                    ; fill with 0
    mov rdx, r14                    ; size = N
    call memset

    ; Partition the memory region into largest possible correctly-aligned buddy blocks
    ; A = start_addr (R12)
    ; S = size (R13)
.partition_loop:
    cmp r13, 4096                   ; minimum block size is 4KB
    jb .done

    ; Find largest order O (from 11 down to 0) such that:
    ; 1. (1 << O) * 4096 <= S
    ; 2. A % ((1 << O) * 4096) == 0
    mov rcx, 11                     ; RCX = order (11 down to 0)

.find_order_loop:
    ; Calculate block size for order RCX: size = (1 << RCX) * 4096
    mov rax, 1
    shl rax, cl                     ; RAX = 1 << RCX
    shl rax, 12                     ; RAX = (1 << RCX) * 4096 (block size in bytes)

    ; Condition 1: size <= S
    cmp rax, r13
    ja .next_order

    ; Condition 2: A % size == 0
    push rax
    mov rax, r12                    ; RAX = A
    xor rdx, rdx
    pop rbx                         ; RBX = size
    div rbx                         ; RDX = A % size
    test rdx, rdx
    jz .found_order                 ; division remainder is 0, we found the largest order!

.next_order:
    dec rcx
    cmp rcx, 0
    jge .find_order_loop
    jmp .done

.found_order:
    ; We found the largest order in RCX, and block size in RBX
    ; Link the block at R12 into the free list of order RCX
    mov rdi, r12                    ; RDI = block pointer
    mov rsi, rcx                    ; RSI = order
    call buddy_link_block

    ; Update metadata for this block head
    ; Page index = (R12 - start_addr) / 4096
    mov rax, r12
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = page index
    
    ; Mark as free (bit 7 = 1) and store order in metadata
    mov rdx, rcx                    ; RDX = order
    or rdx, 0x80                    ; free flag
    mov rbx, [buddy_metadata]
    mov [rbx + rax], dl             ; metadata[index] = free | order

    ; Advance A and S
    mov rax, 1
    shl rax, cl
    shl rax, 12                     ; RAX = block size
    add r12, rax                    ; A = A + block_size
    sub r13, rax                    ; S = S - block_size
    jmp .partition_loop

.done:
    ; Save context to slot 0 and mark active
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    xor rax, rax                    ; index 0
    call buddy_save_context
    
    mov qword [buddy_nodes + buddy_node_t.flags], 1
    mov qword [buddy_node_count], 1
    mov qword [buddy_active_node_index], 0
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; buddy_generate_node — Instantiates a buddy allocator node for a RAM module
; Input:
;   RDI = start address of managed memory region (4KB aligned)
;   RSI = size of region in bytes
; Output:
;   RAX = allocated node index, or -1 if failed
; -----------------------------------------------------------------------------
global buddy_generate_node
buddy_generate_node:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = start_addr
    mov r13, rsi                    ; R13 = size

    ; 1. Find a free slot in buddy_nodes array
    xor rbp, rbp                    ; RBP = index i = 0
.find_slot_loop:
    cmp rbp, 8
    jae .fail_no_slot

    mov rax, rbp
    imul rax, buddy_node_t_size
    lea rbx, [buddy_nodes + rax]
    
    mov rax, [rbx + buddy_node_t.flags]
    test rax, rax
    jz .slot_found                  ; found empty slot!

    inc rbp
    jmp .find_slot_loop

.slot_found:
    ; RBP = free slot index
    ; RBX = pointer to buddy_nodes[RBP]

    ; 2. Initialize node boundaries
    mov [rbx + buddy_node_t.start_addr], r12
    mov rax, r12
    add rax, r13
    mov [rbx + buddy_node_t.end_addr], rax       ; end_addr = start_addr + size

    ; Clear the node's free heads list to zero
    lea rdi, [rbx + buddy_node_t.free_heads]
    mov rcx, 12
    xor rax, rax
    cld
    rep stosq                       ; zero free_heads in slot

    ; Calculate page count N = size / 4096
    mov rax, r13
    shr rax, 12                     ; RAX = page count (N)
    mov r14, rax                    ; R14 = N

    ; 3. Allocate metadata array: R14 bytes
    mov rdi, r14
    call heap_alloc
    test rax, rax
    jz .fail_oom                    ; if allocation fails, return -1 (OOM)
    mov [rbx + buddy_node_t.metadata], rax
    mov r15, rax                    ; R15 = pointer to metadata array

    ; Zero metadata array
    mov rdi, r15
    xor rsi, rsi
    mov rdx, r14
    call memset

    ; 4. Set active context globals to this new node directly
    mov [buddy_start_addr], r12
    mov rax, r12
    add rax, r13
    mov [buddy_end_addr], rax
    mov [buddy_metadata], r15

    ; Zero out the global buddy_free_heads for partitioning
    lea rdi, [buddy_free_heads]
    mov rcx, 12
    xor rax, rax
    rep stosq

    ; Mark this index as active
    mov [buddy_active_node_index], rbp

    ; 5. Partition the memory region into largest possible buddy blocks
    ; A = start_addr (R12)
    ; S = size (R13)
.partition_loop:
    cmp r13, 4096                   ; minimum block size is 4KB
    jb .partition_done

    mov rcx, 11                     ; RCX = order (11 down to 0)

.find_order_loop:
    mov rax, 1
    shl rax, cl
    shl rax, 12                     ; RAX = (1 << RCX) * 4096 (block size in bytes)

    cmp rax, r13
    ja .next_order

    push rax
    mov rax, r12
    xor rdx, rdx
    pop rbx                         ; RBX = size
    div rbx
    test rdx, rdx
    jz .found_order

.next_order:
    dec rcx
    cmp rcx, 0
    jge .find_order_loop
    jmp .partition_done

.found_order:
    mov rdi, r12                    ; RDI = block pointer
    mov rsi, rcx                    ; RSI = order
    call buddy_link_block

    ; Update metadata for this block head
    mov rax, r12
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = page index
    
    mov rdx, rcx
    or rdx, 0x80                    ; free | order
    mov rbx, [buddy_metadata]
    mov [rbx + rax], dl             ; metadata[index] = free | order

    ; Advance A and S
    mov rax, 1
    shl rax, cl
    shl rax, 12                     ; RAX = block size
    add r12, rax                    ; A = A + block_size
    sub r13, rax                    ; S = S - block_size
    jmp .partition_loop

.partition_done:
    ; 6. Save final partitioned state to the slot
    mov rax, rbp
    call buddy_save_context

    ; Mark slot as active/enabled
    mov rax, rbp
    imul rax, buddy_node_t_size
    mov qword [buddy_nodes + rax + buddy_node_t.flags], 1

    ; Update buddy_node_count if needed
    mov rax, rbp
    inc rax                         ; RAX = index + 1
    cmp rax, [buddy_node_count]
    jle .return_index
    mov [buddy_node_count], rax

.return_index:
    mov rax, rbp                    ; return node index
    jmp .exit

.fail_no_slot:
.fail_oom:
    mov rax, -1                     ; return -1 on failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_BUDDY_BUDDY_INIT_ASM
