; =============================================================================
; Tattva OS — boot/stage1/signature.asm
; =============================================================================
; MBR boot signature and padding.
; MUST be the last include in entry.asm.
;
; MBR layout (512 bytes total):
;   0x000 - 0x1BD   bootstrap code + data (446 bytes max)
;   0x1BE - 0x1FD   partition table (4 x 16 byte entries)
;   0x1FE - 0x1FF   boot signature 0x55AA
;
; BIOS checks bytes 510-511 for 0x55 0xAA.
; If not present, BIOS will not boot from this device.
;
; Author:  Utkarsha Labs
; =============================================================================

; -----------------------------------------------------------------------------
; Partition table — 4 entries of 16 bytes each = 64 bytes
; All entries zeroed = no partitions defined
; We use GPT or BXP for partitioning, not MBR partitions
; But the space must exist at exactly offset 0x1BE
; -----------------------------------------------------------------------------
times (0x1BE - ($ - $$)) db 0      ; pad from current position to 0x1BE
                                    ; $ = current address
                                    ; $$ = start of section (0x7C00)
                                    ; if code + data > 446 bytes,
                                    ; NASM will error here (negative times)
                                    ; that means you exceeded the 446 byte limit

; Partition entry 1 (empty)
db 0x00                             ; status: not bootable
db 0x00, 0x00, 0x00                 ; CHS first sector
db 0x00                             ; partition type: empty
db 0x00, 0x00, 0x00                 ; CHS last sector
dd 0x00000000                       ; LBA first sector
dd 0x00000000                       ; number of sectors

; Partition entry 2 (empty)
db 0x00, 0x00, 0x00, 0x00
db 0x00, 0x00, 0x00, 0x00
dd 0x00000000
dd 0x00000000

; Partition entry 3 (empty)
db 0x00, 0x00, 0x00, 0x00
db 0x00, 0x00, 0x00, 0x00
dd 0x00000000
dd 0x00000000

; Partition entry 4 (empty)
db 0x00, 0x00, 0x00, 0x00
db 0x00, 0x00, 0x00, 0x00
dd 0x00000000
dd 0x00000000

; -----------------------------------------------------------------------------
; Boot signature — must be at offset 510-511 exactly
; -----------------------------------------------------------------------------
times (510 - ($ - $$)) db 0        ; pad to offset 510 if needed

dw 0xAA55                           ; boot signature
                                    ; NASM stores in little-endian:
                                    ; byte 510 = 0x55
                                    ; byte 511 = 0xAA
                                    ; BIOS reads as 0x55AA = valid boot sector

; =============================================================================
; Total: exactly 512 bytes
; =============================================================================