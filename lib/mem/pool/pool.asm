; =============================================================================
; Tattva OS — lib/mem/pool/pool.asm
; =============================================================================
; Fixed-Size Pool Allocator top-level include module.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_POOL_POOL_ASM
%define LIB_MEM_POOL_POOL_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

%include "lib/mem/pool/pool_create.asm"
%include "lib/mem/pool/pool_alloc.asm"
%include "lib/mem/pool/pool_free.asm"

%endif ; LIB_MEM_POOL_POOL_ASM
