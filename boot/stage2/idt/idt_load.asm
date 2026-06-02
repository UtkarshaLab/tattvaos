; =============================================================================
; Tattva OS — boot/stage2/idt/idt_load.asm
; =============================================================================
; Stub IDT setup for Phase 1.
; Real IDT handlers and loading are implemented in Phase 2.
; =============================================================================

%ifndef IDT_LOAD_ASM
%define IDT_LOAD_ASM

%include "idt_handlers.asm"

[BITS 32]
%include "idt.asm"
; =============================================================================
; idt_setup — build and load the 32-bit Protected Mode IDT
; Input:  nothing
; Output: IDT loaded
; Clobbers: none
; =============================================================================
idt_setup:
    push eax

    ; Print '1' at start of idt_setup
    mov dx, 0x3F8
    mov al, '1'
    out dx, al

    call idt_build                  ; populate IDT entries at runtime

    ; Print '2' after idt_build
    mov dx, 0x3F8
    mov al, '2'
    out dx, al

    lidt [idt_descriptor]

    ; Print '3' after lidt
    mov dx, 0x3F8
    mov al, '3'
    out dx, al

    pop eax
    ret
[BITS 16]

%endif ; IDT_LOAD_ASM
