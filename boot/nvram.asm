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
    sub rsp, 48                      ; shadow space + parameters

    mov rsi, [rcx + 120]             ; RSI = RuntimeServices table pointer
    test rsi, rsi
    jz .failed

    ; SetVariable(VariableName, VendorGuid, Attributes, DataSize, Data)
    lea rcx, [rel log_var_name]      ; RCX = VariableName
    lea rdx, [rel efi_global_var_guid] ; RDX = VendorGuid
    mov r9d, 0x07                    ; R9 = Attributes (NV | BS | RT)
    mov [rsp + 32], r8               ; fifth parameter: DataSize (on stack)
    ; Wait, SetVariable takes 5 parameters:
    ; 1. VariableName (RCX)
    ; 2. VendorGuid (RDX)
    ; 3. Attributes (R8)
    ; 4. DataSize (R9)
    ; 5. Data (on stack at offset 32)
    ; Let's fix register mapping:
    ; RCX = VariableName
    ; RDX = VendorGuid
    ; R8  = Attributes (0x07)
    ; R9  = DataSize
    ; [rsp + 32] = Data (pointer to Log Data)
    
    mov r8d, 0x07                    ; Attributes
    mov r9, [rbp - 16]               ; DataSize (wait, R8 in input was DataSize. Let's move R8 to R9!)
    ; Input parameters were:
    ; RCX = System Table
    ; RDX = Log Data
    ; R8  = Log Size
    ; Let's write them cleanly:
    
    mov rsi, [rcx + 120]             ; RSI = RuntimeServices
    lea rcx, [rel log_var_name]      ; 1st parameter: VariableName
    lea rdx, [rel efi_global_var_guid] ; 2nd parameter: VendorGuid
    
    ; Save Log Data pointer and Log Size from inputs
    ; R8  = Log Size
    ; RDX = Log Data (Wait! RDX input is overwritten by GUID. Let's retrieve from caller stack or save before!)
    ; Let's save inputs:
    ; RAX = SystemTable (in RCX)
    ; RBX = Log Data (in RDX)
    ; R10 = Log Size (in R8)
    
    ; Let's use simple registers
    mov r10, [rbp + 16]              ; Wait, let's just do it directly with register preservation
    
    ; Let's write a standard clean call:
    ; push rbx
    ; push rbp...
    
    ; Let's do it using:
    ; RCX was SystemTable, RDX was LogData, R8 was LogSize.
    ; Let's save them first:
    ; mov r11, rcx
    ; mov r12, rdx
    ; mov r13, r8
    ; Then:
    ; mov rsi, [r11 + 120] (RuntimeServices)
    ; lea rcx, [rel log_var_name]
    ; lea rdx, [rel efi_global_var_guid]
    ; mov r8d, 0x07 (Attributes)
    ; mov r9, r13 (DataSize)
    ; mov [rsp + 32], r12 (Data pointer)
    ; call [rsi + 80] (SetVariable)
    
    ; Yes, this is completely correct!
    ; Let's rewrite it cleanly:

    jmp .start

.start:
    push rbx
    push rdi
    push rsi
    push r12
    push r13

    mov r12, rdx                     ; r12 = LogData pointer
    mov r13, r8                      ; r13 = LogSize

    mov rsi, [rcx + 120]             ; rsi = RuntimeServices table pointer
    test rsi, rsi
    jz .err_exit

    lea rcx, [rel log_var_name]      ; RCX = VariableName
    lea rdx, [rel efi_global_var_guid] ; RDX = VendorGuid
    mov r8d, 0x07                    ; R8 = Attributes (NV | BS | RT)
    mov r9, r13                      ; R9 = DataSize
    mov [rsp + 32], r12              ; [rsp + 32] = Data pointer

    mov rax, [rsi + 80]              ; SetVariable is offset 80 in RuntimeServices
    call rax
    jmp .exit

.err_exit:
    mov rax, 0x8000000000000003      ; EFI_UNSUPPORTED

.exit:
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

%endif ; NVRAM_ASM
