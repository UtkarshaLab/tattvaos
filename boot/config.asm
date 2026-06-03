; =============================================================================
; Tattva OS — boot/config.asm
; =============================================================================
; ALL boot constants in one place.
; Never scatter constants across files.
; Every boot file includes this.
;
; Author:  Utkarsha Labs
; =============================================================================

%ifndef CONFIG_ASM
%define CONFIG_ASM

; -----------------------------------------------------------------------------
; Memory layout
; -----------------------------------------------------------------------------
STAGE1_LOAD     equ 0x7C00      ; BIOS loads MBR here
STAGE1_RELOC    equ 0x0600      ; MBR relocates self here
STAGE2_LOAD     equ 0x8000      ; stage2 loads here
KERNEL_LOAD     equ 0x100000    ; kernel loads at 1MB mark
KERNEL_TEMP     equ 0x20000     ; temporary real-mode buffer for BIOS load
KERNEL_LBA      equ 65          ; starting LBA sector for the kernel
KERNEL_SECTOR   equ (KERNEL_LBA + 1) ; CHS sector (1-indexed) where kernel starts on disk (LBA 65 -> CHS 66)
KERNEL_SECTORS  equ 64          ; number of sectors to read (64 × 512 = 32KB)
STACK_REAL      equ 0x7C00      ; real mode stack top (grows down)
STACK_PROT      equ 0x9C000     ; protected mode stack top
STACK_LONG      equ 0x9C000     ; long mode stack top
SURVIVE_PAGE    equ 0x90000     ; panic snapshot page (hidden from E820)
PANIC_VECTOR    equ 0x500       ; panic handler address written here
E820_DEST       equ 0x6000      ; E820 memory map stored here
FEATURES_DEST   equ 0x5000      ; CPU feature flags stored here

; -----------------------------------------------------------------------------
; Paging table physical addresses (above BIOS, below stage2, 4KB aligned)
; -----------------------------------------------------------------------------
PAGING_PML4     equ 0x10000     ; PML4 table physical address
PAGING_PDPT     equ 0x11000     ; PDPT table physical address
PAGING_PD0      equ 0x12000     ; PD for 0GB - 1GB
PAGING_PD1      equ 0x13000     ; PD for 1GB - 2GB
PAGING_PD2      equ 0x14000     ; PD for 2GB - 3GB
PAGING_PD3      equ 0x15000     ; PD for 3GB - 4GB

; -----------------------------------------------------------------------------
; Stage2 load size
; -----------------------------------------------------------------------------
STAGE2_SECTORS  equ 64          ; number of 512-byte sectors to load
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

; -----------------------------------------------------------------------------
; BootInfo structure layout (at physical address 0x7000)
; -----------------------------------------------------------------------------
BOOT_INFO_ADDR       equ 0x7000
BOOT_INFO_E820_ADDR  equ 0x7000     ; dq: physical address of E820 entries
BOOT_INFO_E820_COUNT equ 0x7008     ; dd: number of E820 entries
BOOT_INFO_DRIVE      equ 0x700C     ; dd: boot drive number
BOOT_INFO_FEATURES   equ 0x7010     ; dd: CPU feature flags
BOOT_INFO_RESERVED   equ 0x7014     ; dd: reserved/padding
BOOT_INFO_ACPI_RSDP  equ 0x7018     ; dq: ACPI RSDP physical address
BOOT_INFO_FB_ADDR    equ 0x7020     ; dq: framebuffer physical address
BOOT_INFO_FB_WIDTH   equ 0x7028     ; dd: framebuffer width
BOOT_INFO_FB_HEIGHT  equ 0x702C     ; dd: framebuffer height
BOOT_INFO_FB_PITCH   equ 0x7030     ; dd: framebuffer pitch
BOOT_INFO_FB_FORMAT  equ 0x7034     ; dd: framebuffer format
BOOT_INFO_INITRD_ADDR equ 0x7038    ; dq: initrd physical address
BOOT_INFO_INITRD_SIZE equ 0x7040    ; dq: initrd size
BOOT_INFO_EDD_ADDR   equ 0x7048     ; dq: EDD parameters physical address
BOOT_INFO_SMP_CORES  equ 0x7050     ; dd: SMP logical core count

%endif ; CONFIG_ASM