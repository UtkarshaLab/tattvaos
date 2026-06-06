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

    push r8
    push r9
    push r10
    push r11

    ; Validate pointer is within pool memory range
    ; Walk the singly-linked list of blocks to find which one contains RSI
    mov r8, [rdi + pool_t.memory]
    sub r8, 16                      ; R8 = first block address (B)
    mov r9, [rdi + pool_t.obj_size] ; R9 = obj_size

.check_block_loop:
    test r8, r8
    jz .invalid_slot                ; end of block list, slot not found in any block, ignore free

    ; Fetch block capacity (B.capacity is at [r8 + 8])
    mov r10, [r8 + 8]               ; R10 = capacity of this block
    
    ; Calculate slot area range for this block
    mov r11, r8
    add r11, 16                     ; R11 = slot area start = B + 16
    
    mov rax, r10
    imul rax, r9                    ; RAX = B.capacity * obj_size
    add rax, r11                    ; RAX = slot area end = start + capacity * obj_size
    
    ; Check if RSI is within [R11, RAX)
    cmp rsi, r11
    jb .next_block
    cmp rsi, rax
    jae .next_block
    
    ; RSI is in this block! Now validate alignment: (RSI - R11) % obj_size == 0
    mov rax, rsi
    sub rax, r11                    ; RAX = offset
    xor rdx, rdx
    div r9                          ; RAX = slot index, RDX = remainder
    test rdx, rdx
    jnz .invalid_slot               ; misaligned offset, ignore free
    
    ; Valid slot! Proceed to push to free list
    jmp .valid_slot

.next_block:
    mov r8, [r8]                    ; R8 = next block (B.next)
    jmp .check_block_loop

.invalid_slot:
    pop r11
    pop r10
    pop r9
    pop r8
    jmp .exit_pop

.valid_slot:
    pop r11
    pop r10
    pop r9
    pop r8

    ; Load current free_head and free_tag to expected registers RDX:RAX
    mov rax, [rdi + pool_t.free_head]
    mov rdx, [rdi + pool_t.free_tag]

.retry:
    ; Write current free_head (RAX) into the first 8 bytes of the freed slot (RSI)
    mov [rsi], rax

    ; Set new head = rsi (RBX) and new tag = current tag + 1 (RCX)
    mov rbx, rsi
    mov rcx, rdx
    inc rcx                         ; RCX = new_tag = tag + 1

    ; Perform double-width Compare-And-Swap
    lock cmpxchg16b [rdi + pool_t.free_head]
    jnz .retry                      ; if ZF = 0, retry with updated RDX:RAX

    ; CAS succeeded! Decrement used count atomically
    lock dec qword [rdi + pool_t.count]

.exit_pop:
    pop rax
    pop rcx
    pop rdx
    pop rbx
.exit:
    ret

%endif ; LIB_MEM_POOL_POOL_FREE_ASM
