; =============================================================================
; Tattva OS — boot/stage2/hw/disk_errors.asm
; =============================================================================
; BIOS Disk Error Codes description lookup table and strings.
; Used by stage2 disk error logging.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef HW_DISK_ERRORS_ASM
%define HW_DISK_ERRORS_ASM

[BITS 16]

; BIOS Disk Error Codes and descriptions
align 2
bios_error_table:
    db 0x01
    dw err_str_01
    db 0x02
    dw err_str_02
    db 0x03
    dw err_str_03
    db 0x04
    dw err_str_04
    db 0x05
    dw err_str_05
    db 0x06
    dw err_str_06
    db 0x08
    dw err_str_08
    db 0x09
    dw err_str_09
    db 0x0C
    dw err_str_0C
    db 0x10
    dw err_str_10
    db 0x20
    dw err_str_20
    db 0x40
    dw err_str_40
    db 0x80
    dw err_str_80
    db 0xAA
    dw err_str_AA
    db 0xCC
    dw err_str_CC
    db 0x00 ; table terminator

err_str_01: db "Invalid function/parameter", 0
err_str_02: db "Address mark not found", 0
err_str_03: db "Write protect error", 0
err_str_04: db "Sector not found", 0
err_str_05: db "Reset failed", 0
err_str_06: db "Disk changed", 0
err_str_08: db "DMA overrun", 0
err_str_09: db "DMA boundary error", 0
err_str_0C: db "Unsupported track/media type", 0
err_str_10: db "Bad CRC/ECC on read", 0
err_str_20: db "Controller failed", 0
err_str_40: db "Seek failed", 0
err_str_80: db "Timeout/Drive not ready", 0
err_str_AA: db "Drive not ready", 0
err_str_CC: db "Write fault", 0
err_str_unknown: db "Unknown error", 0

%endif ; HW_DISK_ERRORS_ASM
