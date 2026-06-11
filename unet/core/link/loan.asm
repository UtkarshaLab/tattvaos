; =============================================================================
; Tattva OS — unet/core/link/loan.asm
; =============================================================================
; Dynamic page loaning and address space mapper swaps.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_LOAN_ASM
%define UNET_CORE_LINK_LOAN_ASM

[BITS 64]

%include "unet/core/link/net_ring.inc"

section .text

extern is_valid_phys_packet_buffer

; -----------------------------------------------------------------------------
; net_page_loan — Swaps page mapping between driver context and user process context
; Input:
;   RDI = source virtual address (must be page-aligned)
;   RSI = destination virtual address (must be page-aligned)
;   RDX = target user PML4 CR3 (if 0, map to active kernel directory)
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global net_page_loan
net_page_loan:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = source virtual address
    mov r12, rsi                    ; R12 = destination virtual address
    mov r13, rdx                    ; R13 = target PML4 CR3

    ; 1. Resolve source virtual address to physical frame address
    mov rdi, rbx
    call virt_translate
    test rax, rax
    jz .fail                        ; page not mapped!
    mov r14, rax                    ; R14 = physical frame

    ; Security verification: check if physical frame is outside reserved kernel region
    mov rdi, r14
    call is_valid_phys_packet_buffer
    test rax, rax
    jz .fail                        ; security exception: illegal physical mapping!

    ; 2. Unmap source virtual address
    mov rdi, rbx
    call virt_unmap

    ; 3. Map destination virtual address in the target page directory
    mov rdi, cr3                    ; preserve current CR3
    test r13, r13
    jz .map_dest
    mov cr3, r13                    ; swap page table context
.map_dest:
    mov rsi, r14                    ; physical frame
    mov rdx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER | PAGE_NX) ; user-accessible flags
    
    push rdi
    mov rdi, r12                    ; destination virtual address
    call virt_map
    pop rdi
    
    test r13, r13
    jz .mapped_done
    mov cr3, rdi                    ; restore page table context
.mapped_done:
    test rax, rax
    jz .fail                        ; mapping failed!

    mov rax, 1
.exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    xor rax, rax
    jmp .exit

%endif ; UNET_CORE_LINK_LOAN_ASM
