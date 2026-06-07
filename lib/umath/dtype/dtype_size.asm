; =============================================================================
; umath - unified math library
; dtype/dtype_size.asm - dtype size queries
; =============================================================================
; dependencies:
;   dtype_id.asm
;
; functions:
;   umath_dtype_size_bits      (dtype_id → u32) size in bits
;   umath_dtype_size_bytes     (dtype_id → u32) size in bytes (rounded up)
;   umath_dtype_size_bytes_exact(dtype_id → u32) exact bytes (0 if sub-byte)
;   umath_dtype_size_packed    (dtype_id, count → u32) bytes for N elements
;   umath_dtype_elems_per_byte (dtype_id → u32) elements per byte (sub-byte)
;   umath_dtype_elems_per_word (dtype_id → u32) elements per u32
;   umath_dtype_elems_per_qword(dtype_id → u32) elements per u64
;   umath_dtype_elems_per_zmm  (dtype_id → u32) elements per ZMM (512-bit)
;   umath_dtype_elems_per_ymm  (dtype_id → u32) elements per YMM (256-bit)
;   umath_dtype_elems_per_xmm  (dtype_id → u32) elements per XMM (128-bit)
;
; note on sub-byte types:
;   umath_dtype_size_bits  → returns actual bit count (1, 2, 4, 6)
;   umath_dtype_size_bytes → returns 1 (minimum addressable unit)
;   umath_dtype_size_bytes_exact → returns 0 to signal sub-byte
;   umath_dtype_elems_per_byte → returns how many fit in one byte
; =============================================================================

%include "dtype_id.asm"

bits 64

; =============================================================================
; size in bits table (u16 per entry)
; indexed by dtype_id
; =============================================================================

