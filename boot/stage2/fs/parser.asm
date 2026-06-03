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
; Input:  RSI = pointer to text buffer
;         CX = text buffer length
; =============================================================================
config_parse:
    pusha
    push ds
    push es

    xor ax, ax
    mov ds, ax
    mov es, ax

    mov [cfg_buffer_ptr], si
    mov [cfg_buffer_len], cx

    xor di, di                      ; DI = current offset in buffer
.line_loop:
    mov cx, [cfg_buffer_len]
    cmp di, cx
    jae .done

    ; Skip leading whitespace/newlines
    mov si, [cfg_buffer_ptr]
    add si, di
    mov al, [si]
    cmp al, 0x0A                    ; newline
    je .next_char
    cmp al, 0x0D                    ; carriage return
    je .next_char
    cmp al, ' '                     ; space
    je .next_char
    cmp al, '#'                     ; comment
    je .skip_comment

    ; Check if line matches "kernel="
    lea dx, [rel key_kernel]
    call config_match_key
    jc .not_kernel
    add di, 7                       ; len("kernel=")
    
    mov si, [cfg_buffer_ptr]
    add si, di
    lea bx, [rel config_kernel_name]
    push di
    mov di, bx
    call config_copy_value
    pop di
    add di, ax                      ; advance offset
    jmp .line_loop

.not_kernel:
    ; Check if line matches "fallback="
    lea dx, [rel key_fallback]
    call config_match_key
    jc .not_fallback
    add di, 9                       ; len("fallback=")
    
    mov si, [cfg_buffer_ptr]
    add si, di
    lea bx, [rel config_fallback_name]
    push di
    mov di, bx
    call config_copy_value
    pop di
    add di, ax
    jmp .line_loop

.not_fallback:
    ; Check if line matches "initrd="
    lea dx, [rel key_initrd]
    call config_match_key
    jc .next_char
    add di, 7                       ; len("initrd=")
    
    mov si, [cfg_buffer_ptr]
    add si, di
    lea bx, [rel config_initrd_name]
    push di
    mov di, bx
    call config_copy_value
    pop di
    add di, ax
    jmp .line_loop

.skip_comment:
    ; Skip to next newline
    mov si, [cfg_buffer_ptr]
    add si, di
    mov al, [si]
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
; Input:  DI = current offset
;         DX = pointer to key string (null-terminated)
; Output: CF clear if match, set if mismatch
; =============================================================================
config_match_key:
    push si
    push di
    mov si, dx
    mov bx, [cfg_buffer_ptr]
    add bx, di                      ; BX = current buffer position
.cmp_loop:
    mov al, [si]
    test al, al                     ; end of key?
    jz .match
    mov ah, [bx]
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
    pop si
    ret

; =============================================================================
; config_copy_value — Copy value to destination buffer
; Input:  SI = pointer to source value
;         DI = destination buffer
; Output: AX = count of bytes copied
; =============================================================================
config_copy_value:
    push si
    push di
    push es
    push bx

    xor ax, ax
    mov es, ax
    xor bx, bx                      ; BX = count

.copy_loop:
    mov al, [si]
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

    mov [es:di], al
    inc si
    inc di
    inc bx
    jmp .copy_loop

.copy_done:
    mov byte [es:di], 0             ; null terminator
    mov ax, bx                      ; return count

    pop bx
    pop es
    pop di
    pop si
    ret

; Variables
cfg_buffer_ptr:     dw 0
cfg_buffer_len:     dw 0

key_kernel:         db "kernel=", 0
key_fallback:       db "fallback=", 0
key_initrd:         db "initrd=", 0

; Extracted config names
config_kernel_name:   times 32 db 0
config_fallback_name: times 32 db 0
config_initrd_name:   times 32 db 0

%endif ; PARSER_ASM
