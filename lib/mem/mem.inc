; =============================================================================
; Tattva OS — lib/mem/mem.inc
; =============================================================================
; Memory management definitions, structures, and offsets.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_MEM_INC
%define LIB_MEM_MEM_INC

; E820 memory map entry structure
struc e820_entry
    .base       resq 1          ; Base physical address (64-bit)
    .length     resq 1          ; Region length in bytes (64-bit)
    .type       resd 1          ; Region type: 1=Usable, 2=Reserved, 3=ACPI, 4=NVS
    .attrs      resd 1          ; Extended attributes
endstruc

; Core physical allocator state structure
struc phys_state_t
    .bitmap_addr    resq 1      ; Physical address of the page bitmap
    .bitmap_size    resq 1      ; Size of the bitmap in bytes
    .total_pages    resq 1      ; Total usable pages in system
    .free_pages     resq 1      ; Current free page count
    .max_phys_addr  resq 1      ; Maximum physical RAM address detected
    .reserved_pages resq 1      ; Number of reserved/allocated pages
    .swap_pages     resq 1      ; Number of swapped pages
    .dirty_pages    resq 1      ; Number of dirty pages
endstruc

; Slab allocator cache descriptor structure
struc kmem_cache_t
    .name           resq 1      ; Pointer to name string (ASCIIZ)
    .obj_size       resq 1      ; Size of each object in bytes
    .align_size     resq 1      ; Alignment boundary (e.g. 8 or 16)
    .slabs_full     resq 1      ; Head pointer to full slabs list
    .slabs_part     resq 1      ; Head pointer to partial slabs list
    .slabs_free     resq 1      ; Head pointer to empty slabs list
    .lock           resq 1      ; Spinlock for multiprocessor safety
    .ctor           resq 1      ; Object constructor function pointer (optional)
    .dtor           resq 1      ; Object destructor function pointer (optional)
    .colour_next    resq 1      ; Next color offset index
    .colour_max     resq 1      ; Maximum color offset count
endstruc

; Slab management structure
struc slab_t
    .magic          resq 1      ; Verification magic (e.g. 0x51AB51AB)
    .next           resq 1      ; Next slab in current list
    .prev           resq 1      ; Prev slab in current list
    .mem_start      resq 1      ; Start of object payload area in slab
    .free_head      resq 1      ; Head of free objects singly-linked list
    .obj_count      resq 1      ; Total capacity of objects in slab
    .used_count     resq 1      ; Count of allocated objects in slab
endstruc

; Buddy Allocator block header
struc buddy_block_t
    .next       resq 1          ; Next free block in list
    .prev       resq 1          ; Prev free block in list
    .order      resq 1          ; Order of this block
endstruc

; Arena allocator header
struc arena_t
    .start      resq 1          ; Start of allocation payload (16-byte aligned)
    .end        resq 1          ; End of allocation space (exclusive)
    .current    resq 1          ; Current allocation bump pointer
endstruc

; Fixed-size pool allocator header
struc pool_t
    .obj_size   resq 1          ; Aligned size of each object slot
    .capacity   resq 1          ; Max objects in this pool
    .count      resq 1          ; Number of active allocations
    .memory     resq 1          ; Pointer to start of payload memory region
    alignb 16
    .free_head  resq 1          ; Pointer to the first free slot (16-byte aligned)
    .free_tag   resq 1          ; ABA-prevention tag counter (16-byte aligned)
endstruc

; NUMA memory range mapping structure
struc numa_range_t
    .base       resq 1          ; Base physical address (64-bit)
    .length     resq 1          ; Range length in bytes (64-bit)
    .node_id    resd 1          ; Proximity Domain / Node ID (32-bit)
    .flags      resd 1          ; Flags (bit 0 = Enabled)
endstruc

; NUMA node structure
struc numa_node_t
    .node_id         resd 1          ; Proximity Domain / Node ID
    .flags           resd 1          ; Flags (bit 0 = Active/Present, bit 1 = Bitmaps Init)
    .start_page      resq 1          ; Smallest page index in this node
    .end_page        resq 1          ; Largest page index in this node (exclusive)
    .bitmap_addr     resq 1          ; Physical address of this node's bitmap
    .bitmap_size     resq 1          ; Size of this node's bitmap in bytes
    .total_pages     resq 1          ; Usable page count in this node
    .free_pages      resq 1          ; Free page count in this node
    .reserved_pages  resq 1          ; Reserved page count in this node
endstruc

; Heap block signatures (Subfeature 19.3: Double-Free Verifier)
HEAP_BLOCK_FREE_SIG equ 0x54415454414C4F40 ; "TATTALO0" (bit 0 = 0)
HEAP_BLOCK_USED_SIG equ 0x54415454414C4F41 ; "TATTALO1" (bit 0 = 1)

%endif ; LIB_MEM_MEM_INC
