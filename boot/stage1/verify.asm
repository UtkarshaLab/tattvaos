; boot/stage1/verify.asm
; Stage1 sanity checks after loading stage2

; Verifies:
;   - magic number after stage2 load (TATTVA_MAGIC / STAGE2_MAGIC)
;   - stack not corrupted (sp == expected value)
;   - stage2 loaded at correct address (STAGE2_LOAD equ 0x8000)

verify_stage2_load:
    ; TODO: read magic at STAGE2_LOAD
    ; TODO: compare against STAGE2_MAGIC equ 0x32535442
    ; TODO: call error_handler if mismatch
    ret
