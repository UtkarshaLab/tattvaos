; =============================================================================
; Tattva OS — boot/stage2/a20/a20_bios.asm
; =============================================================================
; Enable A20 line using BIOS INT 15h, AX=2401.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef A20_BIOS_ASM
%define A20_BIOS_ASM

[BITS 16]

; =============================================================================
; a20_bios — enable A20 using BIOS AX=2401
; Input:  none
; Output: CF=0 success, CF=1 failure
; Clobbers: AX
; =============================================================================
a20_bios:
    mov ax, 0x2401                  ; bios function: enable A20 gate
    int 0x15
    ret

%endif ; A20_BIOS_ASM
