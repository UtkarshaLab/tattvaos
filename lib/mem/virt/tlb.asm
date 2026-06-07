; =============================================================================
; Tattva OS — lib/mem/virt/tlb.asm
; =============================================================================
; TLB (Translation Lookaside Buffer) management operations.
;
; 4.1: Individual page invalidation (invlpg)
; 4.2: Complete TLB flush (CR3 reload)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_TLB_ASM
%define LIB_MEM_VIRT_TLB_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; tlb_flush_page — invalidate a single page in the TLB (4.1)
; Input:
;   RDI = virtual address of the page to invalidate
; Output: none
; Clobbers: none
; NOTE: This is the preferred method for single-page changes (map/unmap/
;       permission update). Much cheaper than a full TLB flush.
; -----------------------------------------------------------------------------
global tlb_flush_page
tlb_flush_page:
    invlpg [rdi]
    ret

; -----------------------------------------------------------------------------
; tlb_flush_range — invalidate a contiguous range of pages in the TLB (4.1)
; Input:
;   RDI = starting virtual address (page-aligned)
;   RSI = number of pages to invalidate
; Output: none
; Clobbers: RAX, RCX
; NOTE: For large ranges (> ~32 pages), a full CR3 reload via
;       tlb_flush_all may be faster due to invlpg serialization cost.
; -----------------------------------------------------------------------------
global tlb_flush_range
tlb_flush_range:
    mov rcx, rsi                    ; RCX = page count
    mov rax, rdi                    ; RAX = current virtual address

    test rcx, rcx
    jz .done

.loop:
    invlpg [rax]
    add rax, 4096                   ; next page
    dec rcx
    jnz .loop

.done:
    ret

; -----------------------------------------------------------------------------
; tlb_flush_all — flush all non-global TLB entries via CR3 reload (4.2)
; Input:  none
; Output: none
; Clobbers: RAX
; NOTE: This evicts ALL cached translations except those with the Global
;       bit set (PAGE_GLOBAL). Use sparingly — it is expensive. Preferred
;       only when many pages changed (e.g. address space switch, bulk unmap).
; -----------------------------------------------------------------------------
global tlb_flush_all
tlb_flush_all:
    mov rax, cr3
    mov cr3, rax                    ; reload CR3 → flushes all non-global entries
    ret

; -----------------------------------------------------------------------------
; tlb_flush_all_global — flush ALL TLB entries including global pages (4.2)
; Input:  none
; Output: none
; Clobbers: RAX
; NOTE: Temporarily clears CR4.PGE (bit 7) to force eviction of global
;       entries, then re-enables it. Required when modifying kernel mappings
;       marked with PAGE_GLOBAL.
; -----------------------------------------------------------------------------
global tlb_flush_all_global
tlb_flush_all_global:
    mov rax, cr4
    and rax, ~(1 << 7)              ; clear PGE bit
    mov cr4, rax                    ; flush all TLB entries (including global)
    or rax, (1 << 7)                ; re-set PGE bit
    mov cr4, rax
    ret

; -----------------------------------------------------------------------------
; virt_mark_global_range — walks page tables and sets PAGE_GLOBAL on a range (4.4)
; Input:
;   RDI = starting virtual address
;   RSI = range size in bytes
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global virt_mark_global_range
virt_mark_global_range:
    push rbx
    push r12
    push r13

    test rsi, rsi
    jz .done

    ; Align start virtual address down to 4KB
    mov r12, rdi
    and r12, -4096                  ; R12 = current virtual address
    
    ; Calculate end address
    mov r13, rdi
    add r13, rsi                    ; R13 = end virtual address

.loop:
    cmp r12, r13
    jae .done

    ; Walk page table using current virtual address
    mov rdi, r12
    xor rsi, rsi                    ; use current CR3
    call virt_walk_table            ; RAX = PTE address, RDX = level
    test rax, rax
    jz .not_mapped

    ; Set the Global bit (PAGE_GLOBAL = 1 << 8) in the entry
    or qword [rax], PAGE_GLOBAL

    ; Check resolved level to know how much to advance
    cmp rdx, 2                      ; 1GB super page
    je .advance_1gb
    cmp rdx, 3                      ; 2MB huge page
    je .advance_2mb

.advance_4kb:
    add r12, 4096
    jmp .loop

.advance_2mb:
    mov rax, r12
    and rax, 0x1FFFFF               ; offset in 2MB page
    mov rcx, 0x200000
    sub rcx, rax                    ; remaining bytes in this 2MB page
    add r12, rcx
    jmp .loop

.advance_1gb:
    mov rax, r12
    and rax, 0x3FFFFFFF             ; offset in 1GB page
    mov rcx, 0x40000000
    sub rcx, rax                    ; remaining bytes in this 1GB page
    add r12, rcx
    jmp .loop

.not_mapped:
    ; Not mapped, just advance by 4KB to check next page
    add r12, 4096
    jmp .loop

