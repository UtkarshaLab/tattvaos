; =============================================================================
; Tattva OS — boot/stage2/paging/paging_nx.asm
; =============================================================================
; NX (No-Execute) / XD (Execute-Disable) bit support.
;
; The NX bit (bit 63 of a page table entry) marks pages as
; non-executable. Attempts to execute code in NX pages cause
; a page fault (#PF with I/D bit set).
;
; Requirements:
;   1. CPU must support NX (CPUID 0x80000001 EDX bit 20)
;   2. EFER.NXE must be set (done in longmode.asm)
;   3. Bit 63 of PTE/PDE set = no-execute
;
; Usage:
;   Data pages (.data, .bss, stack) → mark NX
;   Code pages (.text) → leave executable (NX=0)
;
; For boot stage: we don't enforce NX on the identity map.
; Kernel sets up proper NX enforcement on its page tables.
; This file provides helpers for when needed.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit) / long mode (64-bit)
; =============================================================================

%ifndef PAGING_NX_ASM
%define PAGING_NX_ASM

; NX bit position in page entry high dword
PTE_NX_BIT      equ (1 << 31)      ; bit 63 of 64-bit entry = bit 31 of high dword

; =============================================================================
; paging_nx_supported — check if NX is available
; Input:  [FEATURES_DEST] filled by cpu_detect
; Output: CF=0 NX supported, CF=1 not supported
; =============================================================================
[BITS 32]
paging_nx_supported:
    mov eax, [FEATURES_DEST]
    test eax, CPU_FEAT_NX
    jz .no_nx
    clc
    ret
.no_nx:
    stc
    ret

; =============================================================================
; paging_set_nx — set NX bit on a PD entry (2MB page)
; Input:  EDI = address of PD entry (8 bytes)
; Output: NX bit set in high dword of entry
; Clobbers: EAX
; =============================================================================
paging_set_nx:
    call paging_nx_supported
    jc .nx_not_supported            ; skip if CPU doesn't support NX

    mov eax, [edi + 4]              ; read high dword
    or eax, PTE_NX_BIT              ; set bit 63 (bit 31 of high dword)
    mov [edi + 4], eax              ; write back

.nx_not_supported:
    ret

; =============================================================================
; paging_clear_nx — clear NX bit on a PD entry (make executable)
; Input:  EDI = address of PD entry
; Output: NX bit cleared
; Clobbers: EAX
; =============================================================================
paging_clear_nx:
    mov eax, [edi + 4]
    and eax, ~PTE_NX_BIT            ; clear bit 63
    mov [edi + 4], eax
    ret

; =============================================================================
; paging_mark_data_nx — mark data region as non-executable
; Walks PD entries covering given physical range and sets NX
; Input:  EAX = start physical address (2MB aligned)
;         EBX = end physical address (2MB aligned)
; Output: NX set on all covered entries
; Note:   Only works within first 4GB (boot stage limitation)
; =============================================================================
paging_mark_data_nx:
    push eax
    push ebx
    push ecx
    push edi

    call paging_nx_supported
    jc .mark_done                   ; NX not supported, skip

.mark_loop:
    cmp eax, ebx
    jae .mark_done

    ; find PD entry for this address
    ; PDPT index = bits 38:30 → for < 4GB: bits 31:30
    mov ecx, eax
    shr ecx, 30
    and ecx, 0x3                    ; 0-3 for 4 PDPTs

    ; get PD base
    push ecx
    mov edi, PAGING_PDPT
    shl ecx, 3
    add edi, ecx
    mov edi, [edi]
    and edi, 0xFFFFF000
    pop ecx

    ; PD index = bits 29:21
    mov ecx, eax
    shr ecx, 21
    and ecx, 0x1FF
    shl ecx, 3
    add edi, ecx                    ; EDI = PD entry address

    call paging_set_nx              ; set NX on this entry

    add eax, 0x200000               ; next 2MB
    jmp .mark_loop

.mark_done:
    pop edi
    pop ecx
    pop ebx
    pop eax
    ret

[BITS 16]

%endif ; PAGING_NX_ASM