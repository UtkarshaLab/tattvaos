; =============================================================================
; Tattva OS — lib/mem/virt/hle.asm
; =============================================================================
; Hardware Lock Elision (HLE) Protection (Subfeature 25.4).
; Enforces Write-Back (WB) caching on speculatively accessed pages by clearing
; PWT and PCD flags in the page table entries, preventing TSX transactional
; aborts. Also provides cache line alignment verification to avoid false sharing.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HLE_ASM
%define LIB_MEM_VIRT_HLE_ASM

[BITS 64]

; Page Cache flags
PAGE_PWT        equ (1 << 3)        ; Write-through caching
PAGE_PCD        equ (1 << 4)        ; Page Cache Disable

section .text

; External symbol
extern virt_walk_table

; -----------------------------------------------------------------------------
; hle_protect_range — enforces Write-Back caching on a virtual address range
;                     by clearing PWT (bit 3) and PCD (bit 4) in leaf PTEs
;                     and flushing the TLB via invlpg.
; Input:
;   RDI = start virtual address (4KB aligned internally)
;   RSI = size in bytes (rounded up to 4KB boundary internally)
; Output: none
; Clobbers: RAX, RCX, RDX, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global hle_protect_range
hle_protect_range:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; If range size is 0, do nothing
    test rsi, rsi
    jz .done

    ; Align start address down to 4KB page boundary
    mov r12, rdi
    and r12, -4096                  ; R12 = aligned virtual start address

    ; Calculate end address: start + size
    mov r13, rdi
    add r13, rsi
    add r13, 4095
    and r13, -4096                  ; R13 = aligned virtual end address (exclusive)

.loop_pages:
    cmp r12, r13
    jae .done

    ; Walk page table to find leaf PTE for the virtual address in R12
    mov rdi, r12
    mov rsi, 0                      ; use current CR3
    call virt_walk_table            ; RAX = physical address of PTE, RDX = level
    test rax, rax
    jz .next_page                   ; page not mapped, skip

    ; Clear PCD and PWT bits to enforce Write-Back (WB) caching (bits 3 and 4)
    ; Clear mask: ~(PAGE_PWT | PAGE_PCD) = ~0x18
    and qword [rax], ~(PAGE_PWT | PAGE_PCD)

    ; Invalidate TLB entry for this virtual address
    invlpg [r12]

.next_page:
    add r12, 4096                   ; move to next page
    jmp .loop_pages

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hle_is_cache_aligned — checks if virtual address is aligned to 64-byte boundary
;                        to prevent speculative aborts due to false sharing.
; Input:
;   RDI = virtual address
; Output:
;   RAX = 1 if aligned, 0 if not
; Clobbers: none
; -----------------------------------------------------------------------------
global hle_is_cache_aligned
hle_is_cache_aligned:
    mov rax, rdi
    and rax, 0x3F                   ; check lowest 6 bits (64-byte alignment)
    test rax, rax
    jnz .not_aligned

    mov rax, 1                      ; aligned
    ret

.not_aligned:
    xor rax, rax                    ; not aligned
    ret

%endif ; LIB_MEM_VIRT_HLE_ASM
