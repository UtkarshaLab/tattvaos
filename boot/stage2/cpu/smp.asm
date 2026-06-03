; =============================================================================
; Tattva OS — boot/stage2/cpu/smp.asm
; =============================================================================
; Early Symmetric Multiprocessing (SMP) AP Bootstrap and Core Parking.
; Initializes Local APIC, sends INIT/SIPI to wake secondary cores, and parks them
; in a safe 64-bit long mode halt loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit) -> long mode (64-bit)
; =============================================================================

%ifndef SMP_ASM
%define SMP_ASM

[BITS 16]

; Local APIC Register Offsets
LAPIC_BASE          equ 0xFEE00000
LAPIC_ICR_LOW       equ 0x300
LAPIC_ICR_HIGH      equ 0x310

; AP Trampoline Physical Address
TRAMPOLINE_ADDR     equ 0x4000

; =============================================================================
; smp_init_cores — Wake Application Processors (APs) and count them
; Input:  none
; Output: [smp_core_count] updated in memory
; =============================================================================
smp_init_cores:
    pusha
    push es
    push ds

    ; 1. Copy Trampoline code to 0x4000
    xor ax, ax
    mov ds, ax
    mov es, ax
    
    mov si, ap_trampoline_start
    mov di, TRAMPOLINE_ADDR
    mov cx, ap_trampoline_end - ap_trampoline_start
    cld
    rep movsb

    ; 2. Initialize active cores counter (BSP is core 1)
    mov dword [smp_active_cores], 1

    ; 3. Send INIT IPI to all APs (excluding self)
    ; Destination Shorthand: 0xC0000 (All excluding self)
    ; Delivery Mode: INIT (0x500)
    ; Level: Assert (0x4000)
    ; ICR Low: 0x000C4500
    mov eax, 0x000C4500
    mov [LAPIC_BASE + LAPIC_ICR_LOW], eax

    ; Wait 10ms (using BIOS wait INT 15h AH=86h)
    mov cx, 0x000F                   ; CX:DX = 10000 microseconds = 10ms
    mov dx, 0x4240
    mov ah, 0x86
    int 0x15

    ; 4. Send 1st Startup IPI (SIPI)
    ; Destination Shorthand: 0xC0000
    ; Delivery Mode: StartUp (0x600)
    ; Vector: 0x04 (maps to page 0x04000)
    ; ICR Low: 0x000C4604
    mov eax, 0x000C4604
    mov [LAPIC_BASE + LAPIC_ICR_LOW], eax

    ; Wait 200 microseconds
    mov cx, 0
    mov dx, 200
    mov ah, 0x86
    int 0x15

    ; Send 2nd Startup IPI (SIPI)
    mov eax, 0x000C4604
    mov [LAPIC_BASE + LAPIC_ICR_LOW], eax

    ; Wait 15ms for APs to check-in
    mov cx, 0x0016
    mov dx, 0xE360
    mov ah, 0x86
    int 0x15

    ; 5. Update BootInfo core count
    mov eax, [smp_active_cores]
    mov [smp_core_count], eax

    ; Populate BootInfo field
    mov edi, BOOT_INFO_ADDR
    mov [edi + 80], eax              ; BOOT_INFO_SMP_CORES (offset 80 = 0x7050)

    pop ds
    pop es
    popa
    ret

smp_core_count:    dd 1
smp_active_cores:  dd 1

; =============================================================================
; AP Trampoline Code Template
; Target: Starts in 16-bit real mode at 0x4000
; =============================================================================
align 16
ap_trampoline_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x3F00                   ; Local stack for this AP (grows down from 0x3F00)

    ; Load GDT
    lgdt [cs:ap_gdtr - ap_trampoline_start + TRAMPOLINE_ADDR]

    ; Transition to 32-bit protected mode
    mov eax, cr0
    or eax, 1                        ; set PE
    mov cr0, eax

    ; Far jump to 32-bit code segment
    jmp 0x08:(ap_pm32 - ap_trampoline_start + TRAMPOLINE_ADDR)

[BITS 32]
ap_pm32:
    mov ax, 0x10                     ; data selector
    mov ds, ax
    mov es, ax
    mov ss, ax

    ; Enable PAE
    mov eax, cr4
    or eax, 0x20                     ; set PAE
    mov cr4, eax

    ; Load CR3 (PML4)
    mov eax, PAGING_PML4
    mov cr3, eax

    ; Enable Long Mode in EFER MSR
    mov ecx, 0xC0000080              ; EFER
    rdmsr
    or eax, 1 << 8                   ; set LME
    wrmsr

    ; Enable Paging and Protected Mode
    mov eax, cr0
    or eax, 0x80000001               ; set PG and PE
    mov cr0, eax

    ; Far jump to 64-bit code segment
    jmp 0x18:(ap_long64 - ap_trampoline_start + TRAMPOLINE_ADDR)

[BITS 64]
ap_long64:
    ; Reload segments in 64-bit mode
    mov ax, 0x20                     ; data selector (SEL_DATA64 in stage2 GDT is 0x10, wait! Let's check GDT descriptors)
    ; In trampoline GDT:
    ; Code32 = 0x08, Data32 = 0x10
    ; Code64 = 0x18, Data64 = 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax

    ; Safely increment global core counter
    lock inc dword [rel smp_active_cores]

.park_loop:
    cli
    hlt
    jmp .park_loop

; Trampoline local GDT
align 16
ap_gdt:
    dq 0x0000000000000000            ; Null descriptor
    dq 0x00CF9A000000FFFF            ; 32-bit Code (0x08), base=0, limit=4GB
    dq 0x00CF92000000FFFF            ; 32-bit Data (0x10), base=0, limit=4GB
    dq 0x00209A0000000000            ; 64-bit Code (0x18)
    dq 0x0000920000000000            ; 64-bit Data (0x20)
ap_gdt_end:

align 4
ap_gdtr:
    dw ap_gdt_end - ap_gdt - 1       ; limit
    dd ap_gdt - ap_trampoline_start + TRAMPOLINE_ADDR ; base address

ap_trampoline_end:

[BITS 16]
%endif ; SMP_ASM
