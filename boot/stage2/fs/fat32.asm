; =============================================================================
; Tattva OS — boot/stage2/fs/fat32.asm
; =============================================================================
; FAT32 filesystem structures and reader.
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef FAT32_ASM
%define FAT32_ASM

[BITS 64]

; FAT32 Boot Parameter Block (BPB) structure
struc fat32_bpb
    .jmp_code:       resb 3
    .oem_name:       resb 8
    .bytes_per_sec:  resw 1         ; bytes per sector (usually 512)
    .sec_per_clus:   resb 1         ; sectors per cluster
    .reserved_sec:   resw 1         ; reserved sectors (usually 32)
    .num_fats:       resb 1         ; number of FATs (usually 2)
    .root_entries:   resw 1         ; root directory entries (always 0 for FAT32)
    .total_sec_16:   resw 1
    .media_type:     resb 1
    .fat_size_16:    resw 1
    .sec_per_track:  resw 1
    .num_heads:      resw 1
    .hidden_sec:     resd 1         ; hidden sectors (LBA of partition start)
    .total_sec_32:   resd 1
    ; FAT32 extended BPB fields
    .fat_size_32:    resd 1         ; sectors per FAT
    .ext_flags:      resw 1
    .fs_version:     resw 1
    .root_cluster:   resd 1         ; starting cluster of root directory (usually 2)
    .fs_info_sec:    resw 1
    .backup_boot:    resw 1
    .reserved:       resb 12
    .drive_num:      resb 1
    .reserved_nt:    resb 1
    .boot_sig:       resb 1         ; 0x29
    .volume_id:      resd 1
    .volume_label:   resb 11
    .fs_type:        resb 8         ; "FAT32   "
endstruc

; FAT32 Directory Entry structure (32 bytes)
struc fat32_dirent
    .name:           resb 8         ; short name
    .ext:            resb 3         ; extension
    .attrib:         resb 1         ; attribute byte
    .reserved_nt:    resb 1
    .creation_time:  resb 3
    .creation_date:  resw 1
    .last_acc_date:  resw 1
    .first_clus_high:resw 1         ; high 16 bits of cluster
    .write_time:     resw 1
    .write_date:     resw 1
    .first_clus_low: resw 1         ; low 16 bits of cluster
    .file_size:      resd 1         ; file size in bytes
endstruc

; =============================================================================
; fat32_find_file — find file entry matching name in a directory buffer
; Input:  RSI = pointer to directory entries buffer
;         RDI = pointer to 11-char name string ("KERNEL  ULF")
;         RCX = buffer size in bytes
; Output: RAX = first cluster number of file, or 0 if not found
;         RDX = file size in bytes
; =============================================================================
fat32_find_file:
    push rbx
    push rsi
    push rdi

.loop:
    cmp rcx, 32
    jl .not_found

    ; Check if entry is free/end
    mov al, [rsi + fat32_dirent.name]
    test al, al                     ; end of directory?
    jz .not_found
    cmp al, 0xE5                    ; deleted file?
    je .next

    ; Skip Volume Label (0x08) and LFN (0x0F) entries
    mov al, [rsi + fat32_dirent.attrib]
    test al, 0x08                   ; Volume Label?
    jnz .next
    cmp al, 0x0F                    ; Long File Name?
    je .next

    ; Compare 11 character 8.3 name
    push rdi
    push rsi
    mov rdx, 11
.compare:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .mismatch
    inc rsi
    inc rdi
    dec rdx
    jnz .compare

    ; Found the file
    pop rsi
    pop rdi
    
    ; Extract starting cluster
    xor rax, rax
    mov ax, [rsi + fat32_dirent.first_clus_high]
    shl eax, 16                     ; shift to high 16 bits
    mov ax, [rsi + fat32_dirent.first_clus_low]  ; load low 16 bits
    
    mov edx, [rsi + fat32_dirent.file_size]     ; RDX = file size
    jmp .done

.mismatch:
    pop rsi
    pop rdi

.next:
    add rsi, 32                     ; next 32-byte directory entry
    sub rcx, 32
    jmp .loop

.not_found:
    xor rax, rax
    xor rdx, rdx

.done:
    pop rdi
    pop rsi
    pop rbx
    ret

[BITS 16]

%endif ; FAT32_ASM
