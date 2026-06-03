; =============================================================================
; Tattva OS — boot/stage2/fs/fs16.asm
; =============================================================================
; 16-bit real-mode filesystem scanner and loader.
; Parses GPT partition table to locate a FAT32 partition, searches the root
; directory for "KERNEL.ULF", and loads it into KERNEL_TEMP (0x20000).
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef FS16_ASM
%define FS16_ASM

[BITS 16]

; =============================================================================
; fs_load_kernel — main real-mode entry point for loading the kernel
; Input:  none
; Output: AX = 1 if successful, 0 if failed (falls back to Option A raw sectors)
; Clobbers: AX
; =============================================================================
fs_load_kernel:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push es

    ; Print FS Init message
    mov si, msg_fs_init
    call uart_print

    ; 1. Read LBA 1 (GPT Header) to 0x2000:0x0000
    mov ax, 0x2000
    mov es, ax
    xor bx, bx
    mov eax, 1                      ; LBA 1
    call fs_read_sector
    jc .fallback                    ; error -> fallback

    ; Check signature "EFI PART" (0x5452415020494645)
    cmp dword [es:bx], 0x45464920    ; "EFI "
    jne .fallback
    cmp dword [es:bx + 4], 0x50415254 ; "PART"
    jne .fallback

    ; Extract partition entry LBA (usually 2) and number of entries (usually 128)
    mov eax, [es:bx + 72]           ; EAX = partition LBA
    mov [gpt_entries_lba], eax
    mov ecx, [es:bx + 80]           ; ECX = number of partitions
    mov [gpt_num_entries], ecx

    ; 2. Scan partition entries sector-by-sector to find the FAT32 partition
    mov eax, [gpt_entries_lba]
    xor edx, edx                    ; EDX = current entry index
.sector_loop:
    cmp edx, [gpt_num_entries]
    jae .fallback

    ; Read one sector of partition entries to 0x2000:0x0000
    push eax
    push edx
    mov ax, 0x2000
    mov es, ax
    xor bx, bx
    pop edx
    pop eax
    call fs_read_sector
    jc .next_sector                 ; read failed, skip sector

    ; Process 4 entries in this sector (each is 128 bytes)
    mov di, 0                       ; DI = offset to current entry
.entry_loop:
    ; Check if entry is empty (Type GUID is all zeros)
    cmp dword [es:di], 0
    jne .check_partition
    cmp dword [es:di+4], 0
    jne .check_partition
    cmp dword [es:di+8], 0
    jne .check_partition
    cmp dword [es:di+12], 0
    je .next_entry                  ; all zero -> unused entry

.check_partition:
    ; Extract starting LBA (offset 32)
    mov ebx, [es:di + 32]           ; low dword of LBA
    test ebx, ebx
    jz .next_entry

    ; Read the partition's boot sector to 0x3000:0x0000
    push eax
    push edx
    push di
    
    mov eax, ebx                    ; EAX = partition starting LBA
    mov cx, 0x3000
    
    push es
    mov es, cx
    xor bx, bx
    call fs_read_sector
    pop es
    
    jc .boot_sector_fail            ; read failed
    
    ; Check signature at offset 510
    mov cx, 0x3000
    mov fs, cx
    cmp word [fs:510], 0xAA55
    jne .boot_sector_fail
    
    ; Check filesystem type at offset 82
    cmp dword [fs:82], 0x33544146   ; "FAT3"
    jne .boot_sector_fail
    cmp dword [fs:86], 0x20202032   ; "2   "
    jne .boot_sector_fail
    
    ; Found FAT32 partition!
    ; Save partition parameters from BPB in FS segment
    mov eax, [fs:36]                ; EAX = sectors per FAT (fat_size_32)
    mov [fat_size], eax
    
    xor eax, eax
    mov al, [fs:16]                 ; AL = number of FATs
    mov [num_fats], al
    
    mov ax, [fs:14]                 ; AX = reserved sectors
    mov [reserved_sectors], ax
    
    mov al, [fs:13]                 ; AL = sectors per cluster
    mov [sec_per_clus], al
    
    mov eax, [fs:44]                ; EAX = root cluster
    mov [root_cluster], eax
    
    pop di
    pop edx
    pop eax
    
    ; Save partition starting LBA
    mov [partition_start], ebx
    jmp .fat32_found

.boot_sector_fail:
    pop di
    pop edx
    pop eax

.next_entry:
    add di, 128                     ; next entry in sector
    inc edx                         ; increment entry index
    cmp di, 512
    jl .entry_loop

