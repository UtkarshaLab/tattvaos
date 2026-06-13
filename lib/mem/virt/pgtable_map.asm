; =============================================================================
; Tattva OS — lib/mem/virt/pgtable_map.asm
; =============================================================================
; Virtual memory page mapping API (maps virtual -> physical).
; Uses the pgtable_cache recycling pool (3.3) as a fast path for
; intermediate table allocation, and per-PML4 spinlocks (3.4) for
; concurrent safety on multi-core systems.
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

    ; Check if PAGE_XO flag is set
    test r14, PAGE_XO
    jz .not_xo_map_setup

    ; It is XO mapping! Check CPUID for PKU support (CPUID.07H.0H:EBX.PKU [bit 3])
    push rax
    push rbx
    push rcx
    push rdx
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, (1 << 3)              ; check bit 3 (PKU support)
    pop rdx
    pop rcx
    pop rbx
    pop rax
    jz .xo_software_fallback

    ; Hardware PKU mode: map as present, clear NX, and set Protection Key 1
    or r14, PAGE_PRESENT
    mov rcx, PAGE_KEY_1             ; Key 1 in bits 62:59
    or r14, rcx
    mov rcx, PAGE_NX
    not rcx
    and r14, rcx                    ; clear NX to allow execution
    jmp .xo_map_done

.xo_software_fallback:
    ; Software fallback mode: map as non-present in hardware (P=0)
    ; But keep PAGE_XO flag (bit 9) set for software fault tracking
    or r14, PAGE_XO
    and r14, ~PAGE_PRESENT
    jmp .xo_map_done

.not_xo_map_setup:
    or r14, PAGE_PRESENT            ; always present when mapped for normal pages
.xo_map_done:

    ; Clear address from UAF quarantine list if it was previously freed
    mov rdi, r12
    extern uaf_quarantine_remove
    call uaf_quarantine_remove

    ; Acquire per-PML4 spinlock for this virtual address (3.4)
    mov rdi, r12
    call pgtable_lock_acquire


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
    and rcx, 0x1FF                  ; RCX = logical index
    lea r8, [pml4_shuffle_map]
    movzx rcx, word [r8 + rcx * 2]  ; RCX = physical (shuffled) index
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
    jz .create_pd

    test rbx, PAGE_HUGE
    jz .have_pd

    ; It is a 1GB super page! Split it first.
    push rax
    push rcx
    mov rdi, r12
    mov rsi, rax
    call virt_split_super_1gb
    pop rcx
    pop rax
    test rax, rax
    jz .oom

    mov rbx, [rax + rcx * 8]         ; re-load split entry (now points to PD)
    jmp .have_pd

.create_pd:
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
    jz .create_pt

    test rbx, PAGE_HUGE
    jz .have_pt

    ; It is a 2MB huge page! Split it first.
    push rax
    push rcx
    mov rdi, r12
    xor rsi, rsi
    call virt_split_huge_2mb
    pop rcx
    pop rax
    test rax, rax
    jz .oom

    mov rbx, [rax + rcx * 8]         ; re-load split entry (now points to PT)
    jmp .have_pt

.create_pt:
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

    ; Hook: Add page to active list if PAGE_USER is set and PAGE_GLOBAL is clear
    test r14, PAGE_USER
    jz .skip_tracking
    test r14, PAGE_GLOBAL
    jnz .skip_tracking

    mov rdi, r13                    ; physical address
    mov rsi, r12                    ; virtual address
    call page_list_add_active

.skip_tracking:
    mov rax, 1                      ; return 1 (success)
    jmp .unlock_exit

.oom:
    xor rax, rax                    ; return 0 (OOM/error)

.unlock_exit:
    ; Release per-PML4 spinlock (3.4)
    push rax
    mov rdi, r12
    call pgtable_lock_release
    pop rax

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_map_global — maps a 4KB virtual page to a physical frame with PAGE_GLOBAL set
; Input:
;   RDI = virtual address (should be 4KB page aligned)
;   RSI = physical address (should be 4KB page aligned)
;   RDX = mapping flags (e.g. PAGE_WRITABLE, PAGE_USER, PAGE_NX)
; Output:
;   RAX = 1 on success, 0 on failure (OOM during table allocation)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_map_global
virt_map_global:
    or rdx, PAGE_GLOBAL
    jmp virt_map

