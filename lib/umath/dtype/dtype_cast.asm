; =============================================================================
; umath - unified math library
; dtype/dtype_cast.asm - dtype casting rules
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_family.asm
;   dtype_size.asm
;   dtype_traits.asm
;   dtype_promote.asm
;
; description:
;   defines casting safety levels and overflow/underflow behavior
;   between every pair of dtypes
;
; cast safety levels:
;   CAST_LOSSLESS    = 0  no precision or range loss possible
;   CAST_SAFE        = 1  possible precision loss, no overflow
;   CAST_OVERFLOW    = 2  overflow possible if value out of range
;   CAST_UNSAFE      = 3  undefined for some inputs (NaN→int etc)
;   CAST_QUANTIZE    = 4  requires scale/zero_point computation
;   CAST_IMPOSSIBLE  = 5  cannot cast (incompatible families)
;
; overflow behaviors:
;   OVERFLOW_WRAP       = 0  wrapping (C unsigned semantics)
;   OVERFLOW_SATURATE   = 1  clamp to min/max
;   OVERFLOW_UNDEFINED  = 2  undefined behavior
;   OVERFLOW_TRAP       = 3  trap/exception
;   OVERFLOW_NA         = 4  not applicable (lossless cast)
;
; functions:
;   umath_dtype_cast_safe        (src_id, dst_id → bool) safe to cast
;   umath_dtype_cast_lossless    (src_id, dst_id → bool) no precision loss
;   umath_dtype_cast_level       (src_id, dst_id → u32) CAST_* level
;   umath_dtype_cast_overflow_beh(src_id, dst_id → u32) OVERFLOW_* behavior
;   umath_dtype_cast_cost        (src_id, dst_id → u32) relative cost 0-3
;   umath_dtype_cast_needs_scale (src_id, dst_id → bool) needs quant scale
; =============================================================================

%include "dtype_id.asm"
%include "dtype_family.asm"
%include "dtype_size.asm"

bits 64

; =============================================================================
; cast safety level constants
; =============================================================================

CAST_LOSSLESS       equ 0
CAST_SAFE           equ 1
CAST_OVERFLOW       equ 2
CAST_UNSAFE         equ 3
CAST_QUANTIZE       equ 4
CAST_IMPOSSIBLE     equ 5

; overflow behavior constants
OVERFLOW_WRAP       equ 0
OVERFLOW_SATURATE   equ 1
OVERFLOW_UNDEFINED  equ 2
OVERFLOW_TRAP       equ 3
OVERFLOW_NA         equ 4

section .text

; -----------------------------------------------------------------------------
; umath_dtype_cast_lossless - can src be cast to dst without any loss?
; args:    edi = src dtype_id
;          esi = dst dtype_id
; returns: eax = 1 if lossless, 0 otherwise
;
; lossless pairs (examples):
;   INT8   → INT16, INT32, INT64
;   INT16  → INT32, INT64
;   INT32  → INT64
;   FP32   → FP64
;   FP16   → FP32, FP64
;   BF16   → FP32, FP64
;   INT8   → FP32  (all INT8 values exactly representable in FP32)
;   INT16  → FP32  (all INT16 values exactly representable in FP32)
;   INT32  → FP64  (all INT32 values exactly representable in FP64)
; -----------------------------------------------------------------------------
global umath_dtype_cast_lossless
umath_dtype_cast_lossless:
    ; same dtype is always lossless
    cmp     edi, esi
    je      .yes

    ; get sizes
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12d, esi

    ; get families
    call    umath_dtype_get_family
    mov     r13d, eax               ; src_family

    mov     edi, r12d
    call    umath_dtype_get_family
    ; eax = dst_family

    ; INT → INT: lossless if dst is same sign and wider or signed dst wider
    cmp     r13d, DFAMILY_INT_SIGNED
    je      .src_int_signed
    cmp     r13d, DFAMILY_INT_UNSIGNED
    je      .src_int_unsigned

    ; FP → FP: lossless if dst has >= precision
    cmp     r13d, DFAMILY_FLOAT_IEEE
    je      .src_float

    ; FP8/FP6 → higher precision float: lossless
    cmp     r13d, DFAMILY_FLOAT_FP8_VAR
    je      .src_float
    cmp     r13d, DFAMILY_FLOAT_FP6
    je      .src_float

    ; anything → BIGNUM: lossless
    cmp     eax, DFAMILY_BIGNUM
    je      .yes

    ; default: not lossless
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

