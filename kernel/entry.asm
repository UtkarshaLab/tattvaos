; =============================================================================
; Tattva OS — kernel/entry.asm
; =============================================================================
; Top-level kernel entry file. Sets up the ULF (Unikernel Loader Format) header
; and includes modular files for startup, early initialization, and main loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef KERNEL_ENTRY_ASM
%define KERNEL_ENTRY_ASM

[BITS 64]
[ORG 0x100000]

; -----------------------------------------------------------------------------
; ULF Header (32 bytes)
; -----------------------------------------------------------------------------
ulf_header:
    dd 0x00464C55                   ; magic: "ULF\0"
    dd kernel_end - ulf_header      ; size of binary
    dq kernel_entry                 ; dynamic entry point
    dq 0x123456789ABCDEF0           ; checksum placeholder (patched by Makefile)
    dq 0                            ; reserved

; -----------------------------------------------------------------------------
; Kernel Entry Point
; -----------------------------------------------------------------------------
kernel_entry:
    section .text
    global kernel_text_start
kernel_text_start:
    %include "entry/start.asm"
    %include "entry/init.asm"
    %include "entry/main.asm"

; -----------------------------------------------------------------------------
; Include Drivers & Libraries (for early boot)
; -----------------------------------------------------------------------------
%include "drivers/serial/uart.asm"
%include "arch/x86_64/cpu.asm"
%include "arch/x86_64/gdt.asm"
%include "arch/x86_64/interrupts.asm"
%include "lib/mem/mem.asm"
%include "lib/hw/ucpu/mtrr.asm"
%include "lib/hw/ucpu/pat.asm"
%include "drivers/gpu/fb.asm"

    section .text
    global kernel_text_end
kernel_text_end:

align 8
kernel_end:

%endif ; KERNEL_ENTRY_ASM
