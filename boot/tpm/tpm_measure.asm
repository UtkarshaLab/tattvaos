; =============================================================================
; Tattva OS — boot/tpm/tpm_measure.asm
; =============================================================================
; TPM measurement coordinator for x86_64 BIOS path.
;
; Author:  Utkarsha Labs
; Target:  x86-64 long mode
; =============================================================================

%ifndef TPM_MEASURE_ASM
%define TPM_MEASURE_ASM

[BITS 64]

%include "tpm/sha256.asm"
%include "tpm/tpm.asm"

; Buffer to hold calculated hash (32 bytes)
align 8
tpm_digest_buf:   times 32 db 0

msg_tpm_measuring: db "TPM: Measuring boot components...", 13, 10, 0
msg_tpm_measured:  db "TPM: Measurement complete.", 13, 10, 0

; =============================================================================
; tpm_measure_all — Measure boot components and extend PCRs
; Input:  none
; Output: none
; =============================================================================
tpm_measure_all:
    push rsi
    push rdi
    push rcx
    push rax

    ; 1. Initialize TPM
    call tpm_init
    test rax, rax
    jz .done                         ; if TPM is not present, skip measurements

    mov rsi, msg_tpm_measuring
    call uart_println_64

    ; 2. Measure Stage 2 (PCR 4)
    ; Stage 2 resides in memory at STAGE2_LOAD (0x8000), size is STAGE2_SECTORS * 512
    mov rsi, STAGE2_LOAD             ; Stage2 Load address
    mov rcx, STAGE2_SECTORS * 512    ; Use config constant
    lea rdi, [rel tpm_digest_buf]
    call sha256_hash

    ; Extend PCR 4
    mov ecx, 4                       ; PCR 4
    lea rsi, [rel tpm_digest_buf]
    call tpm_extend_pcr

    ; 3. Measure Kernel (PCR 4)
    ; Kernel resides in memory at KERNEL_LOAD (0x100000), size is KERNEL_SECTORS * 512
    mov rsi, KERNEL_LOAD             ; Kernel Load address
    mov rcx, KERNEL_SECTORS * 512    ; Use config constant
    lea rdi, [rel tpm_digest_buf]
    call sha256_hash

    ; Extend PCR 4
    mov ecx, 4                       ; PCR 4
    lea rsi, [rel tpm_digest_buf]
    call tpm_extend_pcr

    mov rsi, msg_tpm_measured
    call uart_println_64

.done:
    pop rax
    pop rcx
    pop rdi
    pop rsi
    ret

; Helper to print null-terminated string to COM1 in 64-bit mode
uart_println_64:
    push rsi
    push rbx
    push rdx
.print_loop:
    lodsb
    test al, al
    jz .print_done
    mov bl, al                       ; save character in BL
    ; Wait for TX buffer empty
    mov dx, 0x3F8 + 5               ; Line Status Register
.wait_tx:
    in al, dx
    test al, 0x20                    ; TX holding register empty?
    jz .wait_tx
    ; Send character
    mov dx, 0x3F8                    ; Data register
    mov al, bl                       ; restore character
    out dx, al
    jmp .print_loop
.print_done:
    pop rdx
    pop rbx
    pop rsi
    ret

%endif ; TPM_MEASURE_ASM
