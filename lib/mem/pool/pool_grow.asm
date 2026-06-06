; =============================================================================
; Tattva OS — lib/mem/pool/pool_grow.asm
; =============================================================================
; Pool Expander: Requests a new page frame when the pool is saturated,
; partitions it into fixed-size slots, and links them atomically.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_POOL_POOL_GROW_ASM
%define LIB_MEM_POOL_POOL_GROW_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern phys_alloc_page
extern phys_free_page

; -----------------------------------------------------------------------------
; pool_grow — expands a saturated pool by allocating a new 4KB page frame
; Input:
;   RDI = pointer to the pool descriptor (pool_t)
; Output:
;   RAX = 1 on success, 0 on failure/OOM
; Clobbers: none (preserves non-volatile registers)
; -----------------------------------------------------------------------------
global pool_grow
pool_grow:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = pool descriptor pointer

    ; 1. Allocate a single 4KB page frame
    call phys_alloc_page            ; RAX = physical address (or 0 if OOM)
    test rax, rax
    jz .fail                        ; OOM failure

    mov r13, rax                    ; R13 = new block page address

    ; 2. Initialize new block header (block_hdr_t at offset 0 of R13)
    ; Next block pointer is at [r13] (initialize to 0)
    ; Capacity is at [r13 + 8]
    ; Let's compute slot capacity for this 4KB block: (4096 - 16) / obj_size
    mov r15, 4080                   ; R15 = 4096 - 16
    xor rdx, rdx
    mov rax, r15
    div qword [r12 + pool_t.obj_size] ; RAX = slot_capacity, RDX = remainder
    mov r14, rax                    ; R14 = slot_capacity

    test r14, r14
    jz .fail_free_page              ; If object size is too large to fit even one slot (fail safe)

    mov [r13 + 8], r14              ; Store block capacity in header

    ; 3. Build the intrusive free list inside the new page block
    ; Slots start at R13 + 16 (first slot)
    mov r15, r13
    add r15, 16                     ; R15 = current slot address (S_0)
    mov rcx, [r12 + pool_t.obj_size] ; RCX = obj_size
    xor r8, r8                      ; R8 = index counter (i)

.link_loop:
    mov r9, r8
    inc r9                          ; R9 = i + 1
    cmp r9, r14
    je .link_done                   ; If next is slot_capacity, we've linked all internal slots

    ; Next slot pointer = current + obj_size
    mov rdx, r15
    add rdx, rcx                    ; RDX = next slot pointer
    mov [r15], rdx                  ; Current slot points to next slot

    mov r15, rdx                    ; current = next
    inc r8
    jmp .link_loop

.link_done:
    ; R15 points to the last slot in the page.
    ; Now, atomically prepend the new slots chain to the pool's free list.
    ; We read the current free_head and free_tag to expected registers RDX:RAX
    mov rax, [r12 + pool_t.free_head]
    mov rdx, [r12 + pool_t.free_tag]

.cas_loop:
    ; Link the last slot of our new block to the current free_head (RAX)
    mov [r15], rax

    ; Set desired values for double-width CAS (cmpxchg16b):
    ; RBX = new free_head = R13 + 16 (first slot of new block)
    mov rbx, r13
    add rbx, 16
    ; RCX = new free_tag = RDX + 1 (incremented tag)
    mov rcx, rdx
    inc rcx

    lock cmpxchg16b [r12 + pool_t.free_head]
    jnz .cas_loop                   ; If ZF = 0, retry with updated RDX:RAX

    ; CAS succeeded! Now atomically link the block itself to the block list.
    ; The block list starts at pool.memory - 16.
    mov r8, [r12 + pool_t.memory]
    sub r8, 16                      ; R8 = first block address

    ; Read current first_block.next
    mov rax, [r8]                   ; RAX = first_block.next

.block_cas_loop:
    ; Set new_block.next = first_block.next
    mov [r13], rax

    ; Perform atomic CAS to update first_block.next to our new block (R13)
    lock cmpxchg [r8], r13
    jnz .block_cas_loop             ; If ZF = 0, retry with updated RAX

    ; Atomically update the pool descriptor's total capacity
    lock add [r12 + pool_t.capacity], r14

    mov rax, 1                      ; Return 1 (success)
    jmp .exit

.fail_free_page:
    mov rdi, r13
    call phys_free_page

.fail:
    xor rax, rax                    ; Return 0 (failure/OOM)

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_POOL_POOL_GROW_ASM
