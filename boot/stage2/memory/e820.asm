; =============================================================================
; Tattva OS — boot/stage2/memory/e820.asm
; =============================================================================
; Complete E820 memory map subsystem.
; One file. All functions. One include in main.asm.
;
; Functions (call in this order):
;   e820_detect   — query BIOS for memory map
;   e820_sort     — sort entries by base address
;   e820_merge    — merge overlapping entries
;   e820_parse    — calculate total usable RAM
;   e820_print    — debug: print all entries via UART
;
; Memory layout at E820_DEST:
;   [E820_DEST + 0]   dw  entry count
;   [E820_DEST + 2]   24-byte entries (up to E820_MAX_ENTRIES)
;
; E820 entry format (24 bytes):
;   Offset  Size  Field
;   0x00    8     base address (64-bit)
;   0x08    8     length in bytes (64-bit)
;   0x10    4     type (1=usable 2=reserved 3=ACPI 4=NVS 5=bad)
;   0x14    4     extended attributes (ACPI 3.0+)
;
; Usage in main.asm:
;   call e820_detect
;   call e820_sort
;   call e820_merge
;   call e820_parse
;   call e820_print    ; debug only, remove in release
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef E820_ASM
%define E820_ASM

; -----------------------------------------------------------------------------
; Constants
; -----------------------------------------------------------------------------
E820_MAGIC          equ 0x534D4150  ; "SMAP" magic for BIOS call
E820_ENTRY_SIZE     equ 24          ; bytes per entry
E820_MAX_ENTRIES    equ 128         ; max entries to store
E820_COUNT_OFF      equ 0           ; offset of count word at E820_DEST
E820_ENTRIES_OFF    equ 2           ; offset of first entry

E820_TYPE_USABLE    equ 1           ; usable RAM
E820_TYPE_RESERVED  equ 2           ; reserved — do not use
E820_TYPE_ACPI_REC  equ 3           ; ACPI reclaimable
E820_TYPE_ACPI_NVS  equ 4           ; ACPI NVS
E820_TYPE_BAD       equ 5           ; bad memory

; temporary buffer for sort swap (one entry)
e820_tmp:           times E820_ENTRY_SIZE db 0

; total usable RAM in MB (filled by e820_parse)
e820_total_mb:      dd 0

; =============================================================================
; e820_detect — query BIOS INT 15h E820 for memory map
; Input:  nothing
; Output: entries stored at E820_DEST, count at [E820_DEST]
; Clobbers: EAX, EBX, ECX, EDX, DI, ES
; =============================================================================
e820_detect:
    push eax
    push ebx
    push ecx
    push edx
    push di
    push es

    ; setup ES:DI → entry storage
    xor ax, ax
    mov es, ax
    mov word [E820_DEST + E820_COUNT_OFF], 0
    mov di, E820_DEST + E820_ENTRIES_OFF

    xor ebx, ebx                    ; EBX=0 for first call

.detect_loop:
    ; check max entries
    mov ax, [E820_DEST + E820_COUNT_OFF]
    cmp ax, E820_MAX_ENTRIES
    jae .detect_done

    ; BIOS call
    mov eax, 0x0000E820
    mov ecx, E820_ENTRY_SIZE
    mov edx, E820_MAGIC
    int 0x15

    jc .detect_done                 ; carry = end of list
    cmp eax, E820_MAGIC
    jne .detect_done                ; bad return value

    ; skip zero-length entries
    cmp dword [es:di + 8], 0
    jne .entry_valid
    cmp dword [es:di + 12], 0
    je .skip_entry

.entry_valid:
    inc word [E820_DEST + E820_COUNT_OFF]
    add di, E820_ENTRY_SIZE

.skip_entry:
    test ebx, ebx                   ; EBX=0 means last entry
    jz .detect_done
    jmp .detect_loop

.detect_done:
    pop es
    pop di
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; e820_sort — sort entries by base address ascending (insertion sort)
; Input:  entries at E820_DEST from e820_detect
; Output: entries sorted in place
; Clobbers: AX, BX, CX, DX, SI, DI
; =============================================================================
e820_sort:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov cx, [E820_DEST + E820_COUNT_OFF]
    cmp cx, 2
    jl .sort_done                   ; 0 or 1 entries already sorted

    mov bx, 1                       ; outer loop: i = 1

.sort_outer:
    cmp bx, cx
    jae .sort_done

    ; copy entry[i] to tmp
    push cx
    push bx
    mov ax, bx
    mov dx, E820_ENTRY_SIZE
    mul dx
    add ax, E820_DEST + E820_ENTRIES_OFF
    mov si, ax
    mov di, e820_tmp
    mov cx, E820_ENTRY_SIZE
    rep movsb
    pop bx
    pop cx

    mov dx, bx                      ; j = i

