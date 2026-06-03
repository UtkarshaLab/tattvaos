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

ulf_header:
    dd 0x00464C55                   ; magic: "ULF\0"
    dd kernel_end - ulf_header      ; size of binary
    dq kernel_entry                 ; dynamic entry point
    dq 0x123456789ABCDEF0           ; checksum placeholder (patched by Makefile)
    dq 0                            ; reserved

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

    ; 5. Print ACPI RSDP physical address
    mov rsi, .msg_acpi_rsdp
    call .uart_print_str
    mov rax, [rbp + 24]             ; load acpi_rsdp (BOOT_INFO_ACPI_RSDP offset 24)
    call .uart_print_hex64
    mov rsi, .msg_crlf
    call .uart_print_str

    ; 6. Print Framebuffer address
    mov rsi, .msg_fb_addr
    call .uart_print_str
    mov rax, [rbp + 32]             ; BOOT_INFO_FB_ADDR offset 32
    call .uart_print_hex64
    mov rsi, .msg_crlf
    call .uart_print_str

    ; 7. Print Framebuffer resolution and BPP
    mov rsi, .msg_fb_res
    call .uart_print_str
    xor eax, eax
    mov eax, [rbp + 40]             ; BOOT_INFO_FB_WIDTH offset 40
    call .uart_print_dec
    mov al, 'x'
    call .uart_putc
    xor eax, eax
    mov eax, [rbp + 44]             ; BOOT_INFO_FB_HEIGHT offset 44
    call .uart_print_dec
    mov al, 'x'
    call .uart_putc
    xor eax, eax
    mov eax, [rbp + 52]             ; BOOT_INFO_FB_FORMAT (BPP) offset 52
    call .uart_print_dec
    mov rsi, .msg_crlf
    call .uart_print_str

    ; -------------------------------------------------------------------------
    ; 8. Draw VBE Framebuffer test screen (Deep Purple + Centered Gold Box)
    ; -------------------------------------------------------------------------
    mov rdi, [rbp + 32]             ; RDI = framebuffer physical address
    test rdi, rdi
    jz .no_fb_draw

    ; Calculate total pixels = width * height
    xor rcx, rcx
    mov ecx, [rbp + 40]             ; width
    xor rdx, rdx
    mov edx, [rbp + 44]             ; height
    mov rax, rcx
    imul rax, rdx                   ; RAX = width * height

    ; Check BPP
    mov esi, [rbp + 52]             ; BPP
    cmp esi, 32
    jne .check_24

    ; 32bpp fill loop (Deep Purple: 0x002D004D)
    mov rsi, rax                    ; pixel count
    mov eax, 0x002D004D
    rep stosd
    jmp .draw_box

.check_24:
    cmp esi, 24
    jne .no_fb_draw
    ; 24bpp fill loop
    mov rsi, rax
.loop_24:
    mov byte [rdi], 0x4D            ; Blue
    mov byte [rdi + 1], 0x00        ; Green
    mov byte [rdi + 2], 0x2D        ; Red
    add rdi, 3
    dec rsi
    jnz .loop_24

.draw_box:
    ; Draw a 100x100 Gold Box in the center of the screen
    ; Center X = width / 2, Center Y = height / 2
    xor eax, eax
    mov eax, [rbp + 40]             ; width
    shr eax, 1                      ; width / 2
    sub eax, 50                     ; Start X
    
    xor ebx, ebx
    mov ebx, [rbp + 44]             ; height
    shr ebx, 1                      ; height / 2
    sub ebx, 50                     ; Start Y

    mov ecx, 100                    ; row loop counter (height = 100)
.box_row_loop:
    push rcx
    
    ; Compute row pointer: base + (Start Y + row_index) * Pitch + Start X * BytesPerPixel
    mov rdi, [rbp + 32]             ; FB base
    xor rsi, rsi
    mov esi, ebx                    ; Start Y
    mov r8d, 100
    sub r8d, ecx                    ; row_index
    add esi, r8d                    ; Start Y + row_index
    
    xor r9, r9
    mov r9d, [rbp + 48]             ; Pitch (bytes per row)
    imul rsi, r9
    add rdi, rsi
    
    ; Add Start X offset
    xor rsi, rsi
    mov esi, eax                    ; Start X
    mov r10d, [rbp + 52]            ; BPP
    shr r10d, 3                     ; BytesPerPixel
    imul rsi, r10
    add rdi, rsi                    ; RDI points to row pixel start
    
    ; Draw 100 pixels in this row
    mov ecx, 100
.box_pixel_loop:
    cmp r10d, 4
    jne .draw_pixel_24
    mov dword [rdi], 0x00FFD700     ; Gold (32bpp)
    add rdi, 4
    jmp .next_pixel
.draw_pixel_24:
    mov byte [rdi], 0x00            ; Blue
    mov byte [rdi + 1], 0xD7        ; Green
    mov byte [rdi + 2], 0xFF        ; Red
    add rdi, 3
.next_pixel:
    dec ecx
    jnz .box_pixel_loop

    pop rcx
    dec ecx
    jnz .box_row_loop

.no_fb_draw:

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
    call .uart_putc
    dec edx
    jnz .hex_loop32

    pop rax
    pop rsi
    pop rdx
    pop rcx
    ret

; =============================================================================
; .uart_print_hex64 — print a 64-bit register value in hex
; Input: RAX = value
; Output: nothing
; =============================================================================
.uart_print_hex64:
    push rcx
    push rdx
    push rsi
    push rax

    mov rcx, rax                    ; save to RCX

    ; print "0x"
    mov al, '0'
    call .uart_putc
    mov al, 'x'
    call .uart_putc

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
    call .uart_putc
    dec edx
    jnz .hex_loop64

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
.msg_acpi_rsdp:     db "ACPI RSDP:     ", 0
.msg_fb_addr:       db "FB Address:    ", 0
.msg_fb_res:        db "FB Resolution: ", 0
.msg_crlf:         db 0x0D, 0x0A, 0

align 8
kernel_end:

%endif ; KERNEL_STUB_ASM
