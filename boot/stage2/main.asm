; =============================================================================
; Tattva OS — boot/stage2/main.asm
; =============================================================================
; Main stage2 orchestrator.
; Called from entry.asm after UART is initialized.
; Calls each subsystem in strict order.
; Never returns — jumps to kernel at end.
;
; Order (strict — do not reorder):
;   1.  A20 enable
;   2.  CPU feature detection
;   3.  Memory map (E820)
;   4.  GDT setup
;   5.  IDT setup
;   6.  Paging setup
;   7.  Enable SSE/AVX
;   8.  Load kernel from disk
;   9.  Jump to kernel
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef MAIN_ASM
%define MAIN_ASM

; =============================================================================
; stage2_main — main boot orchestrator
; Input:  nothing (uart already initialized)
; Output: never returns
; =============================================================================
stage2_main:

    ; -------------------------------------------------------------------------
    ; STEP 1: Enable A20 line
    ; -------------------------------------------------------------------------
    mov si, msg_a20
    call uart_print

    call a20_enable                 ; try all methods, verify each

    jc .a20_failed                  ; carry set = all methods failed

    mov si, msg_ok
    call uart_println
    jmp .a20_done

.a20_failed:
    mov si, msg_fail
    call uart_println
    mov si, msg_a20_halt
    call uart_println
    jmp .halt

.a20_done:

    ; -------------------------------------------------------------------------
    ; STEP 2: Detect CPU features
    ; -------------------------------------------------------------------------
    mov si, msg_cpu
    call uart_print

    call cpu_detect                 ; fills feature table at FEATURES_DEST

    ; check long mode supported
    mov eax, [FEATURES_DEST]
    test eax, CPU_FEAT_LM           ; long mode flag
    jz .no_longmode

    mov si, msg_ok
    call uart_println
    jmp .cpu_done

.no_longmode:
    mov si, msg_fail
    call uart_println
    mov si, msg_cpu_halt
    call uart_println
    jmp .halt

.cpu_done:

    ; -------------------------------------------------------------------------
    ; STEP 3: Detect memory map (E820)
    ; -------------------------------------------------------------------------
    mov si, msg_mem
    call uart_print

    call e820_detect                ; fills table at E820_DEST
    call e820_parse                 ; find usable regions
    call e820_sort                  ; sort by base address
    call e820_merge                 ; merge overlapping entries

    ; print total usable RAM
    mov si, msg_ram
    call uart_print
    mov eax, [e820_total_mb]        ; total MB filled by e820_parse
    call uart_print_dec
    mov si, msg_mb
    call uart_println

.mem_done:

    ; -------------------------------------------------------------------------
    ; STEP 3.5: Load kernel from disk (Option A)
    ; -------------------------------------------------------------------------
    mov si, msg_kernel
    call uart_print

    mov ax, (KERNEL_TEMP >> 4)      ; segment for KERNEL_TEMP (0x2000)
    mov es, ax
    xor bx, bx                      ; ES:BX = KERNEL_TEMP segment:0x0000

    mov bp, 17                      ; BP = current LBA (starts at 17, next after stage2)
    mov di, KERNEL_SECTORS          ; DI = sectors left to read

.read_loop:
    ; Convert LBA (in BP) to CHS (floppy 1.44MB layout)
    mov ax, bp
    xor dx, dx
    mov cx, 18                      ; 18 sectors per track
    div cx                          ; AX = LBA / 18, DX = LBA % 18
    
    inc dx                          ; DX = Sector (1-indexed, 1 to 18)
    mov cl, dl                      ; CL = Sector
    
    xor dx, dx
    mov cx, 2                       ; 2 Heads
    div cx                          ; AX = Cylinder (AX / 2), DX = Head (AX % 2)
    
    mov ch, al                      ; CH = Cylinder
    mov dh, dl                      ; DH = Head
    
    mov dl, [boot_drive]            ; DL = boot drive
    
    ; Setup retry loop
    mov si, DISK_RETRY              ; SI = retry count (3)

