; =============================================================================
; Tattva OS — boot/stage2/cpu/longmode.asm
; =============================================================================
; Verify long mode is supported and enter it.
; Must be called after GDT and paging are set up.
;
; Long mode entry sequence (STRICT ORDER — do not reorder):
;   1. Set PAE bit in CR4         (bit 5)
;   2. Load PML4 address into CR3
;   3. Set LME bit in EFER MSR   (MSR 0xC0000080, bit 8)
;   4. Enable paging + protected mode in CR0 simultaneously
;   5. Far jump to 64-bit code segment
;   6. Reload segment registers in 64-bit code
;   7. Enable SSE/AVX
;
; Any other order = triple fault with no error message.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit) → long mode (64-bit)
; =============================================================================

%ifndef LONGMODE_ASM
%define LONGMODE_ASM

; MSR addresses
MSR_EFER        equ 0xC0000080      ; Extended Feature Enable Register
EFER_LME        equ (1 << 8)        ; Long Mode Enable bit
EFER_NXE        equ (1 << 11)       ; No-Execute Enable bit

; CR0 bits
CR0_PE          equ (1 << 0)        ; Protected mode Enable
CR0_MP          equ (1 << 1)        ; Monitor coProcessor
CR0_EM          equ (1 << 2)        ; EMulation (clear for SSE)
CR0_PG          equ (1 << 31)       ; Paging enable

; CR4 bits
CR4_PAE         equ (1 << 5)        ; Physical Address Extension
CR4_OSFXSR      equ (1 << 9)        ; OS support for FXSAVE/FXRSTOR
CR4_OSXMMEXCPT  equ (1 << 10)       ; OS support for SIMD exceptions
CR4_OSXSAVE     equ (1 << 18)       ; OS support for XSAVE (for AVX)

; =============================================================================
; longmode_check — verify CPU supports long mode
; Input:  [FEATURES_DEST] filled by cpu_detect
; Output: CF=0 supported, CF=1 not supported
; =============================================================================
longmode_check:
    mov eax, [FEATURES_DEST]
    test eax, CPU_FEAT_LM
    jz .not_supported
    clc
    ret
.not_supported:
    stc
    ret

[BITS 32]
; =============================================================================
; longmode_enter — switch from protected mode to long mode
; Input:  GDT loaded, paging set up, PML4 at PAGING_PML4
; Output: never returns in protected mode
;         execution continues in 64-bit code after far jump
; =============================================================================
longmode_enter:


    ; -------------------------------------------------------------------------
    ; STEP 1: Enable PAE in CR4
    ; PAE must be set before loading CR3 or enabling LME
    ; -------------------------------------------------------------------------
    mov eax, cr4
    or eax, CR4_PAE                 ; set PAE bit
    or eax, CR4_OSFXSR              ; enable FXSAVE/FXRSTOR (for SSE)
    or eax, CR4_OSXMMEXCPT          ; enable SIMD exception handling
    mov cr4, eax

    ; -------------------------------------------------------------------------
    ; STEP 2: Load PML4 physical address into CR3
    ; CR3 = physical address of PML4 page table
    ; Bits 11:0 of CR3 are control flags (cache disable, etc.)
    ; We use 0 for flags (enable caching, write-back)
    ; -------------------------------------------------------------------------
    mov eax, PAGING_PML4            ; PML4 physical address
    mov cr3, eax


    ; -------------------------------------------------------------------------
    ; STEP 3: Enable LME in EFER MSR
    ; Read EFER, set LME bit, write back
    ; Also enable NXE if CPU supports NX
    ; -------------------------------------------------------------------------
    mov ecx, MSR_EFER
    rdmsr                           ; EDX:EAX = EFER
    or eax, EFER_LME                ; set Long Mode Enable

    ; enable NX if supported
    mov ebx, [FEATURES_DEST]
    test ebx, CPU_FEAT_NX
    jz .no_nx_enable
    or eax, EFER_NXE                ; set No-Execute Enable
.no_nx_enable:


    wrmsr                           ; write back EFER


    ; -------------------------------------------------------------------------
    ; STEP 4: Enable paging and protected mode simultaneously in CR0
    ; CRITICAL: must set PG and PE in the same write
    ; Both bits set in one mov cr0 instruction
    ; -------------------------------------------------------------------------
    mov eax, cr0
    or eax, (CR0_PE | CR0_PG)      ; set PE + PG together
    and eax, ~CR0_EM                ; clear EM (enable SSE, not emulation)
    or eax, CR0_MP                  ; set MP (monitor coprocessor)


    mov cr0, eax


    ; -------------------------------------------------------------------------
    ; STEP 5: Far jump to 64-bit code segment
    ; This flushes the instruction pipeline and activates long mode.
    ; SEL_CODE64 = 0x08 (64-bit code descriptor in GDT)
    ; longmode_64 = entry point in 64-bit code
    ; -------------------------------------------------------------------------
    jmp SEL_CODE64:longmode_64

; =============================================================================
; longmode_64 — we are now in 64-bit long mode
; All code below is [BITS 64]
; =============================================================================
[BITS 64]
longmode_64:

    ; -------------------------------------------------------------------------
    ; STEP 6: Reload all data segment registers
    ; After far jump: CS is loaded with 64-bit descriptor
    ; DS/ES/FS/GS/SS still have protected mode values
    ; Must reload with 64-bit data selector
    ; Forgetting ANY segment = subtle corruption bugs
    ; -------------------------------------------------------------------------
    mov ax, SEL_DATA64              ; 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; set up 64-bit stack
    mov rsp, STACK_LONG             ; 64-bit stack pointer

    ; -------------------------------------------------------------------------
    ; STEP 7: Enable AVX via XSETBV if supported
    ; CR4.OSXSAVE must be set first, then XSETBV sets XCR0
    ; -------------------------------------------------------------------------
    mov eax, [FEATURES_DEST]
    test eax, CPU_FEAT_AVX
    jz .no_avx_enable

    ; set CR4.OSXSAVE
    mov rax, cr4
    or rax, CR4_OSXSAVE
    mov cr4, rax

    ; set XCR0: enable x87, SSE, AVX
    xor rcx, rcx                    ; XCR0 index = 0
    xgetbv                          ; read XCR0 into EDX:EAX
    or eax, 0x07                    ; bit 0=x87, bit 1=SSE, bit 2=AVX
    xsetbv                          ; write back

.no_avx_enable:

    ; -------------------------------------------------------------------------
    ; STEP 8: Print confirmation via UART
    ; (UART still works in long mode, same port I/O)
    ; -------------------------------------------------------------------------
    mov rsi, msg_longmode_ok
    call uart_print_64              ; note: uart_print needs 64-bit version

    ; -------------------------------------------------------------------------
    ; STEP 9: Load and jump to kernel
    ; This is where we load the ULF kernel binary
    ; and jump to its entry point
    ; -------------------------------------------------------------------------
    call kernel_load                ; load kernel from disk to KERNEL_LOAD
    jmp KERNEL_LOAD                 ; jump to kernel entry point

    ; never reaches here
    cli
    hlt

; =============================================================================
; kernel_load stub — replaced when fs/ modules are ready
; =============================================================================
kernel_load:
    ; stub: kernel loading not yet implemented
    ; when stage2/fs/ is ready this loads ULF kernel from disk
    ret

; =============================================================================
; Data (in 64-bit section)
; =============================================================================
msg_longmode_ok:    db "Long mode OK", 0x0D, 0x0A, 0

; Switch back to 16-bit for rest of stage2
[BITS 16]

%endif ; LONGMODE_ASM