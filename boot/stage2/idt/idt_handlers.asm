; =============================================================================
; Tattva OS — boot/stage2/idt/idt_handlers.asm
; =============================================================================
; Low-level exception handlers for Protected Mode IDT.
; Catches faults 0 to 31, saves registers, and displays a detailed register dump
; over the COM1 serial port.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef IDT_HANDLERS_ASM
%define IDT_HANDLERS_ASM

[BITS 32]

; =============================================================================
; Exception Entry Points
; =============================================================================

%macro exc_handler_no_err 1
global exc_handler_%1
exc_handler_%1:
    push 0                          ; dummy error code
    push %1                         ; exception number
    jmp common_exc_handler
%endmacro

%macro exc_handler_err 1
global exc_handler_%1
exc_handler_%1:
    push %1                         ; exception number
    jmp common_exc_handler
%endmacro

exc_handler_no_err 0
exc_handler_no_err 1
exc_handler_no_err 2
exc_handler_no_err 3
exc_handler_no_err 4
exc_handler_no_err 5
exc_handler_no_err 6
exc_handler_no_err 7
exc_handler_err    8
exc_handler_no_err 9
exc_handler_err    10
exc_handler_err    11
exc_handler_err    12
exc_handler_err    13
exc_handler_err    14
exc_handler_no_err 15
exc_handler_no_err 16
exc_handler_err    17
exc_handler_no_err 18
exc_handler_no_err 19
exc_handler_no_err 20
exc_handler_no_err 21
exc_handler_no_err 22
exc_handler_no_err 23
exc_handler_no_err 24
exc_handler_no_err 25
exc_handler_no_err 26
exc_handler_no_err 27
exc_handler_no_err 28
exc_handler_no_err 29
exc_handler_err    30
exc_handler_no_err 31

; =============================================================================
; Common Exception Handler
; Stack structure at entry:
;   [ESP + 0]  = Exception number
;   [ESP + 4]  = Error code
;   [ESP + 8]  = EIP (at exception)
;   [ESP + 12] = CS (at exception)
;   [ESP + 16] = EFLAGS (at exception)
; =============================================================================
common_exc_handler:
    pushad                          ; save general purpose registers
                                    ; pushes: EDI, ESI, EBP, ESP (original), EBX, EDX, ECX, EAX
                                    ; ESP is decremented by 32 bytes

    ; -------------------------------------------------------------------------
    ; 1. Print Exception Header
    ; -------------------------------------------------------------------------
    mov esi, msg_exc_prefix
    call uart_print_pm_idt

    ; Print exception number in decimal
    mov eax, [esp + 32]             ; exception number
    call uart_print_dec_pm_idt

    mov esi, msg_exc_colon
    call uart_print_pm_idt

    ; Lookup exception name
    mov eax, [esp + 32]
    and eax, 0x1F                   ; clamp to 0-31
    mov esi, [exception_names + eax * 4]
    call uart_print_pm_idt

    mov esi, msg_crlf
    call uart_print_pm_idt

    ; -------------------------------------------------------------------------
    ; 2. Print Instruction and Control Registers
    ; -------------------------------------------------------------------------
    mov esi, msg_eip
    call uart_print_pm_idt
    mov eax, [esp + 40]             ; EIP
    call uart_print_hex32_pm_idt

    mov esi, msg_cs
    call uart_print_pm_idt
    mov eax, [esp + 44]             ; CS
    and eax, 0xFFFF
    call uart_print_hex32_pm_idt

    mov esi, msg_eflags
    call uart_print_pm_idt
    mov eax, [esp + 48]             ; EFLAGS
    call uart_print_hex32_pm_idt
    
    mov esi, msg_crlf
    call uart_print_pm_idt

    ; -------------------------------------------------------------------------
    ; 3. Print Register Dump
    ; -------------------------------------------------------------------------
    mov esi, msg_eax
    call uart_print_pm_idt
    mov eax, [esp + 28]             ; EAX
    call uart_print_hex32_pm_idt

    mov esi, msg_ebx
    call uart_print_pm_idt
    mov eax, [esp + 16]             ; EBX
    call uart_print_hex32_pm_idt

    mov esi, msg_ecx
    call uart_print_pm_idt
    mov eax, [esp + 24]             ; ECX
    call uart_print_hex32_pm_idt

    mov esi, msg_edx
    call uart_print_pm_idt
    mov eax, [esp + 20]             ; EDX
    call uart_print_hex32_pm_idt
    
    mov esi, msg_crlf
    call uart_print_pm_idt

    mov esi, msg_esi
    call uart_print_pm_idt
    mov eax, [esp + 4]              ; ESI
    call uart_print_hex32_pm_idt

    mov esi, msg_edi
    call uart_print_pm_idt
    mov eax, [esp + 0]              ; EDI
    call uart_print_hex32_pm_idt

    mov esi, msg_ebp
    call uart_print_pm_idt
    mov eax, [esp + 8]              ; EBP
    call uart_print_hex32_pm_idt

    mov esi, msg_esp
    call uart_print_pm_idt
    mov eax, esp
    add eax, 32 + 20                ; ESP before exception (pushad + exc_num + err_code + EIP + CS + EFLAGS)
    call uart_print_hex32_pm_idt
    
    mov esi, msg_crlf
    call uart_print_pm_idt

    ; -------------------------------------------------------------------------
    ; 4. Print Hardware Error Code and CR2 (if Page Fault)
    ; -------------------------------------------------------------------------
    mov esi, msg_err_code
    call uart_print_pm_idt
    mov eax, [esp + 36]             ; Error code
    call uart_print_hex32_pm_idt
    
    ; If exception was a Page Fault (14), print CR2
    mov eax, [esp + 32]
    cmp eax, 14
    jne .skip_cr2

    mov esi, msg_cr2
    call uart_print_pm_idt
    mov eax, cr2
    call uart_print_hex32_pm_idt

