; =============================================================================
; Tattva OS — lib/mem/virt/pgtable_cache.asm
; =============================================================================
; Directory Cache — Page Table Recycling Pool (3.3).
; Maintains a small pool of pre-zeroed 4KB pages for instant page table
; allocation during virt_map, avoiding PMM allocator locks on the hot path.
; When virt_unmap reclaims an empty table, it returns the page here instead
; of going through phys_free_page (if the pool isn't full).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_CACHE_ASM
%define LIB_MEM_VIRT_PGTABLE_CACHE_ASM

[BITS 64]

; Pool capacity — number of pre-zeroed pages to cache
PGTABLE_CACHE_CAPACITY equ 16

section .text

; -----------------------------------------------------------------------------
; pgtable_cache_init — pre-fills the recycling pool with zeroed pages
; Input:  none
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global pgtable_cache_init
pgtable_cache_init:
    push rbx
    push r12

    xor r12, r12                    ; R12 = pages filled so far

.fill_loop:
    cmp r12, PGTABLE_CACHE_CAPACITY
    jge .fill_done

    ; Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .fill_done                   ; stop early if OOM (partial fill is OK)

    ; Zero the page
    push rax
    mov rdi, rax
    mov rsi, 4096
    call memzero
    pop rax

    ; Store in pool
    lea rcx, [pgtable_cache_pool]
    mov [rcx + r12 * 8], rax

    inc r12
    jmp .fill_loop

.fill_done:
    mov [pgtable_cache_count], r12

    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; pgtable_cache_alloc — pop a pre-zeroed page from the recycling pool
; Input:  none
; Output: RAX = physical address of a zeroed 4KB page, or 0 if pool is empty
; Clobbers: RCX
; NOTE: If pool is empty, caller should fall back to phys_alloc_page + memzero.
; -----------------------------------------------------------------------------
global pgtable_cache_alloc
pgtable_cache_alloc:
    mov rcx, [pgtable_cache_count]
    test rcx, rcx
    jz .empty

    ; Pop from top of stack (last in, first out)
    dec rcx
    mov [pgtable_cache_count], rcx
    lea rax, [pgtable_cache_pool]
    mov rax, [rax + rcx * 8]
    ret

.empty:
    xor rax, rax                    ; return 0 (pool empty)
    ret

; -----------------------------------------------------------------------------
; pgtable_cache_free — push a page back into the recycling pool
; Input:  RDI = physical address of a 4KB page to recycle
; Output: RAX = 1 if accepted into pool, 0 if pool is full
; Clobbers: RCX
; NOTE: The page MUST already be zeroed by the caller before recycling.
;       If pool is full, caller should fall back to phys_free_page.
; -----------------------------------------------------------------------------
global pgtable_cache_free
pgtable_cache_free:
    mov rcx, [pgtable_cache_count]
    cmp rcx, PGTABLE_CACHE_CAPACITY
    jge .full

    ; Push onto top of stack
    lea rax, [pgtable_cache_pool]
    mov [rax + rcx * 8], rdi
    inc rcx
    mov [pgtable_cache_count], rcx
    mov rax, 1                      ; accepted
    ret

.full:
    xor rax, rax                    ; pool full, caller must use phys_free_page
    ret

; -----------------------------------------------------------------------------
; Data — Pool storage
; -----------------------------------------------------------------------------
section .bss

align 8
pgtable_cache_pool: resq PGTABLE_CACHE_CAPACITY    ; array of physical page addresses
pgtable_cache_count: resq 1                         ; current number of cached pages

%endif ; LIB_MEM_VIRT_PGTABLE_CACHE_ASM
