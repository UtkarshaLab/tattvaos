; =============================================================================
; umath - unified math library
; dtype/dtype_align.asm - dtype alignment requirements
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_size.asm
;
; functions:
;   umath_dtype_align_scalar   (dtype_id → u32) scalar alignment in bytes
;   umath_dtype_align_xmm      (dtype_id → u32) XMM alignment (128-bit)
;   umath_dtype_align_ymm      (dtype_id → u32) YMM alignment (256-bit)
;   umath_dtype_align_zmm      (dtype_id → u32) ZMM alignment (512-bit)
;   umath_dtype_align_cache    (dtype_id → u32) cache line alignment
;   umath_dtype_align_for_simd (dtype_id, simd_width → u32) general query
;   umath_dtype_is_aligned     (ptr, dtype_id → bool) check pointer alignment
;   umath_dtype_align_up       (ptr, dtype_id → ptr) align pointer up
;
; alignment rules:
;   scalar  → natural alignment (size of type, max 8 bytes)
;   XMM     → 16 bytes
;   YMM     → 32 bytes
;   ZMM     → 64 bytes
;   cache   → 64 bytes (cache line)
;
; sub-byte types:
;   scalar alignment = 1 byte (minimum addressable)
;   SIMD alignment   = same as container type alignment
;
; variable-size types:
;   scalar alignment = 8 bytes (pointer-aligned)
;   SIMD alignment   = 64 bytes (safe default)
; =============================================================================

%include "dtype_id.asm"

bits 64

; =============================================================================
; scalar alignment table (u8 per entry, alignment in bytes)
; indexed by dtype_id
; =============================================================================