section .rodata
align 8
dtype_size_bits_table:
    dw 0        ; 0x000 DTYPE_NONE

    ; integer signed
    dw 1        ; INT1
    dw 2        ; INT2
    dw 4        ; INT4
    dw 8        ; INT8
    dw 16       ; INT16
    dw 32       ; INT32
    dw 64       ; INT64
    dw 128      ; INT128
    dw 256      ; INT256

    times 6 dw 0  ; 0x00A-0x00F padding

    ; integer unsigned
    dw 4        ; UINT4
    dw 8        ; UINT8
    dw 16       ; UINT16
    dw 32       ; UINT32
    dw 64       ; UINT64
    dw 128      ; UINT128
    dw 256      ; UINT256
    dw 512      ; UINT512
    dw 1024     ; UINT1024
    dw 2048     ; UINT2048

    times 6 dw 0  ; 0x01A-0x01F padding

    ; IEEE float
    dw 8        ; FP8_E4M3
    dw 8        ; FP8_E5M2
    dw 16       ; FP16
    dw 16       ; BF16
    dw 19       ; TF32 (stored in 32-bit, 19 significant bits)
    dw 32       ; FP32
    dw 64       ; FP64
    dw 128      ; FP128

    ; FP8 variants
    dw 8        ; FP8_E4M3_FNUZ
    dw 8        ; FP8_E5M2_FNUZ
    dw 8        ; BFLOAT8
    dw 8        ; MINIFLOAT

    ; FP6 scalar
    dw 6        ; FP6_E2M3
    dw 6        ; FP6_E3M2

    times 2 dw 0  ; padding

    ; OCP MX
    dw 8        ; MXFP8_E4M3
    dw 8        ; MXFP8_E5M2
    dw 6        ; MXFP6_E2M3
    dw 6        ; MXFP6_E3M2
    dw 4        ; MXFP4_E2M1
    dw 8        ; MXINT8
    dw 6        ; MXINT6
    dw 4        ; MXINT4
    dw 8        ; UE8M0
    dw 4        ; NVFP4
    dw 4        ; NVINT4
    dw 8        ; NVFP8

    times 4 dw 0  ; padding

    ; fixed point
    dw 4        ; Q4_0
    dw 4        ; Q4_1
    dw 5        ; Q5_0
    dw 5        ; Q5_1
    dw 8        ; Q8_0
    dw 0        ; BIT_PACKED  (variable)
    dw 0        ; DELTA_ENC   (variable)

    times 9 dw 0  ; padding

    ; normalized
    dw 8        ; UNORM8
    dw 16       ; UNORM16
    dw 8        ; SNORM8
    dw 16       ; SNORM16
    dw 32       ; PROB32
    dw 32       ; LOG_PROB32
    dw 32       ; FUZZY

    times 9 dw 0  ; padding

    ; complex (element size × 2)
    dw 16       ; CI8    (8+8)
    dw 32       ; CI16   (16+16)
    dw 64       ; CI32   (32+32)
    dw 32       ; CF16   (16+16)
    dw 32       ; CBF16  (16+16)
    dw 64       ; CF32   (32+32)
    dw 128      ; CF64   (64+64)
    dw 256      ; CF128  (128+128)
    dw 128      ; CI64   (64+64)

    times 7 dw 0  ; padding

    ; packed SIMD
    dw 8        ; PACK_INT4x2   (2×4=8)
    dw 32       ; PACK_INT4x8   (8×4=32)
    dw 64       ; PACK_INT4x16  (16×4=64)
    dw 16       ; PACK_FP8x2    (2×8=16)
    dw 32       ; PACK_FP8x4    (4×8=32)
    dw 32       ; PACK_BF16x2   (2×16=32)
    dw 32       ; PACK_INT8x4   (4×8=32)
    dw 32       ; PACK_INT16x2  (2×16=32)

    times 8 dw 0  ; padding

    ; Galois fields (variable, return 0)
    times 12 dw 0

    times 4 dw 0  ; padding

    ; PQ crypto (variable)
    times 9 dw 0

    times 7 dw 0  ; padding

    ; coding theory (variable)
    times 8 dw 0

    times 8 dw 0  ; padding

    ; arbitrary precision (variable = 0)
    times 8 dw 0

    times 8 dw 0  ; padding

    ; alternative
    dw 8        ; POSIT8
    dw 16       ; POSIT16
    dw 32       ; POSIT32
    dw 64       ; POSIT64
    dw 128      ; POSIT128
    dw 256      ; POSIT256
    dw 0        ; UNUM1    (variable)
    dw 0        ; UNUM2    (variable)
    dw 0        ; VALID    (variable)
    dw 8        ; LNS8
    dw 16       ; LNS16
    dw 32       ; LNS32
    dw 0        ; DBNS     (variable)
    dw 32       ; STOCHASTIC

    times 2 dw 0  ; padding

    ; interval / differential
    dw 64       ; INTERVAL_F32  (lo:f32 + hi:f32)
    dw 128      ; INTERVAL_F64  (lo:f64 + hi:f64)
    dw 64       ; INTERVAL_INT  (lo:i32 + hi:i32)
    dw 64       ; DUAL          (val:f32 + eps:f32)
    dw 128      ; HYPERDUAL     (4×f32)
    dw 0        ; MULTIDUAL     (variable)
    dw 32       ; TROPICAL_INT
    dw 32       ; TROPICAL_FLOAT

    times 8 dw 0  ; padding

    ; geometric
    dw 128      ; QUAT_F32   (4×32)
    dw 256      ; QUAT_F64   (4×64)
    dw 256      ; DUAL_QUAT  (8×32)
    dw 512      ; OCTONION   (8×64)
    dw 1024     ; SEDENION   (16×64)
    dw 0        ; BIVECTOR   (variable)
    dw 0        ; TRIVECTOR  (variable)
    dw 0        ; MULTIVEC   (variable)
    dw 0        ; ROTOR      (variable)
    dw 0        ; SPINOR     (variable)
    dw 0        ; VERSOR     (variable)
    dw 0        ; TANGENT    (variable)
    dw 0        ; COTANGENT  (variable)
    dw 0        ; FORM_1     (variable)
    dw 0        ; FORM_2     (variable)
    dw 0        ; FORM_3     (variable)

    ; sparse (variable = 0)
    times 12 dw 0

    times 4 dw 0  ; padding

    ; GGUF (variable = 0)
    times 13 dw 0

    times 3 dw 0  ; padding

    ; quantum (variable)
    dw 128      ; QBIT    (2×CF64 simplified to 128-bit)
    dw 0        ; DENSITY (variable NxN)
    dw 0        ; KET     (variable)

    times 13 dw 0  ; padding

    ; graphics
    dw 24       ; RGB8
    dw 32       ; RGBA8
    dw 48       ; RGB16F
    dw 64       ; RGBA16F
    dw 32       ; R11G11B10F
    dw 32       ; RGB9E5
    dw 16       ; DEPTH16
    dw 32       ; DEPTH32F
    dw 32       ; DEPTH24S8
    dw 64       ; HALF4
    dw 32       ; BYTE4
    dw 32       ; HALF2

    times 4 dw 0  ; padding

    ; audio/signal
    dw 8        ; PCM8
    dw 16       ; PCM16
    dw 24       ; PCM24
    dw 32       ; PCM32
    dw 32       ; FLOAT_AUDIO
    dw 8        ; ULAW
    dw 8        ; ALAW
    dw 64       ; TIMESTAMP
    dw 64       ; FREQUENCY
    dw 64       ; PHASE

    times 6 dw 0  ; padding

    ; abstract (variable = 0)
    times 15 dw 0

    dw 0        ; padding

    ; compressed (variable = 0)
    times 4 dw 0

dtype_size_bits_table_end:

section .text

