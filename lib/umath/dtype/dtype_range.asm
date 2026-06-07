; =============================================================================
; umath - unified math library
; dtype/dtype_range.asm - representable value ranges
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_traits.asm
;   dtype_patterns.asm
;
; description:
;   provides min, max, and smallest nonzero values for each dtype
;   float values returned in FP64 for uniformity
;   integer values returned as i64/u64
;   for types wider than 64-bit, returns clamped approximation
;
; functions:
;   umath_dtype_max_f64        (dtype_id → f64 in xmm0)
;   umath_dtype_min_f64        (dtype_id → f64 in xmm0)
;   umath_dtype_smallest_f64   (dtype_id → f64 in xmm0) smallest positive
;   umath_dtype_max_u64        (dtype_id → u64 in rax)  unsigned max
;   umath_dtype_min_i64        (dtype_id → i64 in rax)  signed min
;   umath_dtype_max_i64        (dtype_id → i64 in rax)  signed max
;   umath_dtype_in_range_f64   (dtype_id, f64 val → bool)
;   umath_dtype_in_range_i64   (dtype_id, i64 val → bool)
;   umath_dtype_clamp_f64      (dtype_id, f64 val → f64) clamp to range
; =============================================================================

%include "dtype_id.asm"

bits 64

; =============================================================================
; range table: [max_f64, min_f64, smallest_f64] per dtype
; stored as raw u64 (IEEE 754 double bit patterns)
; indexed sequentially for covered dtypes only
; =============================================================================

; FP64 bit patterns for common values
FP64_POS_INF        equ 0x7FF0000000000000
FP64_NEG_INF        equ 0xFFF0000000000000
FP64_ZERO           equ 0x0000000000000000

; INT limits as u64 bit patterns
; INT8:  max=127    min=-128
; UINT8: max=255    min=0
; INT16: max=32767  min=-32768
; INT32: max=2147483647  min=-2147483648
; INT64: max=0x7FFFFFFFFFFFFFFF

section .rodata
align 64

; format per entry: 3 × f64 (max, min, smallest_positive)
dtype_range_table:

; DTYPE_NONE (0x000)
dq 0x0000000000000000, 0x0000000000000000, 0x0000000000000000

; INT1 (0x001): max=1 min=-1 smallest=1
dq 0x3FF0000000000000, 0xBFF0000000000000, 0x3FF0000000000000

; INT2 (0x002): max=1 min=-2 smallest=1
dq 0x3FF0000000000000, 0xC000000000000000, 0x3FF0000000000000

; INT4 (0x003): max=7 min=-8 smallest=1
dq 0x401C000000000000, 0xC020000000000000, 0x3FF0000000000000

; INT8 (0x004): max=127 min=-128 smallest=1
dq 0x405FC00000000000, 0xC060000000000000, 0x3FF0000000000000

; INT16 (0x005): max=32767 min=-32768 smallest=1
dq 0x40DFFFC000000000, 0x40E0000000000000, 0x3FF0000000000000

; INT32 (0x006): max=2147483647 min=-2147483648 smallest=1
dq 0x41DFFFFFFFC00000, 0x41E0000000000000, 0x3FF0000000000000

; INT64 (0x007): max≈9.22e18 min≈-9.22e18 smallest=1
dq 0x43DFFFFFFFFFFFFF, 0x43E0000000000000, 0x3FF0000000000000

; INT128 (0x008): approximate via FP64
dq FP64_POS_INF, FP64_NEG_INF, 0x3FF0000000000000

; INT256 (0x009): approximate via FP64
dq FP64_POS_INF, FP64_NEG_INF, 0x3FF0000000000000

; padding 0x00A-0x00F
times 6 dq 0, 0, 0

; UINT4 (0x010): max=15 min=0 smallest=1
dq 0x402E000000000000, 0x0000000000000000, 0x3FF0000000000000

; UINT8 (0x011): max=255 min=0 smallest=1
dq 0x406FE00000000000, 0x0000000000000000, 0x3FF0000000000000

