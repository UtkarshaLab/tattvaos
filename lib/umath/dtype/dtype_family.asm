; =============================================================================
; umath - unified math library
; dtype/dtype_family.asm - dtype family classification
; =============================================================================
; dependencies:
;   dtype_id.asm
;
; functions:
;   umath_dtype_get_family    (dtype_id → family_id)
;   umath_dtype_is_integer    (dtype_id → bool)
;   umath_dtype_is_float      (dtype_id → bool)
;   umath_dtype_is_complex    (dtype_id → bool)
;   umath_dtype_is_packed     (dtype_id → bool)
;   umath_dtype_is_signed     (dtype_id → bool)
;   umath_dtype_is_unsigned   (dtype_id → bool)
;   umath_dtype_is_sparse     (dtype_id → bool)
;   umath_dtype_is_geometric  (dtype_id → bool)
;   umath_dtype_is_abstract   (dtype_id → bool)
;   umath_dtype_is_valid_id   (dtype_id → bool)
;   umath_dtype_is_ocp_mx     (dtype_id → bool)
;   umath_dtype_is_nv_format  (dtype_id → bool)
;   umath_dtype_is_gguf       (dtype_id → bool)
;   umath_dtype_is_sub_byte   (dtype_id → bool)
;
; family IDs:
;   DFAMILY_INT_SIGNED        = 0x01
;   DFAMILY_INT_UNSIGNED      = 0x02
;   DFAMILY_FLOAT_IEEE        = 0x03
;   DFAMILY_FLOAT_OCP         = 0x04
;   DFAMILY_FLOAT_NV          = 0x05
;   DFAMILY_FIXED             = 0x06
;   DFAMILY_NORMALIZED        = 0x07
;   DFAMILY_COMPLEX           = 0x08
;   DFAMILY_PACKED            = 0x09
;   DFAMILY_GALOIS            = 0x0A
;   DFAMILY_PQ_CRYPTO         = 0x0B
;   DFAMILY_CODING            = 0x0C
;   DFAMILY_BIGNUM            = 0x0D
;   DFAMILY_ALTERNATIVE       = 0x0E
;   DFAMILY_INTERVAL          = 0x0F
;   DFAMILY_GEOMETRIC         = 0x10
;   DFAMILY_SPARSE            = 0x11
;   DFAMILY_GGUF              = 0x12
;   DFAMILY_QUANTUM           = 0x13
;   DFAMILY_GRAPHICS          = 0x14
;   DFAMILY_AUDIO             = 0x15
;   DFAMILY_ABSTRACT          = 0x16
;   DFAMILY_COMPRESSED        = 0x17
;   DFAMILY_USER              = 0x18
;   DFAMILY_UNKNOWN           = 0xFF
; =============================================================================

%include "dtype_id.asm"

bits 64
section .text

; =============================================================================
; family ID constants
; =============================================================================

DFAMILY_INT_SIGNED      equ 0x01
DFAMILY_INT_UNSIGNED    equ 0x02
DFAMILY_FLOAT_IEEE      equ 0x03
DFAMILY_FLOAT_FP8_VAR   equ 0x04
DFAMILY_FLOAT_FP6       equ 0x05
DFAMILY_FLOAT_OCP       equ 0x06
DFAMILY_FLOAT_NV        equ 0x07
DFAMILY_FIXED           equ 0x08
DFAMILY_NORMALIZED      equ 0x09
DFAMILY_COMPLEX         equ 0x0A
DFAMILY_PACKED          equ 0x0B
DFAMILY_GALOIS          equ 0x0C
DFAMILY_PQ_CRYPTO       equ 0x0D
DFAMILY_CODING          equ 0x0E
DFAMILY_BIGNUM          equ 0x0F
DFAMILY_ALTERNATIVE     equ 0x10
DFAMILY_INTERVAL        equ 0x11
DFAMILY_GEOMETRIC       equ 0x12
DFAMILY_SPARSE          equ 0x13
DFAMILY_GGUF            equ 0x14
DFAMILY_QUANTUM         equ 0x15
DFAMILY_GRAPHICS        equ 0x16
DFAMILY_AUDIO           equ 0x17
DFAMILY_ABSTRACT        equ 0x18
DFAMILY_COMPRESSED      equ 0x19
DFAMILY_USER            equ 0x1A
DFAMILY_UNKNOWN         equ 0xFF

