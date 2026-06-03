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
endstruc

%endif ; LIB_MEM_MEM_INC