; -----------------------------------------------------------------------------
; virt_map_huge_2mb — maps a 2MB huge page in the virtual address space
; Input:
;   RDI = virtual address (should be 2MB aligned)
;   RSI = physical address (should be 2MB aligned)
;   RDX = mapping flags (e.g. PAGE_WRITABLE, PAGE_USER, PAGE_NX, PAGE_GLOBAL)
; Output:
;   RAX = 1 on success, 0 on failure (OOM during table allocation)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_map_huge_2mb
virt_map_huge_2mb:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Align addresses to 2MB boundaries
    mov r12, rdi
    and r12, -0x200000              ; R12 = aligned virtual address
    mov r13, rsi
    and r13, -0x200000              ; R13 = aligned physical address
    
    mov r14, rdx                    ; R14 = flags
    or r14, PAGE_PRESENT | PAGE_HUGE ; always present + huge page bit

    ; Acquire per-PML4 spinlock
    mov rdi, r12
    call pgtable_lock_acquire

    ; Load CR3
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = root physical base

    ; Check 5-level paging
    mov rcx, cr4
    test rcx, (1 << 12)
    jz .do_pml4

    ; PML5
    mov rcx, r12
    shr rcx, 48
    and rcx, 0x1FF
    mov rbx, [rax + rcx * 8]
    test rbx, PAGE_PRESENT
    jnz .have_pml4
    
    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx
    test rax, rax
    jz .oom
    
    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pml4:
    and rbx, 0xFFFFFFFFFFFFF000
    mov rax, rbx

.do_pml4:
    ; PML4
    mov rcx, r12
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = logical index
    lea r8, [pml4_shuffle_map]
    movzx rcx, word [r8 + rcx * 2]  ; RCX = physical (shuffled) index
    mov rbx, [rax + rcx * 8]
    test rbx, PAGE_PRESENT
    jnz .have_pdpt

    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx
    test rax, rax
    jz .oom

    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pdpt:
    and rbx, 0xFFFFFFFFFFFFF000
    mov rax, rbx

    ; PDPT
    mov rcx, r12
    shr rcx, 30
    and rcx, 0x1FF
    mov rbx, [rax + rcx * 8]
    test rbx, PAGE_PRESENT
    jz .create_pd

    test rbx, PAGE_HUGE
    jz .have_pd

    ; It is a 1GB super page! Split it first.
    push rax
    push rcx
    mov rdi, r12
    mov rsi, rax
    call virt_split_super_1gb
    pop rcx
    pop rax
    test rax, rax
    jz .oom

    mov rbx, [rax + rcx * 8]         ; re-load split entry (now points to PD)
    jmp .have_pd

.create_pd:

    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx
    test rax, rax
    jz .oom

    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pd:
    and rbx, 0xFFFFFFFFFFFFF000
    mov rax, rbx                    ; RAX = PD physical address

    ; PD entry (PDE) index
    mov rcx, r12
    shr rcx, 21
    and rcx, 0x1FF                  ; RCX = PD index

    ; Check if an entry is already present
    mov rdx, [rax + rcx * 8]
    test rdx, PAGE_PRESENT
    jz .write_pde

    ; It is present. Check if it points to a sub-page table (not a huge page)
    test rdx, PAGE_HUGE
    jnz .write_pde                  ; if it was already huge, just overwrite

    ; It was a page table pointer. Recycle it to prevent memory leaks!
    and rdx, 0xFFFFFFFFFFFFF000     ; RDX = PT physical address
    
    push rax
    push rcx
    mov rdi, rdx
    call pgtable_cache_free
    test rax, rax
    jnz .recycle_done
    call phys_free_page
.recycle_done:
    pop rcx
    pop rax

.write_pde:
    ; Set PD entry (PDE) with physical address and flags
    mov rdx, r13
    or rdx, r14                     ; RDX = phys_base | flags
    mov [rax + rcx * 8], rdx

    ; Flush TLB
    invlpg [r12]

    mov rax, 1                      ; return 1 (success)
    jmp .unlock_exit

.oom:
    xor rax, rax                    ; return 0 (OOM)

