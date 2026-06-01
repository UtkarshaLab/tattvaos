; boot/stage2/memory/e820_sort.asm
; Sort E820 entries by base address (ascending)
;
; Real hardware returns E820 entries out of order.
; QEMU returns them sorted — do not rely on this.
; Must be run before e820_merge.asm
;
; Algorithm: insertion sort (simple, sufficient for <= 128 entries)

e820_sort:
    ; TODO: read entry count from E820_DEST header
    ; TODO: insertion sort by base address (low 32 bits sufficient for sorting)
    ; TODO: swap full 24-byte entries when out of order
    ret
