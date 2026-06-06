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
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_BUDDY_BUDDY_INIT_ASM
