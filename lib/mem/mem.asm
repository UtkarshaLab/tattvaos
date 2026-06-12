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
%include "lib/mem/ops/user_copy.asm"
%include "lib/mem/phys/map.asm"
%include "lib/mem/phys/bitmap.asm"
%include "lib/mem/phys/phys.asm"
%include "lib/mem/heap/bump.asm"
%include "lib/mem/heap/free_list.asm"
%include "lib/mem/heap/leak_tracker.asm"
%include "lib/mem/heap/heap.asm"
%include "lib/mem/heap/defrag.asm"


%include "lib/mem/slab/slab.asm"
%include "lib/mem/slab/slab_create.asm"
%include "lib/mem/slab/slab_alloc.asm"
%include "lib/mem/slab/slab_free.asm"
%include "lib/mem/slab/slab_reap.asm"
%include "lib/mem/buddy/buddy.asm"
%include "lib/mem/arena/arena.asm"
%include "lib/mem/pool/pool.asm"
%include "lib/mem/numa/numa.asm"
%include "lib/mem/numa/numa_detect.asm"


%include "lib/mem/virt/sched_affinity.asm"
%include "lib/mem/virt/spec_walk.asm"
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
%include "lib/mem/virt/zswap.asm"
%include "lib/mem/virt/swap.asm"
%include "lib/mem/virt/kswapd.asm"
%include "lib/mem/virt/uaf.asm"
%include "lib/mem/virt/stack.asm"
%include "lib/mem/virt/pf.asm"
%include "lib/mem/virt/ept.asm"
%include "lib/mem/virt/spt.asm"
%include "lib/mem/virt/vtlb.asm"
%include "lib/mem/virt/eve.asm"
%include "lib/mem/virt/pml.asm"
%include "lib/mem/virt/nested.asm"
%include "lib/mem/virt/hmm.asm"
%include "lib/mem/virt/dmabuf.asm"
%include "lib/mem/virt/gpummu.asm"
%include "lib/mem/virt/p2pdma.asm"
%include "lib/mem/virt/hmm_metrics.asm"
%include "lib/mem/virt/acpi_hotplug.asm"
%include "lib/mem/virt/kernel_relocator.asm"
%include "lib/mem/virt/zone_transition.asm"
%include "lib/mem/virt/locality_scorer.asm"

%include "lib/mem/virt/replacement.asm"
%include "storage/ummapf/mmap.asm"
%include "lib/mem/virt/ipc.asm"

%endif ; LIB_MEM_MEM_ASM



