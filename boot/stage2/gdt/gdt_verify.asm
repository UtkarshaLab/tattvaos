; =============================================================================
; Tattva OS — boot/stage2/gdt/gdt_verify.asm
; =============================================================================
; Verify the GDT was loaded correctly after gdt_setup.
; Reads back the GDT register and checks key descriptor fields.
; Halts with error if anything is wrong.
;
; Checks:
;   1. GDTR base address matches gdt_start
;   2. GDTR limit matches expected size
;   3. Code64 descriptor has L=1 (64-bit flag)
;   4. Data64 descriptor has W=1 (writable flag)
;   5. Null descriptor is actually zero
;
; Call after gdt_setup, before switching to long mode.
; Debug builds only — strip in release.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef GDT_VERIFY_ASM
%define GDT_VERIFY_ASM

; temporary buffer for sgdt result (6 bytes)
gdt_verify_buf: times 6 db 0

; =============================================================================
; gdt_verify — verify GDT register and key descriptors
; Input:  GDT loaded by gdt_setup
; Output: CF=0 all checks passed
;         CF=1 verification failed (caller should halt)
; Clobbers: EAX, EBX, ECX, ESI
; =============================================================================
[BITS 32]
gdt_verify:
    push eax
    push ebx
    push ecx
    push esi

    ; -------------------------------------------------------------------------
    ; Check 1: Read back GDTR using SGDT instruction
    ; SGDT stores 6 bytes: 2-byte limit + 4-byte base
    ; -------------------------------------------------------------------------
    sgdt [gdt_verify_buf]

    ; check limit = GDT_SIZE - 1
    mov ax, [gdt_verify_buf]        ; limit word
    cmp ax, GDT_SIZE - 1
    jne .verify_fail_limit

    ; check base = gdt_start address
    mov eax, [gdt_verify_buf + 2]   ; base dword
    cmp eax, gdt_start
    jne .verify_fail_base

    ; -------------------------------------------------------------------------
    ; Check 2: Null descriptor must be all zeros
    ; -------------------------------------------------------------------------
    mov esi, gdt_start
    mov eax, [esi]                  ; low dword of null descriptor
    mov ebx, [esi + 4]              ; high dword of null descriptor
    or eax, ebx
    jnz .verify_fail_null           ; non-zero = corrupted GDT

    ; -------------------------------------------------------------------------
    ; Check 3: Code64 descriptor must have L=1 (bit 53 = byte 6 bit 5)
    ; Byte 6 of descriptor = G|D|L|AVL|limit[19:16]
    ; L is bit 5 of byte 6
    ; gdt_code64 is at gdt_start + 8
    ; -------------------------------------------------------------------------
    mov al, [gdt_start + 8 + 6]    ; byte 6 of code64 descriptor
    test al, (1 << 5)               ; test L bit
    jz .verify_fail_l_bit           ; L=0 means not 64-bit code descriptor

    ; -------------------------------------------------------------------------
    ; Check 4: Data64 descriptor must have W=1 (writable)
    ; Access byte (byte 5) bit 1 = writable
    ; gdt_data64 is at gdt_start + 16
    ; -------------------------------------------------------------------------
    mov al, [gdt_start + 16 + 5]   ; access byte of data64
    test al, (1 << 1)               ; test W bit
    jz .verify_fail_w_bit

    ; -------------------------------------------------------------------------
    ; All checks passed
    ; -------------------------------------------------------------------------
    mov esi, msg_gdt_verify_ok
    call uart_print_pm              ; protected mode UART print
    clc
    jmp .verify_done

.verify_fail_limit:
    mov esi, msg_gdt_fail_limit
    call uart_print_pm
    stc
    jmp .verify_done

.verify_fail_base:
    mov esi, msg_gdt_fail_base
    call uart_print_pm
    stc
    jmp .verify_done

.verify_fail_null:
    mov esi, msg_gdt_fail_null
    call uart_print_pm
    stc
    jmp .verify_done

.verify_fail_l_bit:
    mov esi, msg_gdt_fail_lbit
    call uart_print_pm
    stc
    jmp .verify_done

.verify_fail_w_bit:
    mov esi, msg_gdt_fail_wbit
    call uart_print_pm
    stc

.verify_done:
    pop esi
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; uart_print_pm — print null-terminated string in 32-bit protected mode
; In protected mode we can still use port I/O for UART
; but we need a 32-bit version since real mode BIOS calls are gone
; Input:  ESI = pointer to string
; Clobbers: AL, EDX
; =============================================================================
uart_print_pm:
    push eax
    push ebx
    push edx
    push esi
    cld                             ; Clear direction flag for lodsb

.pm_print_loop:
    lodsb                           ; AL = [ESI], ESI++
    test al, al
    jz .pm_print_done

    mov bl, al                      ; save character in BL

    ; wait for THRE (transmitter empty)
.pm_wait:
    mov edx, UART_COM1 + 5          ; LSR register
    in al, dx
    test al, 0x20
    jz .pm_wait

    mov al, bl                      ; restore character
    mov edx, UART_COM1
    out dx, al

    jmp .pm_print_loop

.pm_print_done:
    pop esi
    pop edx
    pop ebx
    pop eax
    ret

; =============================================================================
; Strings
; =============================================================================
msg_gdt_verify_ok:      db "GDT verify: OK", 0x0D, 0x0A, 0
msg_gdt_fail_limit:     db "GDT verify: FAIL limit mismatch", 0x0D, 0x0A, 0
msg_gdt_fail_base:      db "GDT verify: FAIL base mismatch", 0x0D, 0x0A, 0
msg_gdt_fail_null:      db "GDT verify: FAIL null descriptor not zero", 0x0D, 0x0A, 0
msg_gdt_fail_lbit:      db "GDT verify: FAIL code64 L bit not set", 0x0D, 0x0A, 0
msg_gdt_fail_wbit:      db "GDT verify: FAIL data64 not writable", 0x0D, 0x0A, 0

[BITS 16]

%endif ; GDT_VERIFY_ASM