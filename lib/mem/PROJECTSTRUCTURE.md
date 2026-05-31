# Tattva OS — lib/mem/ Complete File Structure

> Physical and virtual memory management primitives.
> The absolute foundation — nothing else can exist without this.
> Zero dependencies. Builds first. Everything else depends on this.

---

## Full Directory + File List

```
lib/mem/
│
├── Makefile                        ← build mem module
├── mem.asm                         ← top level, includes all below
├── mem.inc                         ← public API definitions, structs, constants
│
├── phys/                           ← physical memory management
│   ├── phys.asm                    ← physical memory manager entry
│   ├── map.asm                     ← parse E820 map from bootloader
│   ├── map_print.asm               ← debug print memory map
│   ├── bitmap.asm                  ← page bitmap allocator
│   │                                  one bit per 4KB page
│   │                                  0 = free, 1 = used
│   ├── bitmap_set.asm              ← mark page as used
│   ├── bitmap_clear.asm            ← mark page as free
│   ├── bitmap_find.asm             ← find N contiguous free pages
│   └── regions.asm                 ← memory region tracker
│                                      DMA region (0-16MB)
│                                      normal region (16MB+)
│                                      reserved regions
│
├── virt/                           ← virtual memory management
│   ├── virt.asm                    ← virtual memory manager entry
│   ├── pgtable.asm                 ← page table management
│   │                                  PML4 → PDPT → PD → PT
│   ├── pgtable_map.asm             ← map virtual → physical
│   ├── pgtable_unmap.asm           ← unmap virtual address
│   ├── pgtable_walk.asm            ← walk page table for address
│   ├── pgtable_flags.asm           ← page flags constants
│   │                                  present, writable, user
│   │                                  NX, huge, global
│   ├── tlb.asm                     ← TLB flush operations
│   │                                  invlpg single page
│   │                                  full CR3 reload
│   └── identity.asm                ← identity map setup
│                                      virtual == physical
│                                      used during early boot
│
├── heap/                           ← kernel heap allocator
│   ├── heap.asm                    ← heap entry, init with region
│   ├── bump.asm                    ← bump allocator
│   │                                  simplest allocator possible
│   │                                  just increment pointer
│   │                                  no free, used for early boot
│   ├── free_list.asm               ← free list allocator
│   │                                  linked list of free blocks
│   │                                  first fit strategy
│   ├── free_list_alloc.asm         ← find free block, split if needed
│   ├── free_list_free.asm          ← return block, coalesce neighbors
│   └── free_list_verify.asm        ← debug: verify heap integrity
│
├── arena/                          ← arena allocator
│   ├── arena.asm                   ← arena entry
│   ├── arena_create.asm            ← create arena from region
│   ├── arena_alloc.asm             ← bump alloc within arena
│   ├── arena_reset.asm             ← reset arena to start (bulk free)
│   ├── arena_destroy.asm           ← destroy arena, return memory
│   └── arena_checkpoint.asm        ← save + restore arena position
│                                      for partial resets
│
├── pool/                           ← pool allocator (fixed size objects)
│   ├── pool.asm                    ← pool entry
│   ├── pool_create.asm             ← create pool for object size N
│   ├── pool_alloc.asm              ← get one object from pool
│   ├── pool_free.asm               ← return object to pool
│   └── pool_grow.asm               ← expand pool when exhausted
│
├── slab/                           ← slab allocator (kernel objects)
│   ├── slab.asm                    ← slab entry
│   ├── slab_create.asm             ← create slab cache for type
│   ├── slab_alloc.asm              ← allocate one object
│   ├── slab_free.asm               ← free one object
│   └── slab_reap.asm               ← reclaim empty slabs
│
├── ops/                            ← raw memory operations
│   ├── memcpy.asm                  ← copy N bytes src → dst
│   │                                  AVX2 fast path for large copies
│   │                                  fallback for small copies
│   ├── memset.asm                  ← fill N bytes with value
│   │                                  AVX2 fast path
│   ├── memcmp.asm                  ← compare N bytes
│   │                                  returns 0 equal, +/- different
│   ├── memmove.asm                 ← copy with overlap handling
│   │                                  handles src/dst overlap correctly
│   ├── memzero.asm                 ← zero N bytes
│   │                                  faster than memset(0)
│   │                                  uses AVX2 zero register
│   ├── memchr.asm                  ← find byte in memory
│   └── memrchr.asm                 ← find byte in memory reverse
│
├── huge/                           ← huge page management
│   ├── huge.asm                    ← huge page entry
│   ├── huge_alloc.asm              ← allocate 2MB huge page
│   ├── huge_free.asm               ← free huge page
│   └── huge_map.asm                ← map huge page into virtual space
│
├── pin/                            ← pinned memory (no swap, DMA safe)
│   ├── pin.asm                     ← pin memory region
│   └── unpin.asm                   ← unpin memory region
│
├── numa/                           ← NUMA-aware allocation
│   ├── numa.asm                    ← NUMA entry
│   ├── numa_detect.asm             ← detect NUMA topology
│   ├── numa_alloc.asm              ← alloc on specific NUMA node
│   └── numa_local.asm              ← alloc on current CPU NUMA node
│
└── tests/                          ← memory subsystem tests
    ├── test_phys.asm               ← physical allocator tests
    │                                  alloc page, verify bitmap
    │                                  free page, verify bitmap
    ├── test_virt.asm               ← virtual memory tests
    │                                  map, access, unmap
    │                                  verify TLB flush
    ├── test_heap.asm               ← heap allocator tests
    │                                  alloc, free, alloc again
    │                                  verify no corruption
    ├── test_arena.asm              ← arena tests
    │                                  alloc many, reset, alloc again
    ├── test_pool.asm               ← pool tests
    │                                  alloc N objects, free all
    ├── test_ops.asm                ← memcpy/memset/memcmp tests
    │                                  correctness + performance
    └── test_numa.asm               ← NUMA allocation tests
```