.next_sector:
    inc eax                         ; next sector of partition entries
    jmp .sector_loop

.fat32_found:
    ; Print partition found message
    mov si, msg_fat_found
    call uart_print
    mov eax, [partition_start]
    call uart_print_dec
    
    ; print CRLF
    mov al, 0x0D
    call uart_putc
    mov al, 0x0A
    call uart_putc

    ; Calculate FAT and Data region starts
    ; fat_start = partition_start + reserved_sectors
    mov eax, [partition_start]
    xor ecx, ecx
    mov cx, [reserved_sectors]
    add eax, ecx
    mov [fat_start], eax

    ; data_start = fat_start + (num_fats * fat_size)
    mov eax, [fat_size]
    xor ecx, ecx
    mov cl, [num_fats]
    mul ecx                         ; EAX = num_fats * fat_size
    add eax, [fat_start]
    mov [data_start], eax

    ; 3. Scan root directory to find "KERNEL  ULF"
    mov eax, [root_cluster]
.dir_loop:
    ; Read the directory cluster to 0x2000:0x0000
    push eax
    mov cx, 0x2000
    mov es, cx
    xor bx, bx
    call fs_read_cluster
    pop eax
    jc .fallback
    
    ; Scan the directory entries in this cluster
    xor cx, cx
    mov cl, [sec_per_clus]
    shl cx, 4                       ; CX = entries count (sec_per_clus * 16)
    
    mov di, 0                       ; DI = entry offset
.dir_entry_loop:
    ; Check if entry is end of directory
    mov al, [es:di]
    test al, al
    jz .fallback                    ; end of directory -> file not found
    
    cmp al, 0xE5
    je .next_dir_entry              ; deleted entry
    
    ; Check attribute (offset 11). Skip volume label (0x08) and LFN (0x0F)
    mov al, [es:di + 11]
    test al, 0x08
    jnz .next_dir_entry
    cmp al, 0x0F
    je .next_dir_entry
    
    ; Compare filename "KERNEL  ULF"
    mov si, filename_kernel
    push di
    mov dx, 11
.compare_name:
    mov al, [es:di]
    mov bl, [si]
    cmp al, bl
    jne .name_mismatch
    inc di
    inc si
    dec dx
    jnz .compare_name
    
    ; Found the file!
    pop di
    jmp .file_found
    
.name_mismatch:
    pop di
.next_dir_entry:
    add di, 32
    dec cx
    jnz .dir_entry_loop
    
    ; If not found in this cluster, get next cluster of root directory
    call fs_get_next_cluster
    cmp eax, 0x0FFFFFF8
    jb .dir_loop
    jmp .fallback                   ; EOF reached, file not found

.file_found:
    ; Print loading message
    mov si, msg_loading_kernel
    call uart_print

    ; Extract starting cluster
    mov ax, [es:di + 20]            ; high 16 bits
    shl eax, 16
    mov ax, [es:di + 26]            ; low 16 bits
    mov [kernel_start_cluster], eax

    ; Load the kernel file cluster by cluster to KERNEL_TEMP (0x2000:0x0000)
    mov ax, (KERNEL_TEMP >> 4)
    mov es, ax
    xor bx, bx                      ; ES:BX = 0x2000:0x0000
    
    mov eax, [kernel_start_cluster]
.load_file_loop:
    call fs_read_cluster
    jc .fallback
    
    ; Get next cluster
    call fs_get_next_cluster
    cmp eax, 0x0FFFFFF8
    jb .load_file_loop

    ; Success! Set AX = 1
    mov ax, 1
    jmp .done

.fallback:
    ; Failure! Set AX = 0
    xor ax, ax

.done:
    pop es
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; =============================================================================
; fs_read_sector — read 1 sector to ES:BX using LBA (with CHS fallback)
; Input:  EAX = starting LBA sector
;         ES:BX = destination buffer
; Output: CF set on error
; =============================================================================
fs_read_sector:
    push eax
    push ecx
    push edx
    push si
    push di

    ; Check if LBA is supported
    cmp byte [lba_supported], 1
    je .lba_read

    ; CHS fallback for floppy drives
    push bx
    push ax
    ; AX has low 16 bits of LBA
    xor dx, dx
    mov cx, [sectors_per_track]
    test cx, cx
    jz .chs_error                   ; division by zero guard
    div cx                          ; AX = LBA / sectors_per_track, DX = LBA % sectors_per_track
    inc dx                          ; DX = Sector (1-indexed)
    mov cl, dl                      ; CL = Sector
    
    xor dx, dx
    mov cx, [number_of_heads]
    test cx, cx
    jz .chs_error                   ; division by zero guard
    div cx                          ; AX = Cylinder, DX = Head
    
    mov ch, al                      ; CH = Cylinder (low 8 bits)
    shl ah, 6
    or cl, ah                       ; CL bits 6-7 = cylinder bits 8-9
    
    mov dh, dl                      ; DH = Head
    mov dl, [boot_drive]            ; DL = boot drive
    
    pop ax
    pop bx
    
    mov ax, 0x0201                  ; Read 1 sector
    int 0x13
    jmp .done

