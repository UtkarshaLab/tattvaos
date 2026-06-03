; =============================================================================
; Tattva OS — boot/survive/diff.asm
; =============================================================================
; Compares the panic crash state (0x9A00) against the pristine snapshot (0x9000)
; and logs any differing registers via UART.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode)
; =============================================================================

%ifndef SURVIVE_DIFF_ASM
%define SURVIVE_DIFF_ASM

[BITS 64]

global survive_diff

; =============================================================================
; survive_diff — compare registers and log differences to COM1
; Input:  none
; Output: none
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8, R9, R10
; =============================================================================
survive_diff:
    cld                             ; Clear direction flag for string instructions
    
    ; Print header
    lea rsi, [msg_diff_header]
    call uart_print_64

    xor r8, r8                      ; R8 = current register index (0 to 21)

.loop:
    cmp r8, 22
    jae .done

    ; Calculate offset based on register index
    cmp r8, 16
    jl .gpr_offset                  ; index 0-15: GPRs
    cmp r8, 20
    jl .cr_offset                   ; index 16-19: CRs
    cmp r8, 20
    je .rflags_offset               ; index 20: RFLAGS
    ; Otherwise index 21: RIP
    mov r9, 216                     ; offset 0xD8
    jmp .compare

.gpr_offset:
    mov r9, r8
    shl r9, 3                       ; offset = index * 8
    jmp .compare

.cr_offset:
    mov r9, r8
    sub r9, 16
    shl r9, 3
    add r9, 128                     ; offset = 128 + (index-16)*8
    jmp .compare

.rflags_offset:
    mov r9, 208                     ; offset 0xD0

.compare:
    ; Compare [0x9000 + R9] (pristine) vs [0x9A00 + R9] (crash)
    mov rax, [0x9000 + r9]
    mov r10, [0x9A00 + r9]
    cmp rax, r10
    je .next                        ; if equal, skip

    push r10                        ; Push crash value to stack
    push rax                        ; Push pristine value to stack

    ; Print register name
    ; Name string is at reg_names + R8 * 4
    mov rax, r8
    shl rax, 2                      ; RAX = R8 * 4
    lea rsi, [reg_names]
    add rsi, rax
    call uart_print_64

    ; Print diff details
    lea rsi, [msg_diff_middle]      ; " diff: pristine=0x"
    call uart_print_64

    pop rax                         ; Pop pristine value
    call uart_print_hex64

    lea rsi, [msg_diff_crash]       ; " crash=0x"
    call uart_print_64

    pop rax                         ; Pop crash value
    call uart_print_hex64

    lea rsi, [msg_crlf]
    call uart_print_64

.next:
    inc r8
    jmp .loop

.done:
    lea rsi, [msg_diff_footer]
    call uart_print_64
    ret

; =============================================================================
; 64-bit UART helper functions
; =============================================================================
uart_putc_64:
    mov dx, 0x3FD                   ; Line Status Register
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov dx, 0x3F8                   ; Transmit Holding Register
    mov al, cl
    out dx, al
    ret

uart_print_64:
    push rsi
    push rax
    push rdx
.loop:
    lodsb                           ; AL = *RSI++
    test al, al
    jz .done
    mov cl, al
    call uart_putc_64
    jmp .loop
.done:
    pop rdx
    pop rax
    pop rsi
    ret

uart_print_hex64:
    push rbx
    push rcx
    push rdx
    mov rbx, rax
    mov rcx, 16                     ; 16 hex digits
.loop:
    rol rbx, 4
    mov dl, bl
    and dl, 0x0F
    cmp dl, 10
    jae .letter
    add dl, '0'
    jmp .print
.letter:
    add dl, 'A' - 10
.print:
    push rcx
    mov cl, dl
    call uart_putc_64
    pop rcx
    dec rcx
    jnz .loop
    pop rdx
    pop rcx
    pop rbx
    ret

; =============================================================================
; Data strings and register names
; =============================================================================
msg_diff_header:    db 0x0D, 0x0A, "--- Register Diff (Pristine vs Crash) ---", 0x0D, 0x0A, 0
msg_diff_middle:    db " diff: pristine=0x", 0
msg_diff_crash:     db " crash=0x", 0
msg_diff_footer:    db "-----------------------------------------", 0x0D, 0x0A, 0
msg_crlf:           db 0x0D, 0x0A, 0

align 4
reg_names:
    db "RAX", 0, "RBX", 0, "RCX", 0, "RDX", 0
    db "RSI", 0, "RDI", 0, "RBP", 0, "RSP", 0
    db "R8 ", 0, "R9 ", 0, "R10", 0, "R11", 0
    db "R12", 0, "R13", 0, "R14", 0, "R15", 0
    db "CR0", 0, "CR2", 0, "CR3", 0, "CR4", 0
    db "FLG", 0, "RIP", 0

%endif ; SURVIVE_DIFF_ASM