; =============================================================================
; family lookup table
; indexed by dtype_id (0x000–0x153 defined range)
; entries beyond table = DFAMILY_UNKNOWN
; =============================================================================

section .rodata
align 8
dtype_family_table:
    ; 0x000 DTYPE_NONE
    db DFAMILY_UNKNOWN

    ; 0x001–0x009 integer signed
    db DFAMILY_INT_SIGNED       ; INT1
    db DFAMILY_INT_SIGNED       ; INT2
    db DFAMILY_INT_SIGNED       ; INT4
    db DFAMILY_INT_SIGNED       ; INT8
    db DFAMILY_INT_SIGNED       ; INT16
    db DFAMILY_INT_SIGNED       ; INT32
    db DFAMILY_INT_SIGNED       ; INT64
    db DFAMILY_INT_SIGNED       ; INT128
    db DFAMILY_INT_SIGNED       ; INT256

    ; 0x00A–0x00F padding
    times 6 db DFAMILY_UNKNOWN

    ; 0x010–0x019 integer unsigned
    db DFAMILY_INT_UNSIGNED     ; UINT4
    db DFAMILY_INT_UNSIGNED     ; UINT8
    db DFAMILY_INT_UNSIGNED     ; UINT16
    db DFAMILY_INT_UNSIGNED     ; UINT32
    db DFAMILY_INT_UNSIGNED     ; UINT64
    db DFAMILY_INT_UNSIGNED     ; UINT128
    db DFAMILY_INT_UNSIGNED     ; UINT256
    db DFAMILY_INT_UNSIGNED     ; UINT512
    db DFAMILY_INT_UNSIGNED     ; UINT1024
    db DFAMILY_INT_UNSIGNED     ; UINT2048

    ; 0x01A–0x01F padding
    times 6 db DFAMILY_UNKNOWN

    ; 0x020–0x027 IEEE float
    db DFAMILY_FLOAT_IEEE       ; FP8_E4M3
    db DFAMILY_FLOAT_IEEE       ; FP8_E5M2
    db DFAMILY_FLOAT_IEEE       ; FP16
    db DFAMILY_FLOAT_IEEE       ; BF16
    db DFAMILY_FLOAT_IEEE       ; TF32
    db DFAMILY_FLOAT_IEEE       ; FP32
    db DFAMILY_FLOAT_IEEE       ; FP64
    db DFAMILY_FLOAT_IEEE       ; FP128

    ; 0x028–0x02B FP8 variants
    db DFAMILY_FLOAT_FP8_VAR    ; FP8_E4M3_FNUZ
    db DFAMILY_FLOAT_FP8_VAR    ; FP8_E5M2_FNUZ
    db DFAMILY_FLOAT_FP8_VAR    ; BFLOAT8
    db DFAMILY_FLOAT_FP8_VAR    ; MINIFLOAT

    ; 0x02C–0x02D FP6 scalar
    db DFAMILY_FLOAT_FP6        ; FP6_E2M3
    db DFAMILY_FLOAT_FP6        ; FP6_E3M2

    ; 0x02E–0x02F padding
    times 2 db DFAMILY_UNKNOWN

    ; 0x030–0x03B OCP MX + NVIDIA
    db DFAMILY_FLOAT_OCP        ; MXFP8_E4M3
    db DFAMILY_FLOAT_OCP        ; MXFP8_E5M2
    db DFAMILY_FLOAT_OCP        ; MXFP6_E2M3
    db DFAMILY_FLOAT_OCP        ; MXFP6_E3M2
    db DFAMILY_FLOAT_OCP        ; MXFP4_E2M1
    db DFAMILY_FLOAT_OCP        ; MXINT8
    db DFAMILY_FLOAT_OCP        ; MXINT6
    db DFAMILY_FLOAT_OCP        ; MXINT4
    db DFAMILY_FLOAT_OCP        ; UE8M0
    db DFAMILY_FLOAT_NV         ; NVFP4
    db DFAMILY_FLOAT_NV         ; NVINT4
    db DFAMILY_FLOAT_NV         ; NVFP8

    ; 0x03C–0x03F padding
    times 4 db DFAMILY_UNKNOWN

    ; 0x040–0x046 fixed point
    db DFAMILY_FIXED            ; Q4_0
    db DFAMILY_FIXED            ; Q4_1
    db DFAMILY_FIXED            ; Q5_0
    db DFAMILY_FIXED            ; Q5_1
    db DFAMILY_FIXED            ; Q8_0
    db DFAMILY_FIXED            ; BIT_PACKED
    db DFAMILY_FIXED            ; DELTA_ENC

    ; 0x047–0x04F padding
    times 9 db DFAMILY_UNKNOWN

    ; 0x050–0x056 normalized
    db DFAMILY_NORMALIZED       ; UNORM8
    db DFAMILY_NORMALIZED       ; UNORM16
    db DFAMILY_NORMALIZED       ; SNORM8
    db DFAMILY_NORMALIZED       ; SNORM16
    db DFAMILY_NORMALIZED       ; PROB32
    db DFAMILY_NORMALIZED       ; LOG_PROB32
    db DFAMILY_NORMALIZED       ; FUZZY

    ; 0x057–0x05F padding
    times 9 db DFAMILY_UNKNOWN

    ; 0x060–0x068 complex
    db DFAMILY_COMPLEX          ; CI8
    db DFAMILY_COMPLEX          ; CI16
    db DFAMILY_COMPLEX          ; CI32
    db DFAMILY_COMPLEX          ; CF16
    db DFAMILY_COMPLEX          ; CBF16
    db DFAMILY_COMPLEX          ; CF32
    db DFAMILY_COMPLEX          ; CF64
    db DFAMILY_COMPLEX          ; CF128
    db DFAMILY_COMPLEX          ; CI64

    ; 0x069–0x06F padding
    times 7 db DFAMILY_UNKNOWN

    ; 0x070–0x077 packed SIMD
    db DFAMILY_PACKED           ; PACK_INT4x2
    db DFAMILY_PACKED           ; PACK_INT4x8
    db DFAMILY_PACKED           ; PACK_INT4x16
    db DFAMILY_PACKED           ; PACK_FP8x2
    db DFAMILY_PACKED           ; PACK_FP8x4
    db DFAMILY_PACKED           ; PACK_BF16x2
    db DFAMILY_PACKED           ; PACK_INT8x4
    db DFAMILY_PACKED           ; PACK_INT16x2

    ; 0x078–0x07F padding
    times 8 db DFAMILY_UNKNOWN

    ; 0x080–0x08B Galois fields
    db DFAMILY_GALOIS           ; GF2
    db DFAMILY_GALOIS           ; GFP
    db DFAMILY_GALOIS           ; GF2N
    db DFAMILY_GALOIS           ; GF2_128
    db DFAMILY_GALOIS           ; GF2_256
    db DFAMILY_GALOIS           ; GF2_POLY
    db DFAMILY_GALOIS           ; GFQ_ELEM
    db DFAMILY_GALOIS           ; ZMOD
    db DFAMILY_GALOIS           ; MONTGOMERY
    db DFAMILY_GALOIS           ; BARRETT
    db DFAMILY_GALOIS           ; SCALAR_FIELD
    db DFAMILY_GALOIS           ; BASE_FIELD

    ; 0x08C–0x08F padding
    times 4 db DFAMILY_UNKNOWN

    ; 0x090–0x098 PQ crypto
    db DFAMILY_PQ_CRYPTO        ; PROJ_COORD
    db DFAMILY_PQ_CRYPTO        ; EXT_COORD
    db DFAMILY_PQ_CRYPTO        ; JACOBIAN
    db DFAMILY_PQ_CRYPTO        ; KYBER_POLY
    db DFAMILY_PQ_CRYPTO        ; DILITH_POLY
    db DFAMILY_PQ_CRYPTO        ; NTRU_POLY
    db DFAMILY_PQ_CRYPTO        ; FALCON_POLY
    db DFAMILY_PQ_CRYPTO        ; RLWE_POLY
    db DFAMILY_PQ_CRYPTO        ; LWE_SAMPLE

    ; 0x099–0x09F padding
    times 7 db DFAMILY_UNKNOWN

    ; 0x0A0–0x0A7 coding theory
    db DFAMILY_CODING           ; RS_SYMBOL
    db DFAMILY_CODING           ; BCH_WORD
    db DFAMILY_CODING           ; LDPC_BIT
    db DFAMILY_CODING           ; LLR
    db DFAMILY_CODING           ; POLAR_BIT
    db DFAMILY_CODING           ; TURBO_SYMBOL
    db DFAMILY_CODING           ; VITERBI_STATE
    db DFAMILY_CODING           ; HAMMING_WORD

    ; 0x0A8–0x0AF padding
    times 8 db DFAMILY_UNKNOWN

    ; 0x0B0–0x0B7 arbitrary precision
    db DFAMILY_BIGNUM           ; BIGINT
    db DFAMILY_BIGNUM           ; BIGFLOAT
    db DFAMILY_BIGNUM           ; RATIONAL
    db DFAMILY_BIGNUM           ; PADIC
    db DFAMILY_BIGNUM           ; SURREAL
    db DFAMILY_BIGNUM           ; HYPERREAL
    db DFAMILY_BIGNUM           ; ORDINAL
    db DFAMILY_BIGNUM           ; CARDINAL

    ; 0x0B8–0x0BF padding
    times 8 db DFAMILY_UNKNOWN

    ; 0x0C0–0x0CD alternative number systems
    db DFAMILY_ALTERNATIVE      ; POSIT8
    db DFAMILY_ALTERNATIVE      ; POSIT16
    db DFAMILY_ALTERNATIVE      ; POSIT32
    db DFAMILY_ALTERNATIVE      ; POSIT64
    db DFAMILY_ALTERNATIVE      ; POSIT128
    db DFAMILY_ALTERNATIVE      ; POSIT256
    db DFAMILY_ALTERNATIVE      ; UNUM1
    db DFAMILY_ALTERNATIVE      ; UNUM2
    db DFAMILY_ALTERNATIVE      ; VALID
    db DFAMILY_ALTERNATIVE      ; LNS8
    db DFAMILY_ALTERNATIVE      ; LNS16
    db DFAMILY_ALTERNATIVE      ; LNS32
    db DFAMILY_ALTERNATIVE      ; DBNS
    db DFAMILY_ALTERNATIVE      ; STOCHASTIC

    ; 0x0CE–0x0CF padding
    times 2 db DFAMILY_UNKNOWN

    ; 0x0D0–0x0D7 interval / differential / tropical
    db DFAMILY_INTERVAL         ; INTERVAL_F32
    db DFAMILY_INTERVAL         ; INTERVAL_F64
    db DFAMILY_INTERVAL         ; INTERVAL_INT
    db DFAMILY_INTERVAL         ; DUAL
    db DFAMILY_INTERVAL         ; HYPERDUAL
    db DFAMILY_INTERVAL         ; MULTIDUAL
    db DFAMILY_INTERVAL         ; TROPICAL_INT
    db DFAMILY_INTERVAL         ; TROPICAL_FLOAT

    ; 0x0D8–0x0DF padding
    times 8 db DFAMILY_UNKNOWN

    ; 0x0E0–0x0EF geometric
    db DFAMILY_GEOMETRIC        ; QUAT_F32
    db DFAMILY_GEOMETRIC        ; QUAT_F64
    db DFAMILY_GEOMETRIC        ; DUAL_QUAT
    db DFAMILY_GEOMETRIC        ; OCTONION
    db DFAMILY_GEOMETRIC        ; SEDENION
    db DFAMILY_GEOMETRIC        ; BIVECTOR
    db DFAMILY_GEOMETRIC        ; TRIVECTOR
    db DFAMILY_GEOMETRIC        ; MULTIVEC
    db DFAMILY_GEOMETRIC        ; ROTOR
    db DFAMILY_GEOMETRIC        ; SPINOR
    db DFAMILY_GEOMETRIC        ; VERSOR
    db DFAMILY_GEOMETRIC        ; TANGENT
    db DFAMILY_GEOMETRIC        ; COTANGENT
    db DFAMILY_GEOMETRIC        ; FORM_1
    db DFAMILY_GEOMETRIC        ; FORM_2
    db DFAMILY_GEOMETRIC        ; FORM_3

    ; 0x0F0–0x0FB sparse
    db DFAMILY_SPARSE           ; CSR_VAL
    db DFAMILY_SPARSE           ; CSR_IDX
    db DFAMILY_SPARSE           ; CSC_VAL
    db DFAMILY_SPARSE           ; CSC_IDX
    db DFAMILY_SPARSE           ; COO_VAL
    db DFAMILY_SPARSE           ; COO_ROW
    db DFAMILY_SPARSE           ; COO_COL
    db DFAMILY_SPARSE           ; BSR_VAL
    db DFAMILY_SPARSE           ; ELL_VAL
    db DFAMILY_SPARSE           ; DIA_VAL
    db DFAMILY_SPARSE           ; SPARSE_VAL
    db DFAMILY_SPARSE           ; SPARSE_IDX

    ; 0x0FC–0x0FF padding
    times 4 db DFAMILY_UNKNOWN

    ; 0x100–0x10C GGUF
    db DFAMILY_GGUF             ; GGUF_Q2K
    db DFAMILY_GGUF             ; GGUF_Q3K
    db DFAMILY_GGUF             ; GGUF_Q4K
    db DFAMILY_GGUF             ; GGUF_Q5K
    db DFAMILY_GGUF             ; GGUF_Q6K
    db DFAMILY_GGUF             ; GGUF_Q8K
    db DFAMILY_GGUF             ; GGUF_IQ1S
    db DFAMILY_GGUF             ; GGUF_IQ2XXS
    db DFAMILY_GGUF             ; GGUF_IQ3XXS
    db DFAMILY_GGUF             ; GGUF_IQ4NL
    db DFAMILY_GGUF             ; BLOCKED_FP8
    db DFAMILY_GGUF             ; AMX_TILE
    db DFAMILY_GGUF             ; VNNI_BLOCK

    ; 0x10D–0x10F padding
    times 3 db DFAMILY_UNKNOWN

    ; 0x110–0x112 quantum
    db DFAMILY_QUANTUM          ; QBIT
    db DFAMILY_QUANTUM          ; DENSITY
    db DFAMILY_QUANTUM          ; KET

    ; 0x113–0x11F padding
    times 13 db DFAMILY_UNKNOWN

    ; 0x120–0x12B graphics
    db DFAMILY_GRAPHICS         ; RGB8
    db DFAMILY_GRAPHICS         ; RGBA8
    db DFAMILY_GRAPHICS         ; RGB16F
    db DFAMILY_GRAPHICS         ; RGBA16F
    db DFAMILY_GRAPHICS         ; R11G11B10F
    db DFAMILY_GRAPHICS         ; RGB9E5
    db DFAMILY_GRAPHICS         ; DEPTH16
    db DFAMILY_GRAPHICS         ; DEPTH32F
    db DFAMILY_GRAPHICS         ; DEPTH24S8
    db DFAMILY_GRAPHICS         ; HALF4
    db DFAMILY_GRAPHICS         ; BYTE4
    db DFAMILY_GRAPHICS         ; HALF2

    ; 0x12C–0x12F padding
    times 4 db DFAMILY_UNKNOWN

    ; 0x130–0x139 audio/signal
    db DFAMILY_AUDIO            ; PCM8
    db DFAMILY_AUDIO            ; PCM16
    db DFAMILY_AUDIO            ; PCM24
    db DFAMILY_AUDIO            ; PCM32
    db DFAMILY_AUDIO            ; FLOAT_AUDIO
    db DFAMILY_AUDIO            ; ULAW
    db DFAMILY_AUDIO            ; ALAW
    db DFAMILY_AUDIO            ; TIMESTAMP
    db DFAMILY_AUDIO            ; FREQUENCY
    db DFAMILY_AUDIO            ; PHASE

    ; 0x13A–0x13F padding
    times 6 db DFAMILY_UNKNOWN

    ; 0x140–0x14E abstract math
    db DFAMILY_ABSTRACT         ; MORPHISM
    db DFAMILY_ABSTRACT         ; FUNCTOR_VAL
    db DFAMILY_ABSTRACT         ; NAT_TRANS
    db DFAMILY_ABSTRACT         ; MEASURE
    db DFAMILY_ABSTRACT         ; SIGNED_MEAS
    db DFAMILY_ABSTRACT         ; PROB_MEAS
    db DFAMILY_ABSTRACT         ; UTILITY
    db DFAMILY_ABSTRACT         ; STRATEGY
    db DFAMILY_ABSTRACT         ; PAYOFF
    db DFAMILY_ABSTRACT         ; SAMPLE_PATH
    db DFAMILY_ABSTRACT         ; TRANSITION
    db DFAMILY_ABSTRACT         ; GENERATOR
    db DFAMILY_ABSTRACT         ; TYPE_IDX
    db DFAMILY_ABSTRACT         ; UNIVERSE
    db DFAMILY_ABSTRACT         ; IDENTITY

    ; 0x14F padding
    db DFAMILY_UNKNOWN

    ; 0x150–0x153 compressed
    db DFAMILY_COMPRESSED       ; RLE_BLOCK
    db DFAMILY_COMPRESSED       ; ZSTD_BLOCK
    db DFAMILY_COMPRESSED       ; DICT_ENC
    db DFAMILY_COMPRESSED       ; BIT_PACKED_BLK

