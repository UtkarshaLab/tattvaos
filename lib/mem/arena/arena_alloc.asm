; =============================================================================
; Tattva OS — lib/mem/arena/arena_alloc.asm
; =============================================================================
; Arena Allocation: Bump allocate memory from an arena with 16-byte alignment.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_ARENA_ARENA_ALLOC_ASM
%define LIB_MEM_ARENA_ARENA_ALLOC_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; arena_alloc — bump allocates memory from the specified arena
; Input:
;   RDI = pointer to the arena (arena_t)
;   RSI = size of the allocation in bytes
; Output:
;   RAX = pointer to the allocated block, or 0 if OOM or invalid arguments
; Clobbers: none (preserves all non-volatile registers)
; -----------------------------------------------------------------------------
global arena_alloc
arena_alloc:
    push rbx
    push rcx
    push rdx
    push rsi

    ; Validate arena pointer
    test rdi, rdi
    jz .fail

    ; Validate requested size
    test rsi, rsi
    jz .fail

    ; Align requested size to a 16-byte boundary
    mov rax, rsi
    add rax, 15
    jc .fail                        ; check overflow
    and rax, -16                    ; RAX = aligned size

    ; Retrieve current pointer and end pointer
    mov rbx, [rdi + arena_t.current]
    mov rcx, [rdi + arena_t.end]

    ; Calculate new current pointer
    mov rdx, rbx
    add rdx, rax                    ; RDX = new_current = current + aligned_size
    jc .fail                        ; check overflow

    ; Check if new_current exceeds end pointer (unsigned comparison)
    cmp rdx, rcx
    ja .fail                        ; if new_current > end, fail (OOM)

    ; Update current pointer in arena header
    mov [rdi + arena_t.current], rdx

    ; Return the old current pointer (start of allocated block)
    mov rax, rbx
    jmp .exit

.fail:
    xor rax, rax

.exit:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

%endif ; LIB_MEM_ARENA_ARENA_ALLOC_ASM