.retry:
    mov ax, 0x0201                  ; AH = 0x02 (read), AL = 0x01 (1 sector)
    int 0x13
    jnc .read_ok                    ; if carry clear, read was successful

    ; read failed, reset disk system (AH=0) and retry
    push ax
    xor ax, ax
    int 0x13
    pop ax
    
    dec si
    jnz .retry                      ; retry if we still have retries left
    
    ; If we ran out of retries, it's a hard failure
    jmp .read_failed

.read_ok:
    ; Successfully read 1 sector!
    add bx, 512                     ; advance buffer offset
    inc bp                          ; advance LBA
    dec di                          ; decrement sectors left
    jnz .read_loop                  ; continue if DI > 0

    ; All sectors read successfully!
    xor ax, ax
    mov es, ax                      ; restore ES to 0x0000
    
    mov si, msg_ok
    call uart_println
    jmp .kernel_done

.read_failed:
    ; AH contains the BIOS error code. Save it in DL
    xor dx, dx
    mov dl, ah
    
    xor ax, ax
    mov es, ax                      ; restore ES to 0x0000
    
    mov si, msg_fail
    call uart_print
    
    ; Print " (Error: 0xXX)"
    mov si, msg_err_prefix
    call uart_print
    
    mov al, dl                      ; AL = error code
    call uart_print_hex8
    
    mov si, msg_err_suffix
    call uart_println
    
    mov si, msg_kernel_halt
    call uart_println
    jmp .halt

.kernel_done:

    ; -------------------------------------------------------------------------
    ; STEP 4: Setup GDT — never returns, continues in 32-bit protected mode
    ; -------------------------------------------------------------------------
    mov si, msg_gdt
    call uart_print

    call gdt_setup                  ; far jumps to pm32_entry, never returns

    ; never reaches here
    jmp .halt

.halt:
    cli
    hlt
    jmp .halt

; =============================================================================
; Strings
; =============================================================================
msg_a20:        db "A20...    ", 0
msg_cpu:        db "CPU...    ", 0
msg_mem:        db "Memory... ", 0
msg_gdt:        db "GDT...    ", 0
msg_idt:        db "IDT...    ", 0
msg_paging:     db "Paging... ", 0
msg_lm:         db "LongMode. ", 0
msg_ok:         db "OK", 0
msg_fail:       db "FAIL", 0
msg_ram:        db "RAM: ", 0
msg_kernel:     db "Kernel... ", 0
msg_err_prefix: db " (Error: ", 0
msg_err_suffix: db ")", 0
msg_a20_halt:   db "HALT: A20 enable failed on all methods", 0
msg_cpu_halt:   db "HALT: CPU does not support long mode", 0
msg_kernel_halt:db "HALT: Kernel load failed", 0

; CPU feature flags (stored at FEATURES_DEST by cpu_detect)
CPU_FEAT_LM     equ (1 << 0)       ; long mode supported
CPU_FEAT_NX     equ (1 << 1)       ; NX/XD bit supported
CPU_FEAT_SSE    equ (1 << 2)       ; SSE supported
CPU_FEAT_SSE2   equ (1 << 3)       ; SSE2 supported
CPU_FEAT_AVX    equ (1 << 4)       ; AVX supported
CPU_FEAT_AVX2   equ (1 << 5)       ; AVX2 supported
CPU_FEAT_AVX512 equ (1 << 6)       ; AVX-512 supported
CPU_FEAT_AMX    equ (1 << 7)       ; AMX supported

; =============================================================================
; stage2_main_pm32 — 32-bit protected mode continuation
; Called from pm32_entry in gdt_load.asm after GDT far jump.
; Continues boot: IDT → paging → long mode.
; Never returns.
; =============================================================================
[BITS 32]
stage2_main_pm32:


    call idt_setup


    call paging_setup

    call simd_enable

    call longmode_enter


    cli
    hlt
[BITS 16]

%endif ; MAIN_ASM