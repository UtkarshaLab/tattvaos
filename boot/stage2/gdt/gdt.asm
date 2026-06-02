; =============================================================================
; Tattva OS — boot/stage2/gdt/gdt.asm
; =============================================================================
; Global Descriptor Table definition.
;
; CRITICAL: GDT must be 8-byte aligned.
;   Misalignment works in QEMU.
;   Causes subtle failures on real hardware.
;   The 'align 8' before gdt_start is non-negotiable.
;
; GDT layout:
;   [0x00] null descriptor          — required by CPU, always zero
;   [0x08] 64-bit code segment      — kernel code ring 0
;   [0x10] 64-bit data segment      — kernel data ring 0
;   [0x18] 16-bit code segment      — real mode transition
;   [0x20] 32-bit code segment      — protected mode transition
;   [0x28] 64-bit user code         — userspace ring 3 (future)
;   [0x30] 64-bit user data         — userspace ring 3 (future)
;
; Descriptor format (8 bytes):
;   Bits 15:0   limit low 16 bits
;   Bits 31:16  base low 16 bits
;   Bits 39:32  base mid 8 bits
;   Bits 43:40  type (code/data flags)
;   Bit  44     S: descriptor type (1=code/data, 0=system)
;   Bits 46:45  DPL: privilege level (0=kernel, 3=user)
;   Bit  47     P: present
;   Bits 51:48  limit high 4 bits
;   Bit  52     AVL: available for OS use
;   Bit  53     L: 64-bit code segment (1 for 64-bit, 0 for 32/16)
;   Bit  54     D/B: default op size (0 for 64-bit, 1 for 32-bit)
;   Bit  55     G: granularity (0=byte, 1=4KB)
;   Bits 63:56  base high 8 bits
;
; For flat 64-bit model: base=0, limit=0xFFFFF, G=1
; Effective limit = 0xFFFFF * 4KB = 4GB (ignored in 64-bit mode anyway)
;
; Author:  Utkarsha Labs
; =============================================================================

%ifndef GDT_ASM
%define GDT_ASM

%include "selectors.asm"

; =============================================================================
; GDT data — MUST be 8-byte aligned
; =============================================================================
align 8                             ; CRITICAL — do not remove

gdt_start:

; -----------------------------------------------------------------------------
; [0x00] Null descriptor — always required, always zero
; CPU requires index 0 to be null. Loading any null selector = GP fault.
; -----------------------------------------------------------------------------
gdt_null:
    dq 0x0000000000000000

; -----------------------------------------------------------------------------
; [0x08] 64-bit code segment — kernel ring 0
; L=1 (64-bit), D=0, G=1, P=1, DPL=0, S=1, Type=1010 (execute/read)
; Base=0, Limit=0xFFFFF
; -----------------------------------------------------------------------------
gdt_code64:
    dw 0xFFFF                       ; limit low
    dw 0x0000                       ; base low
    db 0x00                         ; base mid
    db 10011010b                    ; P=1 DPL=00 S=1 Type=1010
    ;  P DPL  S  E  DC  R  A
    ;  1  00  1  1   0  1  0  = execute/read, non-conforming
    db 10101111b                    ; G=1 D=0 L=1 AVL=0 limit_high=1111
    ;  G  D  L  AVL  limit[19:16]
    ;  1  0  1   0    1111
    db 0x00                         ; base high

; -----------------------------------------------------------------------------
; [0x10] 64-bit data segment — kernel ring 0
; L=0, D=1, G=1, P=1, DPL=0, S=1, Type=0010 (read/write)
; Base=0, Limit=0xFFFFF
; In 64-bit mode most data segment fields are ignored
; but segment must be present and writable
; -----------------------------------------------------------------------------
gdt_data64:
    dw 0xFFFF                       ; limit low
    dw 0x0000                       ; base low
    db 0x00                         ; base mid
    db 10010010b                    ; P=1 DPL=00 S=1 Type=0010
    ;  P DPL  S  E  EC  W  A
    ;  1  00  1  0   0  1  0  = read/write, expand-up
    db 11001111b                    ; G=1 D=1 L=0 AVL=0 limit_high=1111
    db 0x00                         ; base high

; -----------------------------------------------------------------------------
; [0x18] 16-bit code segment — for real mode transition if needed
; P=1, DPL=0, S=1, Type=1010, G=0 (byte granularity), D=0 (16-bit)
; Limit=0xFFFF (64KB)
; -----------------------------------------------------------------------------
gdt_code16:
    dw 0xFFFF                       ; limit low (64KB)
    dw 0x0000                       ; base low
    db 0x00                         ; base mid
    db 10011010b                    ; P=1 DPL=00 S=1 Type=1010
    db 00000000b                    ; G=0 D=0 L=0 AVL=0 limit_high=0000
    db 0x00                         ; base high

; -----------------------------------------------------------------------------
; [0x20] 32-bit code segment — protected mode transition
; P=1, DPL=0, S=1, Type=1010, G=1, D=1 (32-bit default op size)
; Base=0, Limit=0xFFFFF (4GB with G=1)
; -----------------------------------------------------------------------------
gdt_code32:
    dw 0xFFFF                       ; limit low
    dw 0x0000                       ; base low
    db 0x00                         ; base mid
    db 10011010b                    ; P=1 DPL=00 S=1 Type=1010
    db 11001111b                    ; G=1 D=1 L=0 AVL=0 limit_high=1111
    db 0x00                         ; base high

; -----------------------------------------------------------------------------
; [0x28] 64-bit user code segment — ring 3 (future userspace)
; DPL=3, rest same as kernel code
; -----------------------------------------------------------------------------
gdt_user_code64:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 11111010b                    ; P=1 DPL=11 S=1 Type=1010
    db 10101111b                    ; G=1 D=0 L=1 AVL=0 limit=1111
    db 0x00

; -----------------------------------------------------------------------------
; [0x30] 64-bit user data segment — ring 3 (future userspace)
; DPL=3, rest same as kernel data
; -----------------------------------------------------------------------------
gdt_user_data64:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 11110010b                    ; P=1 DPL=11 S=1 Type=0010
    db 11001111b                    ; G=1 D=1 L=0 AVL=0 limit=1111
    db 0x00

gdt_end:

; =============================================================================
; GDT descriptor — passed to lgdt instruction
; =============================================================================
align 2                             ; word-aligned for lgdt
gdt_descriptor:
    dw gdt_end - gdt_start - 1     ; limit = size - 1
    dd gdt_start                   ; base address (32-bit in PM, 64-bit in LM)

; GDT size in bytes (for verification)
GDT_SIZE equ (gdt_end - gdt_start)

%endif ; GDT_ASM