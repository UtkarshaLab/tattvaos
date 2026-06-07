; =============================================================================
; umath - unified math library
; dtype/dtype_support.asm - runtime hardware support per dtype
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_family.asm
;
; description:
;   queries CPU feature flags at runtime to determine which dtypes
;   can be used with native hardware instructions
;   results cached after first call to avoid repeated CPUID
;
;   support levels:
;     SUPPORT_NONE     = 0  not supported, no fallback
;     SUPPORT_SOFTWARE = 1  supported via software emulation only
;     SUPPORT_PARTIAL  = 2  partial hardware (some ops native)
;     SUPPORT_NATIVE   = 3  full native hardware support
;
; functions:
;   umath_dtype_support_init      ()         → void  (call once at startup)
;   umath_dtype_supported         (dtype_id) → bool
;   umath_dtype_support_level     (dtype_id) → u32   SUPPORT_* constant
;   umath_dtype_support_avx512f   ()         → bool
;   umath_dtype_support_avx512bf16()         → bool
;   umath_dtype_support_avx512fp16()         → bool
;   umath_dtype_support_avx512vnni()         → bool
;   umath_dtype_support_avx2      ()         → bool
;   umath_dtype_support_amx       ()         → bool
;   umath_dtype_support_matrix    ()         → *support_table
; =============================================================================

%include "dtype_id.asm"
%include "dtype_family.asm"

bits 64

; =============================================================================
; support level constants
; =============================================================================

SUPPORT_NONE        equ 0
SUPPORT_SOFTWARE    equ 1
SUPPORT_PARTIAL     equ 2
SUPPORT_NATIVE      equ 3

; =============================================================================
; cached CPU feature flags (set by umath_dtype_support_init)
; =============================================================================

section .bss
align 8

cpu_features_cached:    db 0        ; 1 = cache is valid
cpu_has_avx2:           db 0
cpu_has_avx512f:        db 0
cpu_has_avx512bw:       db 0
cpu_has_avx512dq:       db 0
cpu_has_avx512vl:       db 0
cpu_has_avx512vnni:     db 0
cpu_has_avx512bf16:     db 0
cpu_has_avx512fp16:     db 0
cpu_has_avx512vpopcntdq: db 0
cpu_has_amx_tile:       db 0
cpu_has_amx_bf16:       db 0
cpu_has_amx_int8:       db 0
cpu_has_bmi2:           db 0
cpu_has_popcnt:         db 0
cpu_has_lzcnt:          db 0
cpu_has_f16c:           db 0       ; VCVTPH2PS / VCVTPS2PH
align 8

; support level cache (one byte per dtype_id, up to 0x200)
dtype_support_cache:    times 0x200 db 0xFF  ; 0xFF = not computed yet

section .text

; =============================================================================
; CPUID helpers
; =============================================================================

; -----------------------------------------------------------------------------
; detect_cpu_features - run CPUID and cache all relevant feature flags
; clobbers: rax, rbx, rcx, rdx
; -----------------------------------------------------------------------------
detect_cpu_features:
    push    rbx
    push    r12

    ; check CPUID max leaf
    xor     eax, eax
    cpuid
    cmp     eax, 7
    jl      .no_leaf7

    ; leaf 1: basic features
    mov     eax, 1
    cpuid
    ; ecx bit 23 = POPCNT
    bt      ecx, 23
    setc    [rel cpu_has_popcnt]
    ; ecx bit 29 = F16C (VCVTPH2PS)
    bt      ecx, 29
    setc    [rel cpu_has_f16c]

    ; leaf 7, subleaf 0: extended features
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    ; ebx bit 5  = AVX512F
    bt      ebx, 5
    setc    [rel cpu_has_avx512f]
    ; ebx bit 16 = AVX512F (AVX-512 enabled)
    ; ebx bit 30 = AVX512BW
    bt      ebx, 30
    setc    [rel cpu_has_avx512bw]
    ; ebx bit 17 = AVX512DQ
    bt      ebx, 17
    setc    [rel cpu_has_avx512dq]
    ; ebx bit 31 = AVX512VL
    bt      ebx, 31
    setc    [rel cpu_has_avx512vl]
    ; ebx bit 3  = BMI2
    bt      ebx, 8
    setc    [rel cpu_has_avx2]      ; AVX2 is bit 5 of ebx, corrected below
    bt      ebx, 5
    ; already handled AVX512F above
    ; ecx bit 11 = AVX512VNNI
    bt      ecx, 11
    setc    [rel cpu_has_avx512vnni]
    ; ecx bit 12 = AVX512BITALG
    ; ecx bit 14 = AVX512VPOPCNTDQ
    bt      ecx, 14
    setc    [rel cpu_has_avx512vpopcntdq]

    ; AVX2: leaf 7 ebx bit 5
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    bt      ebx, 5                  ; re-read for AVX2 (bit 5 = AVX2 in leaf7)
    setc    [rel cpu_has_avx2]
    ; BMI2: leaf 7 ebx bit 8
    bt      ebx, 8
    setc    [rel cpu_has_bmi2]

    ; leaf 7 subleaf 1: AVX512BF16, AVX512FP16
    mov     eax, 7
    mov     ecx, 1
    cpuid
    ; eax bit 5 = AVX512BF16
    bt      eax, 5
    setc    [rel cpu_has_avx512bf16]
    ; eax bit 23 = AVX512FP16
    bt      eax, 23
    setc    [rel cpu_has_avx512fp16]

    ; AMX: leaf 7, subleaf 0
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    ; edx bit 22 = AMX-BF16
    bt      edx, 22
    setc    [rel cpu_has_amx_bf16]
    ; edx bit 24 = AMX-TILE
    bt      edx, 24
    setc    [rel cpu_has_amx_tile]
    ; edx bit 25 = AMX-INT8
    bt      edx, 25
    setc    [rel cpu_has_amx_int8]

    ; LZCNT: leaf 0x80000001 ecx bit 5
    mov     eax, 0x80000001
    cpuid
    bt      ecx, 5
    setc    [rel cpu_has_lzcnt]

    jmp     .done

