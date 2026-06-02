; =============================================================================
; Tattva OS — boot/stage2/fs/gpt.asm
; =============================================================================
; GUID Partition Table (GPT) structures and helpers.
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef GPT_ASM
%define GPT_ASM

[BITS 64]

; GPT Header structure definition
struc gpt_header
    .signature:      resq 1         ; "EFI PART" (0x5452415020494645)
    .revision:       resd 1         ; revision (e.g. 0x00010000)
    .header_size:    resd 1         ; size of GPT header (usually 92)
    .header_crc32:   resd 1         ; CRC32 of header
    .reserved1:      resd 1
    .my_lba:         resq 1         ; LBA of this header (usually 1)
    .alternate_lba:  resq 1         ; LBA of backup header
    .first_usable:   resq 1         ; first usable LBA for partitions
    .last_usable:    resq 1         ; last usable LBA
    .disk_guid:      resb 16        ; unique disk GUID
    .partition_lba:  resq 1         ; LBA of partition entry array (usually 2)
    .num_partitions: resd 1         ; number of partition entries (usually 128)
    .entry_size:     resd 1         ; size of each entry (usually 128)
    .entries_crc32:  resd 1         ; CRC32 of partition array
endstruc

; GPT Partition Entry structure definition (128 bytes)
struc gpt_entry
    .type_guid:      resb 16        ; partition type GUID
    .unique_guid:    resb 16        ; unique partition GUID
    .starting_lba:   resq 1         ; starting LBA
    .ending_lba:     resq 1         ; ending LBA
    .attributes:     resq 1         ; attribute flags
    .name:           resw 36        ; partition name (UTF-16LE, 72 bytes)
endstruc

; =============================================================================
; gpt_find_partition — locate partition in the entry array by its Type GUID
; Input:  RSI = pointer to GPT partition entries buffer
;         RDI = pointer to partition type GUID to find (16 bytes)
; Output: RAX = starting LBA of matching partition, or 0 if not found
;         RCX = size of partition in sectors
; =============================================================================
gpt_find_partition:
    push rbx
    push rdx
    push rsi

    mov ecx, 128                    ; search up to 128 partition entries
.loop:
    push rdi
    push rsi
    
    ; Compare type_guid (16 bytes)
    mov rdx, 16                     ; GUID size in bytes
.compare:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .mismatch
    inc rsi
    inc rdi
    dec rdx
    jnz .compare
    
    ; Found matching partition type
    pop rsi
    pop rdi
    
    ; Extract starting LBA and size
    mov rax, [rsi + gpt_entry.starting_lba]
    mov rbx, [rsi + gpt_entry.ending_lba]
    sub rbx, rax
    inc rbx                         ; RBX = size in sectors
    mov rcx, rbx
    jmp .done

.mismatch:
    pop rsi
    pop rdi
    add rsi, 128                    ; move to next partition entry (128 bytes)
    dec ecx
    jnz .loop

    xor rax, rax                    ; not found
    xor rcx, rcx

.done:
    pop rsi
    pop rdx
    pop rbx
    ret

[BITS 16]

%endif ; GPT_ASM
