; =============================================================================
; Tattva OS — boot/survive/log/log.asm
; =============================================================================
; Saves the panic reason description string and crash location to the log area
; at SURVIVE_PAGE + 0x800 (0x9800) so it survives warm reboots.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode)
; =============================================================================

%ifndef SURVIVE_LOG_ASM
%define SURVIVE_LOG_ASM

%include "config.asm"

[BITS 64]

; =============================================================================
; survive_log_panic — copies crash location and panic description to 0x9800
; Input:  RCX = pointer to ASCII null-terminated panic message string
;         RDX = crash RIP
; Clobbers: RAX, RCX, RDX, RSI, RDI
; =============================================================================
survive_log_panic:
    cld                             ; Clear direction flag for forward copy
    ; 1. Store the crash RIP at SURVIVE_PAGE + 0x800
    mov [SURVIVE_PAGE + 0x800], rdx

    ; 2. Copy the ASCII string from RCX to SURVIVE_PAGE + 0x808 (limit to 256 bytes)
    test rcx, rcx
    jz .write_default
    
    mov rsi, rcx
    mov rdi, SURVIVE_PAGE + 0x808
    mov rcx, 255                    ; limit size (leaving 1 byte for null)

.copy_loop:
    test rcx, rcx
    jz .null_terminate
    lodsb                           ; AL = *RSI++
    stosb                           ; *RDI++ = AL
    test al, al
    jz .done
    dec rcx
    jmp .copy_loop

.null_terminate:
    xor al, al
    stosb                           ; null terminate

.done:
    ret

.write_default:
    ; If pointer is null, write a default message
    mov rdi, SURVIVE_PAGE + 0x808
    mov dword [rdi], 0x6B6E6E55     ; "Unkn"
    mov dword [rdi + 4], 0x206E6F77 ; "own "
    mov dword [rdi + 8], 0x696E6150 ; "Pani"
    mov word [rdi + 12], 0x0063     ; "c" + null
    ret

%endif ; SURVIVE_LOG_ASM
