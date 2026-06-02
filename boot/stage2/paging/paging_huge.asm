; =============================================================================
; Tattva OS — boot/stage2/paging/paging_huge.asm
; =============================================================================
; 2MB huge page support helpers.
;
; In normal 4KB paging:
;   PML4 → PDPT → PD → PT → 4KB page
;
; With 2MB huge pages (PS bit set in PD entry):
;   PML4 → PDPT → PD → 2MB page   (PT level skipped)
;
; Advantages for boot stage:
;   Simpler — no PT level needed
;   Faster — fewer page table walks
;   Sufficient — kernel sets up 4KB pages later
;   Less memory — 6 tables vs 6 + 2048 PT tables
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef PAGING_HUGE_ASM
%define PAGING_HUGE_ASM

; =============================================================================
; paging_fill_pd_huge — fill PD with 2MB huge page entries
; Wrapper around paging_fill_pd in paging.asm
; Kept separate so it can be included/excluded independently
;
; Input:  EDI = PD physical address
;         EBX = starting physical address (must be 2MB aligned)
; Output: PD filled
; Note:   This is a forward declaration stub.
;         Actual implementation is paging_fill_pd in paging.asm
;         which is the canonical version.
;         This file exists for structural completeness.
; =============================================================================
[BITS 32]
paging_fill_pd_huge:
    ; forward to paging_fill_pd — same implementation
    ; paging.asm includes this file before defining paging_fill_pd
    ; so we just ret here; paging.asm's paging_fill_pd is used directly
    ret

; =============================================================================
; paging_make_huge_entry — build a single 2MB PD entry
; Input:  EBX = physical address of 2MB page (must be 2MB aligned)
;         ECX = flags (PAGE_PRESENT | PAGE_RW | PAGE_HUGE minimum)
; Output: EAX = low dword of entry
;         EDX = high dword of entry (NX bit if needed)
; =============================================================================
paging_make_huge_entry:
    mov eax, ebx
    or eax, ecx                     ; physical address | flags
    xor edx, edx                   ; high dword = 0 (no NX for now)
    ret

; =============================================================================
; paging_is_huge — check if a PD entry is a huge page
; Input:  EAX = PD entry low dword
; Output: ZF clear = huge page, ZF set = not huge
; =============================================================================
paging_is_huge:
    test eax, PAGE_HUGE             ; test bit 7
    ret

[BITS 16]

%endif ; PAGING_HUGE_ASM