.sort_inner:
    cmp dx, 0
    je .sort_insert

    ; get address of entry[j-1]
    push cx
    push bx
    push dx
    mov ax, dx
    dec ax
    mov cx, E820_ENTRY_SIZE
    mul cx
    add ax, E820_DEST + E820_ENTRIES_OFF
    mov si, ax

    ; compare entry[j-1].base with tmp.base (64-bit, high dword first)
    mov eax, [si + 4]
    mov ebx, [e820_tmp + 4]
    cmp eax, ebx
    jb .sort_no_swap
    ja .sort_swap

    mov eax, [si + 0]
    mov ebx, [e820_tmp + 0]
    cmp eax, ebx
    jbe .sort_no_swap

.sort_swap:
    ; move entry[j-1] → entry[j]
    pop dx
    push dx
    mov ax, dx
    mov cx, E820_ENTRY_SIZE
    mul cx
    add ax, E820_DEST + E820_ENTRIES_OFF
    mov di, ax
    mov cx, E820_ENTRY_SIZE
    rep movsb

    pop dx
    pop bx
    pop cx
    dec dx
    jmp .sort_inner

.sort_no_swap:
    pop dx
    pop bx
    pop cx

.sort_insert:
    ; write tmp → entry[j]
    mov ax, dx
    mov cx, E820_ENTRY_SIZE
    mul cx
    add ax, E820_DEST + E820_ENTRIES_OFF
    mov di, ax
    mov si, e820_tmp
    mov cx, E820_ENTRY_SIZE
    rep movsb

    inc bx
    jmp .sort_outer

.sort_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =============================================================================
; e820_merge — merge overlapping/adjacent entries
; Reserved always beats usable in overlaps.
; Must be called after e820_sort.
; Input:  sorted entries at E820_DEST
; Output: merged entries in place, count updated
; Clobbers: EAX, EBX, ECX, EDX, SI, DI
; =============================================================================
e820_merge:
    push eax
    push ebx
    push ecx
    push edx
    push si
    push di

    mov cx, [E820_DEST + E820_COUNT_OFF]
    cmp cx, 2
    jl .merge_done

    mov bx, 0                       ; write pointer i
    mov dx, 1                       ; read pointer j

.merge_loop:
    cmp dx, cx
    jae .merge_finalize

    ; SI = &entry[i]
    push cx
    push bx
    push dx
    mov ax, bx
    mov cx, E820_ENTRY_SIZE
    mul cx
    add ax, E820_DEST + E820_ENTRIES_OFF
    mov si, ax

    ; DI = &entry[j]
    mov ax, dx
    mov cx, E820_ENTRY_SIZE
    mul cx
    add ax, E820_DEST + E820_ENTRIES_OFF
    mov di, ax

    ; end[i] = base[i] + length[i]
    mov eax, [si + 0]
    mov ebx, [si + 4]
    add eax, [si + 8]
    adc ebx, [si + 12]
    ; EBX:EAX = end[i]

    ; compare end[i] with base[j]
    mov ecx, [di + 4]               ; base[j] high
    mov edx, [di + 0]               ; base[j] low

    cmp ebx, ecx
    jb .merge_no_overlap
    ja .merge_overlap
    cmp eax, edx
    jb .merge_no_overlap

.merge_overlap:
    ; non-usable type wins
    mov ecx, [si + 16]              ; type[i]
    mov edx, [di + 16]              ; type[j]
    cmp ecx, E820_TYPE_USABLE
    jne .merge_extend               ; i is reserved, keep its type
    cmp edx, E820_TYPE_USABLE
    je .merge_extend                ; both usable, just extend
    mov [si + 16], edx              ; j is reserved, use j's type

.merge_extend:
    ; end[j] = base[j] + length[j]
    mov ecx, [di + 0]
    mov edx, [di + 4]
    add ecx, [di + 8]
    adc edx, [di + 12]
    ; EDX:ECX = end[j]

    ; new end = max(end[i], end[j])
    cmp ebx, edx
    ja .use_end_i
    jb .use_end_j
    cmp eax, ecx
    jae .use_end_i

.use_end_j:
    mov eax, ecx
    mov ebx, edx

.use_end_i:
    ; new length = new_end - base[i]
    sub eax, [si + 0]
    sbb ebx, [si + 4]
    mov [si + 8], eax
    mov [si + 12], ebx

    pop dx
    pop bx
    pop cx
    inc dx
    jmp .merge_loop

