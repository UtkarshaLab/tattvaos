; =============================================================================
; Tattva OS — boot/stage2/idt/idt.asm
; =============================================================================
; Protected Mode Interrupt Descriptor Table (IDT) definition.
; Configures gates for the first 32 exceptions.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef IDT_ASM
%define IDT_ASM

%include "selectors.asm"

; -----------------------------------------------------------------------------
; IDT entry generation macro
; Format of 32-bit Interrupt Gate (8 bytes):
;   Bits 15:0  — Offset Low
;   Bits 31:16 — Segment Selector
;   Bits 39:32 — Reserved (0)
;   Bits 47:40 — Access / Type Attributes
;   Bits 63:48 — Offset High
; -----------------------------------------------------------------------------
%macro idt_entry 1
    dw (%1) & 0xFFFF                ; offset bits 15:0
    dw SEL_CODE32                   ; selector (0x20)
    db 0                            ; reserved (always 0)
    db 0x8E                         ; P=1, DPL=00, S=0, Type=1110 (32-bit interrupt gate)
    dw ((%1) >> 16) & 0xFFFF        ; offset bits 31:16
%endmacro

; =============================================================================
; IDT table layout — must be 8-byte aligned
; =============================================================================
align 8

idt_start:
    %assign i 0
    %rep 32
        idt_entry exc_handler_%[i]
        %assign i i+1
    %endrep
idt_end:

; =============================================================================
; IDT descriptor — loaded via lidt instruction
; =============================================================================
align 2
idt_descriptor:
    dw idt_end - idt_start - 1      ; limit
    dd idt_start                    ; base address (32-bit)

%endif ; IDT_ASM
