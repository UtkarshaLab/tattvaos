; =============================================================================
; Tattva OS — boot/tpm/uefi_tpm.asm
; =============================================================================
; UEFI TPM 2.0 Integration.
; Uses EFI_TCG2_PROTOCOL to measure and extend PCRs in UEFI long mode.
;
; Author:  Utkarsha Labs
; Target:  x86-64 UEFI PE32+
; =============================================================================

%ifndef UEFI_TPM_ASM
%define UEFI_TPM_ASM

[BITS 64]

; TCG2 Protocol GUID: 607f766c-7457-4214-a979-9951a704de84
align 8
efi_tcg2_protocol_guid:
    dd 0x607f766c
    dw 0x7457, 0x4214
    db 0xa9, 0x79, 0x99, 0x51, 0xa7, 0x04, 0xde, 0x84

; Local Storage
tcg2_protocol:      dq 0

; TCG2 Event Structure for Hashing
align 8
tcg2_event:
    dd 33                           ; Size (sizeof(EFI_TCG2_EVENT) without flexible array + 1 byte event = 4 + 16 + 1 = 21, let's allocate 33 bytes for safety)
    ; Header:
    dd 16                           ; HeaderSize = 16
    dw 1                            ; HeaderVersion = 1
    dd 4                            ; PCRIndex (default PCR 4)
    dd 0x0D                         ; EventType (EV_IPL = 0x0D, Bootloader/OS Loader)
    ; Event Payload:
    db 0                            ; Dummy event data (1 byte)

; =============================================================================
; uefi_tpm_init — Locate the EFI_TCG2_PROTOCOL interface
; Input:  RCX = pointer to System Table
; Output: RAX = EFI_STATUS (0 = success)
; =============================================================================
uefi_tpm_init:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    mov rax, [rcx + 96]              ; RAX = BootServices (offset 96 in System Table)
    
    ; LocateProtocol(GUID*, Registration*, Interface**)
    lea rcx, [rel efi_tcg2_protocol_guid] ; RCX = GUID*
    xor rdx, rdx                     ; RDX = Registration (NULL)
    lea r8, [rel tcg2_protocol]      ; R8 = Interface**
    
    mov rax, [rax + 320]             ; Offset 320 in BootServices is LocateProtocol
    call rax                         ; execute LocateProtocol
    
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; uefi_tpm_measure — Hash data and extend a PCR
; Input:  RCX = pointer to System Table
;         RDX = physical address of buffer to measure
;         R8  = length of buffer to measure (bytes)
;         R9D = PCR index to extend (e.g. 4 or 5)
; Output: RAX = EFI_STATUS (0 = success)
; =============================================================================
uefi_tpm_measure:
    push rbp
    mov rbp, rsp
    sub rsp, 48                      ; shadow space + local variables

    ; Check if TCG2 Protocol was successfully located
    mov rax, [rel tcg2_protocol]
    test rax, rax
    jz .no_protocol                  ; if protocol is NULL, fail

    ; Setup parameters for HashLogExtendEvent:
    ; Protocol function offset:
    ; 0: GetCapability
    ; 8: GetEventLog
    ; 16: HashLogExtendEvent
    
    ; Save inputs
    mov [rbp - 8], rdx               ; DataToHash
    mov [rbp - 16], r8               ; DataToHashLen

    ; Update event structure with PCR index
    mov [rel tcg2_event + 10], r9d   ; Header.PCRIndex

    ; HashLogExtendEvent(This, Flags, DataToHash, DataToHashLen, EfiTcgEvent)
    mov rcx, [rel tcg2_protocol]     ; RCX = This
    xor rdx, rdx                     ; RDX = Flags (0 = hash and log)
    mov r8, [rbp - 8]                ; R8 = DataToHash
    mov r9, [rbp - 16]               ; R9 = DataToHashLen
    
    lea rax, [rel tcg2_event]        ; RDI = EfiTcgEvent
    mov [rsp + 32], rax              ; fifth parameter on stack
    
    mov rax, [rcx + 16]              ; RAX = HashLogExtendEvent function pointer
    call rax                         ; execute HashLogExtendEvent
    jmp .done

.no_protocol:
    mov rax, 0x8000000000000003      ; EFI_UNSUPPORTED

.done:
    mov rsp, rbp
    pop rbp
    ret

%endif ; UEFI_TPM_ASM
