; =============================================================================
; Tattva OS — boot/survive/snapshot.asm
; =============================================================================
; Captures the hardware state and stack to SURVIVE_PAGE (0x9000) for recovery.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode)
; =============================================================================

%ifndef SURVIVE_SNAPSHOT_ASM
%define SURVIVE_SNAPSHOT_ASM

%include "config.asm"

[BITS 64]

; =============================================================================
; survive_snapshot_save — saves hardware state to SURVIVE_PAGE (0x9000)
; Input:  none
; Clobbers: none (preserves all registers)
; =============================================================================
survive_snapshot_save:
    ; Temporarily save RAX to the target slot in SURVIVE_PAGE so we can use RAX
    mov [SURVIVE_PAGE], rax
    
    ; Save general purpose registers
    mov [SURVIVE_PAGE + 0x08], rbx
    mov [SURVIVE_PAGE + 0x10], rcx
    mov [SURVIVE_PAGE + 0x18], rdx
    mov [SURVIVE_PAGE + 0x20], rsi
    mov [SURVIVE_PAGE + 0x28], rdi
    mov [SURVIVE_PAGE + 0x30], rbp
    
    ; RSP before the call (which is RSP + 8)
    lea rax, [rsp + 8]
    mov [SURVIVE_PAGE + 0x38], rax
    
    mov [SURVIVE_PAGE + 0x40], r8
    mov [SURVIVE_PAGE + 0x48], r9
    mov [SURVIVE_PAGE + 0x50], r10
    mov [SURVIVE_PAGE + 0x58], r11
    mov [SURVIVE_PAGE + 0x60], r12
    mov [SURVIVE_PAGE + 0x68], r13
    mov [SURVIVE_PAGE + 0x70], r14
    mov [SURVIVE_PAGE + 0x78], r15

    ; Save Control Registers
    mov rax, cr0
    mov [SURVIVE_PAGE + 0x80], rax
    mov rax, cr2
    mov [SURVIVE_PAGE + 0x88], rax
    mov rax, cr3
    mov [SURVIVE_PAGE + 0x90], rax
    mov rax, cr4
    mov [SURVIVE_PAGE + 0x98], rax

    ; Save Segment Selectors (zero-extended to 64-bit for alignment)
    xor rax, rax
    mov ax, cs
    mov [SURVIVE_PAGE + 0xA0], rax
    mov ax, ds
    mov [SURVIVE_PAGE + 0xA8], rax
    mov ax, es
    mov [SURVIVE_PAGE + 0xB0], rax
    mov ax, fs
    mov [SURVIVE_PAGE + 0xB8], rax
    mov ax, gs
    mov [SURVIVE_PAGE + 0xC0], rax
    mov ax, ss
    mov [SURVIVE_PAGE + 0xC8], rax

    ; Save RFLAGS
    pushfq
    pop rax
    mov [SURVIVE_PAGE + 0xD0], rax

    ; Save RIP (the return address of this call)
    mov rax, [rsp]
    mov [SURVIVE_PAGE + 0xD8], rax

    ; Save GDTR and IDTR (16 bytes space each, limit + base)
    sgdt [SURVIVE_PAGE + 0xE0]
    sidt [SURVIVE_PAGE + 0xF0]

    ; Copy stack contents:
    ; Source is original RSP (rsp + 32 inside this stack frame after pushes)
    ; Destination is SURVIVE_PAGE + 256 = SURVIVE_PAGE + 0x100
    ; Size is 1536 bytes (192 quadwords)
    push rsi
    push rdi
    push rcx
    
    cld                             ; Clear direction flag for forward copy
    lea rsi, [rsp + 32]             ; original stack pointer
    mov rdi, SURVIVE_PAGE + 0x100
    mov rcx, 192                    ; 192 * 8 = 1536 bytes
    rep movsq
    
    pop rcx
    pop rdi
    pop rsi

    ; Write magic signature 'TATTVSNP' (8 bytes) at SURVIVE_PAGE + 0xFF0
    mov rax, 0x504E535654544154     ; "TATTVSNP" in little-endian ASCII
    mov [SURVIVE_PAGE + 0xFF0], rax

    ; Calculate and save CRC32 checksum
    push rax
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    
    call survive_checksum_save
    
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rax

    ret

%endif ; SURVIVE_SNAPSHOT_ASM
