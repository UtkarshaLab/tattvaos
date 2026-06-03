; =============================================================================
; Tattva OS — boot/tpm/tpm.asm
; =============================================================================
; TPM 2.0 TIS (TPM Interface Specification) FIFO driver.
; Interfaces with the TPM 2.0 chip via MMIO (0xFED40000) in x86-64 long mode.
;
; Author:  Utkarsha Labs
; Target:  x86-64 long mode
; =============================================================================

%ifndef TPM_ASM
%define TPM_ASM

[BITS 64]

; TPM TIS Registers (Locality 0)
TPM_ACCESS          equ 0xFED40000   ; Access register (R/W)
TPM_INT_ENABLE      equ 0xFED40008   ; Interrupt enable (R/W)
TPM_STS             equ 0xFED40018   ; Status register (R/W)
TPM_DATA_FIFO       equ 0xFED40024   ; Data FIFO register (R/W)
TPM_DID_VID         equ 0xFED40F00   ; Device ID / Vendor ID (RO)

; TPM Commands
TPM_CC_PCR_Extend   equ 0x00000182
TPM_ST_SESSIONS     equ 0x8002
TPM_RS_PW           equ 0x40000009   ; Password authorization session
TPM_ALG_SHA256      equ 0x000B

; =============================================================================
; tpm_init — Initialize the TPM 2.0 chip
; Output: RAX = 1 if initialized/present, 0 if not present/failed
; =============================================================================
tpm_init:
    push rbx
    push rcx
    push rdx

    ; 1. Read DID/VID to check if TPM exists
    mov rdx, TPM_DID_VID
    mov eax, [rdx]
    cmp eax, 0xFFFFFFFF
    je .no_tpm
    cmp eax, 0x00000000
    je .no_tpm

    ; 2. Request Locality 0 access
    mov rdx, TPM_ACCESS
    mov byte [rdx], 0x02             ; requestAccess (bit 1)

    ; Wait for activeLocality (bit 5) to become 1
    mov ecx, 10000                   ; timeout loop
.wait_locality:
    mov al, [rdx]
    test al, 0x20                    ; activeLocality?
    jnz .locality_active
    dec ecx
    jz .no_tpm
    jmp .wait_locality

.locality_active:
    ; 3. Reset command status
    mov rdx, TPM_STS
    mov dword [rdx], 0x40            ; commandReady (bit 6)

    mov rax, 1                       ; Success
    jmp .done

.no_tpm:
    xor rax, rax                     ; Failure

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; =============================================================================
; tpm_extend_pcr — Extend a hash into a PCR register
; Input:  ECX = PCR index (e.g. 4 for kernel, 5/8 for config)
;         RSI = pointer to 32-byte SHA-256 digest buffer
; Output: RAX = 1 if extended successfully, 0 if failed
; =============================================================================
tpm_extend_pcr:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12d, ecx                    ; R12D = PCR index
    mov r13, rsi                     ; R13 = digest pointer

    ; 1. Request Locality 0 active status
    mov rdx, TPM_ACCESS
    mov al, [rdx]
    test al, 0x20                    ; activeLocality?
    jz .failed

    ; 2. Ready status
    mov rdx, TPM_STS
    mov dword [rdx], 0x40            ; commandReady

    ; Prepare command packet on stack
    ; Total size of PCR Extend command packet is 65 bytes:
    ; tag(2) + size(4) + cc(4) + pcr(4) + auth_sz(4) + sess_h(4) + nonce_sz(2) + attrs(1) + hmac_sz(2) + dig_cnt(4) + alg(2) + digest(32)
    sub rsp, 80                      ; allocate stack buffer for command packet
    mov rdi, rsp                     ; RDI = command buffer

    ; Tag (0x8002) - Big Endian
    mov word [rdi], 0x0280           ; swap 0x8002
    ; Command size (65 bytes = 0x00000041) - Big Endian
    mov dword [rdi + 2], 0x41000000  ; swap 65
    ; Command Code (TPM_CC_PCR_Extend = 0x00000182) - Big Endian
    mov dword [rdi + 6], 0x82010000  ; swap 0x182
    ; PCR index (R12D) - Big Endian
    mov eax, r12d
    bswap eax
    mov [rdi + 10], eax
    
    ; Authorization session size (9 bytes) - Big Endian
    mov dword [rdi + 14], 0x09000000
    ; Session Handle (0x40000009) - Big Endian
    mov dword [rdi + 18], 0x09000040
    ; Nonce Size (0) - Big Endian
    mov word [rdi + 22], 0x0000
    ; Session Attributes (0)
    mov byte [rdi + 24], 0x00
    ; Authorization HMAC size (0) - Big Endian
    mov word [rdi + 25], 0x0000

    ; Digests count (1) - Big Endian
    mov dword [rdi + 27], 0x01000000
    ; Hash Algorithm ID (TPM_ALG_SHA256 = 0x000B) - Big Endian
    mov word [rdi + 31], 0x0B00

    ; Copy 32-byte digest
    mov rsi, r13
    lea rdi, [rsp + 33]
    mov ecx, 8                       ; 8 dwords = 32 bytes
    rep movsd

    ; 3. Write command packet to TPM FIFO
    mov rdx, TPM_STS
.wait_ready:
    mov eax, [rdx]
    test eax, 0x40                   ; commandReady?
    jz .wait_ready

    ; Write 65-byte command packet to FIFO

    lea rsi, [rsp]
    mov rcx, 65
    mov rdx, TPM_DATA_FIFO
.write_fifo:
    lodsb
    mov [rdx], al
    loop .write_fifo

    ; 4. Execute command
    mov rdx, TPM_STS
    mov dword [rdx], 0x20            ; tpmGo (bit 5) — trigger command execution

    ; Wait for execution (optionally wait for status response)
    mov ecx, 10000
.wait_done:
    mov eax, [rdx]
    test eax, 0x10                   ; dataAvailable?
    jnz .success
    dec ecx
    jz .failed
    jmp .wait_done

.success:
    mov rax, 1
    jmp .exit

.failed:
    xor rax, rax

.exit:
    add rsp, 80                      ; clean up stack
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

%endif ; TPM_ASM