.src_int_signed:
    ; dst must be signed integer and wider
    cmp     eax, DFAMILY_INT_SIGNED
    jne     .check_int_to_float
    ; compare sizes
    mov     edi, ebx
    call    umath_dtype_size_bits
    mov     ecx, eax                ; src_bits
    mov     edi, r12d
    call    umath_dtype_size_bits
    cmp     eax, ecx               ; dst_bits >= src_bits?
    jge     .yes
    jmp     .no

.src_int_unsigned:
    ; dst unsigned and wider, OR dst signed and wider
    cmp     eax, DFAMILY_INT_UNSIGNED
    je      .check_uint_to_uint
    cmp     eax, DFAMILY_INT_SIGNED
    je      .check_uint_to_sint
    jmp     .check_int_to_float

.check_uint_to_uint:
    mov     edi, ebx
    call    umath_dtype_size_bits
    mov     ecx, eax
    mov     edi, r12d
    call    umath_dtype_size_bits
    cmp     eax, ecx
    jge     .yes
    jmp     .no

.check_uint_to_sint:
    ; need dst 1 bit wider for sign
    mov     edi, ebx
    call    umath_dtype_size_bits
    mov     ecx, eax
    mov     edi, r12d
    call    umath_dtype_size_bits
    cmp     eax, ecx
    jg      .yes                    ; strictly greater (extra sign bit)
    jmp     .no

.check_int_to_float:
    ; INT8/16 → FP32: lossless (FP32 has 23 mantissa bits)
    ; INT32   → FP64: lossless (FP64 has 52 mantissa bits)
    cmp     eax, DFAMILY_FLOAT_IEEE
    jne     .no
    cmp     ebx, DTYPE_INT8
    jg      .check_int16
    cmp     r12d, DTYPE_FP32
    jge     .yes
    jmp     .no
.check_int16:
    cmp     ebx, DTYPE_INT16
    jg      .check_int32
    cmp     r12d, DTYPE_FP32
    jge     .yes
    jmp     .no
.check_int32:
    cmp     ebx, DTYPE_INT32
    jg      .no
    cmp     r12d, DTYPE_FP64
    jge     .yes
    jmp     .no

.src_float:
    ; float → float: lossless if dst has >= exponent AND >= mantissa bits
    cmp     eax, DFAMILY_FLOAT_IEEE
    jne     .no

    ; FP8 → FP16+: lossless
    cmp     ebx, DTYPE_FP8_E4M3
    je      .fp8_to_bigger
    cmp     ebx, DTYPE_FP8_E5M2
    je      .fp8_to_bigger

    ; FP16 → FP32/FP64: lossless
    cmp     ebx, DTYPE_FP16
    je      .fp16_to_bigger

    ; BF16 → FP32/FP64: lossless
    cmp     ebx, DTYPE_BF16
    je      .bf16_to_bigger

    ; FP32 → FP64: lossless
    cmp     ebx, DTYPE_FP32
    je      .fp32_to_bigger

    jmp     .no

.fp8_to_bigger:
    cmp     r12d, DTYPE_FP16
    jge     .yes
    jmp     .no
.fp16_to_bigger:
    cmp     r12d, DTYPE_FP32
    jge     .yes
    jmp     .no
.bf16_to_bigger:
    cmp     r12d, DTYPE_FP32
    jge     .yes
    jmp     .no
