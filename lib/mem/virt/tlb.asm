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

; -----------------------------------------------------------------------------
; virt_mark_global_range — walks page tables and sets PAGE_GLOBAL on a range (4.4)
; Input:
;   RDI = starting virtual address
;   RSI = range size in bytes
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global virt_mark_global_range
virt_mark_global_range:
    push rbx
    push r12
    push r13

    test rsi, rsi
    jz .done

    ; Align start virtual address down to 4KB
    mov r12, rdi
    and r12, -4096                  ; R12 = current virtual address
    
    ; Calculate end address
    mov r13, rdi
    add r13, rsi                    ; R13 = end virtual address

.loop:
    cmp r12, r13
    jae .done

    ; Walk page table using current virtual address
    mov rdi, r12
    xor rsi, rsi                    ; use current CR3
    call virt_walk_table            ; RAX = PTE address, RDX = level
    test rax, rax
    jz .not_mapped

    ; Set the Global bit (PAGE_GLOBAL = 1 << 8) in the entry
    or qword [rax], PAGE_GLOBAL

    ; Check resolved level to know how much to advance
    cmp rdx, 2                      ; 1GB super page
    je .advance_1gb
    cmp rdx, 3                      ; 2MB huge page
    je .advance_2mb

.advance_4kb:
    add r12, 4096
    jmp .loop

.advance_2mb:
    mov rax, r12
    and rax, 0x1FFFFF               ; offset in 2MB page
    mov rcx, 0x200000
    sub rcx, rax                    ; remaining bytes in this 2MB page
    add r12, rcx
    jmp .loop

.advance_1gb:
    mov rax, r12
    and rax, 0x3FFFFFFF             ; offset in 1GB page
    mov rcx, 0x40000000
    sub rcx, rax                    ; remaining bytes in this 1GB page
    add r12, rcx
    jmp .loop

.not_mapped:
    ; Not mapped, just advance by 4KB to check next page
    add r12, 4096
    jmp .loop

.done:
    ; Flush the TLB to make the global pages active immediately
    call tlb_flush_all_global

    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_TLB_ASM
