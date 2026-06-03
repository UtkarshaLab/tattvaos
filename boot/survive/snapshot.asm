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
    mov [0x9000], rax
    
    ; Save general purpose registers
    mov [0x9008], rbx
    mov [0x9010], rcx
    mov [0x9018], rdx
    mov [0x9020], rsi
    mov [0x9028], rdi
    mov [0x9030], rbp
    
    ; RSP before the call (which is RSP + 8)
    lea rax, [rsp + 8]
    mov [0x9038], rax
    
    mov [0x9040], r8
    mov [0x9048], r9
    mov [0x9050], r10
    mov [0x9058], r11
    mov [0x9060], r12
    mov [0x9068], r13
    mov [0x9070], r14
    mov [0x9078], r15

    ; Save Control Registers
    mov rax, cr0
    mov [0x9080], rax
    mov rax, cr2
    mov [0x9088], rax
    mov rax, cr3
    mov [0x9090], rax
    mov rax, cr4
    mov [0x9098], rax

    ; Save Segment Selectors (zero-extended to 64-bit for alignment)
    xor rax, rax
    mov ax, cs
    mov [0x90A0], rax
    mov ax, ds
    mov [0x90A8], rax
    mov ax, es
    mov [0x90B0], rax
    mov ax, fs
    mov [0x90B8], rax
    mov ax, gs
    mov [0x90C0], rax
    mov ax, ss
    mov [0x90C8], rax

    ; Save RFLAGS
    pushfq
    pop rax
    mov [0x90D0], rax

    ; Save RIP (the return address of this call)
    mov rax, [rsp]
    mov [0x90D8], rax

    ; Save GDTR and IDTR (16 bytes space each, limit + base)
    sgdt [0x90E0]
    sidt [0x90F0]

    ; Copy stack contents:
    ; Source is original RSP (rsp + 32 inside this stack frame after pushes)
    ; Destination is 0x9000 + 256 = 0x9100
    ; Size is 1536 bytes (192 quadwords)
    push rsi
    push rdi
    push rcx
    
    cld                             ; Clear direction flag for forward copy
    lea rsi, [rsp + 32]             ; original stack pointer
    mov rdi, 0x9100
    mov rcx, 192                    ; 192 * 8 = 1536 bytes
    rep movsq
    
    pop rcx
    pop rdi
    pop rsi

    ; Write magic signature 'TATTVSNP' (8 bytes) at SURVIVE_PAGE + 0xFF0 = 0x9FF0
    mov rax, 0x504E535654544154     ; "TATTVSNP" in little-endian ASCII
    mov [0x9FF0], rax

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
