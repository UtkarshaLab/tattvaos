; =============================================================================
; Tattva OS — lib/mem/buddy/buddy_alloc.asm
; =============================================================================
; Buddy Allocator Allocation and Splitting logic (Subfeature 11.2).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_BUDDY_BUDDY_ALLOC_ASM
%define LIB_MEM_BUDDY_BUDDY_ALLOC_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern buddy_free_heads
extern buddy_start_addr
extern buddy_metadata
extern buddy_link_block
extern buddy_unlink_block
extern buddy_nodes
extern buddy_node_count
extern buddy_load_context

; -----------------------------------------------------------------------------
; buddy_alloc — allocates a power-of-two block of pages of the requested order
; Input:
;   RDI = requested order (0 to 11)
; Output:
;   RAX = physical address of the allocated block, or 0 if OOM
; Clobbers: none (preserves all registers except scratch RAX)
; -----------------------------------------------------------------------------
global buddy_alloc
buddy_alloc:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = requested order
    xor r13, r13                    ; R13 = current node index i = 0

.loop:
    cmp r13, [buddy_node_count]
    jae .oom

    ; Check if node is active
    mov rax, r13
    imul rax, buddy_node_t_size
    mov rax, [buddy_nodes + rax + buddy_node_t.flags]
    test rax, rax
    jz .next_node

    ; Load node context
    mov rax, r13
    call buddy_load_context

    ; Try allocation on this node
    mov rdi, r12
    call buddy_alloc_internal
    test rax, rax
    jnz .success                    ; If RAX != 0, allocation succeeded!

.next_node:
    inc r13
    jmp .loop

.success:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

.oom:
    xor rax, rax
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

buddy_alloc_internal:
    push rbx
    push rcx
    push rdx
    push rsi
    push r12
    push r13
    push r14

    mov r12, rdi                    ; R12 = requested order (R)

    ; Validate requested order is between 0 and 11
    cmp r12, 11
    ja .oom                         ; if order > 11, return 0 (OOM)

    ; Scan free lists starting from requested order R12 up to order 11
    mov r13, r12                    ; R13 = current scanning order (O)

.scan_loop:
    lea rax, [buddy_free_heads]
    mov r14, [rax + r13 * 8]        ; R14 = buddy_free_heads[O]
    test r14, r14
    jnz .found_block                ; we found a free block at order O!

    inc r13
    cmp r13, 11
    jbe .scan_loop

    ; If we scanned up to order 11 and found nothing, we are OOM
    jmp .oom

.found_block:
    ; R14 points to the block we are allocating (which is at buddy_free_heads[O])
    ; Unlink it from order O list
    mov rdi, r14
    mov rsi, r13                    ; current order O
    call buddy_unlink_block

    ; If current order O (R13) == requested order R (R12), no split needed!
    cmp r13, r12
    je .alloc_done

    ; We must recursively split the block from order O down to order R
.split_loop:
    cmp r13, r12
    jbe .alloc_done                 ; if current order <= requested order, we are done

    ; Decrement current order O
    dec r13                         ; R13 = O - 1

    ; Left block starts at R14.
    ; Right block starts at R14 + (1 << (O - 1)) * 4096
    mov rax, 1
    mov rcx, r13                    ; RCX = O - 1
    shl rax, cl                     ; RAX = 1 << (O - 1)
    shl rax, 12                     ; RAX = (1 << (O - 1)) * 4096 (right block offset)
    
    mov rsi, r14
    add rsi, rax                    ; RSI = right block address

    ; Link the Right block into the free list of order O - 1 (R13)
    mov rdi, rsi                    ; RDI = right block ptr
    mov rsi, r13                    ; RSI = order (O - 1)
    call buddy_link_block

    ; Update metadata for Right block: mark as free (bit 7 = 1) and set order (O - 1)
    ; Page index = (right_block_ptr - start_addr) / 4096
    mov rax, rdi
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = right page index
    
    mov rbx, [buddy_metadata]
    mov rdx, r13
    or rdx, 0x80                    ; free | order
    mov [rbx + rax], dl             ; metadata[right_index] = free | (O - 1)

    ; Left block (R14) is split to order O - 1, and we keep splitting it if O - 1 > R
    jmp .split_loop

.alloc_done:
    ; R14 is the allocated block of order R (R12)
    ; Update metadata for Left block: mark as allocated (bit 7 = 0) and set order (R)
    mov rax, r14
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = allocated page index

    mov rbx, [buddy_metadata]
    mov [rbx + rax], r12b           ; metadata[index] = R (allocated, order R)

    mov rax, r14                    ; return allocated block address in RAX
    jmp .exit

.oom:
    xor rax, rax

.exit:
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

%endif ; LIB_MEM_BUDDY_BUDDY_ALLOC_ASM
