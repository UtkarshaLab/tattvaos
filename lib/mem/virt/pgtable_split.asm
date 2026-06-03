; =============================================================================
; Tattva OS — lib/mem/virt/pgtable_split.asm
; =============================================================================
; Huge page and super page splitting logic (Subfeature 5.4).
; Splits 1GB super pages into 512 2MB huge pages, and 2MB huge pages into
; 512 4KB pages.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_SPLIT_ASM
%define LIB_MEM_VIRT_PGTABLE_SPLIT_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; virt_split_super_1gb — splits a 1GB super page into 512 2MB huge pages
; Input:
;   RDI = virtual address (any address inside the 1GB super page)
;   RSI = physical address of root page directory (if 0, reads current CR3)
; Output:
;   RAX = 1 on success, 0 on failure (OOM)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_split_super_1gb
virt_split_super_1gb:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = virtual address
    mov rbx, rsi                    ; RBX = root directory base

    ; 1. Resolve root base
    test rbx, rbx
    jnz .have_root
    mov rbx, cr3
    and rbx, 0xFFFFFFFFFFFFF000
.have_root:

    ; 2. Check 5-level paging (LA57)
    mov rcx, cr4
    test rcx, (1 << 12)
    jz .level4

    ; PML5 Walk
    mov rcx, r12
    shr rcx, 48
    and rcx, 0x1FF
    mov rax, [rbx + rcx * 8]
    test rax, PAGE_PRESENT
    jz .not_mapped
    and rax, 0xFFFFFFFFFFFFF000
    mov rbx, rax

.level4:
    ; PML4 Walk
    mov rcx, r12
    shr rcx, 39
    and rcx, 0x1FF
    mov rax, [rbx + rcx * 8]
    test rax, PAGE_PRESENT
    jz .not_mapped
    and rax, 0xFFFFFFFFFFFFF000
    mov rbx, rax                    ; RBX = PDPT base

    ; PDPT Entry Lookup
    mov rcx, r12
    shr rcx, 30
    and rcx, 0x1FF                  ; RCX = PDPT index
    lea r13, [rbx + rcx * 8]        ; R13 = address of PDPTE slot

    mov r14, [r13]                  ; R14 = PDPTE value
    test r14, PAGE_PRESENT
    jz .not_mapped

    test r14, PAGE_HUGE
    jz .already_split               ; if present but not huge, it's already split

    ; 3. We have a 1GB super page. Perform the split!
    ; Allocate a new PD
    call .alloc_zeroed_page
    test rax, rax
    jz .oom
    mov r15, rax                    ; R15 = new PD physical address

    ; Extract base physical address of the 1GB page
    mov r8, r14
    and r8, 0xFFFFFFFFFFFFF000      ; 1GB page physical base
    
    ; Extract PDPTE flags, keep PAGE_HUGE
    mov r9, r14
    mov r10, 0xFFFFFFFFFFFFF000
    not r10                         ; R10 = flags mask (lower 12 bits)
    and r9, r10                     ; R9 = flags (includes PAGE_HUGE, PRESENT, etc.)
    
    ; Also preserve NX bit (bit 63)
    mov r10, (1 << 63)
    and r10, r14
    or r9, r10                      ; R9 = flags + NX

    ; Populate the 512 PD entries
    xor rcx, rcx                    ; index 0 to 511
.fill_pd_loop:
    cmp rcx, 512
    jge .link_pd

    ; PDE_value = r8 (current 2MB physical base) | r9 (flags with PAGE_HUGE)
    mov rax, r8
    or rax, r9
    mov [r15 + rcx * 8], rax

    add r8, 0x200000                ; next 2MB physical page
    inc rcx
    jmp .fill_pd_loop