.no_leaf7:
    ; minimal CPU, no AVX512 etc
    ; popcnt still possible via leaf 1
    mov     eax, 1
    cpuid
    bt      ecx, 23
    setc    [rel cpu_has_popcnt]

.done:
    mov     byte [rel cpu_features_cached], 1
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; ensure_features - call detect_cpu_features if not already cached
; -----------------------------------------------------------------------------
ensure_features:
    cmp     byte [rel cpu_features_cached], 0
    jne     .cached
    call    detect_cpu_features
.cached:
    ret

; =============================================================================
; public feature query functions
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_support_init - initialize support detection (call once at boot)
; args:    none
; returns: void
; -----------------------------------------------------------------------------
global umath_dtype_support_init
umath_dtype_support_init:
    call    detect_cpu_features
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx512f - check AVX-512 Foundation support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx512f
umath_dtype_support_avx512f:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx512f]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx512bf16 - check AVX-512 BF16 support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx512bf16
umath_dtype_support_avx512bf16:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx512bf16]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx512fp16 - check AVX-512 FP16 support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx512fp16
umath_dtype_support_avx512fp16:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx512fp16]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx512vnni - check AVX-512 VNNI support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx512vnni
umath_dtype_support_avx512vnni:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx512vnni]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx2 - check AVX2 support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx2
umath_dtype_support_avx2:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx2]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_amx - check Intel AMX support
; returns: eax = 1 if AMX-TILE supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_amx
umath_dtype_support_amx:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_amx_tile]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_level - get hardware support level for dtype
; args:    edi = dtype_id
; returns: eax = SUPPORT_* level
; -----------------------------------------------------------------------------
global umath_dtype_support_level
umath_dtype_support_level:
    call    ensure_features
    push    rbx
    mov     ebx, edi

    ; check cache first
    cmp     edi, 0x200
    jae     .compute
    lea     rax, [rel dtype_support_cache]
    movzx   eax, byte [rax + rdi]
    cmp     eax, 0xFF
    jne     .cached_return

.compute:
    mov     edi, ebx
    call    compute_support_level
    ; cache it
    cmp     ebx, 0x200
    jae     .no_cache
    lea     rcx, [rel dtype_support_cache]
    mov     byte [rcx + rbx], al
.no_cache:
    pop     rbx
    ret

