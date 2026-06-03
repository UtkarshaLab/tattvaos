; =============================================================================
; Tattva OS — boot/nvram.asm
; =============================================================================
; Persistent Early Console Logging to NVRAM via UEFI Runtime Services.
;
; Author:  Utkarsha Labs
; Target:  x86-64 UEFI PE32+
; =============================================================================

%ifndef NVRAM_ASM
%define NVRAM_ASM

[BITS 64]

; EFI Global Variable Vendor GUID: 8be4df61-93ca-11d2-aa0d-00e098032b8c
align 8
efi_global_var_guid:
    dd 0x8BE4DF61
    dw 0x93CA, 0x11D2
    db 0xAA, 0x0D, 0x00, 0xE0, 0x98, 0x03, 0x2B, 0x8C

align 8
log_var_name:
    dw 'T', 'a', 't', 't', 'v', 'a', 'B', 'o', 'o', 't', 'L', 'o', 'g', 0

; UEFI SetVariable function offset in RuntimeServices is 80
; RuntimeServices table offset in SystemTable is 120

; =============================================================================
; uefi_write_boot_log — Write early boot diagnostic log to UEFI NVRAM
; Input:  RCX = pointer to System Table
;         RDX = pointer to Log Data (ASCII/Unicode buffer)
;         R8  = size of Log Data in bytes
; Output: RAX = EFI_STATUS (0 = success)
; =============================================================================
uefi_write_boot_log:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; Save inputs before they are clobbered
    ; RCX = System Table, RDX = Log Data, R8 = Log Size
    mov r12, rdx                     ; R12 = LogData pointer
    mov r13, r8                      ; R13 = LogSize

    ; Get RuntimeServices table pointer
    mov rbx, [rcx + 120]             ; RBX = RuntimeServices table pointer
    test rbx, rbx
    jz .err_exit

    ; Allocate shadow space (32 bytes) + 5th parameter (8 bytes) = 40 bytes
    ; Align to 16 bytes: 48 bytes
    sub rsp, 48

    ; SetVariable(VariableName, VendorGuid, Attributes, DataSize, Data)
    lea rcx, [rel log_var_name]      ; RCX = VariableName
    lea rdx, [rel efi_global_var_guid] ; RDX = VendorGuid
    mov r8d, 0x07                    ; R8 = Attributes (NV | BS | RT)
    mov r9, r13                      ; R9 = DataSize
    mov [rsp + 32], r12              ; 5th param on stack = Data pointer

    mov rax, [rbx + 80]              ; SetVariable is offset 80 in RuntimeServices
    call rax

    add rsp, 48                      ; clean up shadow space
    jmp .exit

.err_exit:
    mov rax, 0x8000000000000003      ; EFI_UNSUPPORTED

.exit:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

%endif ; NVRAM_ASM
