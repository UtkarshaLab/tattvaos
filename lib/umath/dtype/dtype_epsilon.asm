; =============================================================================
; umath - unified math library
; dtype/dtype_epsilon.asm - machine epsilon and precision
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_traits.asm
;   dtype_patterns.asm
;
; description:
;   machine epsilon: smallest e such that 1.0 + e != 1.0
;   ULP: unit in the last place for a given value
;   decimal digits: number of significant decimal digits
;   binary digits: number of significant binary digits (mantissa bits + 1)
;
; functions:
;   umath_dtype_epsilon_f64      (dtype_id → f64 in xmm0)
;   umath_dtype_epsilon_f32      (dtype_id → f32 in xmm0)
;   umath_dtype_ulp_f64          (dtype_id, f64 val → f64)  ULP at value
;   umath_dtype_decimal_digits   (dtype_id → u32)
;   umath_dtype_binary_digits    (dtype_id → u32)
;   umath_dtype_round_error_f64  (dtype_id → f64)  max rounding error
;   umath_dtype_precision_bits   (dtype_id → u32)  total significand bits
; =============================================================================

%include "dtype_id.asm"

bits 64

; =============================================================================
; epsilon table: [epsilon_f64_bits, decimal_digits, binary_digits]
; epsilon_f64_bits: IEEE 754 double bit pattern of machine epsilon
; indexed by dtype_id
; =============================================================================

section .rodata
align 64

; struct: epsilon_bits(u64), decimal_digits(u32), binary_digits(u32)
EPSILON_ENTRY_SIZE equ 16

dtype_epsilon_table:
; DTYPE_NONE (0x000)
dq 0x0000000000000000
dd 0, 0

; INT1: epsilon=1, 1 decimal digit, 1 binary digit
dq 0x3FF0000000000000
dd 1, 1

; INT2: epsilon=1
dq 0x3FF0000000000000
dd 1, 2

; INT4: epsilon=1, ~1 decimal digit, 4 binary digits
dq 0x3FF0000000000000
dd 1, 4

; INT8: epsilon=1, ~2 decimal digits, 8 binary digits
dq 0x3FF0000000000000
dd 2, 8

; INT16: epsilon=1, ~4 decimal digits, 16 binary digits
dq 0x3FF0000000000000
dd 4, 16

; INT32: epsilon=1, ~9 decimal digits, 32 binary digits
dq 0x3FF0000000000000
dd 9, 32

; INT64: epsilon=1, ~18 decimal digits, 64 binary digits
dq 0x3FF0000000000000
dd 18, 64

; INT128: epsilon=1
dq 0x3FF0000000000000
dd 38, 128

; INT256: epsilon=1
dq 0x3FF0000000000000
dd 77, 256

; padding 0x00A-0x00F
times 6 dq 0
times 6 dd 0, 0

; UINT4: epsilon=1, 1 decimal digit, 4 binary digits
dq 0x3FF0000000000000
dd 1, 4

; UINT8: epsilon=1, 2 decimal digits, 8 binary digits
dq 0x3FF0000000000000
dd 2, 8

; UINT16: epsilon=1, 4 decimal digits, 16 binary digits
dq 0x3FF0000000000000
dd 4, 16

; UINT32: epsilon=1, 9 decimal digits, 32 binary digits
dq 0x3FF0000000000000
dd 9, 32

; UINT64: epsilon=1, 19 decimal digits, 64 binary digits
dq 0x3FF0000000000000
dd 19, 64

; UINT128-UINT2048: approx
dq 0x3FF0000000000000
dd 38, 128

dq 0x3FF0000000000000
dd 77, 256

dq 0x3FF0000000000000
dd 154, 512

dq 0x3FF0000000000000
dd 308, 1024

dq 0x3FF0000000000000
dd 616, 2048

; padding 0x01A-0x01F
times 6 dq 0
times 6 dd 0, 0

; FP8_E4M3 (0x020): mantissa=3 bits
; epsilon = 2^-(3) = 0.125 = 1/8
; FP64 bits for 0.125 = 0x3FC0000000000000
dq 0x3FC0000000000000
dd 1, 4          ; ~1 decimal digit, 4 binary (1+3)

; FP8_E5M2 (0x021): mantissa=2 bits
; epsilon = 2^-(2) = 0.25
; FP64 bits for 0.25 = 0x3FD0000000000000
dq 0x3FD0000000000000
dd 1, 3          ; ~1 decimal digit, 3 binary (1+2)

; FP16 (0x022): mantissa=10 bits
; epsilon = 2^-10 ≈ 9.765e-4
; FP64 bits for 2^-10 = 0x3F50000000000000
dq 0x3F50000000000000
dd 3, 11         ; ~3 decimal digits, 11 binary (1+10)

; BF16 (0x023): mantissa=7 bits
; epsilon = 2^-7 = 0.0078125
; FP64 bits for 2^-7 = 0x3F80000000000000
dq 0x3F80000000000000
dd 2, 8          ; ~2 decimal digits, 8 binary (1+7)