.cached_return:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; compute_support_level - compute support level without cache
; args:    edi = dtype_id
; returns: eax = SUPPORT_* level
; -----------------------------------------------------------------------------
compute_support_level:
    ; always supported (software at minimum)
    cmp     edi, DTYPE_NONE
    je      .none

    ; INT types: always native (basic arithmetic)
    cmp     edi, DTYPE_INT1
    jl      .none
    cmp     edi, DTYPE_INT64
    jle     .native
    cmp     edi, DTYPE_UINT64
    jle     .native

    ; INT128/256: partial (no single instruction)
    cmp     edi, DTYPE_INT128
    je      .partial
    cmp     edi, DTYPE_INT256
    je      .partial
    cmp     edi, DTYPE_UINT128
    je      .partial
    cmp     edi, DTYPE_UINT256
    je      .partial

    ; UINT512+ software
    cmp     edi, DTYPE_UINT512
    jge     .software
    cmp     edi, DTYPE_UINT1024
    jge     .software
    cmp     edi, DTYPE_UINT2048
    jge     .software

    ; FP32/FP64: always native
    cmp     edi, DTYPE_FP32
    je      .native
    cmp     edi, DTYPE_FP64
    je      .native
    cmp     edi, DTYPE_FP128
    je      .software           ; no x86 FP128 hardware

    ; FP16: native if F16C or AVX512FP16
    cmp     edi, DTYPE_FP16
    je      .check_fp16

    ; BF16: native if AVX512BF16
    cmp     edi, DTYPE_BF16
    je      .check_bf16

    ; TF32: native on NVIDIA only (software on x86)
    cmp     edi, DTYPE_TF32
    je      .software

    ; FP8: software on x86 (no native FP8 in x86 yet)
    cmp     edi, DTYPE_FP8_E4M3
    je      .software
    cmp     edi, DTYPE_FP8_E5M2
    je      .software
    cmp     edi, DTYPE_FP8_E4M3_FNUZ
    je      .software
    cmp     edi, DTYPE_FP8_E5M2_FNUZ
    je      .software

    ; FP6: software
    cmp     edi, DTYPE_FP6_E2M3
    je      .software
    cmp     edi, DTYPE_FP6_E3M2
    je      .software

    ; OCP MX: software (no native OCP MX on x86 yet)
    cmp     edi, DTYPE_MXFP8_E4M3
    jge     .check_mx
    cmp     edi, DTYPE_MXINT4
    jle     .software           ; all OCP MX = software currently

    ; CF32/CF64: partial (no native complex arithmetic in x86)
    cmp     edi, DTYPE_CF32
    je      .partial
    cmp     edi, DTYPE_CF64
    je      .partial
    cmp     edi, DTYPE_CI8
    je      .partial
    cmp     edi, DTYPE_CI16
    je      .partial
    cmp     edi, DTYPE_CI32
    je      .partial

    ; BIGINT etc: software
    cmp     edi, DTYPE_BIGINT
    je      .software
    cmp     edi, DTYPE_BIGFLOAT
    je      .software
    cmp     edi, DTYPE_RATIONAL
    je      .software

    ; POSIT: software
    cmp     edi, DTYPE_POSIT8
    jge     .check_posit

    ; default: software
    jmp     .software

.check_fp16:
    cmp     byte [rel cpu_has_avx512fp16], 1
    je      .native
    cmp     byte [rel cpu_has_f16c], 1
    je      .partial            ; F16C only converts, no FP16 arithmetic
    jmp     .software

.check_bf16:
    cmp     byte [rel cpu_has_avx512bf16], 1
    je      .native
    jmp     .software

.check_mx:
    cmp     edi, DTYPE_MXFP8_E4M3
    jl      .software
    cmp     edi, DTYPE_NVFP8
    jle     .software
    jmp     .software

.check_posit:
    cmp     edi, DTYPE_POSIT256
    jle     .software
    jmp     .software

.none:
    mov     eax, SUPPORT_NONE
    ret
.native:
    mov     eax, SUPPORT_NATIVE
    ret
.partial:
    mov     eax, SUPPORT_PARTIAL
    ret
.software:
    mov     eax, SUPPORT_SOFTWARE
    ret

; -----------------------------------------------------------------------------
; umath_dtype_supported - is dtype usable (at any support level)?
; args:    edi = dtype_id
; returns: eax = 1 if usable, 0 if SUPPORT_NONE
; -----------------------------------------------------------------------------
global umath_dtype_supported
umath_dtype_supported:
    call    umath_dtype_support_level
    test    eax, eax
    setnz   al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_matrix - get pointer to full support cache table
; args:    none
; returns: rax = pointer to 512-byte support cache (one byte per dtype_id)
; note:    call umath_dtype_support_init first to populate
; -----------------------------------------------------------------------------
global umath_dtype_support_matrix
umath_dtype_support_matrix:
    call    ensure_features
    ; populate cache for common dtypes
    mov     edi, DTYPE_INT8
    call    umath_dtype_support_level
    mov     edi, DTYPE_FP32
    call    umath_dtype_support_level
    mov     edi, DTYPE_FP16
    call    umath_dtype_support_level
    mov     edi, DTYPE_BF16
    call    umath_dtype_support_level
    mov     edi, DTYPE_FP64
    call    umath_dtype_support_level
    lea     rax, [rel dtype_support_cache]
    ret