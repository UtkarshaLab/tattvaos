; =============================================================================
; Tattva OS — lib/mem/arena/arena.asm
; =============================================================================
; Arena Allocator top-level include module.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_ARENA_ARENA_ASM
%define LIB_MEM_ARENA_ARENA_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

%include "lib/mem/arena/arena_create.asm"
%include "lib/mem/arena/arena_alloc.asm"
%include "lib/mem/arena/arena_reset.asm"
%include "lib/mem/arena/arena_destroy.asm"
%include "lib/mem/arena/arena_checkpoint.asm"
%include "lib/mem/arena/arena_local.asm"

%endif ; LIB_MEM_ARENA_ARENA_ASM