; TF32 (0x024): mantissa=10 bits (same as FP16 precision)
dq 0x3F50000000000000
dd 3, 11

; FP32 (0x025): mantissa=23 bits
; epsilon = 2^-23 ≈ 1.192e-7
; FP64 bits for 2^-23 = 0x3E80000000000000
dq 0x3E80000000000000
dd 7, 24         ; ~7 decimal digits, 24 binary (1+23)

; FP64 (0x026): mantissa=52 bits
; epsilon = 2^-52 ≈ 2.220e-16
; FP64 bits for 2^-52 = 0x3CB0000000000000
dq 0x3CB0000000000000
dd 15, 53        ; ~15 decimal digits, 53 binary (1+52)

; FP128 (0x027): mantissa=112 bits
; epsilon = 2^-112 ≈ 1.926e-34
dq 0x38B0000000000000 ; approximate in FP64
dd 33, 113

; FP8_E4M3_FNUZ (0x028)
dq 0x3FC0000000000000
dd 1, 4

; FP8_E5M2_FNUZ (0x029)
dq 0x3FD0000000000000
dd 1, 3

; BFLOAT8 (0x02A)
dq 0x3FD0000000000000
dd 1, 3

; MINIFLOAT (0x02B)
dq 0x3FC0000000000000
dd 1, 4

; FP6_E2M3 (0x02C): mantissa=3 bits
dq 0x3FC0000000000000
dd 1, 4

; FP6_E3M2 (0x02D): mantissa=2 bits
dq 0x3FD0000000000000
dd 1, 3

; padding
times 2 dq 0
times 2 dd 0, 0

; MXFP8_E4M3 (0x030)
dq 0x3FC0000000000000
dd 1, 4

; MXFP8_E5M2 (0x031)
dq 0x3FD0000000000000
dd 1, 3

; MXFP6_E2M3 (0x032)
dq 0x3FC0000000000000
dd 1, 4

; MXFP6_E3M2 (0x033)
dq 0x3FD0000000000000
dd 1, 3

; MXFP4_E2M1 (0x034): mantissa=1 bit
; epsilon = 2^-1 = 0.5
dq 0x3FE0000000000000
dd 1, 2

; MXINT8 (0x035): integer
dq 0x3FF0000000000000
dd 2, 8

; MXINT6 (0x036)
dq 0x3FF0000000000000
dd 1, 6

; MXINT4 (0x037)
dq 0x3FF0000000000000
dd 1, 4

; UE8M0 (0x038): exponent only, no mantissa
dq 0x3FF0000000000000
dd 0, 1

; NVFP4 (0x039)
dq 0x3FE0000000000000
dd 1, 2

; NVINT4 (0x03A)
dq 0x3FF0000000000000
dd 1, 4

; NVFP8 (0x03B)
dq 0x3FC0000000000000
dd 1, 4

; padding 0x03C-0x03F
times 4 dq 0
times 4 dd 0, 0

; Q4_0 (0x040): fixed point, 4 bits
dq 0x3FF0000000000000
dd 1, 4

; Q4_1 (0x041)
dq 0x3FF0000000000000
dd 1, 4

; Q5_0 (0x042)
dq 0x3FF0000000000000
dd 1, 5

; Q5_1 (0x043)
dq 0x3FF0000000000000
dd 1, 5

; Q8_0 (0x044)
dq 0x3FF0000000000000
dd 2, 8

; BIT_PACKED / DELTA_ENC: variable
dq 0, 0
dq 0, 0

; padding 0x047-0x04F
times 9 dq 0
times 9 dd 0, 0

; UNORM8 (0x050): [0,1] in 8 bits → step = 1/255
; FP64 for 1/255 ≈ 0x3F70101010101010
dq 0x3F70101010101010
dd 2, 8

; UNORM16 (0x051)
dq 0x3EF0001000100010
dd 4, 16

; SNORM8 (0x052)
dq 0x3F80808080808080
dd 2, 7

; SNORM16 (0x053)
dq 0x3F00008000800080
dd 4, 15

; PROB32 (0x054): same as FP32
dq 0x3E80000000000000
dd 7, 24

; LOG_PROB32 (0x055)
dq 0x3E80000000000000
dd 7, 24

; FUZZY (0x056)
dq 0x3E80000000000000
dd 7, 24

dtype_epsilon_table_end:
DTYPE_EPSILON_TABLE_COUNT equ (dtype_epsilon_table_end - dtype_epsilon_table) / EPSILON_ENTRY_SIZE

EPSILON_OFF_BITS    equ 0
EPSILON_OFF_DEC     equ 8
EPSILON_OFF_BIN     equ 12

section .text

; -----------------------------------------------------------------------------
; internal: get pointer to epsilon entry
; args:    edi = dtype_id
; returns: rax = pointer or NULL
; -----------------------------------------------------------------------------
dtype_epsilon_ptr:
    cmp     edi, DTYPE_EPSILON_TABLE_COUNT
    jae     .null
    lea     rax, [rel dtype_epsilon_table]
    imul    edi, EPSILON_ENTRY_SIZE
    add     rax, rdi
    ret