.fp32_to_bigger:
    cmp     r12d, DTYPE_FP64
    jge     .yes
    jmp     .no

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
; umath_dtype_cast_level - get cast safety level
; args:    edi = src dtype_id
;          esi = dst dtype_id
; returns: eax = CAST_* level
; -----------------------------------------------------------------------------
global umath_dtype_cast_level
umath_dtype_cast_level:
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi

    ; same type: lossless
    cmp     edi, esi
    je      .lossless

    ; check lossless
    call    umath_dtype_cast_lossless
    test    eax, eax
    jnz     .lossless

    ; get families
    mov     edi, ebx
    call    umath_dtype_get_family
    push    rax                     ; src_family
    mov     edi, r12d
    call    umath_dtype_get_family
    pop     rcx                     ; src_family
    ; eax = dst_family, ecx = src_family

    ; float → float (not lossless): safe (precision loss only)
    cmp     ecx, DFAMILY_FLOAT_IEEE
    jne     .not_src_float
    cmp     eax, DFAMILY_FLOAT_IEEE
    je      .safe
    cmp     eax, DFAMILY_FLOAT_FP8_VAR
    je      .safe
    cmp     eax, DFAMILY_FLOAT_OCP
    je      .safe
    cmp     eax, DFAMILY_INT_SIGNED
    je      .unsafe             ; float→int: NaN/inf → undefined
    cmp     eax, DFAMILY_INT_UNSIGNED
    je      .unsafe
    jmp     .safe
.not_src_float:

    ; int → narrower int: overflow possible
    cmp     ecx, DFAMILY_INT_SIGNED
    je      .src_int
    cmp     ecx, DFAMILY_INT_UNSIGNED
    je      .src_int

    ; quantization types: need scale
    cmp     eax, DFAMILY_GGUF
    je      .quantize
    cmp     eax, DFAMILY_FLOAT_OCP
    je      .quantize
    cmp     eax, DFAMILY_FLOAT_NV
    je      .quantize
    cmp     ecx, DFAMILY_GGUF
    je      .quantize

    ; bignum → anything: safe (just loses magnitude info)
    cmp     ecx, DFAMILY_BIGNUM
    je      .safe

    ; incompatible families (geometric → int etc)
    cmp     ecx, DFAMILY_GEOMETRIC
    je      .impossible
    cmp     ecx, DFAMILY_ABSTRACT
    je      .impossible
    cmp     ecx, DFAMILY_QUANTUM
    je      .impossible
    cmp     eax, DFAMILY_GEOMETRIC
    je      .impossible

    jmp     .safe

.src_int:
    ; check if narrowing
    mov     edi, ebx
    call    umath_dtype_size_bits
    mov     r13d, eax
    push    r13
    mov     edi, r12d
    call    umath_dtype_size_bits
    pop     r13
    cmp     eax, r13d
    jl      .overflow               ; narrowing → overflow possible
    jmp     .safe

.lossless:
    mov     eax, CAST_LOSSLESS
    jmp     .done
.safe:
    mov     eax, CAST_SAFE
    jmp     .done
.overflow:
    mov     eax, CAST_OVERFLOW
    jmp     .done
.unsafe:
    mov     eax, CAST_UNSAFE
    jmp     .done
.quantize:
    mov     eax, CAST_QUANTIZE
    jmp     .done
.impossible:
    mov     eax, CAST_IMPOSSIBLE
.done:
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_cast_safe - is it safe to cast src to dst?
; args:    edi = src dtype_id
;          esi = dst dtype_id
; returns: eax = 1 if safe (CAST_LOSSLESS or CAST_SAFE), 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_cast_safe
umath_dtype_cast_safe:
    call    umath_dtype_cast_level
    cmp     eax, CAST_SAFE
    setle   al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_cast_overflow_beh - overflow behavior when casting
; args:    edi = src dtype_id
;          esi = dst dtype_id
; returns: eax = OVERFLOW_* constant
; -----------------------------------------------------------------------------
global umath_dtype_cast_overflow_beh
umath_dtype_cast_overflow_beh:
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi

    ; get cast level first
    call    umath_dtype_cast_level

    ; lossless: no overflow
    test    eax, eax
    jz      .na

    ; safe: no overflow possible
    cmp     eax, CAST_SAFE
    je      .na

    ; unsafe (float→int): undefined
    cmp     eax, CAST_UNSAFE
    je      .undefined

    ; overflow case: behavior depends on dst type
    mov     edi, r12d
    call    umath_dtype_get_family

    ; unsigned int: wrapping (C semantics)
    cmp     eax, DFAMILY_INT_UNSIGNED
    je      .wrap

    ; signed int: saturate (safer default for ML)
    cmp     eax, DFAMILY_INT_SIGNED
    je      .saturate

    ; float: saturate to ±inf
    cmp     eax, DFAMILY_FLOAT_IEEE
    je      .saturate

    ; quantized: saturate
    jmp     .saturate

