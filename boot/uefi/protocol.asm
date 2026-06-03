; =============================================================================
; Tattva OS — boot/uefi/protocol.asm
; =============================================================================
; UEFI structures, offsets, and protocols.
; Conforms to UEFI 2.8+ specifications.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_PROTOCOL_ASM
%define UEFI_PROTOCOL_ASM

; -----------------------------------------------------------------------------
; UEFI System Table offsets
; -----------------------------------------------------------------------------
SYS_TABLE_CON_IN            equ 48      ; pointer to Simple Text Input
SYS_TABLE_CON_OUT           equ 64      ; pointer to Simple Text Output (ConOut)
SYS_TABLE_BOOT_SERVICES     equ 96      ; pointer to Boot Services Table

; -----------------------------------------------------------------------------
; Simple Text Output Protocol (ConOut) offsets
; -----------------------------------------------------------------------------
CON_OUT_RESET               equ 0       ; Reset member pointer
CON_OUT_OUTPUT_STRING       equ 8       ; OutputString member pointer

; -----------------------------------------------------------------------------
; UEFI Boot Services offsets
; -----------------------------------------------------------------------------
BS_GET_MEMORY_MAP           equ 56      ; GetMemoryMap pointer
BS_LOCATE_PROTOCOL          equ 320     ; LocateProtocol pointer
BS_EXIT_BOOT_SERVICES       equ 232     ; ExitBootServices pointer

; -----------------------------------------------------------------------------
; UEFI Simple File System / Graphics Output Protocol GUIDs
; -----------------------------------------------------------------------------
; GOP GUID: 9042A9DE-23A6-4A7F-96C7-840AE27F21AA
gop_guid:
    dd 0x9042A9DE
    dw 0x23A6, 0x4A7F
    db 0x96, 0xC7, 0x84, 0x0A, 0xE2, 0x7F, 0x21, 0xAA

; SimpleFileSystem GUID: 964E5B22-6459-11D2-8E39-00A0C969723B
sfs_guid:
    dd 0x964E5B22
    dw 0x6459, 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

%endif ; UEFI_PROTOCOL_ASM
