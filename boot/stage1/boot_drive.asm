; =============================================================================
; Tattva OS — boot/stage1/boot_drive.asm
; =============================================================================
; Storage for the boot drive number (DL register from BIOS).
;
; The BIOS puts the boot drive number in DL at entry.
; ANY INT call can silently overwrite DL.
; We save it to memory immediately in entry.asm.
; Every disk operation reads from [boot_drive] not DL.
;
; This is the #1 cause of bootloaders failing on real hardware
; while working perfectly in QEMU.
;
; Usage:
;   mov [boot_drive], dl    ; save (entry.asm, first thing)
;   mov dl, [boot_drive]    ; restore before any INT 13h call
;
; Author:  Utkarsha Labs
; =============================================================================

boot_drive:
    db 0                            ; boot drive number saved here
                                    ; 0x00 = floppy A
                                    ; 0x80 = first hard disk (most common)
                                    ; 0x81 = second hard disk
                                    ; 0xE0 = first SATA/SCSI device