; =============================================================================
; umath - unified math library
; dtype/dtype_traits.asm - dtype trait queries
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_family.asm
;   dtype_meta.asm
;
; functions:
;   umath_dtype_has_nan          (dtype_id → bool)
;   umath_dtype_has_inf          (dtype_id → bool)
;   umath_dtype_has_neg_zero     (dtype_id → bool)
;   umath_dtype_has_subnormal    (dtype_id → bool)
;   umath_dtype_is_ieee754       (dtype_id → bool)
;   umath_dtype_is_posit         (dtype_id → bool)
;   umath_dtype_is_lns           (dtype_id → bool)
;   umath_dtype_is_unum          (dtype_id → bool)
;   umath_dtype_has_block_scale  (dtype_id → bool)
;   umath_dtype_exponent_bits    (dtype_id → u32)
;   umath_dtype_mantissa_bits    (dtype_id → u32)
;   umath_dtype_exponent_bias    (dtype_id → i32)
;   umath_dtype_sign_bit_pos     (dtype_id → u32)
;   umath_dtype_exp_bit_pos      (dtype_id → u32)
;   umath_dtype_man_bit_pos      (dtype_id → u32)
;   umath_dtype_is_normal        (dtype_id, bits → bool)
;   umath_dtype_is_subnormal_val (dtype_id, bits → bool)
;   umath_dtype_is_nan_val       (dtype_id, bits → bool)
;   umath_dtype_is_inf_val       (dtype_id, bits → bool)
;   umath_dtype_is_zero_val      (dtype_id, bits → bool)
;   umath_dtype_is_neg_zero_val  (dtype_id, bits → bool)
; =============================================================================

%include "dtype_id.asm"
%include "dtype_family.asm"
%include "dtype_meta.asm"

bits 64
section .text

; =============================================================================
; trait queries via flag table — all use meta flags for O(1) lookup
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_has_nan - does dtype represent NaN
; args:    edi = dtype_id
; returns: eax = 1 if has NaN, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_has_nan
umath_dtype_has_nan:
    mov     esi, DTYPE_FLAG_HAS_NAN
    jmp     umath_dtype_meta_has_flag

; -----------------------------------------------------------------------------
; umath_dtype_has_inf - does dtype represent infinity
; args:    edi = dtype_id
; returns: eax = 1 if has inf, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_has_inf
umath_dtype_has_inf:
    mov     esi, DTYPE_FLAG_HAS_INF
    jmp     umath_dtype_meta_has_flag

; -----------------------------------------------------------------------------
; umath_dtype_has_neg_zero - does dtype have negative zero (-0.0)
; args:    edi = dtype_id
; returns: eax = 1 if has -0, 0 otherwise
; note:    IEEE 754 floats have -0, posits and integers do not
; -----------------------------------------------------------------------------
global umath_dtype_has_neg_zero
umath_dtype_has_neg_zero:
    mov     esi, DTYPE_FLAG_HAS_NEG_ZERO
    jmp     umath_dtype_meta_has_flag

; -----------------------------------------------------------------------------
; umath_dtype_has_subnormal - does dtype support subnormal numbers
; args:    edi = dtype_id
; returns: eax = 1 if has subnormals, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_has_subnormal
umath_dtype_has_subnormal:
    mov     esi, DTYPE_FLAG_HAS_SUBNORMAL
    jmp     umath_dtype_meta_has_flag

; -----------------------------------------------------------------------------
; umath_dtype_is_ieee754 - is dtype an IEEE 754 standard float
; args:    edi = dtype_id
; returns: eax = 1 if IEEE 754, 0 otherwise
; note:    FP32, FP64, FP16, BF16, FP8 variants = yes
;          posit, LNS, unum = no
; -----------------------------------------------------------------------------
global umath_dtype_is_ieee754
umath_dtype_is_ieee754:
    mov     esi, DTYPE_FLAG_IS_IEEE754
    jmp     umath_dtype_meta_has_flag

