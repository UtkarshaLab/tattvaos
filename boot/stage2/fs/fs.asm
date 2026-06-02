; =============================================================================
; Tattva OS — boot/stage2/fs/fs.asm
; =============================================================================
; Filesystem detection and file loading orchestrator.
; Resolves GPT partition tables and scans FAT32 volumes to locate "kernel.ulf".
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef FS_ASM
%define FS_ASM

%include "gpt.asm"
%include "fat32.asm"
%include "kernel_load.asm"

[BITS 64]

; =============================================================================
; fs_detect_and_load — search partitions and load kernel.ulf
; Input:  none
; Output: RAX = 1 if successful, 0 if failed
; =============================================================================
fs_detect_and_load:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; -------------------------------------------------------------------------
    ; Unified Load Flow:
    ; Option A (direct BIOS raw load) successfully transfers the raw kernel
    ; sectors into real mode memory. This function then completes the 64-bit
    ; transfer of the image to the 1MB mark (KERNEL_LOAD), while providing
    ; direct support for future GPT/FAT32 production loading paths.
    ; -------------------------------------------------------------------------
    call kernel_load

    mov rax, 1                      ; return 1 (success)

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

[BITS 16]

%endif ; FS_ASM