---

## Public API (mem.inc)

```asm
; ─────────────────────────────────────────────────────
; Physical memory
; ─────────────────────────────────────────────────────
; phys_init(e820_map, e820_count)
;   → initialise physical allocator from E820 map
;
; phys_alloc_page() → rax = physical address | 0 if OOM
;   → allocate one 4KB page
;
; phys_alloc_pages(rcx=count) → rax = physical address | 0
;   → allocate N contiguous 4KB pages
;
; phys_free_page(rdi=addr)
;   → free one 4KB page
;
; phys_free_pages(rdi=addr, rcx=count)
;   → free N contiguous pages

; ─────────────────────────────────────────────────────
; Virtual memory
; ─────────────────────────────────────────────────────
; virt_map(rdi=virt, rsi=phys, rdx=flags)
;   → map virtual address to physical
;
; virt_unmap(rdi=virt)
;   → unmap virtual address
;
; virt_translate(rdi=virt) → rax = phys | 0 if unmapped
;   → walk page table, return physical address

; ─────────────────────────────────────────────────────
; Heap
; ─────────────────────────────────────────────────────
; heap_init(rdi=start, rsi=size)
;   → initialise heap in given region
;
; heap_alloc(rdi=size) → rax = ptr | 0 if OOM
;   → allocate size bytes, 16-byte aligned
;
; heap_free(rdi=ptr)
;   → free previously allocated pointer
;
; heap_realloc(rdi=ptr, rsi=new_size) → rax = ptr | 0
;   → resize allocation

; ─────────────────────────────────────────────────────
; Arena
; ─────────────────────────────────────────────────────
; arena_create(rdi=size) → rax = arena_t ptr
;   → create new arena of given size
;
; arena_alloc(rdi=arena, rsi=size) → rax = ptr | 0
;   → bump allocate from arena
;
; arena_reset(rdi=arena)
;   → reset arena to start, reuse all memory
;
; arena_destroy(rdi=arena)
;   → destroy arena, return memory to heap

; ─────────────────────────────────────────────────────
; Pool
; ─────────────────────────────────────────────────────
; pool_create(rdi=obj_size, rsi=capacity) → rax = pool_t
;   → create pool for fixed size objects
;
; pool_alloc(rdi=pool) → rax = ptr | 0
;   → get one object from pool
;
; pool_free(rdi=pool, rsi=ptr)
;   → return object to pool

; ─────────────────────────────────────────────────────
; Raw ops
; ─────────────────────────────────────────────────────
; memcpy(rdi=dst, rsi=src, rdx=len)
; memset(rdi=dst, rsi=val, rdx=len)
; memcmp(rdi=a, rsi=b, rdx=len) → rax = 0 | +/-
; memmove(rdi=dst, rsi=src, rdx=len)
; memzero(rdi=dst, rsi=len)
```

