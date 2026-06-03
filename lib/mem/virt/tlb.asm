; =============================================================================
; Tattva OS — lib/mem/virt/tlb.asm
; =============================================================================
; TLB (Translation Lookaside Buffer) management operations.
;
; 4.1: Individual page invalidation (invlpg)
; 4.2: Complete TLB flush (CR3 reload)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_TLB_ASM
%define LIB_MEM_VIRT_TLB_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; tlb_flush_page — invalidate a single page in the TLB (4.1)
; Input:
;   RDI = virtual address of the page to invalidate
; Output: none
; Clobbers: none
; NOTE: This is the preferred method for single-page changes (map/unmap/
;       permission update). Much cheaper than a full TLB flush.
; -----------------------------------------------------------------------------
global tlb_flush_page
tlb_flush_page:
    invlpg [rdi]
    ret

; -----------------------------------------------------------------------------
; tlb_flush_range — invalidate a contiguous range of pages in the TLB (4.1)
; Input:
;   RDI = starting virtual address (page-aligned)
;   RSI = number of pages to invalidate
; Output: none
; Clobbers: RAX, RCX
; NOTE: For large ranges (> ~32 pages), a full CR3 reload via
;       tlb_flush_all may be faster due to invlpg serialization cost.
; -----------------------------------------------------------------------------
global tlb_flush_range
tlb_flush_range:
    mov rcx, rsi                    ; RCX = page count
    mov rax, rdi                    ; RAX = current virtual address

    test rcx, rcx
    jz .done

.loop:
    invlpg [rax]
    add rax, 4096                   ; next page
    dec rcx
    jnz .loop

.done:
    ret

; -----------------------------------------------------------------------------
; tlb_flush_all — flush all non-global TLB entries via CR3 reload (4.2)
; Input:  none
; Output: none
; Clobbers: RAX
; NOTE: This evicts ALL cached translations except those with the Global
;       bit set (PAGE_GLOBAL). Use sparingly — it is expensive. Preferred
;       only when many pages changed (e.g. address space switch, bulk unmap).
; -----------------------------------------------------------------------------
global tlb_flush_all
tlb_flush_all:
    mov rax, cr3
    mov cr3, rax                    ; reload CR3 → flushes all non-global entries
    ret

; -----------------------------------------------------------------------------
; tlb_flush_all_global — flush ALL TLB entries including global pages (4.2)
; Input:  none
; Output: none
; Clobbers: RAX
; NOTE: Temporarily clears CR4.PGE (bit 7) to force eviction of global
;       entries, then re-enables it. Required when modifying kernel mappings
;       marked with PAGE_GLOBAL.
; -----------------------------------------------------------------------------
global tlb_flush_all_global
tlb_flush_all_global:
    mov rax, cr4
    and rax, ~(1 << 7)              ; clear PGE bit
    mov cr4, rax                    ; flush all TLB entries (including global)
    or rax, (1 << 7)                ; re-set PGE bit
    mov cr4, rax
    ret

%endif ; LIB_MEM_VIRT_TLB_ASM