.skip_cr2:
    mov esi, msg_crlf
    call uart_print_pm_idt

    mov esi, msg_halt
    call uart_print_pm_idt

    ; -------------------------------------------------------------------------
    ; 5. Halt the system
    ; -------------------------------------------------------------------------
    cli
.halt:
    hlt
    jmp .halt

; =============================================================================
; 32-bit Protected Mode UART Output Helpers
; =============================================================================

; -----------------------------------------------------------------------------
; uart_putc_pm_idt — write a single character via COM1 (polling)
; Input:  AL = character to send
; Output: nothing
; -----------------------------------------------------------------------------
uart_putc_pm_idt:
    push edx
    push eax
    mov bl, al                      ; save character to BL

.wait:
    mov edx, 0x3F8 + 5              ; LSR (line status register)
    in al, dx
    test al, 0x20                   ; transmitter empty?
    jz .wait

    mov al, bl                      ; restore character
    mov edx, 0x3F8                  ; THR (transmit holding register)
    out dx, al

    pop eax
    pop edx
    ret

; -----------------------------------------------------------------------------
; uart_print_pm_idt — print null-terminated string
; Input:  ESI = pointer to string
; Output: nothing
; -----------------------------------------------------------------------------
uart_print_pm_idt:
    push eax
    push esi

.loop:
    lodsb                           ; AL = [ESI], ESI++
    test al, al
    jz .done
    call uart_putc_pm_idt
    jmp .loop

.done:
    pop esi
    pop eax
    ret

; -----------------------------------------------------------------------------
; uart_print_dec_pm_idt — print unsigned integer in decimal
; Input:  EAX = value
; Output: nothing
; -----------------------------------------------------------------------------
uart_print_dec_pm_idt:
    push eax
    push ecx
    push edx
    push ebx

    test eax, eax
    jnz .nonzero
    mov al, '0'
    call uart_putc_pm_idt
    jmp .done

.nonzero:
    mov ecx, 0
    mov ebx, 10

.extract:
    test eax, eax
    jz .print
    xor edx, edx
    div ebx                         ; EAX = quotient, EDX = remainder
    push edx                        ; push digit
    inc ecx
    jmp .extract

.print:
    test ecx, ecx
    jz .done
    pop edx
    mov al, dl
    add al, '0'
    call uart_putc_pm_idt
    dec ecx
    jmp .print

.done:
    pop ebx
    pop edx
    pop ecx
    pop eax
    ret

