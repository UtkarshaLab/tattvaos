; =============================================================================
; Tattva OS — boot/stage2/entry.asm
; =============================================================================
; Stage2 entry point. Loaded by stage1 to 0x8000.
; First 4 bytes MUST be STAGE2_MAGIC for verification.
;
; Responsibilities:
;   1. Place magic number at very start (stage1 verifies this)
;   2. Re-initialize segment registers (never trust stage1)
;   3. Set up stage2 stack
;   4. Re-save boot drive number from DL
;   5. Initialize UART immediately (first thing for debug output)
;   6. Print "Tattva Stage2 OK" via UART
;   7. Call main.asm to orchestrate rest of boot
;
; Memory at entry:
;   CS:IP = 0x0000:0x8000
;   DL    = boot drive (passed from stage1)
;   A20   = may or may not be enabled (stage1 tried fast method)
;   CPU   = still in real mode (16-bit)
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit) entry
; =============================================================================

[BITS 16]
[ORG 0x8000]

; =============================================================================
; MAGIC NUMBER — must be first 4 bytes of binary
; stage1/entry.asm reads [STAGE2_LOAD] and compares to STAGE2_MAGIC
; if mismatch, stage1 halts with error
; =============================================================================
stage2_magic:
    dd STAGE2_MAGIC                 ; 0x32535442 "BTS2"
                                    ; MUST be at offset 0x0000 of this file
                                    ; MUST be first thing assembled

; -----------------------------------------------------------------------------
; includes
; -----------------------------------------------------------------------------
%include "config.asm"

; =============================================================================
; stage2_entry — execution begins here after magic
; =============================================================================
stage2_entry:
    ; -------------------------------------------------------------------------
    ; STEP 1: Re-initialize segment registers
    ; Never trust what stage1 left in registers.
    ; Always re-initialize at the start of each stage.
    ; -------------------------------------------------------------------------
    cli                             ; disable interrupts during setup

    xor ax, ax
    mov ds, ax                      ; data segment = 0x0000
    mov es, ax                      ; extra segment = 0x0000
    mov ss, ax                      ; stack segment = 0x0000
    mov sp, 0x8000                  ; stage2 stack just below ourselves
                                    ; grows down from 0x8000
                                    ; safe: stage1 is at 0x0600, stack has room

    sti                             ; re-enable interrupts

    ; -------------------------------------------------------------------------
    ; STEP 2: Re-save boot drive number
    ; Stage1 passed DL = boot drive when jumping here.
    ; Save it immediately before any INT call.
    ; -------------------------------------------------------------------------
    mov [boot_drive], dl

    ; -------------------------------------------------------------------------
    ; STEP 3: Initialize UART — first thing, always
    ; After this we can print debug output for everything else.
    ; If something fails before this, we have no visibility.
    ; UART init is ~10 port writes, very unlikely to fail.
    ; -------------------------------------------------------------------------
    call uart_init

    ; -------------------------------------------------------------------------
    ; STEP 4: Print banner — confirms stage2 loaded and UART works
    ; -------------------------------------------------------------------------
    mov si, msg_banner
    call uart_println

    mov si, msg_stage2_ok
    call uart_println

    ; -------------------------------------------------------------------------
    ; STEP 5: Print boot drive number for debugging
    ; -------------------------------------------------------------------------
    mov si, msg_drive
    call uart_print
    mov al, [boot_drive]
    call uart_print_hex8
    mov al, 0x0D
    call uart_putc
    mov al, 0x0A
    call uart_putc

    ; -------------------------------------------------------------------------
    ; STEP 6: Hand off to main.asm
    ; main.asm orchestrates the rest of boot:
    ;   A20, CPU detection, memory map, GDT, IDT, paging, kernel load
    ; -------------------------------------------------------------------------
    call stage2_main

    ; -------------------------------------------------------------------------
    ; Should never reach here — stage2_main jumps to kernel
    ; If we get here something went wrong
    ; -------------------------------------------------------------------------
    mov si, msg_main_returned
    call uart_println
    jmp .halt

.halt:
    cli
    hlt
    jmp .halt

; =============================================================================
; includes — uart must come before any uart calls
; =============================================================================
%include "uart.asm"
%include "uart_print.asm"
%include "uart_hex.asm"
%include "main.asm"
%include "a20.asm"
%include "cpuid.asm"
%include "longmode.asm"
%include "msr.asm"
%include "vendor.asm"
%include "cores.asm"
%include "cache.asm"
%include "simd_enable.asm"
%include "fs.asm"
%include "fs16.asm"
%include "hw/acpi.asm"
%include "hw/disk.asm"
%include "hw/disk_errors.asm"
%include "hw/vbe.asm"
%include "e820.asm"
%include "gdt_load.asm"
%include "gdt_verify.asm"
%include "idt_load.asm"
%include "paging.asm"
%include "paging_map.asm"
%include "paging_verify.asm"
%include "tests/test_a20.asm"
%include "tests/test_paging.asm"
%include "tests/test_e820.asm"

; survive submodule
%include "survive/snapshot.asm"
%include "survive/checksum.asm"
%include "survive/hide.asm"
%include "survive/vector.asm"
%include "survive/wakeup.asm"
%include "survive/diff.asm"
%include "survive/recover.asm"
%include "survive/reset.asm"
%include "survive/log/log.asm"

%include "boot_drive.asm"



; =============================================================================
; Strings
; =============================================================================
msg_banner:
    db "================================", 0

msg_stage2_ok:
    db "  Tattva OS  |  Stage2 OK", 0

msg_drive:
    db "Boot drive: ", 0

msg_main_returned:
    db "ERROR: stage2_main returned unexpectedly", 0

; =============================================================================
; End of entry.asm
; =============================================================================