section .rodata
align 8
dtype_scalar_align_table:
    db 0        ; 0x000 DTYPE_NONE

    ; integer signed
    db 1        ; INT1    (sub-byte, packed in byte)
    db 1        ; INT2
    db 1        ; INT4
    db 1        ; INT8
    db 2        ; INT16
    db 4        ; INT32
    db 8        ; INT64
    db 16       ; INT128  (two qwords)
    db 32       ; INT256  (four qwords)

    times 6 db 0  ; padding

    ; integer unsigned
    db 1        ; UINT4
    db 1        ; UINT8
    db 2        ; UINT16
    db 4        ; UINT32
    db 8        ; UINT64
    db 16       ; UINT128
    db 32       ; UINT256
    db 64       ; UINT512
    db 64       ; UINT1024   (use cache-line align)
    db 64       ; UINT2048

    times 6 db 0  ; padding

    ; IEEE float
    db 1        ; FP8_E4M3
    db 1        ; FP8_E5M2
    db 2        ; FP16
    db 2        ; BF16
    db 4        ; TF32       (stored as 32-bit)
    db 4        ; FP32
    db 8        ; FP64
    db 16       ; FP128

    ; FP8 variants
    db 1        ; FP8_E4M3_FNUZ
    db 1        ; FP8_E5M2_FNUZ
    db 1        ; BFLOAT8
    db 1        ; MINIFLOAT

    ; FP6 scalar
    db 1        ; FP6_E2M3   (sub-byte, packed)
    db 1        ; FP6_E3M2

    times 2 db 0  ; padding

    ; OCP MX
    db 1        ; MXFP8_E4M3   (element only, block has own alignment)
    db 1        ; MXFP8_E5M2
    db 1        ; MXFP6_E2M3
    db 1        ; MXFP6_E3M2
    db 1        ; MXFP4_E2M1
    db 1        ; MXINT8
    db 1        ; MXINT6
    db 1        ; MXINT4
    db 1        ; UE8M0
    db 1        ; NVFP4
    db 1        ; NVINT4
    db 1        ; NVFP8

    times 4 db 0  ; padding

    ; fixed point
    db 1        ; Q4_0
    db 1        ; Q4_1
    db 1        ; Q5_0
    db 1        ; Q5_1
    db 1        ; Q8_0
    db 8        ; BIT_PACKED   (align to qword for bit ops)
    db 8        ; DELTA_ENC

    times 9 db 0  ; padding

    ; normalized
    db 1        ; UNORM8
    db 2        ; UNORM16
    db 1        ; SNORM8
    db 2        ; SNORM16
    db 4        ; PROB32
    db 4        ; LOG_PROB32
    db 4        ; FUZZY

    times 9 db 0  ; padding

    ; complex (align to element size)
    db 2        ; CI8    (2 bytes)
    db 4        ; CI16
    db 8        ; CI32
    db 4        ; CF16
    db 4        ; CBF16
    db 8        ; CF32
    db 16       ; CF64
    db 32       ; CF128
    db 16       ; CI64

    times 7 db 0  ; padding

    ; packed SIMD (align to container size)
    db 1        ; PACK_INT4x2   (1 byte)
    db 4        ; PACK_INT4x8   (4 bytes)
    db 8        ; PACK_INT4x16  (8 bytes)
    db 2        ; PACK_FP8x2    (2 bytes)
    db 4        ; PACK_FP8x4    (4 bytes)
    db 4        ; PACK_BF16x2   (4 bytes)
    db 4        ; PACK_INT8x4   (4 bytes)
    db 4        ; PACK_INT16x2  (4 bytes)

    times 8 db 0  ; padding

    ; Galois fields
    db 4        ; GF2           (use u32)
    db 8        ; GFP           (use u64)
    db 8        ; GF2N
    db 16       ; GF2_128
    db 32       ; GF2_256
    db 8        ; GF2_POLY
    db 8        ; GFQ_ELEM
    db 4        ; ZMOD
    db 8        ; MONTGOMERY
    db 8        ; BARRETT
    db 8        ; SCALAR_FIELD
    db 8        ; BASE_FIELD

    times 4 db 0  ; padding

    ; PQ crypto (variable, use 64-byte alignment)
    times 9 db 64

    times 7 db 0  ; padding

    ; coding theory
    db 1        ; RS_SYMBOL
    db 1        ; BCH_WORD
    db 1        ; LDPC_BIT
    db 4        ; LLR
    db 1        ; POLAR_BIT
    db 1        ; TURBO_SYMBOL
    db 4        ; VITERBI_STATE
    db 1        ; HAMMING_WORD

    times 8 db 0  ; padding

    ; arbitrary precision (variable, use 8-byte alignment)
    times 8 db 8

    times 8 db 0  ; padding

    ; alternative
    db 1        ; POSIT8
    db 2        ; POSIT16
    db 4        ; POSIT32
    db 8        ; POSIT64
    db 16       ; POSIT128
    db 32       ; POSIT256
    db 8        ; UNUM1    (variable, use 8)
    db 8        ; UNUM2
    db 8        ; VALID
    db 1        ; LNS8
    db 2        ; LNS16
    db 4        ; LNS32
    db 8        ; DBNS     (variable)
    db 4        ; STOCHASTIC

    times 2 db 0  ; padding

    ; interval / differential
    db 8        ; INTERVAL_F32   (2×f32)
    db 16       ; INTERVAL_F64   (2×f64)
    db 8        ; INTERVAL_INT   (2×i32)
    db 8        ; DUAL           (2×f32)
    db 16       ; HYPERDUAL      (4×f32)
    db 8        ; MULTIDUAL      (variable)
    db 4        ; TROPICAL_INT
    db 4        ; TROPICAL_FLOAT

    times 8 db 0  ; padding

    ; geometric
    db 16       ; QUAT_F32   (4×f32)
    db 32       ; QUAT_F64   (4×f64)
    db 32       ; DUAL_QUAT  (8×f32)
    db 64       ; OCTONION   (8×f64)
    db 64       ; SEDENION   (16×f64)
    db 8        ; BIVECTOR   (variable)
    db 8        ; TRIVECTOR
    db 8        ; MULTIVEC
    db 8        ; ROTOR
    db 8        ; SPINOR
    db 8        ; VERSOR
    db 8        ; TANGENT
    db 8        ; COTANGENT
    db 8        ; FORM_1
    db 8        ; FORM_2
    db 8        ; FORM_3

    ; sparse
    db 4        ; CSR_VAL
    db 4        ; CSR_IDX
    db 4        ; CSC_VAL
    db 4        ; CSC_IDX
    db 4        ; COO_VAL
    db 4        ; COO_ROW
    db 4        ; COO_COL
    db 4        ; BSR_VAL
    db 4        ; ELL_VAL
    db 4        ; DIA_VAL
    db 4        ; SPARSE_VAL
    db 4        ; SPARSE_IDX

    times 4 db 0  ; padding

    ; GGUF (variable, use 64-byte alignment)
    times 13 db 64

    times 3 db 0  ; padding

    ; quantum
    db 16       ; QBIT
    db 64       ; DENSITY  (variable, use 64)
    db 64       ; KET      (variable)

    times 13 db 0  ; padding

    ; graphics
    db 4        ; RGB8       (pad to 4 in practice)
    db 4        ; RGBA8
    db 8        ; RGB16F     (pad to 8)
    db 8        ; RGBA16F
    db 4        ; R11G11B10F
    db 4        ; RGB9E5
    db 2        ; DEPTH16
    db 4        ; DEPTH32F
    db 4        ; DEPTH24S8
    db 8        ; HALF4
    db 4        ; BYTE4
    db 4        ; HALF2

    times 4 db 0  ; padding

    ; audio/signal
    db 1        ; PCM8
    db 2        ; PCM16
    db 4        ; PCM24  (stored in 32-bit)
    db 4        ; PCM32
    db 4        ; FLOAT_AUDIO
    db 1        ; ULAW
    db 1        ; ALAW
    db 8        ; TIMESTAMP
    db 8        ; FREQUENCY
    db 8        ; PHASE

    times 6 db 0  ; padding

    ; abstract (variable, use 8)
    times 15 db 8

    db 0        ; padding

    ; compressed (variable, use 64)
    times 4 db 64