.na:
    mov     eax, OVERFLOW_NA
    jmp     .done
.wrap:
    mov     eax, OVERFLOW_WRAP
    jmp     .done
.saturate:
    mov     eax, OVERFLOW_SATURATE
    jmp     .done
.undefined:
    mov     eax, OVERFLOW_UNDEFINED
.done:
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_cast_cost - relative cost of cast operation (0=free, 3=expensive)
; args:    edi = src dtype_id
;          esi = dst dtype_id
; returns: eax = cost 0-3
;   0: same dtype, register rename
;   1: single instruction (VCVTPH2PS, VCVTPS2PH etc)
;   2: multi-step conversion (FP8→FP32 needs software)
;   3: very expensive (quantization, bignum ops)
; -----------------------------------------------------------------------------
global umath_dtype_cast_cost
umath_dtype_cast_cost:
    ; same type: free
    cmp     edi, esi
    je      .free

    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi

    call    umath_dtype_get_family
    push    rax
    mov     edi, r12d
    call    umath_dtype_get_family
    pop     rcx
    ; eax = dst_family, ecx = src_family

    ; FP32 ↔ FP64: single CVT instruction
    cmp     ebx, DTYPE_FP32
    je      .check_fp32_fp64
    cmp     ebx, DTYPE_FP64
    je      .check_fp64_fp32

    ; FP16 ↔ FP32: single AVX instruction VCVTPH2PS/VCVTPS2PH
    cmp     ebx, DTYPE_FP16
    je      .cheap
    cmp     r12d, DTYPE_FP16
    je      .cheap

    ; BF16 ↔ FP32: single instruction (AVX512_BF16)
    cmp     ebx, DTYPE_BF16
    je      .cheap
    cmp     r12d, DTYPE_BF16
    je      .cheap

    ; INT ↔ INT same family: cheap
    cmp     ecx, DFAMILY_INT_SIGNED
    jne     .not_int_int
    cmp     eax, DFAMILY_INT_SIGNED
    je      .cheap
    cmp     eax, DFAMILY_INT_UNSIGNED
    je      .cheap
.not_int_int:

    ; FP8 conversions: software, medium cost
    cmp     ecx, DFAMILY_FLOAT_FP8_VAR
    je      .medium
    cmp     eax, DFAMILY_FLOAT_FP8_VAR
    je      .medium
    cmp     ebx, DTYPE_FP8_E4M3
    je      .medium
    cmp     ebx, DTYPE_FP8_E5M2
    je      .medium
    cmp     r12d, DTYPE_FP8_E4M3
    je      .medium
    cmp     r12d, DTYPE_FP8_E5M2
    je      .medium

    ; quantization casts: expensive
    cmp     eax, DFAMILY_GGUF
    je      .expensive
    cmp     ecx, DFAMILY_GGUF
    je      .expensive
    cmp     eax, DFAMILY_FLOAT_OCP
    je      .expensive
    cmp     ecx, DFAMILY_FLOAT_OCP
    je      .expensive

    ; bignum: expensive
    cmp     eax, DFAMILY_BIGNUM
    je      .expensive
    cmp     ecx, DFAMILY_BIGNUM
    je      .expensive

    ; default: medium
    jmp     .medium

.check_fp32_fp64:
    cmp     r12d, DTYPE_FP64
    je      .cheap
    jmp     .medium
.check_fp64_fp32:
    cmp     r12d, DTYPE_FP32
    je      .cheap
    jmp     .medium

.free:
    xor     eax, eax
    ret
.cheap:
    mov     eax, 1
    pop     r12
    pop     rbx
    ret
.medium:
    mov     eax, 2
    pop     r12
    pop     rbx
    ret
.expensive:
    mov     eax, 3
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_cast_needs_scale - does cast require quantization scale?
; args:    edi = src dtype_id
;          esi = dst dtype_id
; returns: eax = 1 if needs scale/zero_point, 0 otherwise
; note:    FP32→INT8, FP32→MXFP4, FP32→GGUF etc all need scale
; -----------------------------------------------------------------------------
global umath_dtype_cast_needs_scale
umath_dtype_cast_needs_scale:
    call    umath_dtype_cast_level
    cmp     eax, CAST_QUANTIZE
    sete    al
    movzx   eax, al
    ret