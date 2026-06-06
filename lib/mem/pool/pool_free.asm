; =============================================================================
; Tattva OS — lib/mem/pool/pool_free.asm
; =============================================================================
; Pool Deallocation: Pushes a slot back to the intrusive stack-based free list.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_POOL_POOL_FREE_ASM
%define LIB_MEM_POOL_POOL_FREE_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; pool_free — returns an allocated slot back to the pool in O(1) time
; Input:
;   RDI = pointer to the pool (pool_t)
;   RSI = pointer to the object/slot to free
; Output: none
; Clobbers: none (preserves non-volatile registers)
; -----------------------------------------------------------------------------
global pool_free
pool_free:
    ; Validate pointers
    test rdi, rdi
    jz .exit
    test rsi, rsi
    jz .exit

    push rbx
    push rdx
    push rcx
    push rax

    ; Validate pointer is within pool memory range
    mov rax, [rdi + pool_t.memory]  ; RAX = start of memory
    cmp rsi, rax
    jb .exit_pop                    ; if rsi < start, ignore

    mov rbx, [rdi + pool_t.capacity]
    imul rbx, [rdi + pool_t.obj_size] ; RBX = total memory size
    add rbx, rax                    ; RBX = end of memory
    cmp rsi, rbx
    jae .exit_pop                   ; if rsi >= end, ignore

    ; Validate slot alignment: (rsi - start) % obj_size == 0
    mov rax, rsi
    sub rax, [rdi + pool_t.memory]  ; RAX = offset
    xor rdx, rdx                    ; clear high bits for division
    div qword [rdi + pool_t.obj_size] ; RAX = slot index, RDX = remainder
    test rdx, rdx
    jnz .exit_pop                   ; if offset is not a multiple of obj_size, ignore

    ; Push the slot to the head of the free list
    mov rcx, [rdi + pool_t.free_head] ; RCX = current free_head
    mov [rsi], rcx                  ; store current free_head in freed slot
    mov [rdi + pool_t.free_head], rsi ; pool.free_head = freed slot

    ; Decrement count
    dec qword [rdi + pool_t.count]

.exit_pop:
    pop rax
    pop rcx
    pop rdx
    pop rbx
.exit:
    ret

%endif ; LIB_MEM_POOL_POOL_FREE_ASM
