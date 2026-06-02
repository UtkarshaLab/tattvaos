; =============================================================================
; Tattva OS — boot/stage2/hw/uart/uart.asm
; =============================================================================
; Initialize COM1 UART at 115200 baud, 8N1, polling mode.
; No interrupts. No DMA. Just port I/O.
;
; Call once at stage2 entry — before anything else.
; After this: uart_print.asm and uart_hex.asm work.
;
; COM1 base port: 0x3F8
; Baud rate:      115200  (divisor = 1)
; Format:         8 data bits, no parity, 1 stop bit (8N1)
; Mode:           polling (check THRE before each byte)
;
; Port map (offset from base 0x3F8):
;   +0  THR/RBR   transmit / receive (DLAB=0)
;   +0  DLL       divisor low byte   (DLAB=1)
;   +1  IER       interrupt enable   (DLAB=0)
;   +1  DLH       divisor high byte  (DLAB=1)
;   +2  FCR       FIFO control
;   +3  LCR       line control (bit 7 = DLAB)
;   +4  MCR       modem control
;   +5  LSR       line status (bit 5 = THRE = transmitter empty)
; =============================================================================

%define UART_COM1       0x3F8
%define UART_THR        (UART_COM1 + 0)    ; transmit holding register
%define UART_IER        (UART_COM1 + 1)    ; interrupt enable register
%define UART_FCR        (UART_COM1 + 2)    ; FIFO control register
%define UART_LCR        (UART_COM1 + 3)    ; line control register
%define UART_MCR        (UART_COM1 + 4)    ; modem control register
%define UART_LSR        (UART_COM1 + 5)    ; line status register
%define UART_DLL        (UART_COM1 + 0)    ; divisor latch low  (DLAB=1)
%define UART_DLH        (UART_COM1 + 1)    ; divisor latch high (DLAB=1)

%define UART_LCR_DLAB   0x80               ; divisor latch access bit
%define UART_LCR_8N1    0x03               ; 8 data, no parity, 1 stop
%define UART_FCR_INIT   0xC7               ; enable + clear FIFOs, 14-byte trigger
%define UART_MCR_INIT   0x0B               ; DTR + RTS + OUT2
%define UART_LSR_THRE   0x20               ; transmitter holding register empty

; =============================================================================
; uart_init — initialize COM1 at 115200 baud
; Input:  nothing
; Output: nothing
; Clobbers: AL, DX
; =============================================================================
uart_init:
    ; Step 1: Disable all UART interrupts
    mov dx, UART_IER
    mov al, 0x00
    out dx, al

    ; Step 2: Enable DLAB (divisor latch access)
    mov dx, UART_LCR
    mov al, UART_LCR_DLAB
    out dx, al

    ; Step 3: Set baud rate divisor = 1 (115200 baud)
    ;         Divisor = 115200 / 115200 = 1
    mov dx, UART_DLL
    mov al, 0x01                    ; low byte = 1
    out dx, al

    mov dx, UART_DLH
    mov al, 0x00                    ; high byte = 0
    out dx, al

    ; Step 4: Set 8N1, clear DLAB
    mov dx, UART_LCR
    mov al, UART_LCR_8N1            ; 8 data bits, no parity, 1 stop, DLAB=0
    out dx, al

    ; Step 5: Enable and clear FIFOs
    mov dx, UART_FCR
    mov al, UART_FCR_INIT
    out dx, al

    ; Step 6: Enable DTR + RTS + OUT2 (required for some hardware)
    mov dx, UART_MCR
    mov al, UART_MCR_INIT
    out dx, al

    ret

; =============================================================================
; uart_putc — send a single character via COM1 (polling)
; Input:  AL = character to send
; Output: nothing
; Clobbers: AL, DX
; =============================================================================
uart_putc:
    push ax                         ; save character

    ; Wait for THRE (transmitter holding register empty)
.wait:
    mov dx, UART_LSR
    in al, dx
    test al, UART_LSR_THRE          ; test bit 5
    jz .wait                        ; not empty yet, keep polling

    ; Send the character
    pop ax
    mov dx, UART_THR
    out dx, al

    ret
