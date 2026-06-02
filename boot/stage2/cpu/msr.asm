; =============================================================================
; Tattva OS — boot/stage2/cpu/msr.asm
; =============================================================================
; Read and write Model Specific Registers (MSRs).
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit) / long mode (64-bit)
; =============================================================================

%ifndef MSR_ASM
%define MSR_ASM

; =============================================================================
; msr_read — read a 64-bit MSR value
; Input:  ECX = MSR address
; Output: EDX:EAX = MSR value (EDX = high dword, EAX = low dword)
; Clobbers: EAX, EDX
; =============================================================================
msr_read:
    rdmsr
    ret

; =============================================================================
; msr_write — write a 64-bit MSR value
; Input:  ECX = MSR address
;         EDX:EAX = MSR value to write
; Clobbers: none
; =============================================================================
msr_write:
    wrmsr
    ret

%endif ; MSR_ASM
