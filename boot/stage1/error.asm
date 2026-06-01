; boot/stage1/error.asm
; Centralized error handler for stage1
; Print error code via UART + VGA, retry or halt

; Usage: set AH = error code, call error_handler
; Error codes:
;   0x01 = disk read failed after 3 retries
;   0x02 = LBA not supported, CHS fallback failed
;   0x03 = stage2 magic mismatch
;   0xFF = unknown error

error_handler:
    ; TODO: print error code via print.asm (BIOS int 10h)
    ; TODO: retry logic for disk reads (DISK_RETRY equ 3)
    ; TODO: halt on unrecoverable error
    cli
    hlt
