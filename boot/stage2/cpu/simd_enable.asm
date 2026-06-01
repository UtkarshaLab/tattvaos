; boot/stage2/cpu/simd_enable.asm
; Enable SSE/AVX before kernel handoff
;
; MUST be done in bootloader — kernel uses SIMD from first instruction
;
; Steps:
;   1. Clear CR0.EM (bit 2), set CR0.MP (bit 1)
;   2. Set CR4.OSFXSR (bit 9), CR4.OSXMMEXCPT (bit 10)
;   3. Enable AVX via XSETBV if XSAVE is available (check CPUID first)

simd_enable:
    ; Step 1: Fix CR0 flags for SSE
    ; TODO: mov eax, cr0 / and eax, ~(1 << 2) / or eax, (1 << 1) / mov cr0, eax

    ; Step 2: Enable OS support for FXSAVE and SSE exceptions in CR4
    ; TODO: mov eax, cr4 / or eax, (1 << 9) | (1 << 10) / mov cr4, eax

    ; Step 3: Enable AVX via XSETBV (XCR0 register)
    ; TODO: check CPUID for XSAVE support first
    ; TODO: xor ecx, ecx / xgetbv / or eax, 0x7 / xsetbv

    ret