; -----------------------------------------------------------------------------
; umath_dtype_size_bits - get dtype size in bits
; args:    edi = dtype_id
; returns: eax = size in bits (0 if variable/unknown)
; -----------------------------------------------------------------------------
global umath_dtype_size_bits
umath_dtype_size_bits:
    cmp     edi, (dtype_size_bits_table_end - dtype_size_bits_table) / 2
    jae     .unknown
    lea     rax, [rel dtype_size_bits_table]
    movzx   eax, word [rax + rdi*2]
    ret
.unknown:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_size_bytes - get dtype size in bytes (rounded up to minimum 1)
; args:    edi = dtype_id
; returns: eax = size in bytes
;          returns 1 for sub-byte types (INT1, INT2, INT4, FP6 etc)
;          returns 0 for variable-size types
; -----------------------------------------------------------------------------
global umath_dtype_size_bytes
umath_dtype_size_bytes:
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .variable
    ; round up: bytes = (bits + 7) / 8
    add     eax, 7
    shr     eax, 3
    ; minimum 1 byte
    cmp     eax, 0
    jne     .done
    mov     eax, 1
.done:
    ret
.variable:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_size_bytes_exact - get exact bytes (0 if sub-byte)
; args:    edi = dtype_id
; returns: eax = size in bytes, 0 if sub-byte or variable
; -----------------------------------------------------------------------------
global umath_dtype_size_bytes_exact
umath_dtype_size_bytes_exact:
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .zero
    cmp     eax, 8
    jl      .zero           ; sub-byte → return 0
    ; divide by 8
    shr     eax, 3
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_elems_per_byte - how many elements fit in one byte
; args:    edi = dtype_id
; returns: eax = count (1 for byte-aligned, 2+ for sub-byte, 0 if over 1 byte)
; -----------------------------------------------------------------------------
global umath_dtype_elems_per_byte
umath_dtype_elems_per_byte:
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .zero
    cmp     eax, 8
    jg      .zero           ; larger than byte → 0
    ; elems = 8 / bits
    mov     ecx, eax
    mov     eax, 8
    xor     edx, edx
    div     ecx
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_elems_per_word - elements per u32 (32-bit word)
; args:    edi = dtype_id
; returns: eax = count (0 if larger than 32 bits or variable)
; -----------------------------------------------------------------------------
global umath_dtype_elems_per_word
umath_dtype_elems_per_word:
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .zero
    cmp     eax, 32
    jg      .zero
    mov     ecx, eax
    mov     eax, 32
    xor     edx, edx
    div     ecx
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_elems_per_qword - elements per u64 (64-bit qword)
; args:    edi = dtype_id
; returns: eax = count (0 if larger than 64 bits or variable)
; -----------------------------------------------------------------------------
global umath_dtype_elems_per_qword
umath_dtype_elems_per_qword:
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .zero
    cmp     eax, 64
    jg      .zero
    mov     ecx, eax
    mov     eax, 64
    xor     edx, edx
    div     ecx
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_elems_per_xmm - elements per XMM register (128-bit)
; args:    edi = dtype_id
; returns: eax = count (0 if larger than 128 bits or variable)
; -----------------------------------------------------------------------------
global umath_dtype_elems_per_xmm
umath_dtype_elems_per_xmm:
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .zero
    cmp     eax, 128
    jg      .zero
    mov     ecx, eax
    mov     eax, 128
    xor     edx, edx
    div     ecx
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_elems_per_ymm - elements per YMM register (256-bit)
; args:    edi = dtype_id
; returns: eax = count (0 if larger than 256 bits or variable)
; -----------------------------------------------------------------------------
global umath_dtype_elems_per_ymm
umath_dtype_elems_per_ymm:
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .zero
    cmp     eax, 256
    jg      .zero
    mov     ecx, eax
    mov     eax, 256
    xor     edx, edx
    div     ecx
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_elems_per_zmm - elements per ZMM register (512-bit / AVX-512)
; args:    edi = dtype_id
; returns: eax = count (0 if larger than 512 bits or variable)
; example: FP32 → 16, FP64 → 8, INT8 → 64, FP16 → 32, INT4 → 128
; -----------------------------------------------------------------------------
global umath_dtype_elems_per_zmm
umath_dtype_elems_per_zmm:
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .zero
    cmp     eax, 512
    jg      .zero
    mov     ecx, eax
    mov     eax, 512
    xor     edx, edx
    div     ecx
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_size_packed - total bytes for N elements
; args:    edi = dtype_id
;          esi = count (number of elements)
; returns: rax = total bytes (rounded up)
;          0 if variable size dtype
; -----------------------------------------------------------------------------
global umath_dtype_size_packed
umath_dtype_size_packed:
    push    rbx
    mov     ebx, esi                ; save count
    call    umath_dtype_size_bits
    test    eax, eax
    jz      .variable
    ; total_bits = size_bits * count
    imul    rax, rbx
    ; round up to bytes: (total_bits + 7) / 8
    add     rax, 7
    shr     rax, 3
    pop     rbx
    ret
.variable:
    xor     eax, eax
    pop     rbx
    ret