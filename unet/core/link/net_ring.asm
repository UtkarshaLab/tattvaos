; =============================================================================
; Tattva OS — unet/core/link/net_ring.asm
; =============================================================================
; Common utilities and physical address validations for zero-copy network frames.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_NET_RING_ASM
%define UNET_CORE_LINK_NET_RING_ASM

[BITS 64]

; Include structures and symbols
%include "unet/core/link/net_ring.inc"

section .text

; -----------------------------------------------------------------------------
; is_valid_phys_packet_buffer
; Input:
;   RDI = physical page address to check
; Output:
;   RAX = 1 if valid, 0 if invalid (reserved kernel address range)
; -----------------------------------------------------------------------------
global is_valid_phys_packet_buffer
is_valid_phys_packet_buffer:
    ; 1. Check page alignment (must be 4KB aligned)
    test rdi, 4095
    jnz .invalid
    
    ; 2. Check kernel memory boundaries (avoid hijacking/reading kernel text/data)
    ; Kernel code/data resides between 1MB (0x100000) and kernel_end
    cmp rdi, 0x100000
    jb .check_high
    
    mov rax, kernel_end
    ; Calculate physical kernel_end (since kernel maps 1:1 during boot)
    cmp rdi, rax
    jb .invalid                     ; overlaps with kernel physical space!
    
.check_high:
    ; 3. Check upper physical memory bounds
    extern phys_state
    struc phys_state_t
        .bitmap_addr    resq 1
        .bitmap_size    resq 1
        .total_pages    resq 1
        .free_pages     resq 1
        .max_phys_addr  resq 1
    endstruc
    
    mov rax, [phys_state + phys_state_t.max_phys_addr]
    cmp rdi, rax
    jae .invalid                    ; out of system RAM range!
    
    mov rax, 1
    ret
.invalid:
    xor rax, rax
    ret

section .data
msg_security_err: db "CRITICAL SECURITY BREACH: Illegal physical address in zero-copy descriptor!", 0

%endif ; UNET_CORE_LINK_NET_RING_ASM
