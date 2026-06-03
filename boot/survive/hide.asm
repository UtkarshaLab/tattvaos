; =============================================================================
; Tattva OS — boot/survive/hide.asm
; =============================================================================
; Hides the SURVIVE_PAGE (0x9000 - 0xA000) from the E820 memory map.
; Splits the usable RAM entry containing 0x9000 into:
;   1. Usable RAM below 0x9000
;   2. Reserved memory at 0x9000 - 0xA000
;   3. Usable RAM above 0xA000
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef SURVIVE_HIDE_ASM
%define SURVIVE_HIDE_ASM

%include "config.asm"

[BITS 16]

; =============================================================================
; hide_survive_page — split the E820 entry containing 0x9000 to hide it
; Input:  none
; Output: none (modifies E820 map in place at E820_DEST)
; Clobbers: none
; =============================================================================
hide_survive_page:
    push bp
    mov bp, sp
    pusha
    push es

    cld                             ; Clear direction flag for forward copy
    xor ax, ax
    mov es, ax

    mov cx, [E820_DEST]             ; CX = E820 entry count
    test cx, cx
    jz .done                         ; if count is 0, nothing to do

    mov bx, 0                       ; BX = current entry index
.loop:
    cmp bx, cx
    jae .done

    ; Calculate pointer to entry[bx]
    mov ax, bx
    shl ax, 3                       ; AX = bx * 8
    mov si, ax
    shl ax, 1                       ; AX = bx * 16
    add si, ax                      ; SI = bx * 24
    add si, E820_DEST + 2

    ; Check if type is USABLE (1)
    cmp dword [es:si + 16], 1
    jne .next

    ; Check if base <= 0x9000
    cmp dword [es:si + 4], 0        ; base high must be 0
    jne .next
    cmp dword [es:si], 0x9000       ; base low must be <= 0x9000
    ja .next

    ; Check if base + length >= 0xA000
    mov eax, [es:si]
    mov edx, [es:si + 4]
    add eax, [es:si + 8]
    adc edx, [es:si + 12]           ; EDX:EAX = base + length
    
    test edx, edx                   ; if high dword is non-zero, then end > 0xA000
    jnz .found
    cmp eax, 0xA000
    jae .found

.next:
    inc bx
    jmp .loop

.found:
    ; Save original entry values on the stack
    mov eax, [es:si]                ; orig_base (low)
    push eax
    mov eax, [es:si + 8]            ; orig_len (low)
    push eax
    mov eax, [es:si + 12]           ; orig_len (high)
    push eax

    ; Shift subsequent entries by 2 slots to make room
    mov di, cx
    dec di                          ; DI = count - 1 (last entry index)

.shift_loop:
    cmp di, bx
    jle .shift_done

    ; Source entry pointer (di)
    mov ax, di
    shl ax, 3                       ; AX = di * 8
    mov si, ax
    shl ax, 1                       ; AX = di * 16
    add si, ax                      ; SI = di * 24
    add si, E820_DEST + 2

    ; Destination entry pointer (di + 2)
    mov ax, di
    add ax, 2
    shl ax, 3                       ; AX = (di + 2) * 8
    mov bp, ax
    shl ax, 1                       ; AX = (di + 2) * 16
    add bp, ax                      ; BP = (di + 2) * 24
    add bp, E820_DEST + 2

    ; Copy 24 bytes
    push cx
    mov cx, 12                      ; 12 words = 24 bytes
    push di
    push si
    mov di, bp
    rep movsw
    pop si
    pop di
    pop cx

    dec di
    jmp .shift_loop

.shift_done:
    ; Restore saved original values
    pop edx                         ; EDX = orig_len (high)
    pop ecx                         ; ECX = orig_len (low)
    pop eax                         ; EAX = orig_base (low)

    ; Calculate pointer to entry[bx]
    mov ax, bx
    shl ax, 3                       ; AX = bx * 8
    mov di, ax
    shl ax, 1                       ; AX = bx * 16
    add di, ax                      ; DI = bx * 24
    add di, E820_DEST + 2

    ; 1. Write Entry A at entry[bx] (usable RAM below 0x9000)
    mov [es:di], eax                ; base low = orig_base
    mov dword [es:di + 4], 0        ; base high = 0
    
    mov ebx, 0x9000
    sub ebx, eax                    ; EBX = 0x9000 - orig_base
    mov [es:di + 8], ebx            ; length low
    mov dword [es:di + 12], 0       ; length high
    mov dword [es:di + 16], 1       ; type = USABLE
    mov dword [es:di + 20], 1       ; ext attributes

    ; 2. Write Entry B at entry[bx+1] (reserved snapshot page)
    add di, 24                      ; DI points to entry[bx+1]
    mov dword [es:di], 0x9000       ; base low = 0x9000
    mov dword [es:di + 4], 0        ; base high = 0
    mov dword [es:di + 8], 0x1000   ; length low = 0x1000 (4KB)
    mov dword [es:di + 12], 0       ; length high = 0
    mov dword [es:di + 16], 2       ; type = RESERVED
    mov dword [es:di + 20], 1       ; ext attributes

    ; 3. Write Entry C at entry[bx+2] (usable RAM above 0xA000)
    add di, 24                      ; DI points to entry[bx+2]
    mov dword [es:di], 0xA000       ; base low = 0xA000
    mov dword [es:di + 4], 0        ; base high = 0
    
    ; length = (orig_base + orig_len) - 0xA000
    add eax, ecx
    adc edx, 0                      ; EDX:EAX = orig_base + orig_len
    sub eax, 0xA000
    sbb edx, 0                      ; EDX:EAX = new length
    
    mov [es:di + 8], eax            ; length low
    mov [es:di + 12], edx           ; length high
    mov dword [es:di + 16], 1       ; type = USABLE
    mov dword [es:di + 20], 1       ; ext attributes

    ; Update total count: count = count + 2
    mov cx, [E820_DEST]
    add cx, 2
    mov [E820_DEST], cx

.done:
    pop es
    popa
    pop bp
    ret

%endif ; SURVIVE_HIDE_ASM
