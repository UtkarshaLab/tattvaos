; boot/stage2/stage2_entry_check.asm
; Verify stage2 loaded correctly before doing anything else

; Checks:
;   - magic number at start of stage2 binary
;   - load address is 0x8000
;   - halts with error code if wrong

stage2_entry_check:
    ; TODO: read dword at own start
    ; TODO: compare to STAGE2_MAGIC equ 0x32535442
    ; TODO: halt with UART error if mismatch
    ret