; -----------------------------------------------------------------------------
; umath_dtype_has_block_scale - does dtype use block-level scaling
; args:    edi = dtype_id
; returns: eax = 1 if block-scaled (OCP MX, NVFP4 etc), 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_has_block_scale
umath_dtype_has_block_scale:
    mov     esi, DTYPE_FLAG_HAS_BLOCK_SCALE
    jmp     umath_dtype_meta_has_flag

; -----------------------------------------------------------------------------
; umath_dtype_is_posit - is dtype a posit number system type
; args:    edi = dtype_id
; returns: eax = 1 if posit, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_posit
umath_dtype_is_posit:
    cmp     edi, DTYPE_POSIT8
    jl      .no
    cmp     edi, DTYPE_POSIT256
    jg      .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_lns - is dtype a logarithmic number system type
; args:    edi = dtype_id
; returns: eax = 1 if LNS, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_lns
umath_dtype_is_lns:
    cmp     edi, DTYPE_LNS8
    je      .yes
    cmp     edi, DTYPE_LNS16
    je      .yes
    cmp     edi, DTYPE_LNS32
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_unum - is dtype a unum type
; args:    edi = dtype_id
; returns: eax = 1 if unum, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_unum
umath_dtype_is_unum:
    cmp     edi, DTYPE_UNUM1
    je      .yes
    cmp     edi, DTYPE_UNUM2
    je      .yes
    cmp     edi, DTYPE_VALID
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; =============================================================================
; float format field queries
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_exponent_bits - number of exponent bits
; args:    edi = dtype_id
; returns: eax = exponent bit count (0 for non-float or integer)
; -----------------------------------------------------------------------------
global umath_dtype_exponent_bits
umath_dtype_exponent_bits:
    jmp     umath_dtype_meta_get_exp_bits

; -----------------------------------------------------------------------------
; umath_dtype_mantissa_bits - number of mantissa (significand) bits
; args:    edi = dtype_id
; returns: eax = mantissa bit count (0 for non-float)
; note:    does NOT include implicit leading 1 bit for normal numbers
; -----------------------------------------------------------------------------
global umath_dtype_mantissa_bits
umath_dtype_mantissa_bits:
    jmp     umath_dtype_meta_get_man_bits

; -----------------------------------------------------------------------------
; umath_dtype_exponent_bias - exponent bias value
; args:    edi = dtype_id
; returns: eax = bias as signed i32 (0 for non-float)
; examples:
;   FP32  → 127
;   FP64  → 1023
;   FP16  → 15
;   BF16  → 127
;   FP8_E4M3 → 7
;   FP8_E5M2 → 15
; -----------------------------------------------------------------------------
global umath_dtype_exponent_bias
umath_dtype_exponent_bias:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .zero
    movzx   eax, word [rax + META_OFF_EXP_BIAS_LO]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_sign_bit_pos - position of sign bit (MSB position from bit 0)
; args:    edi = dtype_id
; returns: eax = bit position of sign bit
;          returns size_bits-1 for standard signed formats
;          returns 0 if unsigned or non-applicable
; -----------------------------------------------------------------------------
global umath_dtype_sign_bit_pos
umath_dtype_sign_bit_pos:
    push    rbx
    mov     ebx, edi
    ; check if signed
    call    umath_dtype_meta_get_flags
    test    eax, DTYPE_FLAG_IS_SIGNED
    jz      .unsigned
    ; sign bit is at size_bits - 1
    mov     edi, ebx
    call    umath_dtype_meta_get_size_bits
    test    eax, eax
    jz      .zero
    dec     eax
    pop     rbx
    ret
.unsigned:
.zero:
    xor     eax, eax
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_exp_bit_pos - position of exponent field (lowest bit)
; args:    edi = dtype_id
; returns: eax = bit position of lowest exponent bit
;          returns 0 if non-float
; note:    for IEEE 754: exp starts at mantissa_bits
; -----------------------------------------------------------------------------
global umath_dtype_exp_bit_pos
umath_dtype_exp_bit_pos:
    jmp     umath_dtype_mantissa_bits   ; exp starts right above mantissa

