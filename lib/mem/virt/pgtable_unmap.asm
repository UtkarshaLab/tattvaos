; =============================================================================
; Tattva OS — lib/mem/virt/pgtable_unmap.asm
; =============================================================================
; Virtual memory page unmapping API (clears entry and flushes TLB).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_UNMAP_ASM
%define LIB_MEM_VIRT_PGTABLE_UNMAP_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; virt_unmap — unmaps a virtual page
; Input:
;   RDI = virtual address to unmap
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global virt_unmap
virt_unmap:
    push rbx
    mov rbx, rdi
    and rbx, -4096                  ; RBX = page-aligned virtual address

    ; 1. Walk the page tables to find the PTE
    mov rdi, rbx
    mov rsi, 0
    call virt_walk_table            ; RAX = physical address of PTE/PDE/PDPTE
    test rax, rax
    jz .done                         ; if not mapped, nothing to do

    ; 2. Clear the entry (mark as absent/free)
    mov qword [rax], 0

    ; 3. Invalidate TLB mapping
    invlpg [rbx]

.done:
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_PGTABLE_UNMAP_ASM