.chs_error:
    pop ax                          ; clean up stack on error
    pop bx
    stc                             ; set carry flag to signal read error
    jmp .done

.lba_read:
    ; Setup DAP packet
    mov [fs_dap_lba], eax
    mov [fs_dap_offset], bx
    mov [fs_dap_segment], es

    mov si, fs_dap_packet
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13

.done:
    pop di
    pop si
    pop edx
    pop ecx
    pop eax
    ret

; =============================================================================
; fs_read_cluster — read a cluster to ES:BX
; Input:  EAX = cluster number
;         ES:BX = target buffer
; Output: ES:BX advanced by cluster size
;         CF set on error
; =============================================================================
fs_read_cluster:
    push eax
    push ecx
    push edx
    
    ; LBA = data_start + (cluster - 2) * sectors_per_cluster
    sub eax, 2
    xor edx, edx
    mov dl, [sec_per_clus]
    mul edx                         ; EAX = (cluster - 2) * sectors_per_cluster
    add eax, [data_start]           ; EAX = starting LBA of cluster
    
    mov cl, [sec_per_clus]          ; CL = sectors to read
.read_loop:
    call fs_read_sector
    jc .error
    add bx, 512                     ; advance buffer pointer
    test bx, bx                     ; check 64KB wrap
    jnz .no_wrap
    mov dx, es
    add dx, 0x1000                  ; advance ES segment by 64KB (0x1000 paragraphs)
    mov es, dx
.no_wrap:
    inc eax                         ; next LBA
    dec cl
    jnz .read_loop
    
    clc
    jmp .done
.error:
    stc
.done:
    pop edx
    pop ecx
    pop eax
    ret

; =============================================================================
; fs_get_next_cluster — read the FAT table to find the next cluster in the chain
; Input:  EAX = current cluster number
; Output: EAX = next cluster number
;         CF set on error
; =============================================================================
fs_get_next_cluster:
    push ebx
    push ecx
    push edx
    push es
    
    ; Calculate sector and offset
    shl eax, 2                      ; EAX = cluster * 4
    xor edx, edx
    mov ecx, 512
    div ecx                         ; EAX = sector offset, EDX = byte offset in sector
    
    add eax, [fat_start]            ; EAX = LBA of FAT sector
    
    ; Read the FAT sector to a temporary buffer at 0x3000:0x0000
    push edx
    mov cx, 0x3000
    mov es, cx
    xor bx, bx
    call fs_read_sector
    pop edx
    jc .error
    
    ; Read the next cluster value from the buffer
    mov bx, dx
    mov eax, [es:bx]
    and eax, 0x0FFFFFFF             ; mask upper 4 bits in FAT32
    clc
    jmp .done
    
.error:
    mov eax, 0x0FFFFFFF             ; return EOF
    stc
.done:
    pop es
    pop edx
    pop ecx
    pop ebx
    ret

; =============================================================================
; Variables and Strings
; =============================================================================
align 4
partition_start:      dd 0
gpt_entries_lba:      dd 0
gpt_num_entries:      dd 0
fat_start:            dd 0
data_start:           dd 0
fat_size:             dd 0
num_fats:             db 0
reserved_sectors:     dw 0
sec_per_clus:         db 0
root_cluster:         dd 0
kernel_start_cluster: dd 0

filename_kernel:      db "KERNEL  ULF" ; 11 chars in 8.3 format

msg_fs_init:          db "FS Init... ", 0
msg_fat_found:        db "FAT32 partition found at LBA: ", 0
msg_loading_kernel:   db "Loading KERNEL.ULF... ", 0

align 4
fs_dap_packet:
    db 0x10                         ; packet size = 16 bytes
    db 0x00                         ; reserved = 0
    dw 1                            ; number of sectors to read = 1
fs_dap_offset:
    dw 0                            ; destination offset
fs_dap_segment:
    dw 0                            ; destination segment
fs_dap_lba:
    dq 0                            ; starting LBA (8 bytes)

%endif ; FS16_ASM
