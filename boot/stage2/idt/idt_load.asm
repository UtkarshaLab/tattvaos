; =============================================================================
; Tattva OS — boot/stage2/idt/idt_load.asm
; =============================================================================
; Stub IDT setup for Phase 1.
; Real IDT handlers and loading are implemented in Phase 2.
; =============================================================================

%ifndef IDT_LOAD_ASM
%define IDT_LOAD_ASM

%include "idt.asm"
%include "idt_handlers.asm"

[BITS 32]
; =============================================================================
; idt_setup — load the 32-bit Protected Mode IDT
; Input:  nothing
; Output: IDT loaded
; Clobbers: none
; =============================================================================
idt_setup:
    push eax

    lidt [idt_descriptor]

    pop eax
    ret
[BITS 16]

%endif ; IDT_LOAD_ASM
