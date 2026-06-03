; =============================================================================
; Tattva OS — boot/stage2/fs/fs16.asm
; =============================================================================
; 16-bit real-mode filesystem scanner and loader.
; Parses GPT partition table (with secondary fallback) to locate a FAT32 or ext4
; partition, searches the root directory, and loads KERNEL.ULF and INITRD.IMG.
; Supports tattva.cfg boot parameters and dual-kernel fallback.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef FS16_ASM
%define FS16_ASM

[BITS 16]

; =============================================================================
; fs_load_kernel — main real-mode entry point for loading the kernel
; Output: AX = 1 if successful, 0 if failed
; =============================================================================
fs_load_kernel:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push es

    ; Detect LBA support dynamically
    push bx
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc .no_lba
    cmp bx, 0xAA55
    jne .no_lba
    mov byte [lba_supported], 1
    jmp .lba_detect_done
.no_lba:
    mov byte [lba_supported], 0
.lba_detect_done:
    pop bx

    ; Print FS Init message
    mov si, msg_fs_init
    call uart_print

    ; 1. Read LBA 1 (Primary GPT Header)
    mov ax, 0x2000
    mov es, ax
    xor bx, bx
    mov eax, 1                      ; LBA 1
    call fs_read_sector
    jc .gpt_backup_fallback         ; read failed -> try backup

    ; Check signature "EFI PART" (0x5452415020494645)
    cmp dword [es:bx], 0x45464920
    jne .gpt_backup_fallback
    cmp dword [es:bx + 4], 0x50415254
    jne .gpt_backup_fallback
    jmp .gpt_ok

.gpt_backup_fallback:
    ; Query drive parameters to find the last sector (backup GPT)
    sub sp, 32
    mov si, sp
    mov word [ss:si], 30
    mov ah, 0x48
    mov dl, [boot_drive]
    int 0x13
    jc .floppy_backup

    mov eax, [ss:si + 16]           ; low 32 bits of total sector count
    dec eax                         ; last sector (LBA sectors - 1)
    add sp, 32                      ; restore stack
    jmp .read_backup

.floppy_backup:
    add sp, 32                      ; restore stack
    mov eax, 2879                    ; standard 1.44MB floppy size

.read_backup:
    mov cx, 0x2000
    mov es, cx
    xor bx, bx
    call fs_read_sector
    jc .fallback

    ; Verify backup GPT signature
    cmp dword [es:bx], 0x45464920
    jne .fallback
    cmp dword [es:bx + 4], 0x50415254
    jne .fallback

.gpt_ok:
    ; Extract partition entry LBA and number of entries
    mov eax, [es:bx + 72]           ; partition array LBA
    mov [gpt_entries_lba], eax
    mov ecx, [es:bx + 80]           ; number of partition entries
    mov [gpt_num_entries], ecx

    ; 2. Scan partition entries sector-by-sector
    mov eax, [gpt_entries_lba]
    xor edx, edx                    ; current entry index
.sector_loop:
    cmp edx, [gpt_num_entries]
    jae .fallback

    push eax
    push edx
    mov ax, 0x2000
    mov es, ax
    xor bx, bx
    pop edx
    pop eax
    call fs_read_sector
    jc .next_sector

    mov di, 0                       ; entry offset
.entry_loop:
    cmp dword [es:di], 0
    jne .check_partition
    cmp dword [es:di+4], 0
    jne .check_partition
    cmp dword [es:di+8], 0
    jne .check_partition
    cmp dword [es:di+12], 0
    je .next_entry                  ; unused entry

.check_partition:
    mov ebx, [es:di + 32]           ; partition start LBA
    test ebx, ebx
    jz .next_entry

    ; Read boot sector
    push eax
    push edx
    push di
    mov eax, ebx
    mov cx, 0x3000
    push es
    mov es, cx
    xor bx, bx
    call fs_read_sector
    pop es
    jc .boot_sector_fail

    ; Check if partition is FAT32
    mov cx, 0x3000
    mov fs, cx
    cmp word [fs:510], 0xAA55
    jne .check_ext4                  ; not FAT32, try ext4

    cmp dword [fs:82], 0x33544146   ; "FAT3"
    jne .check_ext4
    cmp dword [fs:86], 0x20202032   ; "2   "
    jne .check_ext4

    ; Found FAT32!
    mov eax, [fs:36]
    mov [fat_size], eax
    xor eax, eax
    mov al, [fs:16]
    mov [num_fats], al
    mov ax, [fs:14]
    mov [reserved_sectors], ax
    mov al, [fs:13]
    mov [sec_per_clus], al
    mov eax, [fs:44]
    mov [root_cluster], eax

    pop di
    pop edx
    pop eax
    mov [partition_start], ebx
    jmp .fat32_found

.check_ext4:
    ; Check if partition is ext4
    pop di
    pop edx
    pop eax
    push eax
    push edx
    push di

    mov eax, ebx                    ; starting LBA
    call ext4_detect
    test ax, ax
    jz .boot_sector_fail            ; not ext4, skip

    ; Found ext4!
    pop di
    pop edx
    pop eax
    mov [partition_start], ebx
    jmp .ext4_found