.null:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_epsilon_f64 - machine epsilon as FP64
; args:    edi = dtype_id
; returns: xmm0 = epsilon as double (0.0 if not applicable)
; -----------------------------------------------------------------------------
global umath_dtype_epsilon_f64
umath_dtype_epsilon_f64:
    call    dtype_epsilon_ptr
    test    rax, rax
    jz      .zero
    movsd   xmm0, [rax + EPSILON_OFF_BITS]
    ret
.zero:
    xorpd   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_dtype_epsilon_f32 - machine epsilon as FP32
; args:    edi = dtype_id
; returns: xmm0 = epsilon as float (0.0 if not applicable)
; -----------------------------------------------------------------------------
global umath_dtype_epsilon_f32
umath_dtype_epsilon_f32:
    call    umath_dtype_epsilon_f64
    cvtsd2ss xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_dtype_decimal_digits - significant decimal digits
; args:    edi = dtype_id
; returns: eax = decimal digit count (0 if variable or non-numeric)
; -----------------------------------------------------------------------------
global umath_dtype_decimal_digits
umath_dtype_decimal_digits:
    call    dtype_epsilon_ptr
    test    rax, rax
    jz      .zero
    mov     eax, [rax + EPSILON_OFF_DEC]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_binary_digits - significant binary digits (precision bits)
; args:    edi = dtype_id
; returns: eax = binary digit count (mantissa_bits + 1 for floats)
; -----------------------------------------------------------------------------
global umath_dtype_binary_digits
umath_dtype_binary_digits:
    call    dtype_epsilon_ptr
    test    rax, rax
    jz      .zero
    mov     eax, [rax + EPSILON_OFF_BIN]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_precision_bits - total precision bits (alias for binary_digits)
; args:    edi = dtype_id
; returns: eax = precision in bits
; -----------------------------------------------------------------------------
global umath_dtype_precision_bits
umath_dtype_precision_bits:
    jmp     umath_dtype_binary_digits

; -----------------------------------------------------------------------------
; umath_dtype_ulp_f64 - unit in the last place for a given value
; args:    edi  = dtype_id
;          xmm0 = value as f64
; returns: xmm0 = ULP size as f64
;
; ULP computation:
;   for float types: ulp = epsilon * 2^floor(log2(|val|))
;   simplified: extract exponent from val, combine with epsilon
; -----------------------------------------------------------------------------
global umath_dtype_ulp_f64
umath_dtype_ulp_f64:
    sub     rsp, 24
    movsd   [rsp], xmm0            ; save value
    push    rdi
    call    umath_dtype_epsilon_f64 ; xmm0 = epsilon
    movsd   [rsp + 8], xmm0        ; save epsilon
    ; get |value|
    movsd   xmm0, [rsp + 16]
    ; extract biased exponent from value
    movq    rax, xmm0
    shr     rax, 52
    and     rax, 0x7FF             ; biased exponent
    test    rax, rax
    jz      .subnormal_or_zero
    ; ulp = epsilon * 2^(exponent - 1022)
    ; = epsilon * 2^(biased_exp - 1023 - 52 + 1)
    ; combined: set exponent of epsilon to (biased_exp - 52)
    movsd   xmm0, [rsp + 8]        ; epsilon
    movq    rdx, xmm0
    shr     rdx, 52
    and     rdx, 0x7FF             ; epsilon exponent
    add     rax, rdx
    sub     rax, 1023              ; adjust
    ; clamp exponent
    cmp     rax, 0
    jle     .zero_ulp
    cmp     rax, 2046
    jge     .max_ulp
    movq    rdx, xmm0
    and     rdx, 0x800FFFFFFFFFFFFF ; clear exponent
    shl     rax, 52
    or      rdx, rax
    movq    xmm0, rdx
    add     rsp, 24
    ret
.subnormal_or_zero:
    movsd   xmm0, [rsp + 8]        ; just return epsilon
    add     rsp, 24
    ret
.zero_ulp:
    xorpd   xmm0, xmm0
    add     rsp, 24
    ret
.max_ulp:
    mov     rax, FP64_POS_INF
    movq    xmm0, rax
    add     rsp, 24
    ret

; -----------------------------------------------------------------------------
; umath_dtype_round_error_f64 - maximum rounding error (0.5 ULP)
; args:    edi = dtype_id
; returns: xmm0 = 0.5 * epsilon
; -----------------------------------------------------------------------------
global umath_dtype_round_error_f64
umath_dtype_round_error_f64:
    call    umath_dtype_epsilon_f64
    ; multiply by 0.5: decrement exponent by 1
    movq    rax, xmm0
    test    rax, rax
    jz      .zero
    sub     rax, 0x0010000000000000 ; decrement exponent
    movq    xmm0, rax
    ret
.zero:
    xorpd   xmm0, xmm0
    ret

FP64_POS_INF equ 0x7FF0000000000000