; -----------------------------------------------------------------------------
; uart_print_hex32_pm_idt — print 32-bit value in hex "0x########"
; Input:  EAX = value
; Output: nothing
; -----------------------------------------------------------------------------
uart_print_hex32_pm_idt:
    push eax
    push ecx
    push edx

    mov ecx, eax                    ; save to ECX

    ; print "0x"
    mov al, '0'
    call uart_putc_pm_idt
    mov al, 'x'
    call uart_putc_pm_idt

    ; print 8 nibbles
    mov edx, 8
.loop:
    rol ecx, 4                      ; rotate top nibble to bottom
    mov al, cl
    and al, 0x0F
    cmp al, 10
    jl .digit
    add al, 'A' - 10
    jmp .print
.digit:
    add al, '0'
.print:
    call uart_putc_pm_idt
    dec edx
    jnz .loop

    pop edx
    pop ecx
    pop eax
    ret

; =============================================================================
; Data and Strings
; =============================================================================

msg_exc_prefix: db "EXCEPTION ", 0
msg_exc_colon:  db ": ", 0
msg_crlf:       db 0x0D, 0x0A, 0
msg_eip:        db "EIP: ", 0
msg_cs:         db "  CS: ", 0
msg_eflags:     db "  EFLAGS: ", 0
msg_eax:        db "EAX: ", 0
msg_ebx:        db "  EBX: ", 0
msg_ecx:        db "  ECX: ", 0
msg_edx:        db "  EDX: ", 0
msg_esi:        db "ESI: ", 0
msg_edi:        db "  EDI: ", 0
msg_ebp:        db "  EBP: ", 0
msg_esp:        db "  ESP: ", 0
msg_err_code:   db "Error Code: ", 0
msg_cr2:        db "  CR2: ", 0
msg_halt:       db "Halting.", 0x0D, 0x0A, 0

align 4
exception_names:
    dd exc_name_0, exc_name_1, exc_name_2, exc_name_3, exc_name_4, exc_name_5, exc_name_6, exc_name_7
    dd exc_name_8, exc_name_9, exc_name_10, exc_name_11, exc_name_12, exc_name_13, exc_name_14, exc_name_15
    dd exc_name_16, exc_name_17, exc_name_18, exc_name_19, exc_name_20, exc_name_21, exc_name_22, exc_name_23
    dd exc_name_24, exc_name_25, exc_name_26, exc_name_27, exc_name_28, exc_name_29, exc_name_30, exc_name_31

exc_name_0:  db "Divide-by-Zero Error", 0
exc_name_1:  db "Debug Exception", 0
exc_name_2:  db "Non-Maskable Interrupt", 0
exc_name_3:  db "Breakpoint", 0
exc_name_4:  db "Overflow", 0
exc_name_5:  db "Bound Range Exceeded", 0
exc_name_6:  db "Invalid Opcode", 0
exc_name_7:  db "Device Not Available", 0
exc_name_8:  db "Double Fault", 0
exc_name_9:  db "Coprocessor Segment Overrun", 0
exc_name_10: db "Invalid TSS", 0
exc_name_11: db "Segment Not Present", 0
exc_name_12: db "Stack-Segment Fault", 0
exc_name_13: db "General Protection Fault", 0
exc_name_14: db "Page Fault", 0
exc_name_15: db "Intel Reserved", 0
exc_name_16: db "x87 FPU Floating-Point Error", 0
exc_name_17: db "Alignment Check", 0
exc_name_18: db "Machine Check", 0
exc_name_19: db "SIMD Floating-Point Exception", 0
exc_name_20: db "Virtualization Exception", 0
exc_name_21: db "Control Protection Exception", 0
exc_name_22: db "Intel Reserved", 0
exc_name_23: db "Intel Reserved", 0
exc_name_24: db "Intel Reserved", 0
exc_name_25: db "Intel Reserved", 0
exc_name_26: db "Intel Reserved", 0
exc_name_27: db "Intel Reserved", 0
exc_name_28: db "Hypervisor Injection Exception", 0
exc_name_29: db "VMM Communication Exception", 0
exc_name_30: db "Security Exception", 0
exc_name_31: db "Intel Reserved", 0

[BITS 16]

%endif ; IDT_HANDLERS_ASM
