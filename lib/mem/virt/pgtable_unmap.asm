; =============================================================================
; Tattva OS — lib/mem/virt/pgtable_unmap.asm
; =============================================================================
; Virtual memory page unmapping API with empty table reclamation (3.2)
; and recycling pool integration (3.3). Protected by per-PML4
; spinlocks (3.4) for concurrent safety on multi-core systems.
; After clearing the leaf PTE, walks back up the hierarchy and reclaims
; any page table that has become completely empty, recycling them into
; the pgtable_cache pool for instant reuse.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_UNMAP_ASM
%define LIB_MEM_VIRT_PGTABLE_UNMAP_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; virt_unmap — unmaps a virtual page and reclaims empty intermediate tables
; Input:
;   RDI = virtual address to unmap
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_unmap
virt_unmap:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r12, rdi
    and r12, -4096                  ; R12 = page-aligned virtual address

    ; Acquire per-PML4 spinlock for this virtual address (3.4)
    mov rdi, r12
    call pgtable_lock_acquire

    ; Load CR3 as the root page table base
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = root physical base

    ; =========================================================================
    ; Walk down and record parent entry addresses at each level
    ; R13 = address of PML4 entry slot (pointer into PML4 table)
    ; R14 = address of PDPT entry slot
    ; R15 = address of PD entry slot
    ; RBP = address of PT entry slot (the leaf PTE)
    ; =========================================================================
    xor r13, r13                    ; clear all parent trackers
    xor r14, r14
    xor r15, r15
    xor rbp, rbp

    ; Check if 5-level paging (LA57) is active
    mov rcx, cr4
    test rcx, (1 << 12)
    jz .walk_pml4

    ; -------------------------------------------------------------------------
    ; Level 5: PML5
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 48
    and rcx, 0x1FF
    lea rbx, [rax + rcx * 8]       ; RBX = &PML5[index]
    mov rax, [rbx]
    test rax, PAGE_PRESENT
    jz .done                        ; not mapped at PML5
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = PML4 base
    ; We don't reclaim PML4 from PML5 (too aggressive), just track for walk
    ; Store PML5 entry address in a local (we use stack if needed)
    ; For simplicity, reclamation covers PT, PD, PDPT levels only.

.walk_pml4:
    ; -------------------------------------------------------------------------
    ; Level 4: PML4
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = logical index
    lea rbx, [pml4_shuffle_map]
    movzx rcx, word [rbx + rcx * 2]  ; RCX = physical (shuffled) index
    lea r13, [rax + rcx * 8]       ; R13 = &PML4[index] (parent of PDPT)
    mov rax, [r13]
    test rax, PAGE_PRESENT
    jz .done
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = PDPT base

    ; -------------------------------------------------------------------------
    ; Level 3: PDPT
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 30
    and rcx, 0x1FF
    lea r14, [rax + rcx * 8]       ; R14 = &PDPT[index] (parent of PD)
    mov rax, [r14]
    test rax, PAGE_PRESENT
    jz .done
    
    test rax, PAGE_HUGE
    jz .pdpt_not_huge

    ; It is a 1GB super page! Split it first.
    push r14
    push r13
    mov rdi, r12
    xor rsi, rsi
    call virt_split_super_1gb
    pop r13
    pop r14
    test rax, rax
    jz .done

    mov rax, [r14]

.pdpt_not_huge:
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = PD base

    ; -------------------------------------------------------------------------
    ; Level 2: PD
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 21
    and rcx, 0x1FF
    lea r15, [rax + rcx * 8]       ; R15 = &PD[index] (parent of PT)
    mov rax, [r15]
    test rax, PAGE_PRESENT
    jz .done
    
    test rax, PAGE_HUGE
    jz .pd_not_huge

    ; It is a 2MB huge page! Split it first.
    push r15
    push r14
    push r13
    mov rdi, r12
    xor rsi, rsi
    call virt_split_huge_2mb
    pop r13
    pop r14
    pop r15
    test rax, rax
    jz .done

    mov rax, [r15]

