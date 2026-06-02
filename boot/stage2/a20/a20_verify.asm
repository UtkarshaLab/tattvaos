; =============================================================================
; Tattva OS — boot/stage2/a20/a20_verify.asm
; =============================================================================
; Verify whether the A20 address line is enabled.
;
; Method:
;   Write a value to 0x0000:0x7DFE (just below MBR)
;   Read from  0xFFFF:0x7E0E (wraps to same physical address if A20 off)
;   If A20 is OFF:  0xFFFF:0x7E0E == 0x0000:0x7DFE (wrap-around)
;   If A20 is ON:   0xFFFF:0x7E0E != 0x0000:0x7DFE (different addresses)
;
;   We rotate the test value to rule out coincidence.
;
; Returns:
;   ZF clear (JNZ taken) = A20 is ON
;   ZF set   (JZ  taken) = A20 is OFF
;   Also sets/clears carry: CF=0 ON, CF=1 OFF
;
; Clobbers: AX, BX, CX, ES
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef A20_VERIFY_ASM
%define A20_VERIFY_ASM

; =============================================================================
; a20_verify — check if A20 line is enabled
; Input:  nothing
; Output: CF=0 if A20 ON (enabled)
;         CF=1 if A20 OFF (disabled)
; Clobbers: AX, BX, CX, ES
; =============================================================================
a20_verify:
    push ax
    push bx
    push cx
    push es

    ; -------------------------------------------------------------------------
    ; Set up segment to access 0xFFFF:0x7E0E
    ; Physical address = 0xFFFF * 16 + 0x7E0E = 0x10_7DFE
    ; With A20 off:    = 0x00_7DFE (wraps, same as 0x0000:0x7DFE)
    ; With A20 on:     = 0x10_7DFE (different physical address)
    ; -------------------------------------------------------------------------
    mov ax, 0xFFFF
    mov es, ax                      ; ES = 0xFFFF

    ; -------------------------------------------------------------------------
    ; Save original values so we can restore them
    ; -------------------------------------------------------------------------
    mov ax, [0x7DFE]                ; save value at 0x0000:0x7DFE
    push ax
    mov ax, [es:0x7E0E]             ; save value at 0xFFFF:0x7E0E
    push ax

    ; -------------------------------------------------------------------------
    ; Write test pattern to 0x0000:0x7DFE
    ; Then check if 0xFFFF:0x7E0E changed (A20 off = they alias)
    ; Rotate test value each call to rule out coincidence
    ; -------------------------------------------------------------------------
    mov cx, 3                       ; try 3 different test values

.try_next:
    ; write test value to low address
    mov ax, 0xA5A5                  ; test pattern
    add ax, cx                      ; vary it slightly each iteration
    mov [0x7DFE], ax

    ; memory barrier — flush any caching effects
    ; (use IO port read as delay/barrier in real mode)
    in al, 0x80                     ; port 0x80 = diagnostic port, dummy read

    ; read from high address
    mov bx, [es:0x7E0E]

    ; compare: if equal, A20 is off (addresses alias)
    cmp ax, bx
    jne .a20_on                     ; different = A20 is on

    dec cx
    jnz .try_next                   ; try again with different value

    ; all three tries showed aliasing — A20 is definitely off
    jmp .a20_off

.a20_on:
    ; -------------------------------------------------------------------------
    ; Restore original values
    ; -------------------------------------------------------------------------
    pop ax
    mov [es:0x7E0E], ax             ; restore 0xFFFF:0x7E0E
    pop ax
    mov [0x7DFE], ax                ; restore 0x0000:0x7DFE

    pop es
    pop cx
    pop bx
    pop ax

    clc                             ; CF=0: A20 is ON
    ret

.a20_off:
    ; -------------------------------------------------------------------------
    ; Restore original values
    ; -------------------------------------------------------------------------
    pop ax
    mov [es:0x7E0E], ax
    pop ax
    mov [0x7DFE], ax

    pop es
    pop cx
    pop bx
    pop ax

    stc                             ; CF=1: A20 is OFF
    ret

%endif ; A20_VERIFY_ASM