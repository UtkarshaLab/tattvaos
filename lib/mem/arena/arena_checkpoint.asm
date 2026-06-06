; =============================================================================
; Tattva OS — lib/mem/arena/arena_checkpoint.asm
; =============================================================================
; Arena Checkpointing: Save and restore allocation points (Subfeature 12.3: Arena Checkpoints).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_ARENA_ARENA_CHECKPOINT_ASM
%define LIB_MEM_ARENA_ARENA_CHECKPOINT_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; -----------------------------------------------------------------------------
; arena_checkpoint_save — returns the current bump pointer of the arena
; Input:
;   RDI = pointer to the arena (arena_t)
; Output:
;   RAX = current allocation pointer (checkpoint value), or 0 if NULL
; Clobbers: none
; -----------------------------------------------------------------------------
global arena_checkpoint_save
arena_checkpoint_save:
    test rdi, rdi
    jz .fail

    mov rax, [rdi + arena_t.current]
    ret

.fail:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; arena_checkpoint_restore — restores the arena bump pointer to a saved checkpoint
; Input:
;   RDI = pointer to the arena (arena_t)
;   RSI = checkpoint value (previously saved allocation pointer)
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
global arena_checkpoint_restore
arena_checkpoint_restore:
    test rdi, rdi
    jz .exit

    ; Validate checkpoint is within managed memory bounds: start <= checkpoint <= end
    mov rax, [rdi + arena_t.start]
    cmp rsi, rax
    jb .exit                        ; if checkpoint < start, ignore

    mov rax, [rdi + arena_t.end]
    cmp rsi, rax
    ja .exit                        ; if checkpoint > end, ignore

    ; Restore current pointer
    mov [rdi + arena_t.current], rsi

.exit:
    ret

%endif ; LIB_MEM_ARENA_ARENA_CHECKPOINT_ASM