; UINT16 (0x012): max=65535 min=0 smallest=1
dq 0x40EFFFE000000000, 0x0000000000000000, 0x3FF0000000000000

; UINT32 (0x013): max=4294967295 min=0 smallest=1
dq 0x41EFFFFFFFE00000, 0x0000000000000000, 0x3FF0000000000000

; UINT64 (0x014): max≈1.84e19 min=0 smallest=1
dq 0x43EFFFFFFFFFFFFF, 0x0000000000000000, 0x3FF0000000000000

; UINT128 (0x015): approximate
dq FP64_POS_INF, 0x0000000000000000, 0x3FF0000000000000

; UINT256 (0x016)
dq FP64_POS_INF, 0x0000000000000000, 0x3FF0000000000000

; UINT512 (0x017)
dq FP64_POS_INF, 0x0000000000000000, 0x3FF0000000000000

; UINT1024 (0x018)
dq FP64_POS_INF, 0x0000000000000000, 0x3FF0000000000000

; UINT2048 (0x019)
dq FP64_POS_INF, 0x0000000000000000, 0x3FF0000000000000

; padding 0x01A-0x01F
times 6 dq 0, 0, 0

; FP8_E4M3 (0x020): max=448.0 min=-448.0 smallest_normal≈0.015625
; max = 0x7E = 0111_1110 = 1.111 × 2^7 = 240 (corrected: 1.110 * 2^7 = 448)
dq 0x407C000000000000, 0xC07C000000000000, 0x3F80000000000000

; FP8_E5M2 (0x021): max=57344.0 min=-57344.0 smallest_normal≈2^-14
dq 0x40EC000000000000, 0xC0EC000000000000, 0x3F10000000000000

; FP16 (0x022): max=65504 min=-65504 smallest_normal=2^-14
dq 0x40EFFC0000000000, 0xC0EFFC0000000000, 0x3F10000000000000

; BF16 (0x023): max≈3.39e38 min≈-3.39e38 smallest_normal≈1.175e-38
dq 0x47EFFE0000000000, 0xC7EFFE0000000000, 0x3810000000000000

; TF32 (0x024): same range as FP32
dq 0x47EFFFFFE0000000, 0xC7EFFFFFE0000000, 0x3810000000000000

; FP32 (0x025): max≈3.4028e38 min≈-3.4028e38 smallest_normal≈1.175e-38
dq 0x47EFFFFFE0000000, 0xC7EFFFFFE0000000, 0x3810000000000000

; FP64 (0x026): max≈1.798e308 min≈-1.798e308
dq 0x7FEFFFFFFFFFFFFF, 0xFFEFFFFFFFFFFFFF, 0x0010000000000000

; FP128 (0x027): approximate as FP64_INF
dq FP64_POS_INF, FP64_NEG_INF, 0x0000000000000001

; FP8_E4M3_FNUZ (0x028): same max as E4M3
dq 0x407C000000000000, 0xC07C000000000000, 0x3F80000000000000

; FP8_E5M2_FNUZ (0x029)
dq 0x40EC000000000000, 0xC0EC000000000000, 0x3F10000000000000

; BFLOAT8 (0x02A)
dq 0x40EC000000000000, 0xC0EC000000000000, 0x3F10000000000000

; MINIFLOAT (0x02B)
dq 0x407C000000000000, 0xC07C000000000000, 0x3F80000000000000

; FP6_E2M3 (0x02C): max=7.5 min=-7.5 smallest_normal=0.25
dq 0x401E000000000000, 0xC01E000000000000, 0x3FD0000000000000

; FP6_E3M2 (0x02D): max=28.0 min=-28.0 smallest_normal=0.25
dq 0x403C000000000000, 0xC03C000000000000, 0x3FD0000000000000

; padding 0x02E-0x02F
times 2 dq 0, 0, 0

; MXFP8_E4M3 (0x030): same as FP8_E4M3 element range
dq 0x407C000000000000, 0xC07C000000000000, 0x3F80000000000000

