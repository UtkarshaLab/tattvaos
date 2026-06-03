; =============================================================================
; Tattva OS — boot/survive/reset.asm
; =============================================================================
; Triggers a hardware reset/reboot.
; Method 1: PS/2 Keyboard Controller output port pulse (standard legacy reset)
; Method 2: CPU Triple Fault (fallback)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode)
; =============================================================================

%ifndef SURVIVE_RESET_ASM
%define SURVIVE_RESET_ASM

[BITS 64]

; =============================================================================
; survive_reset — hardware reboot
; Input:  none
; Output: none (should not return)
; Clobbers: RAX, RCX
; =============================================================================
survive_reset:
    cli                             ; disable interrupts

    ; 1. Try Keyboard Controller pulse method
    mov al, 0xFE
    out 0x64, al                    ; pulse reset line

    ; Wait up to 100ms (busy loop) for the pulse to trigger
    mov ecx, 0x100000
.delay:
    in al, 0x64                     ; delay
    dec ecx
    jnz .delay

    ; 2. Fallback: Trigger Triple Fault
    ; Create a zero-limit descriptor structure on stack
    sub rsp, 10
    mov word [rsp], 0               ; limit = 0
    mov qword [rsp + 2], 0          ; base = 0
    lidt [rsp]                      ; load invalid IDT
    add rsp, 10

    ; Execute invalid instruction to trigger undefined opcode exception
    ud2                             ; CPU tries to handle UD, double faults, then triple faults

.halt:
    hlt
    jmp .halt

%endif ; SURVIVE_RESET_ASM