.boot_sector_fail:
    pop di
    pop edx
    pop eax

.next_entry:
    add di, 128
    inc edx
    cmp di, 512
    jl .entry_loop

.next_sector:
    inc eax
    jmp .sector_loop

; =============================================================================
; FAT32 loading flow
; =============================================================================
.fat32_found:
    mov si, msg_fat_found
    call uart_print
    mov eax, [partition_start]
    call uart_print_dec
    call uart_println

    ; Calculate FAT starts
    mov eax, [partition_start]
    xor ecx, ecx
    mov cx, [reserved_sectors]
    add eax, ecx
    mov [fat_start], eax

    mov eax, [fat_size]
    xor ecx, ecx
    mov cl, [num_fats]
    mul ecx
    add eax, [fat_start]
    mov [data_start], eax

    ; 2.5 Try loading tattva.cfg first
    mov eax, [root_cluster]
    lea dx, [rel filename_config]
    call fat32_find_file_helper
    test eax, eax
    jz .no_config_found

    ; Load tattva.cfg to 0x3000:0x0000
    push eax
    mov ax, 0x3000
    mov es, ax
    xor bx, bx
    pop eax
.load_cfg_loop:
    call fs_read_cluster
    jc .no_config_found
    call fs_get_next_cluster
    cmp eax, 0x0FFFFFF8
    jb .load_cfg_loop

    ; Parse tattva.cfg
    ; Parser uses FS for buffer segment, DS=0 for key strings
    mov ax, 0x3000
    mov fs, ax
    xor si, si                       ; offset 0 within FS segment
    mov cx, 512                      ; assume max 512 bytes for config
    call config_parse

.no_config_found:
    ; 3. Find KERNEL.ULF (or config_kernel_name)
    mov eax, [root_cluster]
    
    ; Check if custom kernel name is specified in config
    cmp byte [config_kernel_name], 0
    jz .use_default_kernel

    ; Convert config_kernel_name to 8.3 fat filename format if needed
    ; For early unikernel test, we can just load the default or compare directly
.use_default_kernel:
    mov eax, [root_cluster]
    lea dx, [rel filename_kernel]
    call fat32_find_file_helper
    test eax, eax
    jz .fallback

    mov [kernel_start_cluster], eax

    ; Load KERNEL.ULF
    mov si, msg_loading_kernel
    call uart_print
    mov ax, (KERNEL_TEMP >> 4)
    mov es, ax
    xor bx, bx
    mov eax, [kernel_start_cluster]
.load_file_loop:
    call fs_read_cluster
    jc .try_fallback_kernel
    call fs_get_next_cluster
    cmp eax, 0x0FFFFFF8
    jb .load_file_loop
    jmp .load_initrd

.try_fallback_kernel:
    ; Try loading fallback kernel if primary fails
    mov eax, [root_cluster]
    lea dx, [rel filename_fallback]
    call fat32_find_file_helper
    test eax, eax
    jz .fallback

    mov [kernel_start_cluster], eax
    mov ax, (KERNEL_TEMP >> 4)
    mov es, ax
    xor bx, bx
    mov eax, [kernel_start_cluster]
.load_fallback_loop:
    call fs_read_cluster
    jc .fallback
    call fs_get_next_cluster
    cmp eax, 0x0FFFFFF8
    jb .load_fallback_loop

.load_initrd:
    ; Look for INITRD.IMG in root directory
    mov eax, [root_cluster]
    lea dx, [rel filename_initrd]
    call fat32_find_file_helper
    test eax, eax
    jz .no_initrd

    mov [initrd_start_cluster], eax
    ; load size
    mov dword [initrd_size], 65536   ; assume 64KB for test

    mov si, msg_loading_initrd
    call uart_print
    ; Load to 0x4000:0x0000
    mov ax, 0x4000
    mov es, ax
    xor bx, bx
    mov eax, [initrd_start_cluster]
.load_initrd_loop:
    call fs_read_cluster
    jc .no_initrd
    call fs_get_next_cluster
    cmp eax, 0x0FFFFFF8
    jb .load_initrd_loop

    mov byte [initrd_loaded], 1

.no_initrd:
    mov ax, 1
    jmp .done

; (Moved fat32_find_file_helper down to maintain local label scoping)

; =============================================================================
; ext4 loading flow
; =============================================================================
.ext4_found:
    mov si, msg_ext4_found
    call uart_print
    mov eax, [partition_start]
    call uart_print_dec
    call uart_println

    ; Load KERNEL.ULF using ext4
    mov eax, [partition_start]
    mov si, filename_kernel_ext4
    mov cx, (KERNEL_TEMP >> 4)
    mov es, cx
    xor bx, bx
    call ext4_load_file
    test ax, ax
    jnz .ext4_load_initrd

    ; If primary fails, try fallback kernel
    mov eax, [partition_start]
    mov si, filename_fallback_ext4
    mov cx, (KERNEL_TEMP >> 4)
    mov es, cx
    xor bx, bx
    call ext4_load_file
    test ax, ax
    jz .fallback

