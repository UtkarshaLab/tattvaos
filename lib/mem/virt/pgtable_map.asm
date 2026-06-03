; =============================================================================
; Tattva OS — lib/mem/virt/pgtable_map.asm
; =============================================================================
; Virtual memory page mapping API (maps virtual -> physical).
; Uses the pgtable_cache recycling pool (3.3) as a fast path for
; intermediate table allocation, falling back to phys_alloc_page + memzero.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_MAP_ASM
%define LIB_MEM_VIRT_PGTABLE_MAP_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; virt_map — maps a 4KB virtual page to a physical frame
; Input:
;   RDI = virtual address (should be 4KB page aligned)
;   RSI = physical address (should be 4KB page aligned)
;   RDX = mapping flags (e.g. PAGE_WRITABLE, PAGE_USER, PAGE_NX)
; Output:
;   RAX = 1 on success, 0 on failure (OOM during table allocation)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_map
virt_map:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Page-align addresses
    mov r12, rdi
    and r12, -4096                  ; R12 = virtual address
    mov r13, rsi
    and r13, -4096                  ; R13 = physical address
    mov r14, rdx                    ; R14 = flags
    or r14, PAGE_PRESENT            ; always present when mapped

    ; Load CR3 as the initial directory base
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = root physical base

    ; Check if 5-level paging (LA57) is active in CR4
    mov rcx, cr4
    test rcx, (1 << 12)             ; bit 12 = LA57
    jz .do_pml4                     ; if not set, skip PML5

    ; -------------------------------------------------------------------------
    ; 1. Walk / Create PML5 Entry
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 48
    and rcx, 0x1FF                  ; RCX = PML5 index
    mov rbx, [rax + rcx * 8]         ; RBX = PML5 entry
    test rbx, PAGE_PRESENT
    jnz .have_pml4
    
    ; Allocate new PML4 table (cache fast path → PMM fallback)
    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx                         ; RDX = parent directory address
    test rax, rax
    jz .oom
    
    ; Link PML4 to PML5: present, writable, user
    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pml4:
    and rbx, 0xFFFFFFFFFFFFF000      ; RBX = PML4 physical address
    mov rax, rbx

.do_pml4:
    ; -------------------------------------------------------------------------
    ; 2. Walk / Create PML4 Entry
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = PML4 index
    mov rbx, [rax + rcx * 8]         ; RBX = PML4 entry
    test rbx, PAGE_PRESENT
    jnz .have_pdpt

    ; Allocate new PDPT table
    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx                         ; RDX = parent directory address
    test rax, rax
    jz .oom

    ; Link PDPT to PML4
    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pdpt:
    and rbx, 0xFFFFFFFFFFFFF000      ; RBX = PDPT physical address
    mov rax, rbx

    ; -------------------------------------------------------------------------
    ; 3. Walk / Create PDPT Entry
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 30
    and rcx, 0x1FF                  ; RCX = PDPT index
    mov rbx, [rax + rcx * 8]         ; RBX = PDPT entry
    test rbx, PAGE_PRESENT
    jnz .have_pd

    ; Allocate new PD table
    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx
    test rax, rax
    jz .oom

    ; Link PD to PDPT
    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pd:
    and rbx, 0xFFFFFFFFFFFFF000      ; RBX = PD physical address
    mov rax, rbx

    ; -------------------------------------------------------------------------
    ; 4. Walk / Create PD Entry
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 21
    and rcx, 0x1FF                  ; RCX = PD index
    mov rbx, [rax + rcx * 8]         ; RBX = PD entry
    test rbx, PAGE_PRESENT
    jnz .have_pt

    ; Allocate new PT leaf table
    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx
    test rax, rax
    jz .oom

    ; Link PT to PD
    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pt:
    and rbx, 0xFFFFFFFFFFFFF000      ; RBX = PT physical address

    ; -------------------------------------------------------------------------
    ; 5. Set Leaf PT Entry (PTE)
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 12
    and rcx, 0x1FF                  ; RCX = PT index
    
    ; Map virtual address to physical with flags
    mov rdx, r13
    or rdx, r14                     ; RDX = phys_frame | flags
    mov [rbx + rcx * 8], rdx        ; write PTE

    ; Flush TLB for this virtual address
    invlpg [r12]

    mov rax, 1                      ; return 1 (success)
    jmp .exit

.oom:
    xor rax, rax                    ; return 0 (OOM/error)

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ._alloc_zeroed_table — allocates a zeroed 4KB page for a page table
; Tries the recycling pool first (O(1), no locks), then falls back to
; phys_alloc_page + memzero.
; Input:  none
; Output: RAX = physical address of zeroed page, or 0 on OOM
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; NOTE: This is a local helper, not a public API.
; -----------------------------------------------------------------------------
._alloc_zeroed_table:
    ; Fast path: try the recycling pool
    call pgtable_cache_alloc
    test rax, rax
    jnz .alloc_done                 ; got a pre-zeroed page, return it

    ; Slow path: allocate from PMM and zero it
    call phys_alloc_page
    test rax, rax
    jz .alloc_done                  ; OOM, return 0

    ; Zero the freshly allocated page
    push rax
    mov rdi, rax
    mov rsi, 4096
    call memzero
    pop rax

.alloc_done:
    ret

%endif ; LIB_MEM_VIRT_PGTABLE_MAP_ASM
