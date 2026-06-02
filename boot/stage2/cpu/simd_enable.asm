; =============================================================================
; Tattva OS — boot/stage2/cpu/simd_enable.asm
; =============================================================================
; Enable SSE and AVX SIMD coprocessor features.
; Must be called in 32-bit Protected Mode before entering Long Mode.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef SIMD_ENABLE_ASM
%define SIMD_ENABLE_ASM

[BITS 32]

; =============================================================================
; simd_enable — configure CR0, CR4, and XCR0 to enable SSE and AVX
; =============================================================================
simd_enable:
    push eax
    push ecx
    push edx

    ; -------------------------------------------------------------------------
    ; Step 1: Configure CR0 flags
    ; Clear CR0.EM (bit 2) — disable x87 emulation
    ; Set CR0.MP (bit 1)   — monitor coprocessor (required for SSE)
    ; -------------------------------------------------------------------------
    mov eax, cr0
    and eax, ~0x00000004            ; clear EM
    or eax, 0x00000002              ; set MP
    mov cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 2: Configure CR4 flags
    ; Set CR4.OSFXSR (bit 9)      — enable FXSAVE/FXRSTOR for SSE registers
    ; Set CR4.OSXMMEXCPT (bit 10) — enable unmasked SIMD floating-point exceptions
    ; -------------------------------------------------------------------------
    mov eax, cr4
    or eax, (1 << 9) | (1 << 10)    ; set OSFXSR + OSXMMEXCPT
    mov cr4, eax

    ; -------------------------------------------------------------------------
    ; Step 3: Enable AVX via XCR0 if supported by hardware
    ; Query CPUID basic leaf 1 to check for XSAVE support (ECX bit 26)
    ; If XSAVE is supported, we can set XCR0 flags.
    ; -------------------------------------------------------------------------
    mov eax, 1
    cpuid
    test ecx, (1 << 26)             ; check XSAVE bit
    jz .no_avx

    ; Set CR4.OSXSAVE (bit 18) to allow XSETBV/XGETBV instructions
    mov eax, cr4
    or eax, (1 << 18)
    mov cr4, eax

    ; Set XCR0: enable bit 0 (x87), bit 1 (SSE), bit 2 (AVX)
    xor ecx, ecx                    ; XCR0 index = 0
    xgetbv                          ; read current XCR0 into EDX:EAX
    or eax, 0x07                    ; set x87 + SSE + AVX flags
    xsetbv                          ; write back XCR0

.no_avx:
    pop edx
    pop ecx
    pop eax
    ret

[BITS 16]

%endif ; SIMD_ENABLE_ASM
