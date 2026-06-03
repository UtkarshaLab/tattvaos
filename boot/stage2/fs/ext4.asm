; =============================================================================
; Tattva OS — boot/stage2/fs/ext4.asm
; =============================================================================
; Read-only ext4 filesystem reader for x86 16-bit real mode.
; Traverses the ext4 superblock, group descriptors, inodes, and extent trees
; to locate and load files.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef EXT4_ASM
%define EXT4_ASM

[BITS 16]

; ext4 Superblock Offsets (relative to superblock start)
EXT4_SB_MAGIC       equ 56           ; word (0xEF53)
EXT4_SB_BLOCK_SIZE  equ 24           ; dword (log2(block_size) - 10)
EXT4_SB_INODES_GRP  equ 40           ; dword (inodes per group)
EXT4_SB_INODE_SIZE  equ 88           ; word (size of inode structure)

; ext4 Inode Offsets
EXT4_INODE_SIZE_LO  equ 4            ; dword (file size low)
EXT4_INODE_FLAGS    equ 32           ; dword
EXT4_INODE_BLOCKS   equ 40           ; 60 bytes (extent tree or block pointers)

; ext4 Extent Header Offsets
EXT4_EH_MAGIC       equ 0            ; word (0xF30A)
EXT4_EH_ENTRIES     equ 2            ; word
EXT4_EH_DEPTH       equ 6            ; word

; ext4 Extent Leaf Offsets
EXT4_EE_BLOCK       equ 0            ; dword
EXT4_EE_LEN         equ 4            ; word
EXT4_EE_START_HI    equ 6            ; word
EXT4_EE_START_LO    equ 8            ; dword

; =============================================================================
; ext4_detect — Check if partition has an ext4 filesystem
; Input:  EAX = starting LBA of partition
; Output: AX = 1 if ext4, 0 if not
; =============================================================================
ext4_detect:
    push ebx
    push ecx
    push edx
    push es

    ; Read superblock (located at 1024 bytes offset = partition LBA + 2)
    add eax, 2                       ; LBA offset 2 (sector 2 of partition)
    mov cx, 0x3000
    mov es, cx
    xor bx, bx                       ; ES:BX = 0x3000:0x0000
    call fs_read_sector
    jc .not_ext4                     ; read error

    ; Check magic 0xEF53 at offset 56 of sector
    cmp word [es:bx + EXT4_SB_MAGIC], 0xEF53
    jne .not_ext4

    ; Found ext4!
    mov ax, 1
    jmp .done

.not_ext4:
    xor ax, ax

.done:
    pop es
    pop edx
    pop ecx
    pop ebx
    ret

; =============================================================================
; ext4_load_file — Load a file from ext4 partition
; Input:  EAX = starting LBA of partition
;         RSI = pointer to filename string (e.g. "kernel.ulf")
;         ES:BX = target destination buffer (e.g. KERNEL_TEMP)
; Output: AX = 1 if successful, 0 if failed
; =============================================================================
ext4_load_file:
    push ebp
    mov bp, sp
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ds

    ; Save inputs
    mov [ext4_part_lba], eax
    mov [ext4_filename_ptr], si
    mov [ext4_dest_offset], bx
    mov [ext4_dest_segment], es

    ; 1. Read superblock again to extract parameters
    mov eax, [ext4_part_lba]
    add eax, 2                       ; LBA 2
    mov cx, 0x3000
    mov es, cx
    xor bx, bx
    call fs_read_sector
    jc .failed

    ; s_log_block_size is at offset 24
    mov ecx, [es:bx + EXT4_SB_BLOCK_SIZE]
    add ecx, 10                      ; block_size = 1 << (10 + log_block_size)
    mov eax, 1
    shl eax, cl
    mov [ext4_block_size], eax       ; usually 4096

    ; sectors per block = block_size / 512
    shr eax, 9
    mov [ext4_sec_per_block], ax     ; usually 8

    ; Inodes per group
    mov eax, [es:bx + EXT4_SB_INODES_GRP]
    mov [ext4_inodes_per_group], eax

    ; Inode size
    mov ax, [es:bx + EXT4_SB_INODE_SIZE]
    mov [ext4_inode_size], ax

    ; 2. Read Block Group Descriptor Table (starts at block 1 for 4096 block size)
    ; LBA = partition_start + (1 * sectors_per_block)
    mov eax, [ext4_part_lba]
    xor ecx, ecx
    mov cx, [ext4_sec_per_block]
    add eax, ecx                     ; EAX = LBA of descriptor table
    mov cx, 0x3000
    mov es, cx
    xor bx, bx
    call fs_read_sector
    jc .failed

    ; Group 0 Inode Table block number is at offset 8 of group descriptor 0
    mov eax, [es:bx + 8]             ; Inode table block number
    mov [ext4_inode_table_block], eax

    ; 3. Load Inode 2 (Root Inode)
    ; Root inode is index 1 (0-based) in Inode Table of Group 0
    ; LBA offset of Inode 2 = table_start_lba + (1 * inode_size) / 512
    mov eax, [ext4_inode_table_block]
    xor ecx, ecx
    mov cx, [ext4_sec_per_block]
    mul ecx                          ; EAX = inode table LBA offset from partition start
    add eax, [ext4_part_lba]         ; EAX = absolute starting LBA of inode table

    ; Calculate sector and offset for Inode 2
    xor edx, edx
    mov dx, [ext4_inode_size]        ; Inode 2 offset = 1 * inode_size
    mov ecx, 512
    div ecx                          ; EAX = sector offset, EDX = byte offset in sector

    add eax, [ext4_inode_table_block]
    ; Read sector
    mov cx, 0x3000
    mov es, cx
    xor bx, bx
    call fs_read_sector
    jc .failed

    ; Read root inode block list / extent tree (starts at offset 40 of inode)
    lea si, [es:bx + di + EXT4_INODE_BLOCKS] ; SI = pointer to extent tree in root inode

    ; Walk extent tree to find root directory blocks and scan for filename
    ; We assume root directory fits in 1 extent for simplicity
    cmp word [si + EXT4_EH_MAGIC], 0xF30A   ; Check extent magic
    jne .failed
    cmp word [si + EXT4_EH_DEPTH], 0        ; Check leaf
    jne .failed

    ; First leaf extent (at offset 12)
    mov eax, [si + 12 + EXT4_EE_START_LO]   ; Block start
    ; Read root directory block to 0x4000:0x0000
    xor ecx, ecx
    mov cx, [ext4_sec_per_block]
    mul ecx
    add eax, [ext4_part_lba]         ; EAX = absolute starting LBA of directory block

    mov cx, 0x4000
    mov es, cx
    xor bx, bx
    call fs_read_sector              ; read directory block sector 0
    jc .failed

    ; Scan directory block for target filename
    mov di, 0                        ; DI = offset in block
