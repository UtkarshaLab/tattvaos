; =============================================================================
; Tattva OS — boot/uefi/handoff.asm
; =============================================================================
; UEFI handoff to kernel. Shuts down boot services and jumps to kernel entry.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_HANDOFF_ASM
%define UEFI_HANDOFF_ASM

%include "protocol.asm"

[BITS 64]

; =============================================================================
; uefi_handoff — ExitBootServices and jump to kernel
; Input:  RCX = pointer to System Table
;         RDX = ImageHandle
;         R8  = MapKey value from GetMemoryMap
;         R9  = kernel entry address (0x100000)
; Output: RAX = status code (only if ExitBootServices fails)
; =============================================================================
uefi_handoff:
    push rbp
    mov rbp, rsp
    sub rsp, 40                     ; shadow space

    mov r10, rcx                    ; R10 = System Table
    mov r11, rdx                    ; R11 = ImageHandle
    mov rsi, r8                     ; RSI = MapKey
    mov rdi, r9                     ; RDI = Kernel Entry

    ; Get BootServices: SystemTable->BootServices (offset 88)
    mov rbx, [r10 + SYS_TABLE_BOOT_SERVICES]

    ; Call ExitBootServices(ImageHandle, MapKey)
    ; Microsoft x64 Calling Convention:
    ;   RCX = ImageHandle (R11)
    ;   RDX = MapKey (RSI)
    mov rcx, r11
    mov rdx, rsi
    
    mov rax, [rbx + BS_EXIT_BOOT_SERVICES]
    call rax                        ; execute ExitBootServices
    test rax, rax
    jnz .failed                     ; failed to exit boot services

    ; Disable interrupts (critical before jumping to kernel)
    cli

    ; Jump directly to the kernel entry point (physical 0x100000)
    ; We are already in 64-bit long mode, flat memory model active.
    jmp rdi

.failed:
    ; Return failure status in RAX
    mov rsp, rbp
    pop rbp
    ret

%endif ; UEFI_HANDOFF_ASM
