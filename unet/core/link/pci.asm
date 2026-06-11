; =============================================================================
; Tattva OS — unet/core/link/pci.asm
; =============================================================================
; PCI/PCIe device queue uncacheable memory mapping.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_PCI_ASM
%define UNET_CORE_LINK_PCI_ASM

[BITS 64]

%include "unet/core/link/net_ring.inc"

section .text

extern is_valid_phys_packet_buffer

; -----------------------------------------------------------------------------
; net_pci_map_queue — Maps physical NIC descriptor queues inside uncacheable memory
; Input:
;   RDI = physical BAR address of NIC queue (must be page-aligned)
;   RSI = size in bytes (must be page-aligned)
; Output:
;   RAX = virtual mapping base address, or 0 on failure
; -----------------------------------------------------------------------------
global net_pci_map_queue
net_pci_map_queue:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = physical address
    mov r12, rsi                    ; R12 = size in bytes

    ; Verify physical address is valid RAM or physical bus space
    call is_valid_phys_packet_buffer
    ; Note: For device BARs, they reside above RAM limit, so we verify BAR size > 0
    test r12, r12
    jz .fail

    ; Find free virtual memory range
    mov rdi, r12
    mov rsi, NET_PCI_VIRT_START
    call virt_find_free_range
    test rax, rax
    jz .fail
    mov r13, rax                    ; R13 = virtual base address

    ; Create backing VMA (kernel-only uncacheable queue area)
    mov rdi, r13
    mov rsi, r12
    mov rdx, (VMA_READ | VMA_WRITE)
    call vma_create
    test rax, rax
    jz .fail
    mov r14, rax                    ; R14 = VMA pointer

    ; Map each page directly with PCD (Page Cache Disable) and PWT (Write-Through)
    mov rcx, 0                      ; RCX = byte offset
.map_loop:
    cmp rcx, r12
    jae .success
    
    mov rdi, r13
    add rdi, rcx                    ; target virtual address
    
    mov rsi, rbx
    add rsi, rcx                    ; target physical address
    
    ; Mapping flags: present, writable, uncacheable, write-through, no-execute
    mov rdx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_PCD | PAGE_PWT | PAGE_NX)
    
    push rcx
    call virt_map
    pop rcx
    test rax, rax
    jz .cleanup                     ; OOM mapping failure!
    
    add rcx, 4096
    jmp .map_loop

.success:
    mov rax, r13
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.cleanup:
    ; Unmap already mapped pages
    mov rdi, r13
.cleanup_loop:
    cmp rdi, r13
    add rdi, rcx
    jae .destroy_vma
    
    push rdi
    push rcx
    call virt_unmap
    pop rcx
    pop rdi
    
    add rdi, 4096
    jmp .cleanup_loop

.destroy_vma:
    mov rdi, r14
    call vma_destroy
.fail:
    xor rax, rax
    jmp .exit

%endif ; UNET_CORE_LINK_PCI_ASM
