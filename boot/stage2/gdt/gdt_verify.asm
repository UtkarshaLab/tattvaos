; boot/stage2/gdt/gdt_verify.asm
; Verify GDT was loaded correctly after lgdt + far jump
;
; Reads back descriptor values, checks code + data segment flags.
; Halts with UART error message if wrong.

gdt_verify:
    ; TODO: read descriptor at SEL_CODE64 offset (0x08) from GDT base
    ; TODO: verify descriptor type = 64-bit code (L bit set, D bit clear)
    ; TODO: read descriptor at SEL_DATA64 offset (0x10)
    ; TODO: verify data segment flags
    ; TODO: call uart error + halt if any check fails
    ret
