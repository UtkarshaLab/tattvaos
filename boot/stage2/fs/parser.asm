; =============================================================================
; Tattva OS — boot/stage2/fs/parser.asm
; =============================================================================
; Simple boot configuration file (tattva.cfg) text parser.
; Reads kernel, fallback, and initrd filenames from the config file.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef PARSER_ASM
%define PARSER_ASM

[BITS 16]

; =============================================================================
; config_parse — Parse tattva.cfg content loaded in memory
; Input:  FS = segment of text buffer (e.g. 0x3000)
;         SI = offset within segment (e.g. 0)
;         CX = text buffer length
; =============================================================================
config_parse:
    pusha
    push ds
    push es

    ; DS = ES = 0 for accessing key strings and output variables
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov [cfg_buffer_off], si
    mov [cfg_buffer_len], cx

    xor di, di                      ; DI = current offset in buffer
.line_loop:
    mov cx, [cfg_buffer_len]
    cmp di, cx
    jae .done

    ; Read current character from FS:buffer_off+DI
    mov si, [cfg_buffer_off]
    add si, di
    mov al, [fs:si]
    cmp al, 0x0A                    ; newline
    je .next_char
    cmp al, 0x0D                    ; carriage return
    je .next_char
    cmp al, ' '                     ; space
    je .next_char
    cmp al, '#'                     ; comment
    je .skip_comment

    ; Check if line matches "kernel="
    lea dx, [key_kernel]
    call config_match_key
    jc .not_kernel
    add di, 7                       ; len("kernel=")
    
    lea bx, [config_kernel_name]
    call config_extract_value
    add di, ax                      ; advance offset
    jmp .line_loop

.not_kernel:
    ; Check if line matches "fallback="
    lea dx, [key_fallback]
    call config_match_key
    jc .not_fallback
    add di, 9                       ; len("fallback=")
    
    lea bx, [config_fallback_name]
    call config_extract_value
    add di, ax
    jmp .line_loop

.not_fallback:
    ; Check if line matches "initrd="
    lea dx, [key_initrd]
    call config_match_key
    jc .next_char
    add di, 7                       ; len("initrd=")
    
    lea bx, [config_initrd_name]
    call config_extract_value
    add di, ax
    jmp .line_loop

.skip_comment:
    ; Skip to next newline
    mov si, [cfg_buffer_off]
    add si, di
    mov al, [fs:si]
    cmp al, 0x0A
    je .next_char
    cmp al, 0x0D
    je .next_char
    inc di
    mov cx, [cfg_buffer_len]
    cmp di, cx
    jb .skip_comment
    jmp .done

.next_char:
    inc di
    jmp .line_loop

.done:
    pop es
    pop ds
    popa
    ret

; =============================================================================
; config_match_key — Compare buffer at current offset with key in DX
; Input:  DI = current offset in buffer
;         DX = pointer to key string (null-terminated, in DS=0 space)
; Output: CF clear if match, set if mismatch
; Uses FS:buffer_off+DI to read buffer data
; =============================================================================
config_match_key:
    push si
    push bx
    push di
    mov si, dx                      ; SI = key pointer (DS=0)
    mov bx, [cfg_buffer_off]
    add bx, di                      ; BX = buffer offset for FS segment
.cmp_loop:
    mov al, [si]                    ; read key char (from DS=0)
    test al, al                     ; end of key?
    jz .match
    mov ah, [fs:bx]                 ; read buffer char (from FS segment)
    cmp al, ah
    jne .mismatch
    inc si
    inc bx
    jmp .cmp_loop
.mismatch:
    stc
    jmp .exit
.match:
    clc
.exit:
    pop di
    pop bx
    pop si
    ret

; =============================================================================
; config_extract_value — Copy value from FS buffer to destination in DS=0
; Input:  DI = current offset in buffer (after key=)
;         BX = destination buffer pointer (DS=0 space)
; Output: AX = count of bytes copied
; Uses FS:buffer_off+DI as source
; =============================================================================
config_extract_value:
    push si
    push di
    push bx
    push cx

    mov si, [cfg_buffer_off]
    add si, di                      ; SI = source offset in FS segment
    xor cx, cx                      ; CX = count

.copy_loop:
    mov al, [fs:si]                 ; read from buffer (FS segment)
    cmp al, 0x0A
    je .copy_done
    cmp al, 0x0D
    je .copy_done
    cmp al, ' '
    je .copy_done
    cmp al, '#'
    je .copy_done
    test al, al
    jz .copy_done

    mov [bx], al                    ; write to destination (DS=0)
    inc si
    inc bx
    inc cx
    jmp .copy_loop

.copy_done:
    mov byte [bx], 0                ; null terminator
    mov ax, cx                      ; return count

    pop cx
    pop bx
    pop di
    pop si
    ret

; Variables
cfg_buffer_off:     dw 0
cfg_buffer_len:     dw 0

key_kernel:         db "kernel=", 0
key_fallback:       db "fallback=", 0
key_initrd:         db "initrd=", 0

; Extracted config names
config_kernel_name:   times 32 db 0
config_fallback_name: times 32 db 0
config_initrd_name:   times 32 db 0

%endif ; PARSER_ASM