dtype_scalar_align_table_end:

section .text

; -----------------------------------------------------------------------------
; umath_dtype_align_scalar - scalar alignment in bytes
; args:    edi = dtype_id
; returns: eax = alignment in bytes (power of 2, minimum 1)
; -----------------------------------------------------------------------------
global umath_dtype_align_scalar
umath_dtype_align_scalar:
    cmp     edi, (dtype_scalar_align_table_end - dtype_scalar_align_table)
    jae     .default
    lea     rax, [rel dtype_scalar_align_table]
    movzx   eax, byte [rax + rdi]
    test    eax, eax
    jz      .default
    ret
.default:
    mov     eax, 8          ; safe default for unknown types
    ret

; -----------------------------------------------------------------------------
; umath_dtype_align_xmm - XMM alignment (16 bytes for SIMD loads)
; args:    edi = dtype_id
; returns: eax = 16 (always, XMM requires 16-byte alignment)
; -----------------------------------------------------------------------------
global umath_dtype_align_xmm
umath_dtype_align_xmm:
    mov     eax, 16
    ret

; -----------------------------------------------------------------------------
; umath_dtype_align_ymm - YMM alignment (32 bytes for AVX loads)
; args:    edi = dtype_id
; returns: eax = 32 (always, YMM requires 32-byte alignment)
; -----------------------------------------------------------------------------
global umath_dtype_align_ymm
umath_dtype_align_ymm:
    mov     eax, 32
    ret

; -----------------------------------------------------------------------------
; umath_dtype_align_zmm - ZMM alignment (64 bytes for AVX-512 loads)
; args:    edi = dtype_id
; returns: eax = 64 (always, ZMM requires 64-byte alignment)
; -----------------------------------------------------------------------------
global umath_dtype_align_zmm
umath_dtype_align_zmm:
    mov     eax, 64
    ret

; -----------------------------------------------------------------------------
; umath_dtype_align_cache - cache line alignment (64 bytes)
; args:    edi = dtype_id
; returns: eax = 64 (always, cache line is 64 bytes on x86-64)
; -----------------------------------------------------------------------------
global umath_dtype_align_cache
umath_dtype_align_cache:
    mov     eax, 64
    ret

; -----------------------------------------------------------------------------
; umath_dtype_align_for_simd - alignment for given SIMD width in bits
; args:    edi = dtype_id
;          esi = simd_width_bits (128, 256, or 512)
; returns: eax = alignment in bytes
; -----------------------------------------------------------------------------
global umath_dtype_align_for_simd
umath_dtype_align_for_simd:
    cmp     esi, 512
    je      .zmm
    cmp     esi, 256
    je      .ymm
    cmp     esi, 128
    je      .xmm
    ; default: scalar
    call    umath_dtype_align_scalar
    ret
.zmm:
    mov     eax, 64
    ret
.ymm:
    mov     eax, 32
    ret
.xmm:
    mov     eax, 16
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_aligned - check if pointer is aligned for dtype scalar
; args:    rdi = pointer
;          esi = dtype_id
; returns: eax = 1 if aligned, 0 if not
; -----------------------------------------------------------------------------
global umath_dtype_is_aligned
umath_dtype_is_aligned:
    push    rbx
    mov     rbx, rdi                ; save pointer
    mov     edi, esi                ; dtype_id
    call    umath_dtype_align_scalar
    ; check: ptr & (align - 1) == 0
    dec     eax                     ; align - 1
    and     rbx, rax                ; ptr & (align-1)
    setz    al
    movzx   eax, al
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_align_up - align pointer up to dtype scalar alignment
; args:    rdi = pointer
;          esi = dtype_id
; returns: rax = aligned pointer (>= input)
; -----------------------------------------------------------------------------
global umath_dtype_align_up
umath_dtype_align_up:
    push    rbx
    mov     rbx, rdi                ; save pointer
    mov     edi, esi                ; dtype_id
    call    umath_dtype_align_scalar
    ; align_up(ptr, align) = (ptr + align - 1) & ~(align - 1)
    mov     rcx, rax                ; align
    dec     rcx                     ; align - 1
    add     rbx, rcx                ; ptr + align - 1
    not     rcx                     ; ~(align - 1)
    and     rax, rbx                ; result = (ptr + align - 1) & ~(align-1)
    mov     rax, rbx
    and     rax, rcx
    pop     rbx
    ret