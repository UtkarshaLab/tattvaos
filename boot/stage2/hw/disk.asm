; =============================================================================
; Tattva OS — boot/stage2/hw/disk.asm
; =============================================================================
; Query and manage BIOS disk drive parameters.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef HW_DISK_ASM
%define HW_DISK_ASM

[BITS 16]

; =============================================================================
; disk_get_geometry — query BIOS for boot drive CHS geometry
; Input:  [boot_drive]
; Output: [sectors_per_track] and [number_of_heads] updated in memory
; Clobbers: none (all registers preserved)
; =============================================================================
disk_get_geometry:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    ; 1. Clear ES:DI (guards against BIOS bugs)
    xor ax, ax
    mov es, ax
    xor di, di

    ; 2. Call INT 13h AH=08h
    mov ah, 0x08
    mov dl, [boot_drive]
    int 0x13
    jc .done                         ; if carry set, query failed, keep defaults

    ; 3. Extract sectors per track
    ; CL bits 0-5 = sectors per track (1-indexed)
    and cx, 0x003F                   ; CX = sectors per track
    test cx, cx
    jz .done                         ; invalid sectors per track, keep defaults
    mov [sectors_per_track], cx

    ; 4. Extract number of heads
    ; DH = maximum head number (0-indexed)
    xor ax, ax
    mov al, dh
    inc ax                           ; AX = number of heads (DH + 1)
    mov [number_of_heads], ax

.done:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Disk geometry variables (for CHS fallback)
align 2
sectors_per_track:  dw 18             ; default to 1.44MB floppy geometry
number_of_heads:    dw 2              ; default to 1.44MB floppy geometry

; =============================================================================
; disk_query_edd — Query Extended Drive Parameters (EDD)
; Input:  none
; Output: none
; =============================================================================
disk_query_edd:
    push ax
    push dx
    push si
    push ds

    xor ax, ax
    mov ds, ax
    mov si, edd_params_block
    mov word [si], 74                ; buffer size = 74 bytes (EDD 3.0)
    mov word [si + 30], 0            ; clear key

    mov ah, 0x48                     ; INT 13h AH=48h
    mov dl, [boot_drive]
    int 0x13
    jc .done

    mov byte [edd_supported], 1

.done:
    pop ds
    pop si
    pop dx
    pop ax
    ret

edd_supported:     db 0
align 4
edd_params_block:  times 74 db 0

%endif ; HW_DISK_ASM