; -----------------------------------------------------------------------------
; umath_dtype_man_bit_pos - position of mantissa field (always bit 0)
; args:    edi = dtype_id
; returns: eax = 0 (mantissa always starts at bit 0 in IEEE layout)
; -----------------------------------------------------------------------------
global umath_dtype_man_bit_pos
umath_dtype_man_bit_pos:
    xor     eax, eax
    ret

; =============================================================================
; value classification functions
; classify a stored bit pattern for a given dtype
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_is_nan_val - check if bit pattern represents NaN
; args:    edi = dtype_id
;          rsi = value bits (right-justified in u64)
; returns: eax = 1 if NaN, 0 otherwise
; note:    returns 0 for dtypes that don't support NaN
; -----------------------------------------------------------------------------
global umath_dtype_is_nan_val
umath_dtype_is_nan_val:
    push    rbx
    push    r12
    mov     r12, rsi                ; save value bits
    ; check dtype supports NaN
    call    umath_dtype_has_nan
    test    eax, eax
    jz      .not_nan
    ; get exp and mantissa bits
    mov     ebx, edi
    call    umath_dtype_exponent_bits
    mov     ecx, eax                ; exp_bits
    mov     edi, ebx
    call    umath_dtype_mantissa_bits
    mov     edx, eax                ; man_bits
    ; NaN: all exponent bits = 1, mantissa != 0
    ; build all-ones exponent mask: ((1 << exp_bits) - 1) << man_bits
    mov     rax, 1
    shl     rax, cl                 ; 1 << exp_bits
    dec     rax                     ; (1 << exp_bits) - 1
    shl     rax, dl                 ; shift up by mantissa_bits
    ; check exponent all ones
    mov     r8, r12
    and     r8, rax
    cmp     r8, rax
    jne     .not_nan
    ; check mantissa non-zero
    mov     rax, 1
    shl     rax, dl                 ; 1 << man_bits
    dec     rax                     ; mantissa mask
    test    r12, rax
    jz      .not_nan
    mov     eax, 1
    pop     r12
    pop     rbx
    ret
.not_nan:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_inf_val - check if bit pattern represents +/-infinity
; args:    edi = dtype_id
;          rsi = value bits
; returns: eax = 1 if infinity, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_inf_val
umath_dtype_is_inf_val:
    push    rbx
    push    r12
    mov     r12, rsi
    call    umath_dtype_has_inf
    test    eax, eax
    jz      .not_inf
    mov     ebx, edi
    call    umath_dtype_exponent_bits
    mov     ecx, eax
    mov     edi, ebx
    call    umath_dtype_mantissa_bits
    mov     edx, eax
    ; inf: all exponent bits = 1, mantissa = 0
    mov     rax, 1
    shl     rax, cl
    dec     rax
    shl     rax, dl                 ; exponent mask
    mov     r8, r12
    and     r8, rax
    cmp     r8, rax
    jne     .not_inf
    ; mantissa must be zero
    mov     rax, 1
    shl     rax, dl
    dec     rax
    test    r12, rax
    jnz     .not_inf
    mov     eax, 1
    pop     r12
    pop     rbx
    ret
.not_inf:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_zero_val - check if bit pattern represents zero
; args:    edi = dtype_id
;          rsi = value bits
; returns: eax = 1 if zero (+0 or -0), 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_zero_val
umath_dtype_is_zero_val:
    push    rbx
    push    r12
    mov     r12, rsi
    mov     ebx, edi
    ; get size bits for mask
    call    umath_dtype_meta_get_size_bits
    ; build mask for all bits except sign
    mov     ecx, eax                ; size_bits
    mov     rax, 1
    shl     rax, cl
    dec     rax                     ; all bits set
    ; for signed types, clear the sign bit
    mov     edi, ebx
    call    umath_dtype_meta_get_flags
    test    eax, DTYPE_FLAG_IS_SIGNED
    jz      .check
    ; clear sign bit (highest bit)
    mov     ecx, eax
    mov     edi, ebx
    call    umath_dtype_meta_get_size_bits
    dec     eax
    btr     rax, rax                ; this is wrong
    ; rebuild: mask = (1 << (size-1)) - 1 to ignore sign bit
    mov     ecx, eax                ; size_bits - 1
    mov     rax, 1
    shl     rax, cl
    dec     rax