; MXFP8_E5M2 (0x031)
dq 0x40EC000000000000, 0xC0EC000000000000, 0x3F10000000000000

; MXFP6_E2M3 (0x032)
dq 0x401E000000000000, 0xC01E000000000000, 0x3FD0000000000000

; MXFP6_E3M2 (0x033)
dq 0x403C000000000000, 0xC03C000000000000, 0x3FD0000000000000

; MXFP4_E2M1 (0x034): max=6.0 min=-6.0 smallest=0.5
dq 0x4018000000000000, 0xC018000000000000, 0x3FE0000000000000

; MXINT8 (0x035): same as INT8
dq 0x405FC00000000000, 0xC060000000000000, 0x3FF0000000000000

; MXINT6 (0x036): max=31 min=-32 smallest=1
dq 0x403F000000000000, 0xC040000000000000, 0x3FF0000000000000

; MXINT4 (0x037): max=7 min=-8 smallest=1
dq 0x401C000000000000, 0xC020000000000000, 0x3FF0000000000000

; UE8M0 (0x038): unsigned exponent only, range 2^-127 to 2^128
dq FP64_POS_INF, 0x0000000000000000, 0x0000000000000001

; NVFP4 (0x039): same as MXFP4 element range
dq 0x4018000000000000, 0xC018000000000000, 0x3FE0000000000000

; NVINT4 (0x03A): same as MXINT4
dq 0x401C000000000000, 0xC020000000000000, 0x3FF0000000000000

; NVFP8 (0x03B): same as FP8_E4M3
dq 0x407C000000000000, 0xC07C000000000000, 0x3F80000000000000

; padding 0x03C-0x03F
times 4 dq 0, 0, 0

; Q4_0 (0x040): range [-8, 7] / scale
dq 0x401C000000000000, 0xC020000000000000, 0x3FF0000000000000

; Q4_1 (0x041)
dq 0x402E000000000000, 0x0000000000000000, 0x3FF0000000000000

; Q5_0 (0x042): range [-16, 15]
dq 0x402E000000000000, 0xC030000000000000, 0x3FF0000000000000

; Q5_1 (0x043)
dq 0x403F000000000000, 0x0000000000000000, 0x3FF0000000000000

; Q8_0 (0x044): range [-128, 127]
dq 0x405FC00000000000, 0xC060000000000000, 0x3FF0000000000000

; BIT_PACKED (0x045): variable
dq 0, 0, 0

; DELTA_ENC (0x046): variable
dq 0, 0, 0

; padding 0x047-0x04F
times 9 dq 0, 0, 0

; UNORM8 (0x050): [0.0, 1.0]
dq 0x3FF0000000000000, 0x0000000000000000, 0x3B70000000000000

; UNORM16 (0x051): [0.0, 1.0]
dq 0x3FF0000000000000, 0x0000000000000000, 0x3EF0000000000000

; SNORM8 (0x052): [-1.0, 1.0]
dq 0x3FF0000000000000, 0xBFF0000000000000, 0x3C00000000000000

; SNORM16 (0x053): [-1.0, 1.0]
dq 0x3FF0000000000000, 0xBFF0000000000000, 0x3F00000000000000

; PROB32 (0x054): [0.0, 1.0]
dq 0x3FF0000000000000, 0x0000000000000000, 0x3810000000000000

; LOG_PROB32 (0x055): (-inf, 0.0]
dq 0x0000000000000000, FP64_NEG_INF, 0x3810000000000000

; FUZZY (0x056): [0.0, 1.0]
dq 0x3FF0000000000000, 0x0000000000000000, 0x3810000000000000

dtype_range_table_end:
DTYPE_RANGE_TABLE_COUNT equ (dtype_range_table_end - dtype_range_table) / 24

; offsets within each entry
RANGE_OFF_MAX           equ 0
RANGE_OFF_MIN           equ 8
RANGE_OFF_SMALLEST      equ 16
RANGE_ENTRY_SIZE        equ 24

section .text

