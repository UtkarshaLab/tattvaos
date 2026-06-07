; =============================================================================
; Tattva OS — lib/mem/arena/arena_reset.asm
; =============================================================================
; Arena Reset: Resets the bump pointer back to start (Subfeature 12.2: O(1) Bulk Deallocations).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_ARENA_ARENA_RESET_ASM
%define LIB_MEM_ARENA_ARENA_RESET_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; arena_reset — resets the arena current pointer back to start (bulk free)
; Input:
;   RDI = pointer to the arena (arena_t)
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
global arena_reset
arena_reset:
    test rdi, rdi
    jz .exit

    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rbx, rdi                    ; RBX = arena pointer
    mov rdi, [rbx + arena_t.start]  ; RDI = start address
    mov rsi, [rbx + arena_t.current]; RSI = current address
    sub rsi, rdi                    ; RSI = size used
    jz .done_zero

    call memzero

.done_zero:
    mov rax, [rbx + arena_t.start]
    mov [rbx + arena_t.current], rax

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
.exit:
    ret

%endif ; LIB_MEM_ARENA_ARENA_RESET_ASM