---

## Key Structs (mem.inc)

```asm
; E820 memory map entry
struc e820_entry
    .base       resq 1          ; base address
    .length     resq 1          ; length in bytes
    .type       resd 1          ; 1=usable, 2=reserved, 3=ACPI, 4=NVS
    .attrs      resd 1          ; extended attributes
endstruc

; Arena header (lives at start of arena memory)
struc arena_t
    .start      resq 1          ; arena start address
    .current    resq 1          ; current bump pointer
    .end        resq 1          ; arena end address
    .checkpoint resq 1          ; saved checkpoint position
endstruc

; Pool header
struc pool_t
    .obj_size   resq 1          ; size of each object
    .capacity   resq 1          ; max objects
    .count      resq 1          ; current used count
    .free_head  resq 1          ; head of free list
    .memory     resq 1          ; pointer to object memory
endstruc

; Heap block header (lives before each allocation)
struc heap_block_t
    .size       resq 1          ; size of this block (not including header)
    .flags      resq 1          ; bit 0 = used/free
    .next       resq 1          ; next block in free list
    .prev       resq 1          ; prev block in free list
endstruc
```

---

## Memory Layout

```
Physical address space (x86-64):

0x0000_0000 - 0x0000_04FF   → BIOS data area (reserved)
0x0000_0500 - 0x0000_7BFF   → Free (stage1 stack)
0x0000_7C00 - 0x0000_7DFF   → Stage1 MBR (relocated to 0x0600)
0x0000_8000 - 0x0000_FFFF   → Stage2
0x0001_0000 - 0x0009_FFFF   → Free (available for boot use)
0x000A_0000 - 0x000F_FFFF   → BIOS/VGA reserved
0x0010_0000 - ...           → Kernel loads here (1MB mark)
...
0x0009_000  - 0x0009_0FFF   → survive/ snapshot page (hidden)

Virtual address space (Tattva kernel):

0xFFFF_8000_0000_0000+      → kernel space
0x0000_0000_0000_0000+      → not used (null pointer protection)
```

---

## Build Priority

```
Phase 1 — Absolute minimum (build first)
    ops/memcpy.asm              ← needed by everything
    ops/memset.asm              ← needed by everything
    ops/memcmp.asm              ← needed by everything
    ops/memmove.asm             ← needed by everything
    ops/memzero.asm             ← needed by everything
    phys/map.asm                ← parse E820 from bootloader
    phys/bitmap.asm             ← page allocator
    phys/phys.asm               ← tie it together
    heap/bump.asm               ← simplest allocator first
    → milestone: can allocate memory, memcpy works

Phase 2 — Full heap
    heap/free_list.asm          ← real allocator with free
    heap/free_list_alloc.asm
    heap/free_list_free.asm
    → milestone: malloc + free working

Phase 3 — Virtual memory
    virt/pgtable.asm
    virt/pgtable_map.asm
    virt/pgtable_unmap.asm
    virt/tlb.asm
    → milestone: virtual memory working

Phase 4 — Arena + Pool
    arena/ (all files)
    pool/ (all files)
    → milestone: fast per-component allocators

Phase 5 — Advanced
    slab/ (all files)
    huge/ (all files)
    pin/ (all files)
    numa/ (all files)
    → milestone: full memory system

Phase 6 — Tests
    tests/ (all files)
    → milestone: verified correct
```

---

## Notes

```
1. Build ops/ first — memcpy/memset are needed before
   anything else can run. These are 10-20 lines each.
   AVX2 fast path matters for inference later.

2. Bump allocator before free list
   Get something working, then make it good.
   bump.asm is ~30 lines. Ship it first.

3. The heap block header adds 32 bytes overhead per alloc.
   For small objects use pool allocator instead.
   For temporary bulk allocations use arena.
   Right tool for each job.

4. NUMA allocation matters for inference
   Model weights should be on same NUMA node as GPU
   Implement numa_local.asm early for this reason
   Even if you only have one NUMA node now.

5. memcpy AVX2 path:
   < 32 bytes  → scalar fallback
   >= 32 bytes → vmovdqu ymm0, [rsi]
                 vmovdqu [rdi], ymm0
                 this is the hot path for weight loading

6. arena_reset is your secret weapon
   Per-request arena in inference:
   arena_alloc for all request temporaries
   arena_reset when request done
   zero fragmentation, zero overhead free
   perfect for inference workloads
```
