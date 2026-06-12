; =============================================================================
; Tattva OS — lib/mem/buddy/buddy.asm
; =============================================================================
; Buddy Allocator top-level include and tracking structures.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_BUDDY_BUDDY_ASM
%define LIB_MEM_BUDDY_BUDDY_ASM

[BITS 64]

%include "lib/mem/mem.inc"

; Buddy node structure definition (128 bytes, power-of-two aligned)
struc buddy_node_t
    .start_addr     resq 1          ; Base physical address
    .end_addr       resq 1          ; End physical address
    .metadata       resq 1          ; Page order metadata pointer
    .free_heads     resq 12         ; 12 free list head pointers (96 bytes)
    .flags          resq 1          ; Status flags (bit 0 = active)
endstruc

section .text

global buddy_save_context
buddy_save_context:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; Index is in RAX (0-7)
    imul rax, buddy_node_t_size
    lea rdi, [buddy_nodes + rax]

    ; Save start_addr, end_addr, metadata
    mov rcx, [buddy_start_addr]
    mov [rdi + buddy_node_t.start_addr], rcx
    mov rcx, [buddy_end_addr]
    mov [rdi + buddy_node_t.end_addr], rcx
    mov rcx, [buddy_metadata]
    mov [rdi + buddy_node_t.metadata], rcx

    ; Save free_heads (12 qwords = 96 bytes)
    lea rsi, [buddy_free_heads]
    lea rdi, [rdi + buddy_node_t.free_heads]
    mov rcx, 12
    cld
    rep movsq

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

global buddy_load_context
buddy_load_context:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; Index is in RAX (0-7)
    cmp rax, [buddy_active_node_index]
    je .done

    ; Save current active context if active index != -1
    mov rdx, [buddy_active_node_index]
    cmp rdx, -1
    je .load_new

    push rax
    mov rax, rdx
    call buddy_save_context
    pop rax

.load_new:
    mov [buddy_active_node_index], rax
    imul rax, buddy_node_t_size
    lea rsi, [buddy_nodes + rax]

    ; Load start_addr, end_addr, metadata
    mov rcx, [rsi + buddy_node_t.start_addr]
    mov [buddy_start_addr], rcx
    mov rcx, [rsi + buddy_node_t.end_addr]
    mov [buddy_end_addr], rcx
    mov rcx, [rsi + buddy_node_t.metadata]
    mov [buddy_metadata], rcx

    ; Load free_heads (12 qwords = 96 bytes)
    lea rsi, [rsi + buddy_node_t.free_heads]
    lea rdi, [buddy_free_heads]
    mov rcx, 12
    cld
    rep movsq

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

%include "lib/mem/buddy/buddy_init.asm"
%include "lib/mem/buddy/buddy_alloc.asm"
%include "lib/mem/buddy/buddy_free.asm"

section .data

global buddy_start_addr
global buddy_end_addr
global buddy_metadata
global buddy_node_count
global buddy_active_node_index

buddy_start_addr: dq 0
buddy_end_addr:   dq 0
buddy_metadata:   dq 0
buddy_node_count: dq 0
buddy_active_node_index: dq -1

section .bss

align 8
global buddy_free_heads
buddy_free_heads: resb 12 * 8       ; 12 list heads for orders 0 to 11

align 16
global buddy_nodes
buddy_nodes:      resb buddy_node_t_size * 8  ; Support up to 8 buddy allocator nodes

%endif ; LIB_MEM_BUDDY_BUDDY_ASM
