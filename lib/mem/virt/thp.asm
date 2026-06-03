; =============================================================================
; Tattva OS — lib/mem/virt/thp.asm
; =============================================================================
; Transparent Huge Pages (THP) sweep daemon (5.3).
; Scans page mappings to identify contiguous blocks of 512 4KB pages and
; merges them into a single 2MB huge page.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_THP_ASM
%define LIB_MEM_VIRT_THP_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; virt_thp_sweep — sweeps a virtual address range to identify and merge
;                  eligible 512 contiguous 4KB pages into 2MB huge pages
; Input:
;   RDI = start virtual address (2MB aligned)
;   RSI = size in bytes (2MB aligned)
; Output:
;   RAX = number of successful 2MB merges performed
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_thp_sweep
virt_thp_sweep:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    xor r15, r15                    ; R15 = merge counter (number of 2MB merges)

    ; Align range start down to 2MB, size up to 2MB
    mov r12, rdi
    and r12, -0x200000              ; R12 = current virtual address (aligned)
    
    add rsi, rdi
    add rsi, 0x1FFFFF
    and rsi, -0x200000              ; RSI = aligned end virtual address
    mov r13, rsi                    ; R13 = end virtual address

.region_loop:
    cmp r12, r13
    jae .done

    ; Walk page tables using virt_walk_table to check if region is mapped
    mov rdi, r12
    xor rsi, rsi                    ; current CR3
    call virt_walk_table            ; RAX = leaf entry address, RDX = level
    test rax, rax
    jz .next_region                 ; not mapped, skip this 2MB region
    
    ; We must check if it is mapped as standard 4KB pages (level 4 or 5)
    cmp rdx, 4                      ; level 4 in 4-level paging
    je .check_merge
    cmp rdx, 5                      ; level 5 in 5-level paging
    je .check_merge
    
    ; Already a huge/super page (level 2 or 3), skip
    jmp .next_region

.check_merge:
    ; RAX is the address of the leaf PTE.
    ; Align RAX down to 4KB to get the base address of the Page Table (PT).
    mov rbp, rax
    and rbp, -4096                  ; RBP = physical address of PT base

    ; Verify all 512 entries in this PT:
    ; 1. All entries must be present.
    ; 2. All entries must have identical flags.
    ; 3. All entries must be physically contiguous (entry[i] == entry[0] + i * 4096).
    
    ; Read reference entry (entry 0)
    mov r9, [rbp + 0]               ; R9 = reference PTE value
    test r9, PAGE_PRESENT
    jz .next_region                 ; entry 0 must be present
    
    ; Extract reference flags (mask out physical address bits 12-51)
    mov r10, 0xFFFFFFFFFFFFF000
    not r10                         ; R10 = flags mask
    
    mov r11, r9
    and r11, r10                    ; R11 = reference flags
    
    ; Extract reference physical address base
    mov r14, r9
    and r14, 0xFFFFFFFFFFFFF000     ; R14 = reference physical base address of page 0
    
    ; Verify that the physical base address is 2MB aligned
    mov rbx, r14
    and rbx, 0x1FFFFF               ; check offset in 2MB page
    jnz .next_region                ; if physical address is not 2MB aligned, cannot merge

    ; Loop through entries 1 to 511
    mov r8, 1                       ; R8 = loop index
.entry_loop:
    cmp r8, 512
    jge .do_merge                   ; all checked, eligible for merge!

    mov rbx, [rbp + r8 * 8]         ; RBX = current PTE value
    test rbx, PAGE_PRESENT
    jz .next_region                 ; must be present

    ; Check identical flags
    mov rcx, rbx
    and rcx, r10                    ; RCX = current flags
    cmp rcx, r11
    jne .next_region                ; flags mismatch

    ; Check physical contiguity: current_phys == reference_phys + r8 * 4096
    and rbx, 0xFFFFFFFFFFFFF000     ; RBX = current physical address
    
    mov rcx, r8
    shl rcx, 12                     ; RCX = r8 * 4096
    add rcx, r14                    ; RCX = expected physical address
    cmp rbx, rcx
    jne .next_region                ; physical address not contiguous

    inc r8
    jmp .entry_loop

.do_merge:
    ; Acquire per-PML4 spinlock to perform the merge safely
    mov rdi, r12
    call pgtable_lock_acquire

    ; Walk directories to find the PDE address
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = root physical base

    ; Check 5-level paging
    mov rcx, cr4
    test rcx, (1 << 12)
    jz .merge_pml4

    ; PML5
    mov rcx, r12
    shr rcx, 48
    and rcx, 0x1FF
    mov rax, [rax + rcx * 8]
    and rax, 0xFFFFFFFFFFFFF000

.merge_pml4:
    ; PML4
    mov rcx, r12
    shr rcx, 39
    and rcx, 0x1FF
    mov rax, [rax + rcx * 8]
    and rax, 0xFFFFFFFFFFFFF000

    ; PDPT
    mov rcx, r12
    shr rcx, 30
    and rcx, 0x1FF
    mov rax, [rax + rcx * 8]
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = PD physical base address

    ; PD index
    mov rcx, r12
    shr rcx, 21
    and rcx, 0x1FF                  ; RCX = PD index
    
    lea rdx, [rax + rcx * 8]        ; RDX = PDE address

    ; Verify that the PDE still points to our PT (RBP) to avoid race conditions
    mov rax, [rdx]
    and rax, 0xFFFFFFFFFFFFF000
    cmp rax, rbp
    jne .merge_abort

    ; 1. Construct the new 2MB huge page entry
    mov rax, r14
    or rax, r11
    or rax, PAGE_HUGE               ; mark as huge page

    ; 2. Write the new PDE
    mov [rdx], rax

    ; 3. Flush the TLB for the entire 2MB region (512 pages) on all cores
    mov rdi, r12
    mov rsi, 512
    call tlb_shootdown

    ; 4. Free the old PT
    mov rdi, rbp
    call pgtable_cache_free
    test rax, rax
    jnz .merge_success
    call phys_free_page

.merge_success:
    inc r15                         ; increment merge counter

.merge_abort:
    mov rdi, r12
    call pgtable_lock_release

.next_region:
    add r12, 0x200000               ; advance to next 2MB region
    jmp .region_loop

.done:
    mov rax, r15                    ; return merge count
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_THP_ASM
