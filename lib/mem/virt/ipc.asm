; =============================================================================
; Tattva OS — lib/mem/virt/ipc.asm
; =============================================================================
; Shared Memory & IPC Primitives implementation (Subfeatures 18.1, 18.2).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_IPC_ASM
%define LIB_MEM_VIRT_IPC_ASM

[BITS 64]

; Page Table Entry Flags (64-bit)
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_HUGE       equ (1 << 7)
PAGE_GLOBAL     equ (1 << 8)
PAGE_NX         equ (1 << 63)

section .text

; External VMM symbols
extern vma_create
extern vma_destroy
extern vma_find
extern phys_alloc_page
extern phys_free_page
extern memzero
extern memcpy
extern virt_map
extern virt_unmap
extern virt_walk_table
extern pgtable_lock_acquire
extern pgtable_lock_release
extern pgtable_cache_alloc
extern pgtable_cache_free
extern virt_split_super_1gb
extern virt_split_huge_2mb

; -----------------------------------------------------------------------------
; virt_map_space — maps a virtual page in a custom PML4 address space
; Input:
;   RDI = virtual address (4KB page aligned)
;   RSI = physical address (4KB page aligned)
;   RDX = mapping flags (e.g. PAGE_WRITABLE, PAGE_USER, PAGE_NX)
;   R8  = physical address of target PML4 root (if 0, reads current CR3)
; Output:
;   RAX = 1 on success, 0 on failure (OOM during table allocation)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_map_space
virt_map_space:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r12, rdi
    and r12, -4096                  ; R12 = virtual address
    mov r13, rsi
    and r13, -4096                  ; R13 = physical address
    mov r14, rdx                    ; R14 = flags
    or r14, PAGE_PRESENT            ; always present when mapped
    mov rbp, r8                     ; RBP = target PML4 physical root directory

    ; Acquire per-PML4 spinlock for this virtual address
    mov rdi, r12
    call pgtable_lock_acquire

    ; Determine root directory base physical address
    mov rax, rbp
    test rax, rax
    jnz .have_root
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = root physical base
.have_root:

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
    
    ; Allocate new PML4 table (cache fast path -> PMM fallback)
    push rax
    push rcx
    call ._alloc_zeroed_table_local
    pop rcx
    pop rdx                         ; RDX = parent directory address
    test rax, rax
    jz .oom
    
    ; Link PML4 to PML5
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
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = logical index
    push rdx
    lea rdx, [pml4_shuffle_map]
    movzx rcx, word [rdx + rcx * 2]  ; RCX = physical (shuffled) index
    pop rdx
    mov rbx, [rax + rcx * 8]         ; RBX = PML4 entry
    test rbx, PAGE_PRESENT
    jnz .have_pdpt

    ; Allocate new PDPT table
    push rax
    push rcx
    call ._alloc_zeroed_table_local
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
    call ._alloc_zeroed_table_local
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
    call ._alloc_zeroed_table_local
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

    ; Flush TLB for this virtual address (only if target address space is current)
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000
    mov rdx, rbp
    test rdx, rdx
    jz .flush
    cmp rdx, rax
    jne .skip_flush
.flush:
    invlpg [r12]
.skip_flush:

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
    xor rax, rax                    ; return 0 (OOM)

.unlock_exit:
    push rax
    mov rdi, r12
    call pgtable_lock_release
    pop rax

    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ._alloc_zeroed_table_local — allocates a zeroed 4KB page for a page table
; -----------------------------------------------------------------------------
._alloc_zeroed_table_local:
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

; -----------------------------------------------------------------------------
; ipc_share_frame — share physical page frame with another PML4 space (Subfeature 18.1)
; Input:
;   RDI = vaddr_src (source virtual address, page-aligned)
;   RSI = pml4_dest (physical address of target PML4)
;   RDX = vaddr_dest (destination virtual address, page-aligned)
;   RCX = flags (mapping flags)
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global ipc_share_frame
ipc_share_frame:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = vaddr_src
    mov r13, rsi                    ; R13 = pml4_dest
    mov r14, rdx                    ; R14 = vaddr_dest
    mov r15, rcx                    ; R15 = flags

    ; 1. Walk current page table for vaddr_src to find physical page address
    mov rdi, r12
    xor rsi, rsi                    ; 0 = use current CR3
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .err

    mov rcx, [rax]                  ; RCX = PTE value
    test rcx, PAGE_PRESENT
    jz .err

    ; Extract physical page frame address
    mov rbx, rcx
    mov rax, 0xFFFFFFFFFFFFF000
    and rbx, rax                    ; RBX = physical page address

    ; 2. Map this physical page to vaddr_dest in the target address space
    mov rdi, r14                    ; vaddr_dest
    mov rsi, rbx                    ; physical page
    mov rdx, r15                    ; flags
    mov r8, r13                     ; target PML4
    call virt_map_space
    test rax, rax
    jz .err

    mov rax, 1                      ; success
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.err:
    xor rax, rax                    ; failure
    jmp .exit

