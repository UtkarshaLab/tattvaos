; =============================================================================
; Tattva OS — lib/mem/virt/uaf.asm
; =============================================================================
; Use-After-Free (UAF) quarantine table and helpers.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_UAF_ASM
%define LIB_MEM_VIRT_UAF_ASM

[BITS 64]

UAF_MAX_ENTRIES equ 128

section .text

; -----------------------------------------------------------------------------
; uaf_init — resets the quarantine table
; Output: none
; -----------------------------------------------------------------------------
global uaf_init
uaf_init:
    push rdi
    push rcx
    push rax

    lea rdi, [uaf_quarantine_table]
    mov rcx, UAF_MAX_ENTRIES
    xor rax, rax
    cld
    rep stosq

    mov qword [uaf_index], 0

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; uaf_quarantine_add — adds a virtual address to the quarantine list
; Input:
;   RDI = virtual address
; Output: none
; -----------------------------------------------------------------------------
global uaf_quarantine_add
uaf_quarantine_add:
    push rbx
    push rcx

    mov rax, rdi
    and rax, -4096                  ; align virtual address to 4KB page

    ; Check if address is already in the table to avoid duplicates
    lea rbx, [uaf_quarantine_table]
    xor rcx, rcx
.dup_check:
    cmp rcx, UAF_MAX_ENTRIES
    jge .add_entry
    cmp [rbx + rcx * 8], rax
    je .exit                        ; already quarantined, ignore
    inc rcx
    jmp .dup_check

.add_entry:
    ; Add in a FIFO round-robin manner
    mov rcx, [uaf_index]
    mov [rbx + rcx * 8], rax

    ; Increment index and wrap around
    inc rcx
    cmp rcx, UAF_MAX_ENTRIES
    jl .save_index
    xor rcx, rcx
.save_index:
    mov [uaf_index], rcx

.exit:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uaf_quarantine_remove — removes a virtual address from the quarantine list
; Input:
;   RDI = virtual address
; Output: none
; -----------------------------------------------------------------------------
global uaf_quarantine_remove
uaf_quarantine_remove:
    push rbx
    push rcx

    mov rax, rdi
    and rax, -4096                  ; align virtual address to 4KB page

    lea rbx, [uaf_quarantine_table]
    xor rcx, rcx
.loop:
    cmp rcx, UAF_MAX_ENTRIES
    jge .exit
    cmp [rbx + rcx * 8], rax
    je .found
    inc rcx
    jmp .loop

.found:
    mov qword [rbx + rcx * 8], 0     ; clear quarantine slot to allow safe re-use

.exit:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uaf_quarantine_check — checks if a virtual address is in the quarantine list
; Input:
;   RDI = virtual address
; Output:
;   RAX = 1 if quarantined, 0 if not
; -----------------------------------------------------------------------------
global uaf_quarantine_check
uaf_quarantine_check:
    push rbx
    push rcx

    mov rax, rdi
    and rax, -4096                  ; align virtual address to 4KB page

    lea rbx, [uaf_quarantine_table]
    xor rcx, rcx
.loop:
    cmp rcx, UAF_MAX_ENTRIES
    jge .not_found
    cmp [rbx + rcx * 8], rax
    je .found
    inc rcx
    jmp .loop

.found:
    mov rax, 1
    jmp .exit

.not_found:
    xor rax, rax

.exit:
    pop rcx
    pop rbx
    ret

section .data

align 8
global uaf_index
uaf_index: dq 0

section .bss

align 8
global uaf_quarantine_table
uaf_quarantine_table: resq UAF_MAX_ENTRIES

%endif ; LIB_MEM_VIRT_UAF_ASM