.check:
    and     r12, rax
    setz    al
    movzx   eax, al
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_neg_zero_val - check if bit pattern represents -0.0
; args:    edi = dtype_id
;          rsi = value bits
; returns: eax = 1 if negative zero, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_neg_zero_val
umath_dtype_is_neg_zero_val:
    push    rbx
    push    r12
    mov     r12, rsi
    mov     ebx, edi
    ; must have neg_zero
    call    umath_dtype_has_neg_zero
    test    eax, eax
    jz      .no
    ; all non-sign bits must be zero
    ; sign bit must be 1
    mov     edi, ebx
    call    umath_dtype_meta_get_size_bits
    test    eax, eax
    jz      .no
    dec     eax
    mov     ecx, eax                ; sign bit position
    mov     rax, 1
    shl     rax, cl                 ; sign bit mask
    ; check only sign bit set
    cmp     r12, rax
    sete    al
    movzx   eax, al
    pop     r12
    pop     rbx
    ret
.no:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_normal - check if value is a normal (not sub/nan/inf/zero)
; args:    edi = dtype_id
;          rsi = value bits
; returns: eax = 1 if normal, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_normal
umath_dtype_is_normal:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13d, edi
    ; not nan
    call    umath_dtype_is_nan_val
    test    eax, eax
    jnz     .no
    ; not inf
    mov     edi, r13d
    mov     rsi, r12
    call    umath_dtype_is_inf_val
    test    eax, eax
    jnz     .no
    ; not zero
    mov     edi, r13d
    mov     rsi, r12
    call    umath_dtype_is_zero_val
    test    eax, eax
    jnz     .no
    ; not subnormal: exponent bits must not all be zero
    ; (for IEEE floats: exponent != 0 means normal)
    mov     edi, r13d
    call    umath_dtype_exponent_bits
    test    eax, eax
    jz      .yes                    ; integer types always "normal"
    mov     ecx, eax
    mov     edi, r13d
    call    umath_dtype_mantissa_bits
    mov     edx, eax
    mov     rax, 1
    shl     rax, cl
    dec     rax
    shl     rax, dl                 ; exp mask
    test    r12, rax
    jz      .no                     ; all exp bits zero = subnormal
.yes:
    mov     eax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret
.no:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_subnormal_val - check if value is subnormal/denormal
; args:    edi = dtype_id
;          rsi = value bits
; returns: eax = 1 if subnormal, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_subnormal_val
umath_dtype_is_subnormal_val:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13d, edi
    ; dtype must support subnormals
    call    umath_dtype_has_subnormal
    test    eax, eax
    jz      .no
    ; not nan and not inf
    mov     edi, r13d
    mov     rsi, r12
    call    umath_dtype_is_nan_val
    test    eax, eax
    jnz     .no
    mov     edi, r13d
    mov     rsi, r12
    call    umath_dtype_is_inf_val
    test    eax, eax
    jnz     .no
    ; not zero
    mov     edi, r13d
    mov     rsi, r12
    call    umath_dtype_is_zero_val
    test    eax, eax
    jnz     .no
    ; exponent field must be all zeros
    mov     edi, r13d
    call    umath_dtype_exponent_bits
    test    eax, eax
    jz      .no
    mov     ecx, eax
    mov     edi, r13d
    call    umath_dtype_mantissa_bits
    mov     edx, eax
    mov     rax, 1
    shl     rax, cl
    dec     rax
    shl     rax, dl                 ; exp mask
    test    r12, rax
    jnz     .no                     ; exp not all zero
    mov     eax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret
.no:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret