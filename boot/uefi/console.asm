; =============================================================================
; Tattva OS — boot/uefi/console.asm
; =============================================================================
; Simple text output utilities for UEFI console (ConOut).
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_CONSOLE_ASM
%define UEFI_CONSOLE_ASM

%include "protocol.asm"

[BITS 64]

; =============================================================================
; uefi_print — print UTF-16LE string to console
; Input:  RCX = pointer to System Table
;         RDX = pointer to UTF-16LE null-terminated string
; Clobbers: RAX, RCX, RDX, R8, R9, R10, R11
; =============================================================================
uefi_print:
    push rbp
    mov rbp, rsp
    sub rsp, 40                     ; 32 bytes shadow space + 8 bytes alignment

    mov r8, rdx                     ; R8 = string pointer
    mov r9, rcx                     ; R9 = System Table pointer

    ; Get ConOut pointer: SystemTable->ConOut (offset 48)
    mov rdx, [r9 + SYS_TABLE_CON_OUT]

    ; Call OutputString: ConOut->OutputString(ConOut, String)
    ; Microsoft x64 Calling Convention:
    ;   RCX = ConOut interface pointer
    ;   RDX = String address
    mov rcx, rdx                    ; RCX = ConOut pointer
    mov rdx, r8                     ; RDX = String pointer
    
    mov rax, [rcx + CON_OUT_OUTPUT_STRING] ; OutputString pointer
    call rax                        ; invoke UEFI output

    mov rsp, rbp
    pop rbp
    ret

%endif ; UEFI_CONSOLE_ASM
