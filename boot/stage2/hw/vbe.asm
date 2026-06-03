; =============================================================================
; Tattva OS — boot/stage2/hw/vbe.asm
; =============================================================================
; VESA BIOS Extensions (VBE) initialization.
; Queries and sets a high-resolution linear framebuffer (LFB) mode.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef VBE_ASM
%define VBE_ASM

[BITS 16]

vbe_init:
    pusha                           ; save all general purpose registers
    push es
    push ds

    ; set DS and ES to 0 for local data access
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; -------------------------------------------------------------------------
    ; Step 1: Query VBE Controller Info
    ; -------------------------------------------------------------------------
    mov si, msg_vbe_init
    call uart_print

    mov di, vbe_info_block
    mov ax, 0x4F00
    int 0x10
    cmp ax, 0x004F
    jne .vbe_failed

    ; Check signature "VESA"
    mov eax, [vbe_info_block]
    cmp eax, 0x41534556             ; "VESA" in little-endian ASCII
    jne .vbe_failed

    ; Check version >= 2.0 (needed for Linear Frame Buffer)
    mov ax, [vbe_info_block + 4]
    cmp ax, 0x0200
    jb .vbe_failed

    ; -------------------------------------------------------------------------
    ; Step 1.5: Query EDID to get native resolution
    ; -------------------------------------------------------------------------
    mov di, vbe_mode_info           ; temporary buffer
    mov ax, 0x4F15                  ; VBE Read EDID
    mov bx, 0x0001                  ; read EDID block
    xor cx, cx                      ; controller 0
    xor dx, dx                      ; block 0
    int 0x10
    cmp ax, 0x004F
    jne .no_edid

    ; Parse horizontal active pixels from detailed timing descriptor
    ; DTD starts at EDID offset 54. Layout:
    ;   +0,+1: pixel clock (skip)
    ;   +2: H active low 8 bits
    ;   +3: H blanking low 8 bits
    ;   +4: H active high (bits 7-4) | H blanking high (bits 3-0)
    xor ax, ax
    mov al, [vbe_mode_info + 56]    ; DTD+2: H active low 8 bits
    mov cl, [vbe_mode_info + 58]    ; DTD+4: H active high nibble
    shr cl, 4
    and cx, 0x0F
    shl cx, 8
    or ax, cx
    mov [edid_width], ax

    ; Parse vertical active pixels
    ;   +5: V active low 8 bits
    ;   +6: V blanking low 8 bits
    ;   +7: V active high (bits 7-4) | V blanking high (bits 3-0)
    xor ax, ax
    mov al, [vbe_mode_info + 59]    ; DTD+5: V active low 8 bits
    mov cl, [vbe_mode_info + 61]    ; DTD+7: V active high nibble
    shr cl, 4
    and cx, 0x0F
    shl cx, 8
    or ax, cx
    mov [edid_height], ax
    jmp .edid_done

.no_edid:
    mov word [edid_width], 0
    mov word [edid_height], 0

.edid_done:

    ; -------------------------------------------------------------------------
    ; Step 2: Loop through modes and find the best one
    ; -------------------------------------------------------------------------
    ; VideoModePtr is at offset 14 (far pointer: offset, segment)
    mov si, [vbe_info_block + 14]
    mov ax, [vbe_info_block + 16]
    mov fs, ax                      ; FS:SI points to mode list

.find_mode_loop:
    mov cx, [fs:si]                 ; read mode number
    cmp cx, 0xFFFF                  ; end of list?
    je .loop_done

    push fs
    push si

    ; Query mode details
    mov di, vbe_mode_info
    mov ax, 0x4F01
    int 0x10

    pop si
    pop fs

    cmp ax, 0x004F
    jne .next_mode

    ; Verify attributes:
    ; Bit 0: supported by hardware
    ; Bit 3: color
    ; Bit 4: graphics
    ; Bit 7: linear frame buffer
    mov ax, [vbe_mode_info]
    and ax, 0x0099
    cmp ax, 0x0099
    jne .next_mode

    ; Extract mode info
    mov dx, [vbe_mode_info + 18]    ; width
    mov bx, [vbe_mode_info + 20]    ; height
    mov al, [vbe_mode_info + 25]    ; bpp

    call vbe_score_mode
    cmp ah, 0
    jz .next_mode

    cmp ah, [best_score]
    jbe .next_mode

    ; Save best mode details
    mov [best_score], ah
    mov [best_mode], cx
    mov [best_width], dx
    mov [best_height], bx
    mov [best_bpp], al
    mov dx, [vbe_mode_info + 16]
    mov [best_pitch], dx
    mov eax, [vbe_mode_info + 40]
    mov [best_fb_addr], eax