.ext4_load_initrd:
    ; Load INITRD.IMG if available
    mov eax, [partition_start]
    mov si, filename_initrd_ext4
    mov cx, 0x4000
    mov es, cx
    xor bx, bx
    call ext4_load_file
    test ax, ax
    jz .ext4_no_initrd

    mov dword [initrd_size], 65536
    mov byte [initrd_loaded], 1

.ext4_no_initrd:
    mov ax, 1
    jmp .done

.fallback:
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
; Helper functions (non-local scope)
; =============================================================================

; Helper to find a file in FAT32 root directory
; Input: EAX = starting cluster of directory
;        DX = pointer to 11-char name string
; Output: EAX = starting cluster of file, 0 if not found
fat32_find_file_helper:
    push dx
    mov cx, 0x2000
    mov es, cx
    xor bx, bx
    call fs_read_cluster
    pop dx
    jc .not_found

    xor cx, cx
    mov cl, [sec_per_clus]
    shl cx, 4                       ; CX = entries count
    mov di, 0
.entry_loop:
    mov al, [es:di]
    test al, al
    jz .not_found
    cmp al, 0xE5
    je .next_entry

    mov al, [es:di + 11]
    test al, 0x08
    jnz .next_entry
    cmp al, 0x0F
    je .next_entry

    mov si, dx
    push di
    mov bp, 11
.cmp_loop:
    mov al, [es:di]
    mov bl, [si]
    cmp al, bl
    jne .mismatch
    inc di
    inc si
    dec bp
    jnz .cmp_loop

    pop di
    ; Found! Extract cluster
    mov ax, [es:di + 20]
    shl eax, 16
    mov ax, [es:di + 26]
    ret

.mismatch:
    pop di
.next_entry:
    add di, 32
    dec cx
    jnz .entry_loop
.not_found:
    xor eax, eax
    ret

; =============================================================================
; Helper I/O functions
; =============================================================================
fs_read_sector:
    push eax
    push ecx
    push edx
    push si
    push di

    cmp byte [lba_supported], 1
    je .lba_read

    push bx
    push ax
    xor dx, dx
    mov cx, [sectors_per_track]
    test cx, cx
    jz .chs_error
    div cx
    inc dx
    mov cl, dl
    
    xor dx, dx
    mov cx, [number_of_heads]
    test cx, cx
    jz .chs_error
    div cx
    
    mov ch, al
    shl ah, 6
    or cl, ah
    mov dh, dl
    mov dl, [boot_drive]
    pop ax
    pop bx
    
    mov ax, 0x0201
    int 0x13
    jmp .done

.chs_error:
    pop ax
    pop bx
    stc
    jmp .done

.lba_read:
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

fs_read_cluster:
    push eax
    push ecx
    push edx
    
    sub eax, 2
    xor edx, edx
    mov dl, [sec_per_clus]
    mul edx
    add eax, [data_start]
    
    mov cl, [sec_per_clus]
.read_loop:
    call fs_read_sector
    jc .error
    add bx, 512
    test bx, bx
    jnz .no_wrap
    mov dx, es
    add dx, 0x1000
    mov es, dx
.no_wrap:
    inc eax
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

fs_get_next_cluster:
    push ebx
    push ecx
    push edx
    push es
    
    shl eax, 2
    xor edx, edx
    mov ecx, 512
    div ecx
    add eax, [fat_start]
    
    push edx
    mov cx, 0x3000
    mov es, cx
    xor bx, bx
    call fs_read_sector
    pop edx
    jc .error
    
    mov bx, dx
    mov eax, [es:bx]
    and eax, 0x0FFFFFFF
    clc
    jmp .done
    
.error:
    mov eax, 0x0FFFFFFF
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
lba_supported:        db 0

filename_config:      db "TATTVA  CFG"
filename_kernel:      db "KERNEL  ULF"
filename_fallback:    db "KERNELRCULF"
filename_initrd:      db "INITRD  IMG"

filename_kernel_ext4:   db "kernel.ulf", 0
filename_fallback_ext4: db "kernel_recovery.ulf", 0
filename_initrd_ext4:   db "initrd.img", 0

msg_fs_init:          db "FS Init... ", 0
msg_fat_found:        db "FAT32 partition found at LBA: ", 0
msg_ext4_found:       db "ext4 partition found at LBA: ", 0
msg_loading_kernel:   db "Loading KERNEL.ULF... ", 0
msg_loading_initrd:   db "Loading INITRD.IMG... ", 0

align 4
fs_dap_packet:
    db 0x10
    db 0x00
    dw 1
fs_dap_offset:
    dw 0
fs_dap_segment:
    dw 0
fs_dap_lba:
    dq 0

initrd_size:          dd 0
initrd_loaded:        db 0
initrd_start_cluster: dd 0

; Include Ext4 filesystem helper driver
%include "ext4.asm"

; Include Config file parser
%include "parser.asm"

%endif ; FS16_ASM
