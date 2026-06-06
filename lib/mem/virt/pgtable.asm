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
PAGE_PAT        equ (1 << 7)        ; Page Attribute Table bit in leaf PTE

PAGE_GLOBAL     equ (1 << 8)
PAGE_SWAPPED    equ (1 << 10)       ; Page is swapped out to mock swap device
PAGE_ZSWAPPED   equ (1 << 11)       ; Page is compressed in Zswap cache
PAGE_NX         equ (1 << 63)       ; No-execute

section .text

; -----------------------------------------------------------------------------
; virt_walk_table — walks the 4-level or 5-level page tables for a virtual address
; Input:
;   RDI = virtual address
;   RSI = physical address of page directory base (PML5 if 5-level, PML4 if 4-level)
;         (if 0, reads current CR3)
; Output:
;   RAX = physical address of the leaf Page Table Entry (PTE), or 0 if not mapped
;   RDX = level where walk resolved:
;         5 = 4KB page in 5-level paging, 4 = 4KB page in 4-level paging,
;         3 = 2MB huge page, 2 = 1GB super page
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global virt_walk_table
virt_walk_table:
    ; 1. Load PML5/PML4 base physical address
    mov rax, rsi
    test rax, rax
    jnz .have_root
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; mask off PCID & status flags
.have_root:

    ; Check if 5-level paging (LA57) is active in CR4
    mov rcx, cr4
    test rcx, (1 << 12)             ; bit 12 = LA57
    jz .level4                      ; if not set, do standard 4-level walk

    ; -------------------------------------------------------------------------
    ; 5-Level Paging Walk (Level 5)
    ; -------------------------------------------------------------------------
    mov rcx, rdi
    shr rcx, 48
    and rcx, 0x1FF                  ; RCX = PML5 index
    mov r8, [rax + rcx * 8]         ; R8 = PML5 entry
    test r8, PAGE_PRESENT
    jz .not_mapped
    
    and r8, 0xFFFFFFFFFFFFF000      ; R8 = PML4 base physical address
    mov rax, r8                     ; RAX = PML4 base for next step
    
.level4:
    ; Walk PML4 (Level 4)
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
    
    ; Verify that the PTE is marked present
    mov rcx, [rax]
    test rcx, PAGE_PRESENT
    jz .not_mapped
    
    ; Determine resolved level (5 for 5-level, 4 for 4-level paging)
    mov rcx, cr4
    test rcx, (1 << 12)
    jz .ret_level4
    mov rdx, 5
    ret
.ret_level4:
    mov rdx, 4
    ret

.not_mapped:
    xor rax, rax                    ; return 0
    xor rdx, rdx
    ret

%endif ; LIB_MEM_VIRT_PGTABLE_ASM