.next_mode:
    add si, 2
    jmp .find_mode_loop

.loop_done:
    ; Check if we found any mode
    cmp byte [best_score], 0
    je .vbe_failed

    ; -------------------------------------------------------------------------
    ; Step 3: Set VBE Mode
    ; -------------------------------------------------------------------------
    mov cx, [best_mode]
    or cx, 0x4000                   ; enable Linear Frame Buffer (LFB)
    mov bx, cx
    mov ax, 0x4F02
    int 0x10
    cmp ax, 0x004F
    jne .vbe_failed

    ; Print success
    mov si, msg_vbe_ok
    call uart_print
    
    ; Print mode details: e.g. "1024x768x32"
    xor eax, eax
    mov ax, [best_width]
    call uart_print_dec
    mov al, 'x'
    call uart_putc
    xor eax, eax
    mov ax, [best_height]
    call uart_print_dec
    mov al, 'x'
    call uart_putc
    xor eax, eax
    mov al, [best_bpp]
    call uart_print_dec
    mov si, msg_crlf_vbe
    call uart_println
    jmp .vbe_done

.vbe_failed:
    ; VBE failed or not supported, fall back to text mode
    mov si, msg_vbe_fail
    call uart_println

.vbe_done:
    pop ds
    pop es
    popa
    ret

; =============================================================================
; vbe_score_mode — score a mode based on resolution/bpp
; Input:  DX = width, BX = height, AL = bpp
; Output: AH = score (0 = unsupported, 1-6 = preference level)
; =============================================================================
vbe_score_mode:
    xor ah, ah                      ; default: 0
    
    ; Check if EDID values are valid
    mov cx, [rel edid_width]
    test cx, cx
    jz .static_score
    mov si, [rel edid_height]
    test si, si
    jz .static_score

    ; Check if matches EDID native resolution
    cmp dx, cx
    jne .static_score
    cmp bx, si
    jne .static_score

    ; Match! High priority score
    cmp al, 32
    je .score_edid_32
    cmp al, 24
    je .score_edid_24
    mov ah, 7                       ; 16-bit EDID mode
    ret
.score_edid_32:
    mov ah, 9
    ret
.score_edid_24:
    mov ah, 8
    ret

.static_score:
    cmp dx, 1024
    jne .score_800
    cmp bx, 768
    jne .score_800
    cmp al, 32
    je .score_1024_32
    cmp al, 24
    je .score_1024_24
    ret
.score_1024_32:
    mov ah, 6
    ret
.score_1024_24:
    mov ah, 5
    ret

.score_800:
    cmp dx, 800
    jne .score_640
    cmp bx, 600
    jne .score_640
    cmp al, 32
    je .score_800_32
    cmp al, 24
    je .score_800_24
    ret
.score_800_32:
    mov ah, 4
    ret
.score_800_24:
    mov ah, 3
    ret

.score_640:
    cmp dx, 640
    jne .score_done
    cmp bx, 480
    jne .score_done
    cmp al, 32
    je .score_640_32
    cmp al, 24
    je .score_640_24
.score_done:
    ret
.score_640_32:
    mov ah, 2
    ret
.score_640_24:
    mov ah, 1
    ret

; =============================================================================
; Data
; =============================================================================
msg_vbe_init:   db "VBE...     ", 0
msg_vbe_ok:     db "OK ", 0
msg_vbe_fail:   db "FAIL (using text mode)", 0
msg_crlf_vbe:   db 0

; VBE state variables
best_score:     db 0
best_mode:      dw 0
best_width:     dw 0
best_height:    dw 0
best_bpp:       db 0
best_pitch:     dw 0
best_fb_addr:   dd 0

edid_width:     dw 0
edid_height:    dw 0

align 16
vbe_info_block:
    db "VESA"                       ; request VBE 2.0+
    times 508 db 0

align 16
vbe_mode_info:
    times 256 db 0

%endif ; VBE_ASM
