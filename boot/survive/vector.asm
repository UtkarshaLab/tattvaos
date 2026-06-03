; =============================================================================
; Tattva OS — boot/survive/vector.asm
; =============================================================================
; Registers the panic vector at PANIC_VECTOR (0x500) so the kernel can find it.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode)
; =============================================================================

%ifndef SURVIVE_VECTOR_ASM
%define SURVIVE_VECTOR_ASM

%include "config.asm"

[BITS 64]

; =============================================================================
; survive_vector_install — register panic entry point at 0x500
; Input:  none
; Output: none
; Clobbers: RAX
; =============================================================================
survive_vector_install:
    mov rax, survive_wakeup_entry
    mov [PANIC_VECTOR], rax
    ret

%endif ; SURVIVE_VECTOR_ASM
