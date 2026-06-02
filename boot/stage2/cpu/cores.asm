; =============================================================================
; Tattva OS — boot/stage2/cpu/cores.asm
; =============================================================================
; Detect total logical core count of the CPU package.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit) / protected mode (32-bit)
; =============================================================================

%ifndef CORES_ASM
%define CORES_ASM

[BITS 16]

; =============================================================================
; cpu_get_cores — detect logical core count
; Input:  none
; Output: EAX = logical processor count (defaults to 1 if unsupported)
; =============================================================================
cpu_get_cores:
    push ebx
    push ecx
    push edx

    ; Check if CPUID leaf 1 is supported (query leaf 0 first)
    xor eax, eax
    cpuid
    cmp eax, 1
    jb .default_one

    mov eax, 1
    cpuid
    ; EBX bits 23:16 = logical processor count
    shr ebx, 16
    and ebx, 0xFF
    jz .default_one                 ; if 0, default to 1
    mov eax, ebx
    jmp .done

.default_one:
    mov eax, 1

.done:
    pop edx
    pop ecx
    pop ebx
    ret

%endif ; CORES_ASM
