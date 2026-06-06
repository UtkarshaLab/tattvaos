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
%include "lib/mem/virt/pgtable.asm"
%include "lib/mem/virt/tlb.asm"
%include "lib/mem/virt/tlb_shootdown.asm"
%include "lib/mem/virt/pgtable_cache.asm"
%include "lib/mem/virt/pgtable_lock.asm"
%include "lib/mem/virt/pgtable_split.asm"
%include "lib/mem/virt/pgtable_map.asm"
%include "lib/mem/virt/pgtable_unmap.asm"
%include "lib/mem/virt/pgtable_walk.asm"
%include "lib/mem/virt/virt.asm"
%include "lib/mem/virt/thp.asm"
%include "lib/mem/virt/swap_device.asm"
%include "lib/mem/virt/swap.asm"
%include "lib/mem/virt/pf.asm"
%include "lib/mem/virt/replacement.asm"

%endif ; LIB_MEM_MEM_ASM

