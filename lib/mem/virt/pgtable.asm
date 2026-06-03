; =============================================================================
; Tattva OS — lib/mem/virt/pgtable.asm
; =============================================================================
; 4-Level Page Table walking and traversal utilities (PML4 -> PDPT -> PD -> PT).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_ASM
%define LIB_MEM_VIRT_PGTABLE_ASM

[BITS 64]

; Page Table Entry Flags (64-bit)
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_PWT        equ (1 << 3)        ; Write-through
PAGE_PCD        equ (1 << 4)        ; Cache disable
PAGE_ACCESSED   equ (1 << 5)
PAGE_DIRTY      equ (1 << 6)
PAGE_HUGE       equ (1 << 7)        ; Huge page (PS bit in PDPT/PD)
PAGE_GLOBAL     equ (1 << 8)
PAGE_NX         equ (1 << 63)       ; No-execute

section .text

; -----------------------------------------------------------------------------
; virt_walk_table — walks the 4-level page tables for a virtual address
; Input:
;   RDI = virtual address
;   RSI = physical address of PML4 (if 0, reads current CR3)
; Output:
;   RAX = physical address of the leaf Page Table Entry (PTE), or 0 if not mapped
;   RDX = level where walk resolved (4 = 4KB page, 3 = 2MB huge page, 2 = 1GB super page)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global virt_walk_table
virt_walk_table:
    ; 1. Load PML4 base physical address
    mov rax, rsi
    test rax, rax
    jnz .have_pml4
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; mask off PCID & status flags
.have_pml4:

    ; 2. Walk PML4 (Level 4)
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = PML4 index
    mov r8, [rax + rcx * 8]         ; R8 = PML4 entry
    test r8, PAGE_PRESENT
    jz .not_mapped
    
    ; 3. Walk PDPT (Level 3)
    and r8, 0xFFFFFFFFFFFFF000      ; R8 = PDPT base physical address
    mov rcx, rdi
    shr rcx, 30
    and rcx, 0x1FF                  ; RCX = PDPT index
    mov rax, [r8 + rcx * 8]         ; RAX = PDPT entry
    test rax, PAGE_PRESENT
    jz .not_mapped
    
    ; Check if 1GB huge page (PAGE_HUGE bit set in PDPTE)
    test rax, PAGE_HUGE
    jz .walk_pd
    ; Resolved at 1GB level (Level 2)
    lea rax, [r8 + rcx * 8]         ; RAX = physical address of PDPTE
    mov rdx, 2
    ret

.walk_pd:
    ; 4. Walk PD (Level 2)
    and rax, 0xFFFFFFFFFFFFF000      ; RAX = PD base physical address
    mov rcx, rdi
    shr rcx, 21
    and rcx, 0x1FF                  ; RCX = PD index
    mov r8, [rax + rcx * 8]         ; R8 = PD entry
    test r8, PAGE_PRESENT
    jz .not_mapped
    
    ; Check if 2MB huge page (PAGE_HUGE bit set in PDE)
    test r8, PAGE_HUGE
    jz .walk_pt
    ; Resolved at 2MB level (Level 3)
    lea rax, [rax + rcx * 8]         ; RAX = physical address of PDE
    mov rdx, 3
    ret

.walk_pt:
    ; 5. Walk PT (Level 1)
    and r8, 0xFFFFFFFFFFFFF000      ; R8 = PT base physical address
    mov rcx, rdi
    shr rcx, 12
    and rcx, 0x1FF                  ; RCX = PT index
    
    lea rax, [r8 + rcx * 8]         ; RAX = physical address of PTE
    mov rdx, 4                      ; Resolved at 4KB level (Level 4)
    
    ; Verify that the PTE is marked present
    mov rcx, [rax]
    test rcx, PAGE_PRESENT
    jz .not_mapped
    ret

.not_mapped:
    xor rax, rax                    ; return 0
    xor rdx, rdx
    ret

%endif ; LIB_MEM_VIRT_PGTABLE_ASM
