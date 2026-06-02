; =============================================================================
; Tattva OS — boot/stage2/paging/paging.asm
; =============================================================================
; Main paging setup. Builds page tables for long mode.
; Uses 2MB huge pages for simplicity — sufficient for boot stage.
; Identity maps first 4GB: virtual address == physical address.
;
; Page table structure (4-level):
;   PML4  — Page Map Level 4   (512 entries × 8 bytes = 4KB)
;   PDPT  — Page Directory Pointer Table (512 entries × 8 bytes = 4KB)
;   PD    — Page Directory      (512 entries × 8 bytes = 4KB)
;   PT    — Page Table          (not used — huge pages skip this level)
;
; With 2MB huge pages:
;   PML4[0] → PDPT
;   PDPT[0..3] → PD[0..3]    (4 PDPTs cover 4 × 1GB = 4GB)
;   PD[0..511] → 2MB page    (512 × 2MB = 1GB per PD)
;
; Page table locations (just above survive page):
;   PAGING_PML4  equ 0x10000   PML4  at 64KB mark
;   PAGING_PDPT  equ 0x11000   PDPT  at 64KB + 4KB
;   PAGING_PD0   equ 0x12000   PD 0  at 64KB + 8KB  (0GB-1GB)
;   PAGING_PD1   equ 0x13000   PD 1  at 64KB + 12KB (1GB-2GB)
;   PAGING_PD2   equ 0x14000   PD 2  at 64KB + 16KB (2GB-3GB)
;   PAGING_PD3   equ 0x15000   PD 3  at 64KB + 20KB (3GB-4GB)
;
; Page flags used:
;   Bit 0: Present
;   Bit 1: Read/Write
;   Bit 7: Page Size (1 = 2MB huge page, in PD only)
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef PAGING_ASM
%define PAGING_ASM

%include "paging_huge.asm"
%include "paging_nx.asm"


; Page entry flags
PAGE_PRESENT    equ 0x01            ; bit 0: page is present
PAGE_RW         equ 0x02            ; bit 1: read/write
PAGE_USER       equ 0x04            ; bit 2: user accessible
PAGE_HUGE       equ 0x80            ; bit 7: 2MB huge page (PD only)
PAGE_NX         equ 0x80000000      ; bit 63 high dword: no-execute

; Common flag combinations
PAGE_KERNEL     equ (PAGE_PRESENT | PAGE_RW)
PAGE_KERNEL_NX  equ (PAGE_PRESENT | PAGE_RW)   ; NX added separately

; =============================================================================
; paging_setup — build page tables and prepare for long mode
; Must be called in 32-bit protected mode.
; Input:  nothing
; Output: page tables ready at PAGING_PML4
;         PAGING_PML4 ready to load into CR3
; Clobbers: EAX, EBX, ECX, EDI
; =============================================================================
[BITS 32]
paging_setup:
    push eax
    push ebx
    push ecx
    push edi

    ; -------------------------------------------------------------------------
    ; Step 1: Zero all page table memory
    ; 6 tables × 4KB = 24KB total
    ; Start at PAGING_PML4, clear 24KB
    ; -------------------------------------------------------------------------
    mov edi, PAGING_PML4
    mov ecx, (6 * 4096) / 4        ; 24KB in dwords
    xor eax, eax
    rep stosd                       ; zero fill

    ; -------------------------------------------------------------------------
    ; Step 2: Set up PML4
    ; PML4[0] → PDPT (covers first 512GB)
    ; Only one entry needed for identity map of 4GB
    ; -------------------------------------------------------------------------
    mov edi, PAGING_PML4
    mov eax, PAGING_PDPT
    or eax, PAGE_KERNEL             ; present + read/write
    mov [edi], eax                  ; PML4[0] low dword
    mov dword [edi + 4], 0          ; PML4[0] high dword (base < 4GB)

    ; -------------------------------------------------------------------------
    ; Step 3: Set up PDPT
    ; PDPT[0] → PD0 (0GB - 1GB)
    ; PDPT[1] → PD1 (1GB - 2GB)
    ; PDPT[2] → PD2 (2GB - 3GB)
    ; PDPT[3] → PD3 (3GB - 4GB)
    ; -------------------------------------------------------------------------
    mov edi, PAGING_PDPT

    mov eax, PAGING_PD0
    or eax, PAGE_KERNEL
    mov [edi + 0x00], eax           ; PDPT[0] low
    mov dword [edi + 0x04], 0       ; PDPT[0] high

    mov eax, PAGING_PD1
    or eax, PAGE_KERNEL
    mov [edi + 0x08], eax           ; PDPT[1] low
    mov dword [edi + 0x0C], 0

    mov eax, PAGING_PD2
    or eax, PAGE_KERNEL
    mov [edi + 0x10], eax           ; PDPT[2] low
    mov dword [edi + 0x14], 0

    mov eax, PAGING_PD3
    or eax, PAGE_KERNEL
    mov [edi + 0x18], eax           ; PDPT[3] low
    mov dword [edi + 0x1C], 0

    ; -------------------------------------------------------------------------
    ; Step 4: Set up PD0 (0GB - 1GB)
    ; 512 entries × 2MB = 1GB
    ; Each entry maps a 2MB huge page
    ; -------------------------------------------------------------------------
    call paging_fill_pd_huge        ; fills PD at EDI with 512 huge entries
    ; Note: paging_fill_pd_huge uses EDI for output PD address
    ; and EBX for starting physical address
    ; We set these up via paging_map_gb helper below

    ; rebuild using explicit calls for clarity
    mov edi, PAGING_PD0
    mov ebx, 0x00000000             ; starting physical address: 0GB
    call paging_fill_pd

    mov edi, PAGING_PD1
    mov ebx, 0x40000000             ; starting physical address: 1GB
    call paging_fill_pd

    mov edi, PAGING_PD2
    mov ebx, 0x80000000             ; starting physical address: 2GB
    call paging_fill_pd

    mov edi, PAGING_PD3
    mov ebx, 0xC0000000             ; starting physical address: 3GB
    call paging_fill_pd

    pop edi
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; paging_fill_pd — fill one PD with 512 × 2MB huge page entries
; Input:  EDI = physical address of PD to fill
;         EBX = starting physical address for first entry
; Output: PD filled with 512 sequential 2MB entries
; Clobbers: EAX, ECX, EDI
; =============================================================================
paging_fill_pd:
    push eax
    push ecx
    push edi

    mov ecx, 512                    ; 512 entries per PD

.fill_loop:
    ; entry = physical_address | PAGE_PRESENT | PAGE_RW | PAGE_HUGE
    mov eax, ebx
    or eax, PAGE_KERNEL | PAGE_HUGE ; present + rw + 2MB huge
    mov [edi], eax                  ; low dword of entry
    mov dword [edi + 4], 0          ; high dword (no NX, no high base bits)

    add ebx, 0x200000               ; advance by 2MB
    add edi, 8                      ; next entry (8 bytes)
    dec ecx
    jnz .fill_loop

    pop edi
    pop ecx
    pop eax
    ret

[BITS 16]

%endif ; PAGING_ASM