; -----------------------------------------------------------------------------
; internal: get pointer to range entry for dtype
; args:    edi = dtype_id
; returns: rax = pointer to entry, NULL if out of range
; -----------------------------------------------------------------------------
dtype_range_ptr:
    cmp     edi, DTYPE_RANGE_TABLE_COUNT
    jae     .null
    lea     rax, [rel dtype_range_table]
    imul    edi, RANGE_ENTRY_SIZE
    add     rax, rdi
    ret
.null:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_max_f64 - maximum finite value as FP64
; args:    edi = dtype_id
; returns: xmm0 = max value as double
; -----------------------------------------------------------------------------
global umath_dtype_max_f64
umath_dtype_max_f64:
    call    dtype_range_ptr
    test    rax, rax
    jz      .zero
    movsd   xmm0, [rax + RANGE_OFF_MAX]
    ret
.zero:
    xorpd   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_dtype_min_f64 - minimum value (most negative) as FP64
; args:    edi = dtype_id
; returns: xmm0 = min value as double
; -----------------------------------------------------------------------------
global umath_dtype_min_f64
umath_dtype_min_f64:
    call    dtype_range_ptr
    test    rax, rax
    jz      .zero
    movsd   xmm0, [rax + RANGE_OFF_MIN]
    ret
.zero:
    xorpd   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_dtype_smallest_f64 - smallest positive normal value as FP64
; args:    edi = dtype_id
; returns: xmm0 = smallest positive value as double
; -----------------------------------------------------------------------------
global umath_dtype_smallest_f64
umath_dtype_smallest_f64:
    call    dtype_range_ptr
    test    rax, rax
    jz      .zero
    movsd   xmm0, [rax + RANGE_OFF_SMALLEST]
    ret
.zero:
    xorpd   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_dtype_max_u64 - maximum value as u64 (for integer types)
; args:    edi = dtype_id
; returns: rax = max value as u64
;          saturates at 0xFFFFFFFFFFFFFFFF for types wider than 64-bit
; -----------------------------------------------------------------------------
global umath_dtype_max_u64
umath_dtype_max_u64:
    ; handle common cases directly
    cmp     edi, DTYPE_UINT8
    je      .uint8
    cmp     edi, DTYPE_UINT16
    je      .uint16
    cmp     edi, DTYPE_UINT32
    je      .uint32
    cmp     edi, DTYPE_UINT64
    je      .uint64
    cmp     edi, DTYPE_INT8
    je      .int8
    cmp     edi, DTYPE_INT16
    je      .int16
    cmp     edi, DTYPE_INT32
    je      .int32
    cmp     edi, DTYPE_INT64
    je      .int64
    cmp     edi, DTYPE_INT4
    je      .int4
    cmp     edi, DTYPE_UINT4
    je      .uint4
    cmp     edi, DTYPE_INT1
    je      .int1
    cmp     edi, DTYPE_INT2
    je      .int2
    ; wider types saturate
    cmp     edi, DTYPE_UINT128
    jge     .saturate
    ; default
    xor     eax, eax
    ret
.uint8:     mov rax, 0xFF                   ; ret
            ret
.uint16:    mov rax, 0xFFFF                 ; ret
            ret
.uint32:    mov rax, 0xFFFFFFFF             ; ret
            ret
.uint64:    mov rax, 0xFFFFFFFFFFFFFFFF     ; ret
            ret
.int8:      mov rax, 127                    ; ret
            ret
.int16:     mov rax, 32767                  ; ret
            ret
.int32:     mov rax, 2147483647             ; ret
            ret
.int64:     mov rax, 0x7FFFFFFFFFFFFFFF     ; ret
            ret
.int4:      mov rax, 7                      ; ret
            ret
.uint4:     mov rax, 15                     ; ret
            ret
.int1:      mov rax, 1                      ; ret (signed: 0/1 or -1/0?)
            ret
.int2:      mov rax, 1                      ; ret
            ret
.saturate:  mov rax, 0xFFFFFFFFFFFFFFFF
            ret