.unlock_exit:
    push rax
    mov rdi, r12
    call pgtable_lock_release
    pop rax

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_map_super_1gb — maps a 1GB super page in the virtual address space
; Input:
;   RDI = virtual address (should be 1GB aligned)
;   RSI = physical address (should be 1GB aligned)
;   RDX = mapping flags (e.g. PAGE_WRITABLE, PAGE_USER, PAGE_NX, PAGE_GLOBAL)
; Output:
;   RAX = 1 on success, 0 on failure (OOM during table allocation)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_map_super_1gb
virt_map_super_1gb:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Align addresses to 1GB boundaries
    mov r12, rdi
    and r12, -0x40000000            ; R12 = aligned virtual address
    mov r13, rsi
    and r13, -0x40000000            ; R13 = aligned physical address
    
    mov r14, rdx                    ; R14 = flags
    or r14, PAGE_PRESENT | PAGE_HUGE ; always present + huge page bit

    ; Acquire per-PML4 spinlock
    mov rdi, r12
    call pgtable_lock_acquire

    ; Load CR3
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = root physical base

    ; Check 5-level paging
    mov rcx, cr4
    test rcx, (1 << 12)
    jz .do_pml4

    ; PML5
    mov rcx, r12
    shr rcx, 48
    and rcx, 0x1FF
    mov rbx, [rax + rcx * 8]
    test rbx, PAGE_PRESENT
    jnz .have_pml4
    
    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx
    test rax, rax
    jz .oom
    
    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pml4:
    and rbx, 0xFFFFFFFFFFFFF000
    mov rax, rbx

.do_pml4:
    ; PML4
    mov rcx, r12
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = logical index
    lea r8, [pml4_shuffle_map]
    movzx rcx, word [r8 + rcx * 2]  ; RCX = physical (shuffled) index
    mov rbx, [rax + rcx * 8]
    test rbx, PAGE_PRESENT
    jnz .have_pdpt

    push rax
    push rcx
    call ._alloc_zeroed_table
    pop rcx
    pop rdx
    test rax, rax
    jz .oom

    mov rbx, rax
    or rbx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [rdx + rcx * 8], rbx

.have_pdpt:
    and rbx, 0xFFFFFFFFFFFFF000
    mov rax, rbx                    ; RAX = PDPT physical address

    ; PDPT entry (PDPTE) index
    mov rcx, r12
    shr rcx, 30
    and rcx, 0x1FF                  ; RCX = PDPT index

    ; Check if an entry is already present
    mov rdx, [rax + rcx * 8]
    test rdx, PAGE_PRESENT
    jz .write_pdpte

    ; It is present. Check if it points to a sub-page directory (not a huge page)
    test rdx, PAGE_HUGE
    jnz .write_pdpte                ; if it was already huge/super, just overwrite

    ; It was a Page Directory pointer. Recursively clean up sub-directories to prevent leaks!
    and rdx, 0xFFFFFFFFFFFFF000     ; RDX = PD physical address

    ; We need to preserve RAX (PDPT address) and RCX (PDPT index)
    push rax
    push rcx
    
    ; Loop through the PD (512 entries)
    xor r8, r8                      ; R8 = PD entry index
.pd_clean_loop:
    cmp r8, 512
    jge .pd_clean_done

    mov r9, [rdx + r8 * 8]          ; R9 = PDE value
    test r9, PAGE_PRESENT
    jz .next_pde
    test r9, PAGE_HUGE
    jnz .next_pde                   ; skip if it is a 2MB huge page (no PT linked)

    ; It points to a Page Table (PT). Free it!
    and r9, 0xFFFFFFFFFFFFF000     ; R9 = PT physical address
    
    push rdx
    push r8
    mov rdi, r9
    call pgtable_cache_free
    test rax, rax
    jnz .pt_free_done
    call phys_free_page
.pt_free_done:
    pop r8
    pop rdx

.next_pde:
    inc r8
    jmp .pd_clean_loop

.pd_clean_done:
    ; Free the PD itself!
    mov rdi, rdx
    call pgtable_cache_free
    test rax, rax
    jnz .pd_free_done
    call phys_free_page
.pd_free_done:

    pop rcx
    pop rax

.write_pdpte:
    ; Set PDPT entry (PDPTE) with physical address and flags
    mov rdx, r13
    or rdx, r14                     ; RDX = phys_base | flags
    mov [rax + rcx * 8], rdx

    ; Flush TLB
    invlpg [r12]

    mov rax, 1                      ; return 1 (success)
    jmp .unlock_exit

.oom:
    xor rax, rax                    ; return 0 (OOM)

.unlock_exit:
    push rax
    mov rdi, r12
    call pgtable_lock_release
    pop rax

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
