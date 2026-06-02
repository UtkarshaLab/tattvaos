; =============================================================================
; Tattva OS — boot/stage2/cpu/cpuid.asm
; =============================================================================
; CPU feature detection using CPUID instruction.
; Stores results at FEATURES_DEST for use by kernel and bootloader.
;
; Features detected:
;   Long mode (64-bit)      — required, halt if absent
;   NX/XD bit               — no-execute page protection
;   SSE / SSE2              — basic SIMD
;   AVX / AVX2              — 256-bit SIMD
;   AVX-512                 — 512-bit SIMD (inference kernels)
;   AMX                     — matrix extensions (Intel, inference)
;
; Feature flags layout at FEATURES_DEST (dword):
;   Bit 0: long mode
;   Bit 1: NX bit
;   Bit 2: SSE
;   Bit 3: SSE2
;   Bit 4: AVX
;   Bit 5: AVX2
;   Bit 6: AVX-512F
;   Bit 7: AMX
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode → protected mode (32-bit CPUID calls)
; =============================================================================

%ifndef CPUID_ASM
%define CPUID_ASM

; =============================================================================
; cpu_detect — detect CPU features, store at FEATURES_DEST
; Input:  nothing
; Output: [FEATURES_DEST] = feature flags dword
; Clobbers: EAX, EBX, ECX, EDX
; =============================================================================
cpu_detect:
    push eax
    push ebx
    push ecx
    push edx

    ; initialize features to 0
    mov dword [FEATURES_DEST], 0

    ; -------------------------------------------------------------------------
    ; First: check CPUID is supported
    ; Method: try to flip bit 21 of EFLAGS (ID flag)
    ; If it can be flipped, CPUID is supported
    ; -------------------------------------------------------------------------
    pushfd                          ; save EFLAGS
    pop eax                         ; EAX = EFLAGS
    mov ebx, eax                    ; save original
    xor eax, (1 << 21)             ; flip bit 21 (ID flag)
    push eax
    popfd                           ; write modified EFLAGS
    pushfd
    pop eax                         ; read back
    push ebx
    popfd                           ; restore original EFLAGS

    xor eax, ebx                    ; did bit 21 change?
    jz .no_cpuid                    ; no change = CPUID not supported

    ; -------------------------------------------------------------------------
    ; CPUID leaf 0: get vendor string + max basic leaf
    ; -------------------------------------------------------------------------
    xor eax, eax
    cpuid
    ; EAX = max basic leaf
    ; EBX:EDX:ECX = vendor string (ignored for now)
    mov [cpu_max_leaf], eax

    ; -------------------------------------------------------------------------
    ; CPUID leaf 1: standard features
    ; EDX bits we care about:
    ;   bit 25: SSE
    ;   bit 26: SSE2
    ; ECX bits we care about:
    ;   bit 28: AVX
    ; -------------------------------------------------------------------------
    cmp dword [cpu_max_leaf], 1
    jb .check_extended              ; leaf 1 not supported

    mov eax, 1
    cpuid

    ; SSE (EDX bit 25)
    test edx, (1 << 25)
    jz .no_sse
    or dword [FEATURES_DEST], CPU_FEAT_SSE
.no_sse:

    ; SSE2 (EDX bit 26)
    test edx, (1 << 26)
    jz .no_sse2
    or dword [FEATURES_DEST], CPU_FEAT_SSE2
.no_sse2:

    ; AVX (ECX bit 28)
    test ecx, (1 << 28)
    jz .no_avx
    or dword [FEATURES_DEST], CPU_FEAT_AVX
.no_avx:

    ; -------------------------------------------------------------------------
    ; CPUID leaf 7: extended features (AVX2, AVX-512, AMX)
    ; EBX bits:
    ;   bit 5:  AVX2
    ;   bit 16: AVX-512F
    ; EDX bits:
    ;   bit 22: AMX-BF16
    ;   bit 24: AMX-TILE
    ; -------------------------------------------------------------------------
    cmp dword [cpu_max_leaf], 7
    jb .check_extended

    mov eax, 7
    xor ecx, ecx                    ; sub-leaf 0
    cpuid

    ; AVX2 (EBX bit 5)
    test ebx, (1 << 5)
    jz .no_avx2
    or dword [FEATURES_DEST], CPU_FEAT_AVX2
