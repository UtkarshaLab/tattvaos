; =============================================================================
; Tattva OS — boot/stage2/hw/acpi.asm
; =============================================================================
; Scan memory for the ACPI Root System Description Pointer (RSDP).
;
; Search regions (16-byte aligned):
;   1. First 1KB of Extended BIOS Data Area (EBDA)
;   2. BIOS ROM space (0x0E0000 - 0x0FFFFF)
;
; Signature: "RSD PTR " (52 53 44 20 50 54 52 20)
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef ACPI_ASM
%define ACPI_ASM

[BITS 16]

; =============================================================================
; acpi_find_rsdp — scan memory for ACPI RSDP pointer
; Input:  none
; Output: EAX = physical address of RSDP, or 0 if not found
; Clobbers: EBX, ECX, EDX, SI, DI, ES
; =============================================================================
acpi_find_rsdp:
    push cx
    push si
    push di
    push es

    ; -------------------------------------------------------------------------
    ; Region 1: Scan first 1KB of EBDA
    ; EBDA segment address is stored at physical 0x0000:0x040E (BDA)
    ; -------------------------------------------------------------------------
    xor ax, ax
    mov es, ax
    mov ax, [es:0x040E]             ; AX = EBDA segment
    test ax, ax
    jz .scan_bios_rom               ; if EBDA is 0, skip to BIOS ROM scan

    mov es, ax                      ; ES = EBDA segment
    xor di, di                      ; start at offset 0
    mov cx, 64                      ; 1024 bytes / 16-byte step = 64 steps

.scan_ebda_loop:
    call .check_signature
    jnc .found_ebda
    add di, 16
    loop .scan_ebda_loop
    jmp .scan_bios_rom

.found_ebda:
    ; Convert ES:DI to 32-bit physical address
    mov ax, es
    xor edx, edx
    mov dx, ax
    shl edx, 4                      ; EDX = segment * 16
    xor eax, eax
    mov ax, di
    add edx, eax                    ; EDX = segment * 16 + offset
    mov eax, edx                    ; EAX = physical address
    jmp .done

    ; -------------------------------------------------------------------------
    ; Region 2: Scan BIOS ROM (0x0E0000 to 0x0FFFFF)
    ; 0x0E0000 = segment 0xE000, offset 0
    ; 0x0FFFFF = segment 0xF000, offset 0xFFFF
    ; -------------------------------------------------------------------------
.scan_bios_rom:
    mov ax, 0xE000
    mov es, ax                      ; ES = 0xE000
    xor di, di                      ; DI = 0
    ; Total range size = 0x20000 bytes (128KB).
    ; 128KB / 16-byte steps = 8192 steps.
    mov cx, 8192

.scan_bios_loop:
    call .check_signature
    jnc .found_bios
    add di, 16
    ; If DI wrapped around (exceeded 0xFFFF), increment ES by 0x1000 (ex: 0xE000 -> 0xF000)
    test di, di
    jnz .bios_loop_continue
    mov ax, es
    add ax, 0x1000
    mov es, ax
.bios_loop_continue:
    loop .scan_bios_loop

    ; RSDP not found anywhere
    xor eax, eax
    jmp .done

.found_bios:
    ; Convert ES:DI to 32-bit physical address
    mov ax, es
    xor edx, edx
    mov dx, ax
    shl edx, 4
    xor eax, eax
    mov ax, di
    add edx, eax
    mov eax, edx
    jmp .done

.done:
    pop es
    pop di
    pop si
    pop cx
    ret

; =============================================================================
; .check_signature — verify signature and checksum of RSDP structure at ES:DI
; Input:  ES:DI = address to check
; Output: CF=0 if valid, CF=1 if invalid
; Clobbers: BX, DX, SI
; =============================================================================
.check_signature:
    ; 1. Check signature "RSD PTR " (8 bytes)
    ; "RSD " (first 4 bytes)
    cmp dword [es:di], 0x20445352   ; "RSD " in little-endian ASCII (52 53 44 20)
    jne .invalid
    ; "PTR " (next 4 bytes)
    cmp dword [es:di + 4], 0x20525450 ; "PTR " in little-endian ASCII (50 54 52 20)
    jne .invalid

    ; 2. Validate Checksum of the 20-byte descriptor
    mov si, di                      ; SI = offset
    xor dx, dx                      ; DL = accumulated sum
    mov bx, 20                      ; 20 bytes to sum

.checksum_loop:
    mov al, [es:si]
    add dl, al
    inc si
    dec bx
    jnz .checksum_loop

    test dl, dl                     ; is sum % 256 == 0?
    jnz .invalid                    ; no -> invalid checksum

    clc                             ; CF=0 (valid)
    ret

.invalid:
    stc                             ; CF=1 (invalid)
    ret

%endif ; ACPI_ASM