.done:
    ; Flush the TLB to make the global pages active immediately
    call tlb_flush_all_global

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tlb_pcid_supported — checks if PCID is supported by the CPU
; Input:  none
; Output: RAX = 1 if supported, 0 otherwise
; Clobbers: RAX, RBX, RCX, RDX
; -----------------------------------------------------------------------------
global tlb_pcid_supported
tlb_pcid_supported:
    mov eax, 1
    cpuid
    test ecx, 1 << 17
    jz .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; tlb_pcid_enable — enables PCID on the current core (if supported)
; Input:  none
; Output: RAX = 1 on success, 0 on failure (not supported)
; Clobbers: RAX, RBX, RCX, RDX
; -----------------------------------------------------------------------------
global tlb_pcid_enable
tlb_pcid_enable:
    call tlb_pcid_supported
    test rax, rax
    jz .failed
    
    mov rax, cr4
    or rax, 1 << 17             ; set PCIDE
    mov cr4, rax
    mov rax, 1
    ret
.failed:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; tlb_pcid_get — gets the current PCID from CR3
; Input:  none
; Output: RAX = current PCID (0 - 4095)
; Clobbers: none (preserves all registers except RAX)
; -----------------------------------------------------------------------------
global tlb_pcid_get
tlb_pcid_get:
    mov rax, cr3
    and rax, 0xFFF              ; PCID is in bits 0-11
    ret

; -----------------------------------------------------------------------------
; tlb_pcid_set — sets the current PCID in CR3
; Input:
;   RDI = target PCID (0 - 4095)
;   RSI = preserve flag (1 = keep TLB entries, 0 = flush TLB entries)
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global tlb_pcid_set
tlb_pcid_set:
    mov rax, cr3
    mov rcx, 0xFFFFFFFFFFFFF000 ; mask out current PCID and preserve bit (63)
    and rax, rcx                ; RAX = PML4 base physical address
    
    and rdi, 0xFFF              ; enforce 12-bit PCID range
    or rax, rdi                 ; set PCID in bits 0-11
    
    test rsi, rsi
    jz .write
    
    ; Set bit 63 (no-preserve flag)
    mov rcx, 1
    shl rcx, 63
    or rax, rcx
    
.write:
    mov cr3, rax
    ret

; -----------------------------------------------------------------------------
; tlb_invpcid — invalidates TLB entries using the INVPCID instruction
; Input:
;   RDI = invalidation type (0: individual, 1: single PCID, 2: all, 3: all including global)
;   RSI = pointer to 128-bit INVPCID descriptor
; Output: RAX = 1 on success, 0 on failure (INVPCID not supported)
; Clobbers: RAX, RBX, RCX, RDX
; -----------------------------------------------------------------------------
global tlb_invpcid
tlb_invpcid:
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, 1 << 10           ; Check INVPCID support (EBX bit 10)
    jz .no_invpcid
    
    invpcid rdi, [rsi]
    mov rax, 1
    ret
.no_invpcid:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; virt_mark_read_only_range — walks page tables and clears PAGE_WRITABLE (bit 1) on a range
; Input:
;   RDI = starting virtual address
;   RSI = range size in bytes
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global virt_mark_read_only_range
virt_mark_read_only_range:
    push rbx
    push r12
    push r13

    test rsi, rsi
    jz .ro_done

    ; Align start virtual address down to 4KB
    mov r12, rdi
    and r12, -4096                  ; R12 = current virtual address
    
    ; Calculate end address
    mov r13, rdi
    add r13, rsi                    ; R13 = end virtual address

.ro_loop:
    cmp r12, r13
    jae .ro_done

    ; Walk page table using current virtual address
    mov rdi, r12
    xor rsi, rsi                    ; use current CR3
    call virt_walk_table            ; RAX = PTE address, RDX = level
    test rax, rax
    jz .ro_not_mapped

    ; Clear the Writable bit (bit 1: PAGE_WRITABLE) in the entry
    and qword [rax], ~0x02

    ; Check resolved level to know how much to advance
    cmp rdx, 2                      ; 1GB super page
    je .ro_advance_1gb
    cmp rdx, 3                      ; 2MB huge page
    je .ro_advance_2mb

.ro_advance_4kb:
    add r12, 4096
    jmp .ro_loop

.ro_advance_2mb:
    mov rax, r12
    and rax, 0x1FFFFF               ; offset in 2MB page
    mov rcx, 0x200000
    sub rcx, rax                    ; remaining bytes in this 2MB page
    add r12, rcx
    jmp .ro_loop

.ro_advance_1gb:
    mov rax, r12
    and rax, 0x3FFFFFFF             ; offset in 1GB page
    mov rcx, 0x40000000
    sub rcx, rax                    ; remaining bytes in this 1GB page
    add r12, rcx
    jmp .ro_loop

.ro_not_mapped:
    ; Not mapped, just advance by 4KB to check next page
    add r12, 4096
    jmp .ro_loop

.ro_done:
    ; Flush the TLB to make the write protection active immediately
    call tlb_flush_all_global

    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_TLB_ASM