.link_pd:
    ; Replace PDPTE with pointer to new PD: PRESENT | WRITABLE | USER
    mov rax, r15
    or rax, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [r13], rax

    ; Flush TLB globally (full shootdown since it's 1GB)
    xor rdi, rdi
    xor rsi, rsi
    call tlb_shootdown

.already_split:
    mov rax, 1                      ; success
    jmp .exit

.not_mapped:
    mov rax, 1                      ; not mapped, no-op success
    jmp .exit

.oom:
    xor rax, rax                    ; failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_split_huge_2mb — splits a 2MB huge page into 512 4KB pages
; Input:
;   RDI = virtual address (any address inside the 2MB huge page)
;   RSI = physical address of root page directory (if 0, reads current CR3)
; Output:
;   RAX = 1 on success, 0 on failure (OOM)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_split_huge_2mb
virt_split_huge_2mb:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = virtual address
    mov rbx, rsi                    ; RBX = root directory base

    ; 1. Resolve root base
    test rbx, rbx
    jnz .have_root
    mov rbx, cr3
    and rbx, 0xFFFFFFFFFFFFF000
.have_root:

    ; 2. Check 5-level paging (LA57)
    mov rcx, cr4
    test rcx, (1 << 12)
    jz .level4

    ; PML5 Walk
    mov rcx, r12
    shr rcx, 48
    and rcx, 0x1FF
    mov rax, [rbx + rcx * 8]
    test rax, PAGE_PRESENT
    jz .not_mapped
    and rax, 0xFFFFFFFFFFFFF000
    mov rbx, rax

.level4:
    ; PML4 Walk
    mov rcx, r12
    shr rcx, 39
    and rcx, 0x1FF
    mov rax, [rbx + rcx * 8]
    test rax, PAGE_PRESENT
    jz .not_mapped
    and rax, 0xFFFFFFFFFFFFF000
    mov rbx, rax                    ; RBX = PDPT base

    ; PDPT Walk
    mov rcx, r12
    shr rcx, 30
    and rcx, 0x1FF
    mov rax, [rbx + rcx * 8]
    test rax, PAGE_PRESENT
    jz .not_mapped
    ; If PDPT is huge (1GB page), split it first!
    test rax, PAGE_HUGE
    jz .walk_pd
    
    push rbx
    mov rdi, r12
    mov rsi, rbx
    call virt_split_super_1gb
    pop rbx
    test rax, rax
    jz .oom
    
    ; Re-read PDPT entry which is now split into a PD
    mov rcx, r12
    shr rcx, 30
    and rcx, 0x1FF
    mov rax, [rbx + rcx * 8]

.walk_pd:
    and rax, 0xFFFFFFFFFFFFF000
    mov rbx, rax                    ; RBX = PD base

    ; PD Entry Lookup
    mov rcx, r12
    shr rcx, 21
    and rcx, 0x1FF                  ; RCX = PD index
    lea r13, [rbx + rcx * 8]        ; R13 = address of PDE slot

    mov r14, [r13]                  ; R14 = PDE value
    test r14, PAGE_PRESENT
    jz .not_mapped

    test r14, PAGE_HUGE
    jz .already_split               ; if present but not huge, it's already split

    ; 3. We have a 2MB huge page. Perform the split!
    ; Allocate a new PT
    call .alloc_zeroed_page
    test rax, rax
    jz .oom
    mov r15, rax                    ; R15 = new PT physical address

    ; Extract base physical address of the 2MB page (aligned to 2MB)
    mov r8, r14
    and r8, 0xFFFFFFFFFFE00000      ; 2MB aligned (bits 21-51)
    
    ; Extract PDE flags, clear PAGE_HUGE
    mov r9, r14
    mov r10, 0xFFFFFFFFFFFFF000
    not r10                         ; R10 = flags mask
    and r9, r10                     ; R9 = flags
    and r9, ~PAGE_HUGE              ; clear PAGE_HUGE (bit 7)
    
    ; Preserve NX bit (bit 63)
    mov r10, (1 << 63)
    and r10, r14
    or r9, r10                      ; R9 = flags + NX

    ; Populate the 512 PT entries
    xor rcx, rcx                    ; index 0 to 511
.fill_pt_loop:
    cmp rcx, 512
    jge .link_pt

    ; PTE_value = r8 (current 4KB physical base) | r9 (flags without PAGE_HUGE)
    mov rax, r8
    or rax, r9
    mov [r15 + rcx * 8], rax

    add r8, 4096                    ; next 4KB physical page
    inc rcx
    jmp .fill_pt_loop

.link_pt:
    ; Replace PDE with pointer to new PT: PRESENT | WRITABLE | USER
    mov rax, r15
    or rax, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [r13], rax

    ; Flush TLB for the 2MB region
    mov rdi, r12
    and rdi, -0x200000              ; align to 2MB boundary
    mov rsi, 512
    call tlb_shootdown

.already_split:
    mov rax, 1                      ; success
    jmp .exit

.not_mapped:
    mov rax, 1                      ; not mapped, no-op success
    jmp .exit

.oom:
    xor rax, rax                    ; failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; .alloc_zeroed_page — local helper to allocate a zeroed page (via cache or PMM)
; -----------------------------------------------------------------------------
.alloc_zeroed_page:
    call pgtable_cache_alloc
    test rax, rax
    jnz .alloc_done

    call phys_alloc_page
    test rax, rax
    jz .alloc_done

    push rax
    mov rdi, rax
    mov rsi, 4096
    call memzero
    pop rax
.alloc_done:
    ret

%endif ; LIB_MEM_VIRT_PGTABLE_SPLIT_ASM
