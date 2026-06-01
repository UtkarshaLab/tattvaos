; boot/survive/checksum.asm
; CRC32 checksum of the hardware snapshot page
;
; MUST be called after snapshot.asm and before recover.asm
; A corrupt snapshot without checksum verification = loading garbage registers
;
; On save: compute CRC32 of snapshot data, store at end of snapshot page
; On recover: recompute CRC32, compare stored value, abort if mismatch

survive_checksum_save:
    ; TODO: compute CRC32 of [SURVIVE_PAGE .. SURVIVE_PAGE + snapshot_size]
    ; TODO: store result at SURVIVE_PAGE + snapshot_size
    ret

survive_checksum_verify:
    ; TODO: recompute CRC32 of snapshot data
    ; TODO: compare against stored checksum
    ; TODO: if mismatch: log via uart, fall through to reset.asm
    ret