dtype_family_table_end:
DTYPE_FAMILY_TABLE_SIZE equ dtype_family_table_end - dtype_family_table

section .text

; -----------------------------------------------------------------------------
; umath_dtype_is_valid_id - check if dtype_id is in valid range
; args:    edi = dtype_id
; returns: eax = 1 if valid, 0 if not
; -----------------------------------------------------------------------------
global umath_dtype_is_valid_id
umath_dtype_is_valid_id:
    cmp     edi, DTYPE_MAX
    jae     .invalid
    cmp     edi, DTYPE_NONE
    je      .invalid
    mov     eax, 1
    ret
.invalid:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_get_family - get family of dtype
; args:    edi = dtype_id
; returns: eax = family_id (DFAMILY_UNKNOWN if invalid or unknown)
; -----------------------------------------------------------------------------
global umath_dtype_get_family
umath_dtype_get_family:
    ; check user-defined range
    cmp     edi, DTYPE_USER_BASE
    jae     .user_range
    ; check table bounds
    cmp     edi, DTYPE_FAMILY_TABLE_SIZE
    jae     .out_of_table
    ; table lookup
    lea     rax, [rel dtype_family_table]
    movzx   eax, byte [rax + rdi]
    ret
.user_range:
    cmp     edi, DTYPE_UNKNOWN
    jae     .unknown
    mov     eax, DFAMILY_USER
    ret
