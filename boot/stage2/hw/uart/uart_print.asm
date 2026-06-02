; =============================================================================
; Tattva OS — boot/stage2/hw/uart/uart_print.asm
; =============================================================================
; Print null-terminated string via COM1 UART.
; Requires uart_init to be called first.
;
; Functions:
;   uart_print      — print null-terminated string
;   uart_println    — print string + CRLF
;   uart_print_char — print single character
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode + protected mode + long mode
; =============================================================================

%ifndef UART_PRINT_ASM
%define UART_PRINT_ASM

%include "uart.asm"

; =============================================================================
; uart_print — print null-terminated string
; Input:  SI (16-bit) or RSI (64-bit) = pointer to string
; Output: nothing
; Clobbers: AL, DX
; =============================================================================
uart_print:
    push ax
    push si

.loop:
    lodsb                           ; load byte at [SI], advance SI
    test al, al                     ; null terminator?
    jz .done                        ; yes — stop

    call uart_putc                  ; print character
    jmp .loop

.done:
    pop si
    pop ax
    ret

; =============================================================================
; uart_println — print null-terminated string followed by CRLF
; Input:  SI = pointer to string
; Output: nothing
; Clobbers: AL, DX
; =============================================================================
uart_println:
    call uart_print                 ; print the string

    ; print carriage return + line feed
    mov al, 0x0D                    ; CR
    call uart_putc
    mov al, 0x0A                    ; LF
    call uart_putc
    ret

; =============================================================================
; uart_print_char — print single character
; Input:  AL = character
; Output: nothing
; Clobbers: AL, DX
; =============================================================================
uart_print_char:
    call uart_putc
    ret

; =============================================================================
; uart_print_dec — print 32-bit unsigned integer in decimal
; Input:  EAX = value to print
; Output: nothing
; Clobbers: AL, AH, DX, ECX, EAX
; =============================================================================
uart_print_dec:
    push ebx
    push ecx
    push edx
    push esi

    ; handle zero specially
    test eax, eax
    jnz .nonzero
    mov al, '0'
    call uart_putc
    jmp .done

.nonzero:
    ; convert digits to stack (in reverse order)
    mov ecx, 0                      ; digit count
    mov ebx, 10                     ; divisor

.extract:
    test eax, eax
    jz .print
    xor edx, edx
    div ebx                         ; eax = quotient, edx = remainder
    push edx                        ; push digit
    inc ecx
    jmp .extract

.print:
    ; print digits in correct order
    test ecx, ecx
    jz .done
    pop edx
    mov al, dl
    add al, '0'                     ; convert to ASCII
    call uart_putc
    dec ecx
    jmp .print

.done:
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

%endif ; UART_PRINT_ASM