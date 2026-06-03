; =============================================================================
; Tattva OS — boot/survive/recover.asm
; =============================================================================
; Handles the transition from 64-bit long mode back to 16-bit real mode,
; reloads KERNEL.ULF, transitions back to 64-bit, restores the snapshot state,
; and resumes kernel execution (warm boot recovery).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode) & real mode (16-bit)
; =============================================================================

%ifndef SURVIVE_RECOVER_ASM
%define SURVIVE_RECOVER_ASM

%include "config.asm"

[BITS 64]

global survive_recover
extern fs_load_kernel
extern kernel_load
extern gdt_descriptor
extern boot_drive
extern sectors_per_track
extern number_of_heads

; =============================================================================
; survive_recover — main recovery entry point (called in 64-bit mode)
; =============================================================================
survive_recover:
    cli                             ; disable interrupts

    ; Push 16-bit Compatibility CS (0x18) and the offset of compat_mode
    push word 0x18                  ; CS = SEL_CODE16
    lea rax, [compat_mode]
    push rax
    retf                            ; far return jumps to 16-bit protected mode

[BITS 16]
compat_mode:
    ; Load 16-bit data selector into data segment registers
    mov ax, 0x10                    ; SEL_DATA64 (writable data segment)
    mov ds, ax
    mov es, ax
    mov ss, ax

    ; Disable Paging (clear CR0.PG)
    mov eax, cr0
    and eax, ~0x80000000            ; clear PG (bit 31)
    mov cr0, eax

    ; Disable Long Mode (clear EFER.LME)
    mov ecx, 0xC0000080             ; EFER MSR
    rdmsr
    and eax, ~0x00000100            ; clear LME (bit 8)
    wrmsr

    ; Disable Protected Mode (clear CR0.PE)
    mov eax, cr0
    and eax, ~0x00000001            ; clear PE (bit 0)
    mov cr0, eax

    ; Far jump to enter 16-bit real mode and reload CS (0x0000)
    jmp 0x0000:real_mode_entry

real_mode_entry:
    ; We are now in 16-bit real mode!
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x8000                  ; temporary real-mode stack pointer

    ; Load real-mode IVT (limit 0x3FF, base 0)
    lidt [real_idt_descriptor]

    sti                             ; enable interrupts for BIOS disk calls

    ; Print message via UART (using 16-bit stage2 print routines)
    mov si, msg_reloading
    call uart_println

    ; Try loading kernel via FAT32 filesystem
    call fs_load_kernel
    test ax, ax
    jnz .load_success

    ; Fallback to raw sector loader if filesystem load failed
    mov si, msg_recover_fallback
    call uart_println
    call load_kernel_raw

.load_success:
    cli                             ; disable interrupts before switching modes

    ; Re-enable Protected Mode
    mov eax, cr0
    or eax, 1                       ; set PE (bit 0)
    mov cr0, eax

    ; Load GDT
    lgdt [gdt_descriptor]

    ; Re-enable PAE
    mov eax, cr4
    or eax, 0x20                    ; set PAE (bit 5)
    mov cr4, eax

    ; Load PML4 page table pointer into CR3
    mov eax, 0x10000                ; PAGING_PML4
    mov cr3, eax

    ; Re-enable LME in EFER MSR
    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x00000100              ; set LME (bit 8)
    wrmsr

    ; Re-enable Paging
    mov eax, cr0
    or eax, 0x80000000              ; set PG (bit 31)
    mov cr0, eax

    ; Far jump back to 64-bit mode using retf
    push word 0x08                  ; CS = SEL_CODE64 (0x08)
    push word longmode_recovery     ; IP = 16-bit offset of longmode_recovery
    retf

