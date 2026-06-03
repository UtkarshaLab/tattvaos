; =============================================================================
; Tattva OS — boot/survive/checksum.asm
; =============================================================================
; CRC32 checksum calculator and verifier for the hardware snapshot page.
; Standard IEEE 802.3 CRC32 implemented in software (tableless, compact).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode)
; =============================================================================

%ifndef SURVIVE_CHECKSUM_ASM
%define SURVIVE_CHECKSUM_ASM

[BITS 64]

global survive_checksum_save
global survive_checksum_verify

; =============================================================================
; survive_checksum_save — computes CRC32 of first 4092 bytes and saves at 0x9FFC
; Input:  none
; Clobbers: none
; =============================================================================
survive_checksum_save:
    push rsi
    push rcx
    push rbx
    push rdx
    push rax

    mov rsi, 0x9000                 ; SURVIVE_PAGE
    mov rcx, 4092                   ; compute over 4092 bytes
    call helper_crc32
    
    mov [0x9FFC], eax               ; store at the very end of the page

    pop rax
    pop rdx
    pop rbx
    pop rcx
    pop rsi
    ret

; =============================================================================
; survive_checksum_verify — recomputes CRC32 and compares to stored value
; Input:  none
; Output: RAX = 1 if matches, 0 if mismatch
; Clobbers: none (except RAX)
; =============================================================================
survive_checksum_verify:
    push rsi
    push rcx
    push rbx
    push rdx

    mov rsi, 0x9000                 ; SURVIVE_PAGE
    mov rcx, 4092                   ; compute over 4092 bytes
    call helper_crc32
    
    cmp eax, [0x9FFC]
    jne .mismatch
    
    mov rax, 1
    jmp .done
    
.mismatch:
    xor rax, rax

.done:
    pop rdx
    pop rbx
    pop rcx
    pop rsi
    ret

; =============================================================================
; helper_crc32 — bit-by-bit software CRC32
; Input:  RSI = buffer pointer
;         RCX = buffer length
; Output: EAX = 32-bit CRC32 checksum
; =============================================================================
helper_crc32:
    mov eax, 0xFFFFFFFF             ; initial CRC
.loop_bytes:
    test rcx, rcx
    jz .done
    movzx r10d, byte [rsi]
    xor al, r10b
    mov edx, 8
.loop_bits:
    shr eax, 1
    jnc .no_carry
    xor eax, 0xEDB88320             ; standard CRC32-IEEE polynomial
.no_carry:
    dec edx
    jnz .loop_bits
    inc rsi
    dec rcx
    jmp .loop_bytes
.done:
    not eax
    ret

%endif ; SURVIVE_CHECKSUM_ASM