; -----------------------------------------------------------------------------
; ipc_create_ring_buffer — creates consecutive twice-mapped ring buffer (Subfeature 18.2)
; Input:
;   RDI = start_vaddr (page-aligned)
;   RSI = size_N (buffer size in bytes, page-aligned)
;   RDX = flags (VMA/mapping flags)
; Output:
;   RAX = start_vaddr on success, 0 on OOM/overlap
; -----------------------------------------------------------------------------
global ipc_create_ring_buffer
ipc_create_ring_buffer:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = start_vaddr
    mov r13, rsi                    ; R13 = size_N
    mov r14, rdx                    ; R14 = flags

    ; Calculate double size (2 * size_N)
    mov r15, r13
    shl r15, 1                      ; R15 = 2 * size_N

    ; 1. Create a single VMA covering the double range
    mov rdi, r12
    mov rsi, r15
    mov rdx, r14
    call vma_create                 ; RAX = VMA pointer or 0
    test rax, rax
    jz .err

    ; 2. Allocate and map N bytes of physical pages twice consecutively
    xor rbx, rbx                    ; RBX = page offset (0, 4096, ...)
.loop:
    cmp rbx, r13
    jae .success

    ; Allocate a physical RAM page frame
    push rbx
    call phys_alloc_page            ; RAX = physical address or 0
    pop rbx
    test rax, rax
    jz .err_allocated

    mov r15, rax                    ; R15 = physical page address

    ; Map to first virtual half: start_vaddr + offset -> physical_page
    mov rdi, r12
    add rdi, rbx                    ; RDI = start_vaddr + offset
    mov rsi, r15                    ; physical page
    mov rdx, r14                    ; flags
    push rbx
    call virt_map
    pop rbx
    test rax, rax
    jz .err_allocated

    ; Map to second virtual half: start_vaddr + size_N + offset -> physical_page
    mov rdi, r12
    add rdi, r13
    add rdi, rbx                    ; RDI = start_vaddr + size_N + offset
    mov rsi, r15                    ; physical page
    mov rdx, r14                    ; flags
    push rbx
    call virt_map
    pop rbx
    test rax, rax
    jz .err_allocated

    add rbx, 4096
    jmp .loop

.success:
    mov rax, r12                    ; return start address
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.err_allocated:
    ; Clean up partially allocated pages by destroying mapped ring buffer up to RBX offset
    mov rdi, r12
    mov rsi, rbx
    call ipc_destroy_ring_buffer

.err:
    xor rax, rax                    ; return 0 (failure)
    jmp .exit

; -----------------------------------------------------------------------------
; ipc_destroy_ring_buffer — unmaps ring buffer double range and frees pages once
; Input:
;   RDI = start_vaddr
;   RSI = size_N
; Output:
;   RAX = 1
; -----------------------------------------------------------------------------
global ipc_destroy_ring_buffer
ipc_destroy_ring_buffer:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = start_vaddr
    mov r13, rsi                    ; R13 = size_N

    xor rbx, rbx                    ; RBX = offset
.loop:
    cmp rbx, r13
    jae .destroy_vma

    ; Walk page table at start_vaddr + offset to extract physical page address
    mov rdi, r12
    add rdi, rbx
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .next

    mov rcx, [rax]
    test rcx, PAGE_PRESENT
    jz .next

    ; Extract physical address of the page frame
    and rcx, 0xFFFFFFFFFFFFF000
    mov r15, rcx                    ; R15 = physical page address

    ; Unmap first half (start_vaddr + offset)
    mov rdi, r12
    add rdi, rbx
    push rax
    call virt_unmap
    pop rax

    ; Unmap second half (start_vaddr + size_N + offset)
    mov rdi, r12
    add rdi, r13
    add rdi, rbx
    call virt_unmap

    ; Free the physical page frame exactly once to prevent double-free corruption
    mov rdi, r15
    call phys_free_page

.next:
    add rbx, 4096
    jmp .loop

.destroy_vma:
    ; Find the double VMA starting at start_vaddr and destroy it
    mov rdi, r12
    call vma_find
    test rax, rax
    jz .done

    mov rdi, rax
    call vma_destroy

.done:
    mov rax, 1                      ; success
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_IPC_ASM
