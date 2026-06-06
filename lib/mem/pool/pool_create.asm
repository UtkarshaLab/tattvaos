; =============================================================================
; Tattva OS — lib/mem/pool/pool_create.asm
; =============================================================================
; Pool Creator: Allocates memory and partitions it into fixed-size slots.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_POOL_POOL_CREATE_ASM
%define LIB_MEM_POOL_POOL_CREATE_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern heap_alloc
extern heap_free

; -----------------------------------------------------------------------------
; pool_create — creates a new fixed-size object pool allocator
; Input:
;   RDI = object size in bytes
;   RSI = capacity (max number of slots)
; Output:
;   RAX = pointer to pool_t, or 0 if invalid params or OOM
; Clobbers: none (preserves non-volatile registers)
; -----------------------------------------------------------------------------
global pool_create
pool_create:
    ; Validate parameters
    test rdi, rdi
    jz .fail_early
    test rsi, rsi
    jz .fail_early

    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = requested obj_size
    mov r13, rsi                    ; R13 = requested capacity

    ; Align object size to 8-byte boundary, with minimum size of 8 bytes
    mov rax, r12
    cmp rax, 8
    jae .align_size
    mov rax, 8                      ; minimum size of 8 bytes for next pointer
.align_size:
    add rax, 7
    and rax, -8
    mov r12, rax                    ; R12 = aligned size

    ; Calculate memory payload size: aligned_size * capacity + 16 (for block_hdr_t)
    mov rax, r12
    mul r13                         ; RDX:RAX = R12 * R13
    test rdx, rdx
    jnz .fail                       ; overflow check

    add rax, 16
    jc .fail                        ; overflow check
    mov r15, rax                    ; R15 = total allocation size including block header

    ; 1. Allocate pool_t descriptor block
    mov rdi, pool_t_size
    call heap_alloc                 ; RAX = pool descriptor pointer
    test rax, rax
    jz .fail
    mov r14, rax                    ; R14 = pool descriptor

    ; 2. Allocate the object memory block
    mov rdi, r15
    call heap_alloc                 ; RAX = memory region start
    test rax, rax
    jz .free_desc_and_fail

    ; Initialize the block header for this first block
    mov qword [rax], 0              ; next_block = NULL
    mov [rax + 8], r13              ; capacity = initial capacity

    ; Store configuration
    mov [r14 + pool_t.obj_size], r12
    mov [r14 + pool_t.capacity], r13
    mov [r14 + pool_t.count], qword 0
    
    mov rbx, rax
    add rbx, 16                     ; RBX = pointer to the first slot
    mov [r14 + pool_t.memory], rbx
    mov [r14 + pool_t.free_head], rbx
    mov qword [r14 + pool_t.free_tag], 0

    ; 3. Build the intrusive stack-based free list
    mov rdx, rbx                    ; RDX = current slot pointer (starts at memory + 16)
    xor rcx, rcx                    ; RCX = loop counter (i)

.link_loop:
    mov rbx, rcx
    inc rbx                         ; RBX = i + 1
    cmp rbx, r13
    je .link_last                   ; if next is capacity, it is the last slot

    ; Calculate next slot address
    mov rsi, rdx
    add rsi, r12                    ; RSI = next slot pointer = current + aligned_size

    ; Write next slot address into the first 8 bytes of current slot
    mov [rdx], rsi

    mov rdx, rsi                    ; current = next
    inc rcx
    jmp .link_loop

.link_last:
    ; Terminate the free list inside the last slot with NULL (0)
    mov qword [rdx], 0

    mov rax, r14                    ; RAX = pool pointer
    jmp .exit

.free_desc_and_fail:
    mov rdi, r14
    call heap_free

.fail:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
.fail_early:
    xor rax, rax
    ret

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_POOL_POOL_CREATE_ASM
