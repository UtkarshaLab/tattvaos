; =============================================================================
; Tattva OS — lib/mem/virt/pgtable_walk.asm
; =============================================================================
; Virtual to physical address translation engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_WALK_ASM
%define LIB_MEM_VIRT_PGTABLE_WALK_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; virt_translate — translates a virtual address to its mapped physical address
; Input:
;   RDI = virtual address to translate
; Output:
;   RAX = physical address mapped to RDI, or 0 if the page is not mapped
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global virt_translate
virt_translate:
    push rbx
    mov rbx, rdi                    ; RBX = original virtual address
    
    ; Walk page table hierarchy using current address space (RSI = 0)
    mov rsi, 0
    call virt_walk_table            ; RAX = physical address of page entry, RDX = level
    test rax, rax
    jz .not_mapped
    
    ; Load the page entry value
    mov rcx, [rax]
    
    ; Check the resolution level
    cmp rdx, 2
    je .super_page_1gb
    cmp rdx, 3
    je .huge_page_2mb
    
    ; Level 4 or 5 (4KB page)
    mov rax, rcx
    mov rsi, 0xFFFFFFFFFFFFF000
    and rax, rsi                    ; RAX = page base address
    mov rsi, 0xFFF
    and rbx, rsi                    ; RBX = page offset
    add rax, rbx                    ; RAX = translated physical address
    jmp .done

.huge_page_2mb:
    mov rax, rcx
    mov rsi, 0xFFFFFFFFFFE00000     ; 2MB page mask
    and rax, rsi                    ; RAX = huge page base address
    mov rsi, 0x1FFFFF
    and rbx, rsi                    ; RBX = huge page offset
    add rax, rbx                    ; RAX = translated physical address
    jmp .done

.super_page_1gb:
    mov rax, rcx
    mov rsi, 0xFFFFFFFFC0000000     ; 1GB page mask
    and rax, rsi                    ; RAX = super page base address
    mov rsi, 0x3FFFFFFF
    and rbx, rsi                    ; RBX = super page offset
    add rax, rbx                    ; RAX = translated physical address
    jmp .done

.not_mapped:
    xor rax, rax                    ; return 0

.done:
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_PGTABLE_WALK_ASM