[BITS 64]
longmode_recovery:
    ; Reload data segment registers
    mov ax, 0x10                    ; SEL_DATA64
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Setup temporary safe stack
    mov rsp, 0x9C000                ; STACK_LONG

    ; Copy reloaded kernel from KERNEL_TEMP (0x20000) to KERNEL_LOAD (0x100000)
    call kernel_load

    ; Restore CR3 (pristine PML4 address)
    mov rax, [0x9090]
    mov cr3, rax

    ; Restore CR0
    mov rax, [0x9080]
    mov cr0, rax

    ; Restore CR4
    mov rax, [0x9098]
    mov cr4, rax

    ; Restore GDTR and IDTR
    lgdt [0x90E0]
    lidt [0x90F0]

    ; Restore Stack contents
    cld                             ; Clear direction flag for forward copy
    mov rdi, [0x9038]               ; RDI = pristine RSP
    mov rsi, 0x9100                 ; RSI = stack backup
    mov rcx, 192                    ; 192 * 8 = 1536 bytes
    rep movsq

    ; Restore general-purpose registers (except RSP and RAX)
    mov rbx, [0x9008]
    mov rcx, [0x9010]
    mov rdx, [0x9018]
    mov rsi, [0x9020]
    mov rdi, [0x9028]
    mov rbp, [0x9030]
    mov r8,  [0x9040]
    mov r9,  [0x9048]
    mov r10, [0x9050]
    mov r11, [0x9058]
    mov r12, [0x9060]
    mov r13, [0x9068]
    mov r14, [0x9070]
    mov r15, [0x9078]

    ; Restore stack pointer
    mov rsp, [0x9038]

    ; Restore RFLAGS
    push qword [0x90D0]
    popfq

    ; Restore RAX (last register)
    mov rax, [0x9000]

    ; Jump to the pristine RIP
    jmp [0x90D8]

[BITS 16]
; =============================================================================
; load_kernel_raw — 16-bit real-mode raw sector disk loader
; =============================================================================
load_kernel_raw:
    pusha
    push es

    ; Destination segment
    mov ax, (KERNEL_TEMP >> 4)
    mov es, ax
    xor bx, bx                      ; ES:BX = 0x2000:0x0000

    ; Check if LBA is supported on the boot drive
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc .chs_fallback
    cmp bx, 0xAA55
    jne .chs_fallback

    ; LBA is supported, attempt LBA read
    mov cx, 3                       ; retry count
.lba_retry:
    push cx
    mov si, recover_lba_packet
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    pop cx
    jnc .done
    
    ; Reset disk
    xor ax, ax
    mov dl, [boot_drive]
    int 0x13
    dec cx
    jnz .lba_retry
    jmp .chs_fallback

.chs_fallback:
    ; Read sector-by-sector CHS
    mov bp, 17                      ; BP = current LBA (starts at 17)
    mov di, KERNEL_SECTORS          ; DI = sectors count (64)
.read_loop:
    ; Convert BP (LBA) to CHS using dynamic variables
    mov ax, bp
    xor dx, dx
    mov cx, [sectors_per_track]
    test cx, cx
    jz .failed
    div cx                          ; AX = LBA / sectors_per_track, DX = LBA % sectors_per_track
    inc dx                          ; DX = Sector
    mov cl, dl
    
    xor dx, dx
    mov cx, [number_of_heads]
    test cx, cx
    jz .failed
    div cx                          ; AX = Cylinder, DX = Head
    
    mov ch, al                      ; low 8 bits of cylinder
    shl ah, 6
    or cl, ah                       ; cylinder bits 8-9
    
    mov dh, dl                      ; DH = Head
    mov dl, [boot_drive]            ; DL = boot drive

    mov si, 3                       ; retry count
.retry:
    mov ax, 0x0201                  ; Read 1 sector
    int 0x13
    jnc .read_ok

    ; Reset disk
    push ax
    xor ax, ax
    int 0x13
    pop ax
    dec si
    jnz .retry
    jmp .failed

.read_ok:
    add bx, 512
    inc bp
    dec di
    jnz .read_loop
    jmp .done

.failed:
    ; Fatal error reloading kernel. Reboot.
    mov si, msg_recover_failed
    call uart_println
    mov al, 0xFE
    out 0x64, al
    cli
    hlt

.done:
    pop es
    popa
    ret

align 2
real_idt_descriptor:
    dw 0x3FF                        ; limit (1024 bytes)
    dd 0x00000000                   ; base address (0x00000000)

align 4
recover_lba_packet:
    db 0x10                         ; packet size = 16 bytes
    db 0x00                         ; reserved = 0
    dw KERNEL_SECTORS               ; number of sectors
    dw 0x0000                       ; offset
    dw (KERNEL_TEMP >> 4)           ; segment (0x2000)
    dq 17                           ; starting LBA

; 16-bit strings
msg_reloading:          db "Recovery: reloading kernel...", 0
msg_recover_fallback:   db "Recovery: FAT32 load failed, falling back to raw sectors...", 0
msg_recover_failed:     db "Recovery: FAILED to reload kernel! Rebooting...", 0

%endif ; SURVIVE_RECOVER_ASM
