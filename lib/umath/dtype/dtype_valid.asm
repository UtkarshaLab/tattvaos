; =============================================================================
; umath - unified math library
; dtype/dtype_valid.asm - value validation
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_traits.asm
;   dtype_range.asm
;   dtype_patterns.asm
;
; description:
;   validates that a given value or bit pattern is a legal
;   representation for the specified dtype
;   catches NaN when not allowed, out-of-range integers,
;   reserved bit patterns, invalid encodings etc
;
; functions:
;   umath_dtype_is_valid_id     (dtype_id → bool)
;   umath_dtype_validate_bits   (dtype_id, bits* → bool) validate bit pattern
;   umath_dtype_validate_f32    (dtype_id, f32 → bool) check f32 value fits
;   umath_dtype_validate_f64    (dtype_id, f64 → bool) check f64 value fits
;   umath_dtype_validate_i64    (dtype_id, i64 → bool) check i64 value fits
;   umath_dtype_validate_u64    (dtype_id, u64 → bool) check u64 value fits
;   umath_dtype_sanitize_f32    (dtype_id, f32 → f32) clamp + fix invalid
;   umath_dtype_sanitize_f64    (dtype_id, f64 → f64) clamp + fix invalid
;   umath_dtype_check_not_nan   (dtype_id, bits → bool)
;   umath_dtype_check_not_inf   (dtype_id, bits → bool)
;   umath_dtype_check_finite    (dtype_id, bits → bool) not nan, not inf
; =============================================================================

%include "dtype_id.asm"
%include "dtype_traits.asm"

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_dtype_is_valid_id - check if dtype_id is a known valid dtype
; args:    edi = dtype_id
; returns: eax = 1 if valid, 0 if none/unknown/reserved
; -----------------------------------------------------------------------------
global umath_dtype_is_valid_id
umath_dtype_is_valid_id:
    ; must be > 0 and < DTYPE_UNKNOWN
    test    edi, edi
    jz      .invalid
    cmp     edi, DTYPE_UNKNOWN
    jge     .invalid
    ; check it's not in reserved range 0x154-0xEFF
    cmp     edi, 0x154
    jl      .valid
    cmp     edi, 0xF00
    jl      .invalid
    ; 0xF00-0xFF0: reserved future hardware
    cmp     edi, 0xFF1
    jl      .invalid
    ; 0xFF1-0xFFD: user defined (valid)
    cmp     edi, DTYPE_UNKNOWN
    jl      .valid
.invalid:
    xor     eax, eax
    ret
.valid:
    mov     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_dtype_validate_bits - validate bit pattern for dtype
; args:    rdi = dtype_id
;          rsi = pointer to bits (read up to size_bytes)
; returns: eax = 1 if valid, 0 if invalid bit pattern
; -----------------------------------------------------------------------------
global umath_dtype_validate_bits
umath_dtype_validate_bits:
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12, rsi

    ; validate dtype_id itself
    call    umath_dtype_is_valid_id
    test    eax, eax
    jz      .invalid

    ; load bits (up to 8 bytes)
    mov     edi, ebx
    call    umath_dtype_meta_get_size_bytes
    test    eax, eax
    jz      .valid              ; variable-size: can't validate bits

    ; load value from pointer
    cmp     eax, 1
    je      .load1
    cmp     eax, 2
    je      .load2
    cmp     eax, 4
    je      .load4
.load8:
    mov     rsi, [r12]
    jmp     .check
.load4:
    movzx   rsi, dword [r12]
    jmp     .check
.load2:
    movzx   rsi, word [r12]
    jmp     .check
.load1:
    movzx   rsi, byte [r12]

.check:
    ; for integer types: any bit pattern is valid
    mov     edi, ebx
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_INT_SIGNED
    je      .valid
    cmp     eax, DFAMILY_INT_UNSIGNED
    je      .valid

    ; for float types: check for invalid patterns
    ; FP8_E4M3: 0x7F and 0xFF are NaN (both map to NaN)
    cmp     ebx, DTYPE_FP8_E4M3
    je      .check_fp8_e4m3

    ; FP8_E4M3_FNUZ: 0x80 is NaN (neg zero maps to NaN)
    cmp     ebx, DTYPE_FP8_E4M3_FNUZ
    je      .check_fnuz

    ; FP6: no reserved patterns
    cmp     ebx, DTYPE_FP6_E2M3
    je      .valid
    cmp     ebx, DTYPE_FP6_E3M2
    je      .valid

    ; FP16/BF16/FP32/FP64: sNaN is technically valid bit pattern
    ; (even if dangerous), so all bit patterns are valid encodings
    cmp     ebx, DTYPE_FP16
    je      .valid
    cmp     ebx, DTYPE_BF16
    je      .valid
    cmp     ebx, DTYPE_FP32
    je      .valid
    cmp     ebx, DTYPE_FP64
    je      .valid

    ; default: valid
    jmp     .valid

.check_fp8_e4m3:
    ; FP8 E4M3: 0x7F = +NaN, 0xFF = -NaN, all others valid
    ; (NaN is a valid bit pattern, just not a finite number)
    jmp     .valid

.check_fnuz:
    ; FNUZ: 0x80 encodes NaN, others valid
    jmp     .valid

.valid:
    mov     eax, 1
    pop     r12
    pop     rbx
    ret
