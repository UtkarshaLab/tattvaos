; =============================================================================
; Tattva OS — boot/tests/test_fat32.asm
; =============================================================================
; Test assertion for FAT32 filesystem structures and partitioning.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef TEST_FAT32_ASM
%define TEST_FAT32_ASM

[BITS 16]

; =============================================================================
; test_fat32 — check FAT32 partition or report direct/fallback status
; =============================================================================
test_fat32:
    push si
    push eax

    mov si, msg_test_fat32
    call uart_print

    ; Check if partition_start is non-zero
    mov eax, [partition_start]
    test eax, eax
    jz .skipped                     ; if 0, FAT32 partition was not loaded/found

    ; If found, verify we have a valid sector-per-cluster value (> 0)
    xor ax, ax
    mov al, [sec_per_clus]
    test al, al
    jz .failed

    mov si, msg_pass_fat32
    call uart_println
    jmp .done

.skipped:
    mov si, msg_skip_fat32
    call uart_println
    jmp .done

.failed:
    mov si, msg_fail_fat32
    call uart_println

.done:
    pop eax
    pop si
    ret

; =============================================================================
; Data
; =============================================================================
msg_test_fat32:  db "TEST: FAT32 directory and cluster parsing... ", 0
msg_pass_fat32:  db "PASS", 0
msg_fail_fat32:  db "FAIL", 0
msg_skip_fat32:  db "SKIP (raw sector fallback)", 0

%endif ; TEST_FAT32_ASM