.dir_loop:
    cmp di, 512                      ; end of sector?
    jae .failed

    mov eax, [es:di]                 ; Inode number of entry
    test eax, eax                    ; empty entry?
    jz .next_dir

    xor cx, cx
    mov cl, [es:di + 6]              ; name length
    lea si, [es:di + 8]              ; pointer to entry name

    ; Compare string length and characters
    ; We will do a simple comparison
    push di
    push si
    mov dx, cx                       ; DX = name length
    mov di, [ext4_filename_ptr]      ; DI = target filename pointer
.cmp_loop:
    dec dx
    js .found_match
    mov al, [es:si]
    mov bl, [di]
    cmp al, bl
    jne .mismatch
    inc si
    inc di
    jmp .cmp_loop

.mismatch:
    pop si
    pop di
.next_dir:
    xor cx, cx
    mov cx, [es:di + 4]              ; rec_len
    add di, cx
    jmp .dir_loop

.found_match:
    pop si
    pop di
    ; Found it! EAX contains the target file inode number
    mov [ext4_file_inode], eax

    ; 4. Load the file inode
    ; Inode group = (inode - 1) / inodes_per_group
    ; Inode index = (inode - 1) % inodes_per_group
    dec eax                          ; EAX = inode - 1
    xor edx, edx
    mov ecx, [ext4_inodes_per_group]
    div ecx                          ; EAX = group, EDX = index inside group

    ; We assume group 0 for simplicity in this loader
    ; LBA offset = inode_table_block + (index * inode_size) / 512
    mov eax, edx                     ; EAX = index
    xor edx, edx
    mov dx, [ext4_inode_size]
    mul edx                          ; EAX = index * inode_size
    mov ecx, 512
    div ecx                          ; EAX = sector offset, EDX = byte offset in sector

    add eax, [ext4_inode_table_block]
    add eax, [ext4_part_lba]         ; absolute LBA of sector containing inode

    mov cx, 0x3000
    mov es, cx
    xor bx, bx
    call fs_read_sector
    jc .failed

    ; Load extent tree of file inode
    lea si, [es:bx + di + EXT4_INODE_BLOCKS] ; SI = pointer to extent tree in file inode

    ; Walk extent tree to load file blocks to target destination
    cmp word [si + EXT4_EH_MAGIC], 0xF30A
    jne .failed
    cmp word [si + EXT4_EH_DEPTH], 0
    jne .failed

    ; Leaf extent (at offset 12)
    mov eax, [si + 12 + EXT4_EE_START_LO]   ; Starting block of file
    xor ecx, ecx
    mov cx, [ext4_sec_per_block]
    mul ecx
    add eax, [ext4_part_lba]         ; absolute LBA

    ; Read sectors directly to target destination ES:BX
    mov es, [ext4_dest_segment]
    mov bx, [ext4_dest_offset]
    
    ; Load 64 sectors (32KB = early kernel size)
    mov cx, 64
.read_file:
    call fs_read_sector
    jc .failed
    add bx, 512                      ; advance buffer offset
    inc eax                          ; next LBA
    loop .read_file

    mov ax, 1                        ; Success
    jmp .done

.failed:
    xor ax, ax                       ; Failure

.done:
    pop ds
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

; ext4 State variables
align 4
ext4_part_lba:          dd 0
ext4_block_size:        dd 0
ext4_sec_per_block:     dw 0
ext4_inodes_per_group:  dd 0
ext4_inode_size:        dw 0
ext4_inode_table_block: dd 0
ext4_filename_ptr:      dw 0
ext4_dest_offset:       dw 0
ext4_dest_segment:      dw 0
ext4_file_inode:        dd 0

%endif ; EXT4_ASM
