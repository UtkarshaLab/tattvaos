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

section .text

%include "lib/mem/buddy/buddy_init.asm"
%include "lib/mem/buddy/buddy_alloc.asm"
%include "lib/mem/buddy/buddy_free.asm"

section .data

global buddy_start_addr
global buddy_end_addr
global buddy_metadata

buddy_start_addr: dq 0
buddy_end_addr:   dq 0
buddy_metadata:   dq 0

section .bss

align 8
global buddy_free_heads
buddy_free_heads: resb 12 * 8       ; 12 list heads for orders 0 to 11

%endif ; LIB_MEM_BUDDY_BUDDY_ASM