.out_of_table:
.unknown:
    mov     eax, DFAMILY_UNKNOWN
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_integer - check if dtype is any integer type
; args:    edi = dtype_id
; returns: eax = 1 if integer (signed or unsigned), 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_integer
umath_dtype_is_integer:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_INT_SIGNED
    je      .yes
    cmp     eax, DFAMILY_INT_UNSIGNED
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_signed - check if dtype is signed
; args:    edi = dtype_id
; returns: eax = 1 if signed, 0 if unsigned or non-integer
; -----------------------------------------------------------------------------
global umath_dtype_is_signed
umath_dtype_is_signed:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_INT_SIGNED
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_unsigned - check if dtype is unsigned integer
; args:    edi = dtype_id
; returns: eax = 1 if unsigned integer, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_unsigned
umath_dtype_is_unsigned:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_INT_UNSIGNED
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_float - check if dtype is any floating point type
; args:    edi = dtype_id
; returns: eax = 1 if float, 0 otherwise
; note:    includes IEEE, FP8 variants, FP6, OCP MX, NV formats
; -----------------------------------------------------------------------------
global umath_dtype_is_float
umath_dtype_is_float:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_FLOAT_IEEE
    je      .yes
    cmp     eax, DFAMILY_FLOAT_FP8_VAR
    je      .yes
    cmp     eax, DFAMILY_FLOAT_FP6
    je      .yes
    cmp     eax, DFAMILY_FLOAT_OCP
    je      .yes
    cmp     eax, DFAMILY_FLOAT_NV
    je      .yes
    cmp     eax, DFAMILY_ALTERNATIVE    ; posit, LNS, unum
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_complex - check if dtype is complex type
; args:    edi = dtype_id
; returns: eax = 1 if complex, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_complex
umath_dtype_is_complex:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_COMPLEX
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_packed - check if dtype is packed SIMD type
; args:    edi = dtype_id
; returns: eax = 1 if packed, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_packed
umath_dtype_is_packed:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_PACKED
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_sparse - check if dtype is sparse format type
; args:    edi = dtype_id
; returns: eax = 1 if sparse, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_sparse
umath_dtype_is_sparse:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_SPARSE
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_geometric - check if dtype is geometric type
; args:    edi = dtype_id
; returns: eax = 1 if geometric, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_geometric
umath_dtype_is_geometric:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_GEOMETRIC
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_abstract - check if dtype is abstract math type
; args:    edi = dtype_id
; returns: eax = 1 if abstract, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_abstract
umath_dtype_is_abstract:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_ABSTRACT
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_ocp_mx - check if dtype is OCP microscaling format
; args:    edi = dtype_id
; returns: eax = 1 if OCP MX, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_ocp_mx
umath_dtype_is_ocp_mx:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_FLOAT_OCP
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_nv_format - check if dtype is NVIDIA specific format
; args:    edi = dtype_id
; returns: eax = 1 if NVIDIA format, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_nv_format
umath_dtype_is_nv_format:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_FLOAT_NV
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_gguf - check if dtype is GGUF quantization format
; args:    edi = dtype_id
; returns: eax = 1 if GGUF, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_is_gguf
umath_dtype_is_gguf:
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_GGUF
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_sub_byte - check if dtype is smaller than 8 bits
; args:    edi = dtype_id
; returns: eax = 1 if sub-byte, 0 otherwise
; note:    INT1, INT2, INT4, UINT4, FP6, FP4 variants are sub-byte
; -----------------------------------------------------------------------------
global umath_dtype_is_sub_byte
umath_dtype_is_sub_byte:
    cmp     edi, DTYPE_INT1
    je      .yes
    cmp     edi, DTYPE_INT2
    je      .yes
    cmp     edi, DTYPE_INT4
    je      .yes
    cmp     edi, DTYPE_UINT4
    je      .yes
    cmp     edi, DTYPE_FP6_E2M3
    je      .yes
    cmp     edi, DTYPE_FP6_E3M2
    je      .yes
    cmp     edi, DTYPE_MXFP6_E2M3
    je      .yes
    cmp     edi, DTYPE_MXFP6_E3M2
    je      .yes
    cmp     edi, DTYPE_MXFP4_E2M1
    je      .yes
    cmp     edi, DTYPE_NVFP4
    je      .yes
    cmp     edi, DTYPE_Q4_0
    je      .yes
    cmp     edi, DTYPE_Q4_1
    je      .yes
    cmp     edi, DTYPE_Q5_0
    je      .yes
    cmp     edi, DTYPE_Q5_1
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret