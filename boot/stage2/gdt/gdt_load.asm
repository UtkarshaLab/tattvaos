; =============================================================================
; Tattva OS — boot/stage2/gdt/gdt_load.asm
; =============================================================================
; Load the GDT and perform far jump to protected mode.
;
; After lgdt + far jump ALL segment registers must be reloaded.
; Forgetting ANY segment = subtle corruption on real hardware.
; QEMU is forgiving about this. Real hardware is not.
;
; Sequence:
;   1. lgdt [gdt_descriptor]      — load GDT register
;   2. set CR0.PE                  — enable protected mode
;   3. far jump to 32-bit code     — flush pipeline, load CS
;   4. reload DS/ES/FS/GS/SS      — load 64-bit data selector
;   5. reload ESP                  — set protected mode stack
;
; Note: we enter 32-bit protected mode first, then longmode.asm
; switches us to 64-bit long mode. This two-step approach is
; more compatible than jumping directly to 64-bit.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit) → protected mode (32-bit)
; =============================================================================

%ifndef GDT_LOAD_ASM
%define GDT_LOAD_ASM

%include "gdt.asm"

; =============================================================================
; gdt_setup — load GDT and switch to 32-bit protected mode
; Input:  nothing (GDT defined in gdt.asm)
; Output: CPU in 32-bit protected mode
;         all segment registers loaded with flat 32-bit selectors
;         stack at STACK_PROT
; Clobbers: EAX, all segment registers
; =============================================================================
gdt_setup:
    ; -------------------------------------------------------------------------
    ; Step 1: Load GDT register
    ; lgdt reads a 6-byte descriptor: 2-byte limit + 4-byte base
    ; After this the CPU knows where the GDT is but hasn't used it yet
    ; -------------------------------------------------------------------------
    lgdt [gdt_descriptor]

    ; -------------------------------------------------------------------------
    ; Step 2: Disable interrupts
    ; We must not receive any interrupt between CR0 write and segment reload
    ; IDT still points to real mode handlers at this point
    ; -------------------------------------------------------------------------
    cli

    ; -------------------------------------------------------------------------
    ; Step 3: Enable protected mode via CR0.PE
    ; Set bit 0 of CR0 (PE = Protection Enable)
    ; Do NOT set PG (paging) yet — that comes in longmode.asm
    ; -------------------------------------------------------------------------
    mov eax, cr0
    or eax, 0x00000001              ; set CR0.PE
    mov cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 4: Far jump to 32-bit code segment
    ; This MUST immediately follow the CR0 write (no instructions between)
    ; The far jump:
    ;   - Flushes the instruction prefetch queue
    ;   - Loads CS with SEL_CODE32 (32-bit code descriptor)
    ;   - Transfers execution to pm32_entry
    ; -------------------------------------------------------------------------
    jmp SEL_CODE32:pm32_entry

; =============================================================================
; pm32_entry — we are now in 32-bit protected mode
; [BITS 32] section begins here
; =============================================================================
[BITS 32]
pm32_entry:
    ; -------------------------------------------------------------------------
    ; Step 5: Reload ALL data segment registers
    ; After the far jump CS is loaded with SEL_CODE32.
    ; DS, ES, FS, GS, SS still hold real mode segment values.
    ; Their descriptor cache is WRONG for protected mode.
    ; Must reload every single one.
    ;
    ; In 32-bit PM we use SEL_DATA64 as our flat data segment.
    ; (It's a valid 32-bit flat segment even with L=0 D=1)
    ; -------------------------------------------------------------------------
    mov ax, SEL_DATA64              ; 0x10 — flat data descriptor
    mov ds, ax                      ; data segment
    mov es, ax                      ; extra segment
    mov fs, ax                      ; F segment (for TLS later)
    mov gs, ax                      ; G segment (for TLS later)
    mov ss, ax                      ; stack segment

    ; -------------------------------------------------------------------------
    ; Step 6: Set up protected mode stack
    ; Real mode stack was at 0x7C00 or 0x8000
    ; Now we have access to full 4GB flat address space
    ; Stack grows down from STACK_PROT (0x9C000)
    ; -------------------------------------------------------------------------
    mov esp, STACK_PROT

    ; -------------------------------------------------------------------------
    ; continue boot in 32-bit protected mode
    call stage2_main_pm32

    ; never returns
    cli
    hlt

; Switch assembler back to 16-bit for rest of stage2 files
[BITS 16]

%endif ; GDT_LOAD_ASM