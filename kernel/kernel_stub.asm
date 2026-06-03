; =============================================================================
; Tattva OS — kernel/kernel_stub.asm
; =============================================================================
; Minimal kernel stub for testing the full boot chain.
; Prints Tattva Kernel status and outputs BootInfo parameters via UART (COM1).
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef KERNEL_STUB_ASM
%define KERNEL_STUB_ASM

[BITS 64]
[ORG 0x100000]

kernel_entry:
    ; -------------------------------------------------------------------------
    ; The bootloader passes the BootInfo pointer in RDI.
    ; Save it in RBP so we can use RDI/RSI freely for printing.
    ; -------------------------------------------------------------------------
    mov rbp, rdi

    ; 1. Print welcoming banner
    mov rsi, .msg_kernel_ok
    call .uart_print_str

    ; 2. Print boot drive
    mov rsi, .msg_boot_drive
    call .uart_print_str
    mov eax, [rbp + 12]             ; load boot_drive (BOOT_INFO_DRIVE offset 12)
    call .uart_print_hex32
    mov rsi, .msg_crlf
    call .uart_print_str

    ; 3. Print E820 entries count
    mov rsi, .msg_e820_entries
    call .uart_print_str
    mov eax, [rbp + 8]              ; load e820_count (BOOT_INFO_E820_COUNT offset 8)
    call .uart_print_dec
    mov rsi, .msg_crlf
    call .uart_print_str

    ; 4. Print CPU features bitmask
    mov rsi, .msg_cpu_features
    call .uart_print_str
    mov eax, [rbp + 16]             ; load cpu_features (BOOT_INFO_FEATURES offset 16)
    call .uart_print_hex32
    mov rsi, .msg_crlf
    call .uart_print_str

    ; -------------------------------------------------------------------------
    ; Halt — kernel has no scheduler yet
    ; -------------------------------------------------------------------------
    cli
.halt:
    hlt
    jmp .halt

; =============================================================================
; .uart_putc — write a single character via COM1 (polling)
; Input:  AL = character to send
; Output: nothing
; =============================================================================
.uart_putc:
    push rdx
    push rax
    mov bl, al                      ; save character

.uart_wait:
    mov dx, 0x3F8 + 5              ; LSR (Line Status Register)
    in al, dx
    test al, 0x20                   ; Transmitter Holding Register Empty?
    jz .uart_wait

    mov al, bl                      ; restore character
    mov dx, 0x3F8                   ; THR (Transmit Holding Register)
    out dx, al

    pop rax
    pop rdx
    ret

; =============================================================================
; .uart_print_str — print null-terminated string
; Input:  RSI = pointer to string
; Output: nothing
; =============================================================================
.uart_print_str:
    push rax
    push rsi
.str_loop:
    lodsb                           ; AL = [RSI], RSI++
    test al, al                     ; null terminator?
    jz .str_done
    call .uart_putc
    jmp .str_loop
.str_done:
    pop rsi
    pop rax
    ret

; =============================================================================
; .uart_print_hex32 — print a 32-bit register value in hex
; Input: EAX = value
; Output: nothing
; =============================================================================
.uart_print_hex32:
    push rcx
    push rdx
    push rsi
    push rax

    mov ecx, eax                    ; save to ECX

    ; print "0x"
    mov al, '0'
    call .uart_putc
    mov al, 'x'
    call .uart_putc

    ; print 8 nibbles
    mov edx, 8
.hex_loop:
    rol ecx, 4                      ; rotate top nibble to bottom
    mov al, cl
    and al, 0x0F
    cmp al, 10
    jl .hex_digit
    add al, 'A' - 10
    jmp .hex_print
.hex_digit:
    add al, '0'
.hex_print:
    call .uart_putc
    dec edx
    jnz .hex_loop

    pop rax
    pop rsi
    pop rdx
    pop rcx
    ret

; =============================================================================
; .uart_print_dec — print unsigned 32-bit integer in decimal
; Input: EAX = value
; Output: nothing
; =============================================================================
.uart_print_dec:
    push rax
    push rcx
    push rdx
    push rbx

    test eax, eax
    jnz .dec_nonzero
    mov al, '0'
    call .uart_putc
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
    call .uart_putc
    dec ecx
    jmp .dec_print

.dec_done:
    pop rbx
    pop rdx
    pop rcx
    pop rax
    ret

; =============================================================================
; Data
; =============================================================================
.msg_kernel_ok:
    db "================================", 0x0D, 0x0A
    db "  Tattva Kernel OK", 0x0D, 0x0A
    db "================================", 0x0D, 0x0A, 0

.msg_boot_drive:    db "Boot Drive:    ", 0
.msg_e820_entries: db "E820 Entries:  ", 0
.msg_cpu_features: db "CPU Features:  ", 0
.msg_crlf:         db 0x0D, 0x0A, 0

%endif ; KERNEL_STUB_ASM
