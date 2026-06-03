; =============================================================================
; Tattva OS — boot/stage2/idt/idt.asm
; =============================================================================
; Protected Mode Interrupt Descriptor Table (IDT) definition.
; Configures gates for the first 32 exceptions.
;
; NOTE: NASM -f bin treats labels as non-scalar, so we cannot use
;       compile-time & and >> on them. Instead we reserve blank IDT
;       space and fill it at runtime via idt_build (CPU instructions
;       have no problem with address arithmetic).
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef IDT_ASM
%define IDT_ASM

%include "selectors.asm"

; =============================================================================
; Handler address table — plain dd, no bitwise ops needed
; =============================================================================
align 4
idt_handler_table:
    %assign i 0
    %rep 32
        dd exc_handler_%[i]
        %assign i i+1
    %endrep

; =============================================================================
; IDT table — 32 entries × 8 bytes = 256 bytes, filled at runtime
; =============================================================================
align 8
idt_start:
    times 32 * 8 db 0
idt_end:

; =============================================================================
; IDT descriptor — loaded via lidt instruction
; =============================================================================
align 2
idt_descriptor:
    dw idt_end - idt_start - 1      ; limit (256 - 1 = 255)
    dd idt_start                    ; base address (32-bit)

; =============================================================================
; idt_build — populate the IDT from the handler address table
; Must be called in 32-bit protected mode BEFORE lidt.
;
; Input:  nothing
; Output: IDT entries filled
; Clobbers: none (all regs saved)
; =============================================================================
[BITS 32]
idt_build:
    pushad
    cld                             ; Clear direction flag for lodsd
    mov edi, idt_start              ; destination: IDT
    mov esi, idt_handler_table      ; source: handler addresses
    mov ecx, 32                     ; 32 entries

.fill_entry:
    lodsd                           ; EAX = handler address from table

    ; Byte 0-1: offset bits 15:0
    mov edx, eax
    and edx, 0xFFFF
    mov [edi + 0], dx

    ; Byte 2-3: segment selector
    mov word [edi + 2], SEL_CODE32

    ; Byte 4: reserved
    mov byte [edi + 4], 0

    ; Byte 5: type/attributes (P=1, DPL=0, 32-bit interrupt gate)
    mov byte [edi + 5], 0x8E

    ; Byte 6-7: offset bits 31:16
    mov edx, eax
    shr edx, 16
    mov [edi + 6], dx

    add edi, 8                      ; advance to next IDT entry
    loop .fill_entry

    popad
    ret

[BITS 16]

%endif ; IDT_ASM