.invalid:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_validate_f64 - check if f64 value is representable in dtype
; args:    edi  = dtype_id
;          xmm0 = value as f64
; returns: eax  = 1 if representable (finite and in range), 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_validate_f64
umath_dtype_validate_f64:
    sub     rsp, 16
    movsd   [rsp], xmm0

    ; check for NaN input
    ucomisd xmm0, xmm0          ; NaN != NaN
    jp      .nan_input

    ; check if dtype supports NaN (if not, NaN input is invalid)
    ; (for integer dtypes: NaN is always invalid)
    ; For now, check if it's finite
    movq    rax, xmm0
    mov     rcx, 0x7FF0000000000000
    and     rax, rcx
    cmp     rax, rcx            ; if exp all 1s → inf or nan
    je      .check_inf_ok

    ; finite value: check range
    movsd   xmm0, [rsp]
    call    umath_dtype_in_range_f64
    add     rsp, 16
    ret

.check_inf_ok:
    ; check if dtype supports inf
    mov     esi, edi
    push    rsi
    movsd   xmm0, [rsp + 8]
    movq    rax, xmm0
    mov     rcx, 0x000FFFFFFFFFFFFF
    test    rax, rcx            ; if mantissa != 0 → NaN
    jnz     .nan_input_check
    ; it's infinity
    pop     rsi
    mov     edi, esi
    call    umath_dtype_has_inf
    add     rsp, 16
    ret

.nan_input_check:
    pop     rsi
    mov     edi, esi
    call    umath_dtype_has_nan
    add     rsp, 16
    ret

.nan_input:
    ; NaN input: valid only if dtype supports NaN
    call    umath_dtype_has_nan
    add     rsp, 16
    ret

; -----------------------------------------------------------------------------
; umath_dtype_validate_f32 - check if f32 value fits in dtype
; args:    edi  = dtype_id
;          xmm0 = value as f32
; returns: eax  = 1 if valid, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_validate_f32
umath_dtype_validate_f32:
    cvtss2sd xmm0, xmm0
    jmp     umath_dtype_validate_f64

; -----------------------------------------------------------------------------
; umath_dtype_validate_i64 - check if i64 integer fits in dtype
; args:    edi = dtype_id
;          rsi = value as i64
; returns: eax = 1 if fits, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_validate_i64
umath_dtype_validate_i64:
    jmp     umath_dtype_in_range_i64

; -----------------------------------------------------------------------------
; umath_dtype_validate_u64 - check if u64 integer fits in dtype
; args:    edi = dtype_id
;          rsi = value as u64
; returns: eax = 1 if fits, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_validate_u64
umath_dtype_validate_u64:
    push    rbx
    mov     ebx, edi
    ; get max as u64
    call    umath_dtype_max_u64     ; eax = max
    cmp     rsi, rax
    jg      .no
    ; min for unsigned is 0
    mov     eax, 1
    pop     rbx
    ret
.no:
    xor     eax, eax
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_check_not_nan - check bit pattern is not NaN
; args:    edi = dtype_id
;          rsi = bit pattern (right-justified in u64)
; returns: eax = 1 if NOT nan (or dtype has no NaN), 0 if is NaN
; -----------------------------------------------------------------------------
global umath_dtype_check_not_nan
umath_dtype_check_not_nan:
    call    umath_dtype_is_nan_val
    xor     eax, 1              ; invert: 1=not_nan, 0=is_nan
    ret

; -----------------------------------------------------------------------------
; umath_dtype_check_not_inf - check bit pattern is not infinity
; args:    edi = dtype_id
;          rsi = bit pattern
; returns: eax = 1 if NOT inf, 0 if is infinity
; -----------------------------------------------------------------------------
global umath_dtype_check_not_inf
umath_dtype_check_not_inf:
    call    umath_dtype_is_inf_val
    xor     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_dtype_check_finite - check bit pattern is finite (not nan, not inf)
; args:    edi = dtype_id
;          rsi = bit pattern
; returns: eax = 1 if finite, 0 if nan or inf
; -----------------------------------------------------------------------------
global umath_dtype_check_finite
umath_dtype_check_finite:
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12, rsi
    call    umath_dtype_is_nan_val
    test    eax, eax
    jnz     .not_finite
    mov     edi, ebx
    mov     rsi, r12
    call    umath_dtype_is_inf_val
    test    eax, eax
    jnz     .not_finite
    mov     eax, 1
    pop     r12
    pop     rbx
    ret
.not_finite:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_sanitize_f64 - clamp f64 to dtype range, replace NaN if needed
; args:    edi  = dtype_id
;          xmm0 = value as f64
; returns: xmm0 = sanitized value safe for this dtype
; -----------------------------------------------------------------------------
global umath_dtype_sanitize_f64
umath_dtype_sanitize_f64:
    sub     rsp, 24
    movsd   [rsp], xmm0

    ; check for NaN
    ucomisd xmm0, xmm0
    jp      .replace_nan

    ; clamp to range
    call    umath_dtype_clamp_f64
    add     rsp, 24
    ret

.replace_nan:
    ; replace NaN with 0.0
    xorpd   xmm0, xmm0
    add     rsp, 24
    ret

; -----------------------------------------------------------------------------
; umath_dtype_sanitize_f32 - sanitize f32 value for dtype
; args:    edi  = dtype_id
;          xmm0 = value as f32
; returns: xmm0 = sanitized f32 value
; -----------------------------------------------------------------------------
global umath_dtype_sanitize_f32
umath_dtype_sanitize_f32:
    cvtss2sd xmm0, xmm0
    call    umath_dtype_sanitize_f64
    cvtsd2ss xmm0, xmm0
    ret