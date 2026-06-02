; =============================================================================
; Tattva OS — boot/stage2/paging/paging_map.asm
; =============================================================================
; Map specific virtual → physical address regions.
; Used after paging_setup to add or modify specific mappings.
;
; paging_setup creates a flat identity map (virtual == physical).
; paging_map allows overriding or extending this for specific regions:
;   - Kernel at high virtual address
;   - MMIO regions
;   - Guard pages (present=0, causes page fault on access)
;
; All functions operate on the page tables at PAGING_PML4.
; Must be called in 32-bit or 64-bit protected mode (not real mode).
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef PAGING_MAP_ASM
%define PAGING_MAP_ASM

; =============================================================================
; paging_map_2mb — map one 2MB region virtual → physical
; Input:  EAX = virtual address  (must be 2MB aligned)
;         EBX = physical address (must be 2MB aligned)
;         ECX = flags (PAGE_PRESENT | PAGE_RW | PAGE_HUGE etc)
; Output: CF=0 success, CF=1 failure (address out of range)
; Clobbers: EAX, EBX, ECX, EDX, EDI
; =============================================================================
[BITS 32]
paging_map_2mb:
    push eax
    push ebx
    push ecx
    push edx
    push edi

    ; -------------------------------------------------------------------------
    ; Decompose virtual address into page table indices
    ; VA bits:
    ;   47:39 → PML4 index  (9 bits)
    ;   38:30 → PDPT index  (9 bits)
    ;   29:21 → PD index    (9 bits)
    ;   20:0  → offset within 2MB page
    ; -------------------------------------------------------------------------

    ; extract PML4 index (bits 47:39)
    mov edx, eax
    shr edx, 39
    and edx, 0x1FF                  ; 9 bits = 0-511
    ; for identity map of 4GB, PML4 index is always 0
    cmp edx, 0
    jne .out_of_range               ; we only set up PML4[0]

    ; extract PDPT index (bits 38:30)
    mov edx, eax
    shr edx, 30
    and edx, 0x1FF
    cmp edx, 3
    ja .out_of_range                ; we only set up PDPT[0..3] (4GB)

    ; get PD base address from PDPT
    push edx
    mov edi, PAGING_PDPT
    shl edx, 3                      ; × 8 bytes per entry
    add edi, edx
    mov edi, [edi]                  ; read PD physical address from PDPT entry
    and edi, 0xFFFFF000             ; mask off flags (keep page-aligned address)
    pop edx

    ; extract PD index (bits 29:21)
    mov edx, eax
    shr edx, 21
    and edx, 0x1FF                  ; 9 bits

    ; calculate PD entry address
    shl edx, 3                      ; × 8 bytes
    add edi, edx                    ; EDI = &PD[index]

    ; -------------------------------------------------------------------------
    ; Write the PD entry
    ; entry = physical_address | flags | PAGE_HUGE
    ; -------------------------------------------------------------------------
    mov eax, ebx                    ; physical address
    or eax, ecx                     ; | flags
    or eax, PAGE_HUGE               ; | huge page bit
    mov [edi], eax                  ; write low dword
    mov dword [edi + 4], 0          ; write high dword (NX=0 for now)

    clc                             ; success
    jmp .map_done

.out_of_range:
    stc                             ; failure

.map_done:
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; paging_unmap_2mb — remove a 2MB mapping (make it not present)
; Creates a guard page — access will cause page fault
; Input:  EAX = virtual address (must be 2MB aligned)
; Output: CF=0 success, CF=1 failure
; Clobbers: EAX, EDX, EDI
; =============================================================================
paging_unmap_2mb:
    push eax
    push edx
    push edi

    ; same decomposition as paging_map_2mb
    ; extract PDPT index
    mov edx, eax
    shr edx, 30
    and edx, 0x1FF
    cmp edx, 3
    ja .unmap_fail

    ; get PD
    push edx
    mov edi, PAGING_PDPT
    shl edx, 3
    add edi, edx
    mov edi, [edi]
    and edi, 0xFFFFF000
    pop edx

    ; extract PD index
    mov edx, eax
    shr edx, 21
    and edx, 0x1FF
    shl edx, 3
    add edi, edx

    ; clear the entry (not present)
    mov dword [edi], 0
    mov dword [edi + 4], 0

    ; invalidate TLB for this address
    ; invlpg [eax] — but EAX was virtual address
    ; Note: in 32-bit PM before long mode, invlpg works on current VA
    pop edi                         ; restore before invlpg
    pop edx
    pop eax
    invlpg [eax]                    ; flush TLB entry
    clc
    ret

.unmap_fail:
    pop edi
    pop edx
    pop eax
    stc
    ret

; =============================================================================
; paging_map_kernel — map kernel at both identity and high virtual address
; Kernel loads at KERNEL_LOAD (0x100000 physical = 1MB)
; Also mapped at high address for proper kernel virtual addressing
; Input:  EBX = kernel physical address
;         ECX = kernel size in bytes (rounded up to 2MB)
; Output: nothing
; =============================================================================
paging_map_kernel:
    ; identity map already covers 0x100000 via paging_setup
    ; add high virtual address mapping here when kernel VA is decided
    ; for now: identity map is sufficient for boot
    ret

[BITS 16]

%endif ; PAGING_MAP_ASM