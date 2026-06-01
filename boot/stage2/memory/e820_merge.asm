; boot/stage2/memory/e820_merge.asm
; Merge overlapping E820 entries after sorting
;
; Real hardware has overlapping and adjacent regions.
; QEMU returns a clean non-overlapping map — do not rely on this.
;
; Rules:
;   - Reserved always beats usable in overlap conflicts
;   - Run AFTER e820_sort.asm
;   - Adjacent usable regions of same type can be merged

e820_merge:
    ; TODO: iterate sorted entries
    ; TODO: check if entry[i] overlaps with entry[i+1]
    ; TODO: if usable overlaps reserved: shrink usable, preserve reserved
    ; TODO: if same type and adjacent: merge into single larger entry
    ; TODO: remove merged entries by shifting remaining down
    ret
