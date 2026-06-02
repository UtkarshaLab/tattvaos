; =============================================================================
; Tattva OS — boot/stage2/gdt/selectors.asm
; =============================================================================
; GDT segment selector constants.
; Include this anywhere a selector value is needed.
; Must match the actual GDT layout in gdt.asm exactly.
;
; Selector format:
;   Bits 15:3  — index into GDT (entry number)
;   Bit  2     — TI: 0=GDT, 1=LDT
;   Bits 1:0   — RPL: requested privilege level (0=kernel, 3=user)
;
; GDT layout:
;   Index 0: null descriptor       (required, always first)
;   Index 1: 64-bit code segment   (kernel code, ring 0)
;   Index 2: 64-bit data segment   (kernel data, ring 0)
;   Index 3: 16-bit code segment   (real mode transition if needed)
;   Index 4: 32-bit code segment   (protected mode transition)
;
; Author:  Utkarsha Labs
; =============================================================================

%ifndef SELECTORS_ASM
%define SELECTORS_ASM

; -----------------------------------------------------------------------------
; Kernel selectors (RPL=0, TI=0)
; -----------------------------------------------------------------------------
SEL_NULL        equ 0x00            ; null descriptor (index 0)
SEL_CODE64      equ 0x08            ; 64-bit code   (index 1, RPL=0)
SEL_DATA64      equ 0x10            ; 64-bit data   (index 2, RPL=0)
SEL_CODE16      equ 0x18            ; 16-bit code   (index 3, RPL=0)
SEL_CODE32      equ 0x20            ; 32-bit code   (index 4, RPL=0)

; -----------------------------------------------------------------------------
; User selectors (RPL=3) — for later when userspace is added
; -----------------------------------------------------------------------------
SEL_USER_CODE64 equ 0x2B            ; 64-bit user code  (index 5, RPL=3)
SEL_USER_DATA64 equ 0x33            ; 64-bit user data  (index 6, RPL=3)

; -----------------------------------------------------------------------------
; GDT descriptor count
; -----------------------------------------------------------------------------
GDT_ENTRY_COUNT equ 7               ; total descriptors in GDT
GDT_ENTRY_SIZE  equ 8               ; bytes per descriptor

%endif ; SELECTORS_ASM