; -----------------------------------------------------------------------------
; umath_dtype_min_i64 - minimum value as i64 (for signed integer types)
; args:    edi = dtype_id
; returns: rax = min value as i64 (sign extended)
; -----------------------------------------------------------------------------
global umath_dtype_min_i64
umath_dtype_min_i64:
    cmp     edi, DTYPE_INT8
    je      .int8
    cmp     edi, DTYPE_INT16
    je      .int16
    cmp     edi, DTYPE_INT32
    je      .int32
    cmp     edi, DTYPE_INT64
    je      .int64
    cmp     edi, DTYPE_INT4
    je      .int4
    cmp     edi, DTYPE_INT2
    je      .int2
    cmp     edi, DTYPE_INT1
    je      .int1
    ; unsigned types: min = 0
    cmp     edi, DTYPE_UINT4
    je      .zero
    cmp     edi, DTYPE_UINT8
    je      .zero
    cmp     edi, DTYPE_UINT16
    je      .zero
    cmp     edi, DTYPE_UINT32
    je      .zero
    cmp     edi, DTYPE_UINT64
    je      .zero
    xor     eax, eax
    ret
.int8:  mov rax, -128                   ; ret
        ret
.int16: mov rax, -32768                 ; ret
        ret
.int32: mov rax, -2147483648            ; ret
        ret
.int64: mov rax, 0x8000000000000000     ; ret
        ret
.int4:  mov rax, -8                     ; ret
        ret
.int2:  mov rax, -2                     ; ret
        ret
.int1:  mov rax, -1                     ; ret
        ret
.zero:  xor eax, eax
        ret

; -----------------------------------------------------------------------------
; umath_dtype_in_range_f64 - check if f64 value fits in dtype range
; args:    edi  = dtype_id
;          xmm0 = value as f64
; returns: eax  = 1 if in range, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_in_range_f64
umath_dtype_in_range_f64:
    sub     rsp, 24
    movsd   [rsp], xmm0            ; save value
    call    umath_dtype_max_f64
    movsd   xmm1, xmm0             ; xmm1 = max
    movsd   xmm0, [rsp]            ; xmm0 = value
    ucomisd xmm0, xmm1
    ja      .out_of_range
    call    umath_dtype_min_f64
    movsd   xmm1, xmm0             ; xmm1 = min
    movsd   xmm0, [rsp]
    ucomisd xmm0, xmm1
    jb      .out_of_range
    mov     eax, 1
    add     rsp, 24
    ret
.out_of_range:
    xor     eax, eax
    add     rsp, 24
    ret

; -----------------------------------------------------------------------------
; umath_dtype_in_range_i64 - check if i64 value fits in dtype range
; args:    edi = dtype_id
;          rsi = value as i64
; returns: eax = 1 if in range, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_in_range_i64
umath_dtype_in_range_i64:
    push    rbx
    push    r12
    mov     r12, rsi                ; save value
    mov     ebx, edi
    call    umath_dtype_max_u64     ; approximate max
    cmp     r12, rax
    jg      .out_of_range
    mov     edi, ebx
    call    umath_dtype_min_i64
    cmp     r12, rax
    jl      .out_of_range
    mov     eax, 1
    pop     r12
    pop     rbx
    ret
.out_of_range:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_clamp_f64 - clamp f64 value to dtype range
; args:    edi  = dtype_id
;          xmm0 = value as f64
; returns: xmm0 = clamped value
; -----------------------------------------------------------------------------
global umath_dtype_clamp_f64
umath_dtype_clamp_f64:
    sub     rsp, 24
    movsd   [rsp], xmm0            ; save value
    call    umath_dtype_max_f64
    movsd   xmm1, xmm0             ; max
    movsd   xmm0, [rsp]            ; value
    minsd   xmm0, xmm1             ; clamp to max
    movsd   [rsp], xmm0
    push    rdi
    call    umath_dtype_min_f64
    movsd   xmm1, xmm0             ; min
    movsd   xmm0, [rsp + 8]        ; clamped value
    maxsd   xmm0, xmm1             ; clamp to min
    pop     rdi
    add     rsp, 24
    ret