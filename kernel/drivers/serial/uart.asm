; =============================================================================
; Tattva OS — kernel/drivers/serial/uart.asm
; =============================================================================
; Early serial UART (COM1) driver for x86-64 long mode.
; Provides early debugging console output functions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef KERNEL_DRIVERS_SERIAL_UART_ASM
%define KERNEL_DRIVERS_SERIAL_UART_ASM

[BITS 64]

; =============================================================================
; uart_putc — write a single character via COM1 (polling)
; Input:  AL = character to send
; Output: nothing
; Clobbers: none (preserves all registers)
; =============================================================================
uart_putc:
    push rdx
    push rax
    push rbx
    mov bl, al                      ; save character

.uart_wait:
    mov dx, 0x3F8 + 5               ; Line Status Register (LSR)
    in al, dx
    test al, 0x20                   ; Transmitter Holding Register Empty?
    jz .uart_wait

    mov al, bl                      ; restore character
    mov dx, 0x3F8                   ; Transmit Holding Register (THR)
    out dx, al

    pop rbx
    pop rax
    pop rdx
    ret

; =============================================================================
; uart_print_str — print a null-terminated string
; Input:  RSI = pointer to string
; Output: nothing
; Clobbers: none (preserves all registers)
; =============================================================================
uart_print_str:
    push rax
    push rsi
.str_loop:
    lodsb                           ; AL = [RSI], RSI++
    test al, al                     ; null terminator?
    jz .str_done
    call uart_putc
    jmp .str_loop
.str_done:
    pop rsi
    pop rax
    ret

; =============================================================================
; uart_print_hex32 — print a 32-bit register value in hex (e.g. "0x12345678")
; Input:  EAX = value
; Output: nothing
; Clobbers: none (preserves all registers)
; =============================================================================
uart_print_hex32:
    push rcx
    push rdx
    push rsi
    push rax

    mov ecx, eax                    ; save to ECX

    ; print "0x"
    mov al, '0'
    call uart_putc
    mov al, 'x'
    call uart_putc

    ; print 8 nibbles
    mov edx, 8
.hex_loop32:
    rol ecx, 4                      ; rotate top nibble to bottom
    mov al, cl
    and al, 0x0F
    cmp al, 10
    jl .hex_digit32
    add al, 'A' - 10
    jmp .hex_print32
.hex_digit32:
    add al, '0'
.hex_print32:
    call uart_putc
    dec edx
    jnz .hex_loop32

    pop rax
    pop rsi
    pop rdx
    pop rcx
    ret

; =============================================================================
; uart_print_hex64 — print a 64-bit register value in hex
; Input:  RAX = value
; Output: nothing
; Clobbers: none (preserves all registers)
; =============================================================================
uart_print_hex64:
    push rcx
    push rdx
    push rsi
    push rax

    mov rcx, rax                    ; save to RCX

    ; print "0x"
    mov al, '0'
    call uart_putc
    mov al, 'x'
    call uart_putc

    ; print 16 nibbles
    mov edx, 16
.hex_loop64:
    rol rcx, 4                      ; rotate top nibble to bottom
    mov al, cl
    and al, 0x0F
    cmp al, 10
    jl .hex_digit64
    add al, 'A' - 10
    jmp .hex_print64
.hex_digit64:
    add al, '0'
.hex_print64:
    call uart_putc
    dec edx
    jnz .hex_loop64

    pop rax
    pop rsi
    pop rdx
    pop rcx
    ret

; =============================================================================
; uart_print_dec — print unsigned 32-bit integer in decimal
; Input:  EAX = value
; Output: nothing
; Clobbers: none (preserves all registers)
; =============================================================================
uart_print_dec:
    push rax
    push rcx
    push rdx
    push rbx

    test eax, eax
    jnz .dec_nonzero
    mov al, '0'
    call uart_putc
    jmp .dec_done

.dec_nonzero:
    mov ecx, 0                      ; digit count
    mov ebx, 10                     ; divisor

.dec_extract:
    test eax, eax
    jz .dec_print
    xor edx, edx
    div ebx                         ; EAX = quotient, EDX = remainder
    push rdx                        ; push digit (64-bit push)
    inc ecx
    jmp .dec_extract

.dec_print:
    test ecx, ecx
    jz .dec_done
    pop rdx
    mov al, dl
    add al, '0'                     ; convert to ASCII
    call uart_putc
    dec ecx
    jmp .dec_print

.dec_done:
    pop rbx
    pop rdx
    pop rcx
    pop rax
    ret

%endif ; KERNEL_DRIVERS_SERIAL_UART_ASM
