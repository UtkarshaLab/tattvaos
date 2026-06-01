; =============================================================================
; Tattva OS — boot/config.asm
; =============================================================================
; ALL boot constants in one place.
; Never scatter constants across files.
; Every boot file includes this.
;
; Author:  Utkarsha Labs
; =============================================================================

; -----------------------------------------------------------------------------
; Memory layout
; -----------------------------------------------------------------------------
STAGE1_LOAD     equ 0x7C00      ; BIOS loads MBR here
STAGE1_RELOC    equ 0x0600      ; MBR relocates self here
STAGE2_LOAD     equ 0x8000      ; stage2 loads here
KERNEL_LOAD     equ 0x100000    ; kernel loads at 1MB mark
STACK_REAL      equ 0x7C00      ; real mode stack top (grows down)
STACK_PROT      equ 0x9C000     ; protected mode stack top
STACK_LONG      equ 0x9C000     ; long mode stack top
SURVIVE_PAGE    equ 0x9000      ; panic snapshot page (hidden from E820)
PANIC_VECTOR    equ 0x500       ; panic handler address written here
E820_DEST       equ 0x6000      ; E820 memory map stored here
FEATURES_DEST   equ 0x5000      ; CPU feature flags stored here

; -----------------------------------------------------------------------------
; Stage2 load size
; -----------------------------------------------------------------------------
STAGE2_SECTORS  equ 16          ; number of 512-byte sectors to load
                                ; 16 sectors = 8KB for stage2
                                ; increase if stage2 grows beyond 8KB

; -----------------------------------------------------------------------------
; GDT segment selectors
; -----------------------------------------------------------------------------
SEL_NULL        equ 0x00        ; null descriptor
SEL_CODE64      equ 0x08        ; 64-bit code segment
SEL_DATA64      equ 0x10        ; 64-bit data segment
SEL_CODE16      equ 0x18        ; 16-bit code (real mode transition)
SEL_CODE32      equ 0x20        ; 32-bit code (protected mode)

; -----------------------------------------------------------------------------
; UART (COM1)
; -----------------------------------------------------------------------------
UART_COM1       equ 0x3F8       ; COM1 base I/O port
UART_BAUD_DIV   equ 1           ; divisor for 115200 baud (1.8432MHz / 16)

; -----------------------------------------------------------------------------
; Magic numbers — placed at start of each stage binary
; -----------------------------------------------------------------------------
TATTVA_MAGIC    equ 0x54415456  ; "TATV" in little-endian ASCII
STAGE1_MAGIC    equ 0x31535442  ; "BTS1"
STAGE2_MAGIC    equ 0x32535442  ; "BTS2"

; -----------------------------------------------------------------------------
; Filesystem detection priority
; -----------------------------------------------------------------------------
FS_BXP          equ 1           ; Tattva native format (always priority 1)
FS_GPT          equ 2           ; GUID Partition Table
FS_MBR_PART     equ 3           ; MBR partition table
FS_FAT32        equ 4           ; FAT32 (development default)
FS_EXT2         equ 5           ; ext2 Linux compatibility

; -----------------------------------------------------------------------------
; Disk I/O
; -----------------------------------------------------------------------------
DISK_RETRY      equ 3           ; retry count before giving up on disk read

; -----------------------------------------------------------------------------
; Misc
; -----------------------------------------------------------------------------
VGA_BUFFER      equ 0xB8000     ; VGA text mode buffer
VGA_WHITE       equ 0x07        ; white text on black background