.merge_no_overlap:
    pop dx
    pop bx
    pop cx
    inc bx

    ; copy entry[j] to entry[bx] if not already there
    mov ax, bx
    mov cx, E820_ENTRY_SIZE
    mul cx
    add ax, E820_DEST + E820_ENTRIES_OFF
    mov di, ax

    mov ax, dx
    mov cx, E820_ENTRY_SIZE
    mul cx
    add ax, E820_DEST + E820_ENTRIES_OFF
    mov si, ax

    mov cx, E820_ENTRY_SIZE
    rep movsb

    inc dx
    jmp .merge_loop

.merge_finalize:
    inc bx
    mov [E820_DEST + E820_COUNT_OFF], bx

.merge_done:
    pop di
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; e820_parse — calculate total usable RAM in MB
; Input:  merged entries at E820_DEST
; Output: [e820_total_mb] = total usable MB
; Clobbers: EAX, EBX, ECX, EDX, SI
; =============================================================================
e820_parse:
    push eax
    push ebx
    push ecx
    push edx
    push si

    mov dword [e820_total_mb], 0

    mov cx, [E820_DEST + E820_COUNT_OFF]
    test cx, cx
    jz .parse_done

    mov si, E820_DEST + E820_ENTRIES_OFF

.parse_loop:
    ; only count usable entries
    mov eax, [si + 16]
    cmp eax, E820_TYPE_USABLE
    jne .parse_next

    ; convert length bytes → MB (shift right 20)
    mov eax, [si + 8]               ; length low
    mov ebx, [si + 12]              ; length high
    shrd eax, ebx, 20
    shr ebx, 20
    add [e820_total_mb], eax        ; accumulate MB

.parse_next:
    add si, E820_ENTRY_SIZE
    dec cx
    jnz .parse_loop

.parse_done:
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; e820_print — debug: print all entries via UART
; Remove call in release build.
; Input:  entries at E820_DEST
; Output: prints table to UART
; =============================================================================
e820_print:
    push ax
    push cx
    push si

    mov si, msg_e820_header
    call uart_println

    mov cx, [E820_DEST + E820_COUNT_OFF]
    test cx, cx
    jz .print_empty

    mov si, E820_DEST + E820_ENTRIES_OFF

.print_loop:
    push cx
    push si

    ; print base address
    mov ax, msg_e820_base
    push ax
    mov si, ax
    call uart_print
    mov eax, [si + 4]               ; base high — reuse si? no, fix:
    pop ax

    ; print base low dword
    push si
    mov si, msg_e820_base
    call uart_print
    pop si
    mov eax, [si + 0]               ; base low
    call uart_print_hex32

    ; print length
    push si
    mov si, msg_e820_len
    call uart_print
    pop si
    mov eax, [si + 8]               ; length low
    call uart_print_hex32

    ; print type
    push si
    mov si, msg_e820_type
    call uart_print
    pop si
    mov eax, [si + 16]
    call uart_print_dec

    ; print type name
    mov eax, [si + 16]
    cmp eax, E820_TYPE_USABLE
    je .type_usable
    cmp eax, E820_TYPE_RESERVED
    je .type_reserved
    cmp eax, E820_TYPE_ACPI_REC
    je .type_acpi
    cmp eax, E820_TYPE_ACPI_NVS
    je .type_nvs
    mov si, msg_type_bad
    jmp .print_type
.type_usable:   mov si, msg_type_usable  ; jmp .print_type
    jmp .print_type
.type_reserved: mov si, msg_type_reserved
    jmp .print_type
.type_acpi:     mov si, msg_type_acpi
    jmp .print_type
.type_nvs:      mov si, msg_type_nvs

.print_type:
    call uart_println

    pop si
    pop cx
    add si, E820_ENTRY_SIZE
    dec cx
    jnz .print_loop

    ; print total usable RAM
    mov si, msg_e820_total
    call uart_print
    mov eax, [e820_total_mb]
    call uart_print_dec
    mov si, msg_mb
    call uart_println
    jmp .print_done

.print_empty:
    mov si, msg_e820_none
    call uart_println

.print_done:
    pop si
    pop cx
    pop ax
    ret

; =============================================================================
; Strings
; =============================================================================
msg_e820_header:    db "Memory map (E820):", 0
msg_e820_base:      db "  base=", 0
msg_e820_len:       db " len=", 0
msg_e820_type:      db " type=", 0
msg_e820_total:     db "  Total usable: ", 0
msg_e820_none:      db "  No entries found", 0
msg_mb:             db " MB", 0
msg_type_usable:    db " (usable)", 0
msg_type_reserved:  db " (reserved)", 0
msg_type_acpi:      db " (ACPI reclaimable)", 0
msg_type_nvs:       db " (ACPI NVS)", 0
msg_type_bad:       db " (bad)", 0

%endif ; E820_ASM