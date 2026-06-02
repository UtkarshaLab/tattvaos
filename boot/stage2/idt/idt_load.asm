; =============================================================================
; Tattva OS — boot/stage2/idt/idt_load.asm
; =============================================================================
; Stub IDT setup for Phase 1.
; Real IDT handlers and loading are implemented in Phase 2.
; =============================================================================

%ifndef IDT_LOAD_ASM
%define IDT_LOAD_ASM

; =============================================================================
; idt_setup — stub to satisfy main.asm compilation in Phase 1
; =============================================================================
idt_setup:
    ; IDT not loaded in real mode / early protected mode during Phase 1
    ret

%endif ; IDT_LOAD_ASM