.no_avx2:

    ; AVX-512F (EBX bit 16)
    test ebx, (1 << 16)
    jz .no_avx512
    or dword [FEATURES_DEST], CPU_FEAT_AVX512
.no_avx512:

    ; AMX-TILE (EDX bit 24)
    test edx, (1 << 24)
    jz .no_amx
    or dword [FEATURES_DEST], CPU_FEAT_AMX
.no_amx:

.check_extended:
    ; -------------------------------------------------------------------------
    ; CPUID extended leaf 0x80000000: max extended leaf
    ; -------------------------------------------------------------------------
    mov eax, 0x80000000
    cpuid
    mov [cpu_max_ext_leaf], eax

    cmp eax, 0x80000001
    jb .detect_done                 ; extended leaf 1 not supported

    ; -------------------------------------------------------------------------
    ; CPUID extended leaf 0x80000001: extended features
    ; EDX bits:
    ;   bit 29: long mode (64-bit)
    ;   bit 20: NX/XD bit
    ; -------------------------------------------------------------------------
    mov eax, 0x80000001
    cpuid

    ; Long mode (EDX bit 29) — REQUIRED
    test edx, (1 << 29)
    jz .no_longmode_feat
    or dword [FEATURES_DEST], CPU_FEAT_LM
.no_longmode_feat:

    ; NX bit (EDX bit 20)
    test edx, (1 << 20)
    jz .no_nx
    or dword [FEATURES_DEST], CPU_FEAT_NX
.no_nx:

    jmp .detect_done

.no_cpuid:
    ; CPUID not supported — very old CPU, definitely no long mode
    ; features remain 0

.detect_done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; cpu_print_features — debug: print detected features via UART
; Input:  nothing (reads from FEATURES_DEST)
; Output: prints feature list
; =============================================================================
cpu_print_features:
    push eax
    push si

    mov eax, [FEATURES_DEST]

    mov si, msg_cpu_features
    call uart_println

    test eax, CPU_FEAT_LM
    jz .no_lm_print
    mov si, msg_feat_lm
    call uart_println
.no_lm_print:

    test eax, CPU_FEAT_NX
    jz .no_nx_print
    mov si, msg_feat_nx
    call uart_println
.no_nx_print:

    test eax, CPU_FEAT_SSE
    jz .no_sse_print
    mov si, msg_feat_sse
    call uart_println
.no_sse_print:

    test eax, CPU_FEAT_SSE2
    jz .no_sse2_print
    mov si, msg_feat_sse2
    call uart_println
.no_sse2_print:

    test eax, CPU_FEAT_AVX
    jz .no_avx_print
    mov si, msg_feat_avx
    call uart_println
.no_avx_print:

    test eax, CPU_FEAT_AVX2
    jz .no_avx2_print
    mov si, msg_feat_avx2
    call uart_println
.no_avx2_print:

    test eax, CPU_FEAT_AVX512
    jz .no_avx512_print
    mov si, msg_feat_avx512
    call uart_println
.no_avx512_print:

    test eax, CPU_FEAT_AMX
    jz .no_amx_print
    mov si, msg_feat_amx
    call uart_println
.no_amx_print:

    pop si
    pop eax
    ret

; =============================================================================
; Data
; =============================================================================
cpu_max_leaf:       dd 0            ; max basic CPUID leaf
cpu_max_ext_leaf:   dd 0            ; max extended CPUID leaf

msg_cpu_features:   db "CPU features:", 0
msg_feat_lm:        db "  [+] Long mode (64-bit)", 0
msg_feat_nx:        db "  [+] NX/XD bit", 0
msg_feat_sse:       db "  [+] SSE", 0
msg_feat_sse2:      db "  [+] SSE2", 0
msg_feat_avx:       db "  [+] AVX", 0
msg_feat_avx2:      db "  [+] AVX2", 0
msg_feat_avx512:    db "  [+] AVX-512F", 0
msg_feat_amx:       db "  [+] AMX", 0

%endif ; CPUID_ASM