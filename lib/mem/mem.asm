; =============================================================================
; Tattva OS — lib/mem/mem.asm
; =============================================================================
; Memory management library top-level include wrapper.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_MEM_ASM
%define LIB_MEM_MEM_ASM

[BITS 64]

%include "lib/mem/mem.inc"
%include "lib/mem/ops/memcpy.asm"
%include "lib/mem/ops/memset.asm"
%include "lib/mem/ops/memzero.asm"
%include "lib/mem/ops/memcmp.asm"
%include "lib/mem/ops/memmove.asm"
%include "lib/mem/phys/map.asm"
%include "lib/mem/phys/bitmap.asm"
%include "lib/mem/phys/phys.asm"
%include "lib/mem/heap/free_list.asm"

%endif ; LIB_MEM_MEM_ASM
