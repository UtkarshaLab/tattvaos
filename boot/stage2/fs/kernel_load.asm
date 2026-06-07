; =============================================================================
; Tattva OS — boot/stage2/fs/kernel_load.asm
; =============================================================================
; Raw sector kernel loader (Option A).
; Copies the kernel loaded into temporary real-mode buffer (0x20000)
; to its active, final destination at KERNEL_LOAD (0x100000 / 1MB).
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef KERNEL_LOAD_ASM
%define KERNEL_LOAD_ASM

[BITS 64]

; =============================================================================
; kernel_load — copy kernel from real mode temporary space to final 1MB address
; Input:  none
; Output: none
; Clobbers: none (preserves all)
; =============================================================================
kernel_load:
    push rsi
    push rdi
    push rcx
    cld                             ; Clear direction flag for rep movsq

    ; Source: KERNEL_TEMP loaded by BIOS int 0x13 in real mode
    mov rsi, KERNEL_TEMP            ; source: 0x20000 (KERNEL_TEMP)
    
    ; If RDI is non-zero, use it as the destination address; otherwise fallback to KERNEL_LOAD
    test rdi, rdi
    jnz .use_dest
    mov rdi, KERNEL_LOAD            ; fallback: 0x100000 (1MB)
.use_dest:
    
    ; Copy 64KB (sufficient for early unikernel binaries)
    mov rcx, 65536 / 8              ; number of quadwords (8192 qwords = 64KB)
    rep movsq                       ; copy 64-bit quadwords from [RSI] to [RDI]

    pop rcx
    pop rdi
    pop rsi
    ret

[BITS 16]

%endif ; KERNEL_LOAD_ASM
