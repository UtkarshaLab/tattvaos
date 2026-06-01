; =============================================================================
; Tattva OS — boot/magic.asm
; =============================================================================
; Magic numbers placed at the start of each stage binary.
; Verified before jumping to next stage.
; Catches corrupt or wrongly-loaded stage binaries.
;
; Usage in stage2/entry.asm (first thing):
;   mov eax, [STAGE2_LOAD]
;   cmp eax, STAGE2_MAGIC
;   jne .bad_load
;
; Author:  Utkarsha Labs
; =============================================================================

; stage2 places this at its very first 4 bytes
; entry.asm verifies this after loading stage2
stage2_magic_value:
    dd STAGE2_MAGIC                 ; 0x32535442 = "BTS2"