.pd_not_huge:
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = PT base

    ; -------------------------------------------------------------------------
    ; Level 1: PT (leaf)
    ; -------------------------------------------------------------------------
    mov rcx, r12
    shr rcx, 12
    and rcx, 0x1FF
    lea rbp, [rax + rcx * 8]       ; RBP = &PT[index] (the PTE itself)
    mov rcx, [rbp]
    test rcx, PAGE_PRESENT
    jz .done                        ; already unmapped

    ; Hook: Remove page from active/inactive list if it was a user page (PAGE_USER set)
    test rcx, PAGE_USER
    jz .skip_untrack

    push rax
    push rcx
    mov rdi, rcx
    and rdi, 0xFFFFFFFFFFFFF000     ; RDI = physical address of page
    call page_list_remove
    pop rcx
    pop rax

.skip_untrack:

    ; =========================================================================
    ; Step 1: Clear the leaf PTE
    ; =========================================================================
    mov qword [rbp], 0
    invlpg [r12]

    ; Add unmapped address to UAF quarantine list to trap future accesses
    mov rdi, r12
    extern uaf_quarantine_add
    call uaf_quarantine_add


    ; =========================================================================
    ; Step 2: Check if the PT is now fully empty → reclaim it
    ; =========================================================================
    ; RAX still holds the PT base physical address
    ; R15 = &PD[index] (parent entry that points to this PT)
    call .check_table_empty         ; RAX = PT base, returns CF=1 if empty
    jnc .done                       ; not empty, we're done

    ; PT is empty — recycle it (cache fast path → PMM fallback)
    mov rdi, rax                    ; RDI = PT physical address
    call ._recycle_table
    mov qword [r15], 0              ; clear PD entry pointing to this PT

    ; =========================================================================
    ; Step 3: Check if the PD is now fully empty → reclaim it
    ; =========================================================================
    mov rax, [r14]                  ; reload PDPT entry to get PD base
    and rax, 0xFFFFFFFFFFFFF000
    call .check_table_empty
    jnc .done

    ; PD is empty — recycle it
    mov rdi, rax
    call ._recycle_table
    mov qword [r14], 0              ; clear PDPT entry pointing to this PD

    ; =========================================================================
    ; Step 4: Check if the PDPT is now fully empty → reclaim it
    ; =========================================================================
    mov rax, [r13]                  ; reload PML4 entry to get PDPT base
    and rax, 0xFFFFFFFFFFFFF000
    call .check_table_empty
    jnc .done

    ; PDPT is empty — recycle it
    mov rdi, rax
    call ._recycle_table
    mov qword [r13], 0              ; clear PML4 entry pointing to this PDPT

    jmp .done

    ; -------------------------------------------------------------------------
    ; Huge page unmap shortcuts (no sub-table reclamation needed)
    ; -------------------------------------------------------------------------
.clear_huge_pdpt:
    mov qword [r14], 0
    invlpg [r12]
    jmp .done

.clear_huge_pd:
    mov qword [r15], 0
    invlpg [r12]
    jmp .done

.done:
    ; Release per-PML4 spinlock (3.4)
    mov rdi, r12
    call pgtable_lock_release

    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; .check_table_empty — checks if all 512 entries in a page table are zero
; Input:
;   RAX = physical base address of the page table
; Output:
;   CF = 1 if table is completely empty (all 512 entries == 0)
;   CF = 0 if table has at least one non-zero entry
; Clobbers: RCX, RDX
; NOTE: This is a local helper, not a public API.
; -----------------------------------------------------------------------------
.check_table_empty:
    xor rcx, rcx                    ; RCX = entry index (0 to 511)

.check_loop:
    cmp rcx, 512
    jge .is_empty

    mov rdx, [rax + rcx * 8]
    test rdx, rdx
    jnz .not_empty                  ; found a non-zero entry

    inc rcx
    jmp .check_loop

.is_empty:
    stc                             ; set CF = 1 (empty)
    ret

.not_empty:
    clc                             ; clear CF = 0 (not empty)
    ret

; -----------------------------------------------------------------------------
; ._recycle_table — recycles a reclaimed page table into the cache pool
; Tries pgtable_cache_free first (page is already zeroed since table was empty).
; Falls back to phys_free_page if the pool is full.
; Input:  RDI = physical address of the empty page table
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
._recycle_table:
    call pgtable_cache_free
    test rax, rax
    jnz .recycled                   ; accepted into pool

    ; Pool full — fall back to PMM
    call phys_free_page

.recycled:
    ret

%endif ; LIB_MEM_VIRT_PGTABLE_UNMAP_ASM
