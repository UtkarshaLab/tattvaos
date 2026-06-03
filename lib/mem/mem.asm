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
%include "lib/mem/phys/map.asm"
%include "lib/mem/phys/bitmap.asm"
%include "lib/mem/phys/phys.asm"

%endif ; LIB_MEM_MEM_ASM
