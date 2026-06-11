; =============================================================================
; Tattva OS — unet/core/link/net_ring.inc
; =============================================================================
; Shared constants, structures, and extern declarations for zero-copy network rings.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_NET_RING_INC
%define UNET_CORE_LINK_NET_RING_INC

[BITS 64]

; -----------------------------------------------------------------------------
; Virtual Space Limits & Caching Flags
; -----------------------------------------------------------------------------
NET_RING_VIRT_START equ 0x800000000000
NET_PCI_VIRT_START  equ 0x900000000000

; Page table mapping flags
%ifndef PAGE_PRESENT
    %define PAGE_PRESENT    (1 << 0)
%endif
%ifndef PAGE_WRITABLE
    %define PAGE_WRITABLE   (1 << 1)
%endif
%ifndef PAGE_USER
    %define PAGE_USER       (1 << 2)
%endif
%ifndef PAGE_PWT
    %define PAGE_PWT        (1 << 3)        ; Write-Through
%endif
%ifndef PAGE_PCD
    %define PAGE_PCD        (1 << 4)        ; Cache Disable (Uncacheable UC)
%endif
%ifndef PAGE_NX
    %define PAGE_NX         (1 << 63)       ; No-Execute
%endif

; VMA permission flags
%ifndef VMA_READ
    %define VMA_READ        (1 << 0)
%endif
%ifndef VMA_WRITE
    %define VMA_WRITE       (1 << 1)
%endif
%ifndef VMA_USER
    %define VMA_USER        (1 << 3)
%endif

; -----------------------------------------------------------------------------
; Structure Definitions
; -----------------------------------------------------------------------------

; 1. Packet Descriptor structure (32 bytes aligned)
struc net_desc_t
    .phys_addr      resq 1      ; Offset 0: 64-bit physical address of packet frame
    .length         resd 1      ; Offset 8: 32-bit length of buffer
    .flags          resw 1      ; Offset 12: 16-bit status/control flags (bit 0 = OWNED_BY_DEV, bit 1 = EOP)
    .flow_hash      resd 1      ; Offset 14: 32-bit hardware flow hash (RSS hash)
    .cpu_id         resw 1      ; Offset 18: Target CPU ID for RSS flow affinity
    .reserved       resb 12     ; Offset 20: Padded to 32 bytes
endstruc

; 2. Ring structure descriptor
struc net_ring_t
    .desc_array     resq 1      ; Offset 0: Virtual address of descriptor array
    .desc_count     resd 1      ; Offset 8: Number of descriptors (must be power of two)
    .head_ptr       resq 1      ; Offset 12: Virtual pointer to head index page (shared)
    .tail_ptr       resq 1      ; Offset 20: Virtual pointer to tail index page (shared)
    .flags          resd 1      ; Offset 28: Ring flags (0 = RX, 1 = TX)
    .vma            resq 1      ; Offset 32: Backing VMA pointer
endstruc

; 3. Socket Buffer structure (48 bytes)
struc net_sbuf_t
    .phys_addr      resq 1      ; Offset 0: Physical packet frame pointer
    .virt_addr      resq 1      ; Offset 8: Kernel/User virtual address pointer
    .length         resd 1      ; Offset 16: Frame length
    .offset         resd 1      ; Offset 20: Frame payload offset
    .ref_count      resd 1      ; Offset 24: Atomic reference counter
    .flow_hash      resd 1      ; Offset 28: RSS flow hash
    .next           resq 1      ; Offset 32: Pointer to next sbuf (chaining)
endstruc

; 4. Page Recycle Pool structure
struc net_recycle_pool_t
    .frames         resq 512    ; Offset 0: Stack array of recycled physical frame pointers
    .count          resd 1      ; Offset 4096: Current stack depth
    .lock           resq 1      ; Offset 4104: Spinlock for safety
endstruc

; -----------------------------------------------------------------------------
; External VM & Memory Symbols
; -----------------------------------------------------------------------------
extern heap_alloc
extern heap_free
extern virt_find_free_range
extern vma_create
extern vma_destroy
extern phys_alloc_page
extern phys_free_page
extern virt_map
extern virt_unmap
extern virt_translate
extern smp_active_cores
extern kernel_end
extern kernel_panic
extern uart_print_str
extern uart_print_hex64

%endif ; UNET_CORE_LINK_NET_RING_INC
