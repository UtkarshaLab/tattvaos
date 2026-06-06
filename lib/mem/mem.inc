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

%endif ; LIB_MEM_MEM_INC
