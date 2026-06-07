; =============================================================================
; umath - unified math library
; dtype/dtype_meta.asm - combined metadata table
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_family.asm
;   dtype_size.asm
;   dtype_align.asm
;   dtype_traits.asm
;
; description:
;   single flat table of dtype_meta_entry structs, one per dtype_id
;   indexed directly by dtype_id for O(1) access to all metadata
;   avoids calling multiple functions for multi-field queries
;
; struct dtype_meta_entry (32 bytes):
;   offset  0  u16  id
;   offset  2  u8   family_id
;   offset  3  u8   size_bits       (0 = variable)
;   offset  4  u8   size_bytes      (0 = variable, 1 = sub-byte rounded up)
;   offset  5  u8   align_scalar
;   offset  6  u8   exponent_bits   (0 for non-float)
;   offset  7  u8   mantissa_bits   (0 for non-float)
;   offset  8  u16  flags           (see DTYPE_FLAG_* constants)
;   offset 10  u8   elems_per_byte  (0 if >= 1 byte)
;   offset 11  u8   elems_per_zmm   (0 if variable or > 512-bit)
;   offset 12  u8   exponent_bias_lo
;   offset 13  u8   exponent_bias_hi (bias = hi<<8 | lo)
;   offset 14  u8   reserved[2]
;   offset 16  u8   name[16]        (short ASCII name, null terminated)
;
; flags (dtype_meta_entry.flags):
;   DTYPE_FLAG_HAS_NAN       = 0x0001
;   DTYPE_FLAG_HAS_INF       = 0x0002
;   DTYPE_FLAG_HAS_NEG_ZERO  = 0x0004
;   DTYPE_FLAG_HAS_SUBNORMAL = 0x0008
;   DTYPE_FLAG_IS_IEEE754    = 0x0010
;   DTYPE_FLAG_IS_SIGNED     = 0x0020
;   DTYPE_FLAG_IS_FLOAT      = 0x0040
;   DTYPE_FLAG_IS_COMPLEX    = 0x0080
;   DTYPE_FLAG_IS_SUB_BYTE   = 0x0100
;   DTYPE_FLAG_IS_VARIABLE   = 0x0200
;   DTYPE_FLAG_IS_OCP_MX     = 0x0400
;   DTYPE_FLAG_IS_NV_FORMAT  = 0x0800
;   DTYPE_FLAG_IS_GGUF       = 0x1000
;   DTYPE_FLAG_HAS_BLOCK_SCALE = 0x2000
;   DTYPE_FLAG_IS_POSIT      = 0x4000
;
; functions:
;   umath_dtype_meta_ptr     (dtype_id → *entry)
;   umath_dtype_meta_get_id          (dtype_id → u16)
;   umath_dtype_meta_get_family      (dtype_id → u8)
;   umath_dtype_meta_get_size_bits   (dtype_id → u8)
;   umath_dtype_meta_get_size_bytes  (dtype_id → u8)
;   umath_dtype_meta_get_align       (dtype_id → u8)
;   umath_dtype_meta_get_exp_bits    (dtype_id → u8)
;   umath_dtype_meta_get_man_bits    (dtype_id → u8)
;   umath_dtype_meta_get_flags       (dtype_id → u16)
;   umath_dtype_meta_get_elems_zmm   (dtype_id → u8)
;   umath_dtype_meta_get_name        (dtype_id → *char)
;   umath_dtype_meta_has_flag        (dtype_id, flag → bool)
; =============================================================================

%include "dtype_id.asm"
%include "dtype_family.asm"

bits 64

; =============================================================================
; flag constants
; =============================================================================

DTYPE_FLAG_HAS_NAN          equ 0x0001
DTYPE_FLAG_HAS_INF          equ 0x0002
DTYPE_FLAG_HAS_NEG_ZERO     equ 0x0004
DTYPE_FLAG_HAS_SUBNORMAL    equ 0x0008
DTYPE_FLAG_IS_IEEE754       equ 0x0010
DTYPE_FLAG_IS_SIGNED        equ 0x0020
DTYPE_FLAG_IS_FLOAT         equ 0x0040
DTYPE_FLAG_IS_COMPLEX       equ 0x0080
DTYPE_FLAG_IS_SUB_BYTE      equ 0x0100
DTYPE_FLAG_IS_VARIABLE      equ 0x0200
DTYPE_FLAG_IS_OCP_MX        equ 0x0400
DTYPE_FLAG_IS_NV_FORMAT     equ 0x0800
DTYPE_FLAG_IS_GGUF          equ 0x1000
DTYPE_FLAG_HAS_BLOCK_SCALE  equ 0x2000
DTYPE_FLAG_IS_POSIT         equ 0x4000

; =============================================================================
; struct offsets
; =============================================================================

META_OFF_ID             equ 0
META_OFF_FAMILY         equ 2
META_OFF_SIZE_BITS      equ 3
META_OFF_SIZE_BYTES     equ 4
META_OFF_ALIGN_SCALAR   equ 5
META_OFF_EXP_BITS       equ 6
META_OFF_MAN_BITS       equ 7
META_OFF_FLAGS          equ 8
META_OFF_ELEMS_BYTE     equ 10
META_OFF_ELEMS_ZMM      equ 11
META_OFF_EXP_BIAS_LO    equ 12
META_OFF_EXP_BIAS_HI    equ 13
META_OFF_RESERVED       equ 14
META_OFF_NAME           equ 16
META_ENTRY_SIZE         equ 32

; =============================================================================
; helper macros for table entries
; =============================================================================

; meta_entry id, family, size_bits, size_bytes, align,
;             exp_bits, man_bits, flags, elems_byte, elems_zmm,
;             bias, name
%macro meta_entry 12
    dw  %1                  ; id
    db  %2                  ; family
    db  %3                  ; size_bits
    db  %4                  ; size_bytes
    db  %5                  ; align_scalar
    db  %6                  ; exp_bits
    db  %7                  ; man_bits
    dw  %8                  ; flags
    db  %9                  ; elems_per_byte
    db  %10                 ; elems_per_zmm
    dw  %11                 ; exp_bias
    dw  0                   ; reserved
    db  %12, 0              ; name (up to 15 chars + null)
    times (16 - 1 - %strlen(%12)) db 0
%endmacro

; =============================================================================
; metadata table
; =============================================================================

section .rodata
align 64
dtype_meta_table:

; ---------- DTYPE_NONE -------------------------------------------------------
meta_entry \
    DTYPE_NONE, DFAMILY_UNKNOWN, 0, 0, 0, 0, 0, \
    0, 0, 0, 0, \
    "none"

; ---------- integer signed ---------------------------------------------------
meta_entry \
    DTYPE_INT1, DFAMILY_INT_SIGNED, 1, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, 8, 0, 0, \
    "int1"

meta_entry \
    DTYPE_INT2, DFAMILY_INT_SIGNED, 2, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, 4, 0, 0, \
    "int2"

meta_entry \
    DTYPE_INT4, DFAMILY_INT_SIGNED, 4, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, 2, 128, 0, \
    "int4"

meta_entry \
    DTYPE_INT8, DFAMILY_INT_SIGNED, 8, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_SIGNED, 1, 64, 0, \
    "int8"

meta_entry \
    DTYPE_INT16, DFAMILY_INT_SIGNED, 16, 2, 2, 0, 0, \
    DTYPE_FLAG_IS_SIGNED, 0, 32, 0, \
    "int16"

meta_entry \
    DTYPE_INT32, DFAMILY_INT_SIGNED, 32, 4, 4, 0, 0, \
    DTYPE_FLAG_IS_SIGNED, 0, 16, 0, \
    "int32"

meta_entry \
    DTYPE_INT64, DFAMILY_INT_SIGNED, 64, 8, 8, 0, 0, \
    DTYPE_FLAG_IS_SIGNED, 0, 8, 0, \
    "int64"

meta_entry \
    DTYPE_INT128, DFAMILY_INT_SIGNED, 128, 16, 16, 0, 0, \
    DTYPE_FLAG_IS_SIGNED, 0, 4, 0, \
    "int128"

meta_entry \
    DTYPE_INT256, DFAMILY_INT_SIGNED, 255, 32, 32, 0, 0, \
    DTYPE_FLAG_IS_SIGNED, 0, 2, 0, \
    "int256"

; 6 padding entries 0x00A-0x00F
times 6 db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ---------- integer unsigned -------------------------------------------------
meta_entry \
    DTYPE_UINT4, DFAMILY_INT_UNSIGNED, 4, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_SUB_BYTE, 2, 128, 0, \
    "uint4"

meta_entry \
    DTYPE_UINT8, DFAMILY_INT_UNSIGNED, 8, 1, 1, 0, 0, \
    0, 1, 64, 0, \
    "uint8"

meta_entry \
    DTYPE_UINT16, DFAMILY_INT_UNSIGNED, 16, 2, 2, 0, 0, \
    0, 0, 32, 0, \
    "uint16"

meta_entry \
    DTYPE_UINT32, DFAMILY_INT_UNSIGNED, 32, 4, 4, 0, 0, \
    0, 0, 16, 0, \
    "uint32"

meta_entry \
    DTYPE_UINT64, DFAMILY_INT_UNSIGNED, 64, 8, 8, 0, 0, \
    0, 0, 8, 0, \
    "uint64"

meta_entry \
    DTYPE_UINT128, DFAMILY_INT_UNSIGNED, 128, 16, 16, 0, 0, \
    0, 0, 4, 0, \
    "uint128"

meta_entry \
    DTYPE_UINT256, DFAMILY_INT_UNSIGNED, 255, 32, 32, 0, 0, \
    0, 0, 2, 0, \
    "uint256"

meta_entry \
    DTYPE_UINT512, DFAMILY_INT_UNSIGNED, 255, 64, 64, 0, 0, \
    0, 0, 1, 0, \
    "uint512"

meta_entry \
    DTYPE_UINT1024, DFAMILY_INT_UNSIGNED, 255, 128, 64, 0, 0, \
    0, 0, 0, 0, \
    "uint1024"

meta_entry \
    DTYPE_UINT2048, DFAMILY_INT_UNSIGNED, 255, 255, 64, 0, 0, \
    0, 0, 0, 0, \
    "uint2048"

; 6 padding entries 0x01A-0x01F
times 6 db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ---------- IEEE float -------------------------------------------------------
; flags common to IEEE floats
%define F_IEEE  DTYPE_FLAG_HAS_NAN|DTYPE_FLAG_HAS_INF|DTYPE_FLAG_HAS_NEG_ZERO|\
                DTYPE_FLAG_HAS_SUBNORMAL|DTYPE_FLAG_IS_IEEE754|\
                DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_FLOAT

meta_entry \
    DTYPE_FP8_E4M3, DFAMILY_FLOAT_IEEE, 8, 1, 1, 4, 3, \
    F_IEEE, 1, 64, 7, \
    "fp8_e4m3"

meta_entry \
    DTYPE_FP8_E5M2, DFAMILY_FLOAT_IEEE, 8, 1, 1, 5, 2, \
    F_IEEE, 1, 64, 15, \
    "fp8_e5m2"

meta_entry \
    DTYPE_FP16, DFAMILY_FLOAT_IEEE, 16, 2, 2, 5, 10, \
    F_IEEE, 0, 32, 15, \
    "fp16"

meta_entry \
    DTYPE_BF16, DFAMILY_FLOAT_IEEE, 16, 2, 2, 8, 7, \
    F_IEEE, 0, 32, 127, \
    "bf16"

meta_entry \
    DTYPE_TF32, DFAMILY_FLOAT_IEEE, 19, 4, 4, 8, 10, \
    F_IEEE, 0, 16, 127, \
    "tf32"

meta_entry \
    DTYPE_FP32, DFAMILY_FLOAT_IEEE, 32, 4, 4, 8, 23, \
    F_IEEE, 0, 16, 127, \
    "fp32"

meta_entry \
    DTYPE_FP64, DFAMILY_FLOAT_IEEE, 64, 8, 8, 11, 52, \
    F_IEEE, 0, 8, 1023, \
    "fp64"

meta_entry \
    DTYPE_FP128, DFAMILY_FLOAT_IEEE, 128, 16, 16, 15, 112, \
    F_IEEE, 0, 4, 16383, \
    "fp128"

; ---------- FP8 FNUZ variants ------------------------------------------------
%define F_FNUZ  DTYPE_FLAG_HAS_NAN|DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_FLOAT|\
                DTYPE_FLAG_HAS_SUBNORMAL

meta_entry \
    DTYPE_FP8_E4M3_FNUZ, DFAMILY_FLOAT_FP8_VAR, 8, 1, 1, 4, 3, \
    F_FNUZ, 1, 64, 8, \
    "fp8_e4m3_fnuz"

meta_entry \
    DTYPE_FP8_E5M2_FNUZ, DFAMILY_FLOAT_FP8_VAR, 8, 1, 1, 5, 2, \
    F_FNUZ, 1, 64, 16, \
    "fp8_e5m2_fnuz"

meta_entry \
    DTYPE_BFLOAT8, DFAMILY_FLOAT_FP8_VAR, 8, 1, 1, 5, 2, \
    F_FNUZ, 1, 64, 15, \
    "bfloat8"

meta_entry \
    DTYPE_MINIFLOAT, DFAMILY_FLOAT_FP8_VAR, 8, 1, 1, 4, 3, \
    DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_IS_SIGNED, 1, 64, 7, \
    "minifloat"

; ---------- FP6 scalar -------------------------------------------------------
%define F_FP6   DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_IS_SIGNED|\
                DTYPE_FLAG_HAS_SUBNORMAL|DTYPE_FLAG_IS_SUB_BYTE

meta_entry \
    DTYPE_FP6_E2M3, DFAMILY_FLOAT_FP6, 6, 1, 1, 2, 3, \
    F_FP6, 1, 85, 1, \
    "fp6_e2m3"

meta_entry \
    DTYPE_FP6_E3M2, DFAMILY_FLOAT_FP6, 6, 1, 1, 3, 2, \
    F_FP6, 1, 85, 3, \
    "fp6_e3m2"

; 2 padding
times 2 db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ---------- OCP MX -----------------------------------------------------------
%define F_MX    DTYPE_FLAG_IS_OCP_MX|DTYPE_FLAG_HAS_BLOCK_SCALE|\
                DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_FLOAT

meta_entry \
    DTYPE_MXFP8_E4M3, DFAMILY_FLOAT_OCP, 8, 1, 1, 4, 3, \
    F_MX|DTYPE_FLAG_HAS_NAN, 1, 64, 7, \
    "mxfp8_e4m3"

meta_entry \
    DTYPE_MXFP8_E5M2, DFAMILY_FLOAT_OCP, 8, 1, 1, 5, 2, \
    F_MX|DTYPE_FLAG_HAS_NAN|DTYPE_FLAG_HAS_INF, 1, 64, 15, \
    "mxfp8_e5m2"

meta_entry \
    DTYPE_MXFP6_E2M3, DFAMILY_FLOAT_OCP, 6, 1, 1, 2, 3, \
    F_MX|DTYPE_FLAG_IS_SUB_BYTE, 1, 85, 1, \
    "mxfp6_e2m3"

meta_entry \
    DTYPE_MXFP6_E3M2, DFAMILY_FLOAT_OCP, 6, 1, 1, 3, 2, \
    F_MX|DTYPE_FLAG_IS_SUB_BYTE, 1, 85, 3, \
    "mxfp6_e3m2"

meta_entry \
    DTYPE_MXFP4_E2M1, DFAMILY_FLOAT_OCP, 4, 1, 1, 2, 1, \
    F_MX|DTYPE_FLAG_IS_SUB_BYTE, 2, 128, 1, \
    "mxfp4_e2m1"

meta_entry \
    DTYPE_MXINT8, DFAMILY_FLOAT_OCP, 8, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_OCP_MX|DTYPE_FLAG_HAS_BLOCK_SCALE|DTYPE_FLAG_IS_SIGNED, \
    1, 64, 0, \
    "mxint8"

meta_entry \
    DTYPE_MXINT6, DFAMILY_FLOAT_OCP, 6, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_OCP_MX|DTYPE_FLAG_HAS_BLOCK_SCALE|\
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, \
    1, 85, 0, \
    "mxint6"

meta_entry \
    DTYPE_MXINT4, DFAMILY_FLOAT_OCP, 4, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_OCP_MX|DTYPE_FLAG_HAS_BLOCK_SCALE|\
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, \
    2, 128, 0, \
    "mxint4"

meta_entry \
    DTYPE_UE8M0, DFAMILY_FLOAT_OCP, 8, 1, 1, 8, 0, \
    DTYPE_FLAG_IS_OCP_MX|DTYPE_FLAG_IS_FLOAT, 1, 64, 127, \
    "ue8m0"

meta_entry \
    DTYPE_NVFP4, DFAMILY_FLOAT_NV, 4, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_NV_FORMAT|DTYPE_FLAG_HAS_BLOCK_SCALE|\
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_IS_SUB_BYTE, \
    2, 128, 0, \
    "nvfp4"

meta_entry \
    DTYPE_NVINT4, DFAMILY_FLOAT_NV, 4, 1, 1, 0, 0, \
    DTYPE_FLAG_IS_NV_FORMAT|DTYPE_FLAG_HAS_BLOCK_SCALE|\
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, \
    2, 128, 0, \
    "nvint4"

meta_entry \
    DTYPE_NVFP8, DFAMILY_FLOAT_NV, 8, 1, 1, 4, 3, \
    DTYPE_FLAG_IS_NV_FORMAT|DTYPE_FLAG_IS_FLOAT|\
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_HAS_NAN, \
    1, 64, 7, \
    "nvfp8"

; 4 padding
times 4 db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ---------- fixed point ------------------------------------------------------
meta_entry \
    DTYPE_Q4_0, DFAMILY_FIXED, 4, 1, 1, 0, 4, \
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, 2, 128, 0, \
    "q4_0"

meta_entry \
    DTYPE_Q4_1, DFAMILY_FIXED, 4, 1, 1, 0, 4, \
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, 2, 128, 0, \
    "q4_1"

meta_entry \
    DTYPE_Q5_0, DFAMILY_FIXED, 5, 1, 1, 0, 5, \
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, 1, 102, 0, \
    "q5_0"

meta_entry \
    DTYPE_Q5_1, DFAMILY_FIXED, 5, 1, 1, 0, 5, \
    DTYPE_FLAG_IS_SIGNED|DTYPE_FLAG_IS_SUB_BYTE, 1, 102, 0, \
    "q5_1"

meta_entry \
    DTYPE_Q8_0, DFAMILY_FIXED, 8, 1, 1, 0, 8, \
    DTYPE_FLAG_IS_SIGNED, 1, 64, 0, \
    "q8_0"

meta_entry \
    DTYPE_BIT_PACKED, DFAMILY_FIXED, 0, 0, 8, 0, 0, \
    DTYPE_FLAG_IS_VARIABLE, 0, 0, 0, \
    "bit_packed"

meta_entry \
    DTYPE_DELTA_ENC, DFAMILY_FIXED, 0, 0, 8, 0, 0, \
    DTYPE_FLAG_IS_VARIABLE, 0, 0, 0, \
    "delta_enc"

; 9 padding
times 9 db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ---------- normalized -------------------------------------------------------
meta_entry \
    DTYPE_UNORM8, DFAMILY_NORMALIZED, 8, 1, 1, 0, 8, \
    0, 1, 64, 0, \
    "unorm8"

meta_entry \
    DTYPE_UNORM16, DFAMILY_NORMALIZED, 16, 2, 2, 0, 16, \
    0, 0, 32, 0, \
    "unorm16"

meta_entry \
    DTYPE_SNORM8, DFAMILY_NORMALIZED, 8, 1, 1, 0, 7, \
    DTYPE_FLAG_IS_SIGNED, 1, 64, 0, \
    "snorm8"

meta_entry \
    DTYPE_SNORM16, DFAMILY_NORMALIZED, 16, 2, 2, 0, 15, \
    DTYPE_FLAG_IS_SIGNED, 0, 32, 0, \
    "snorm16"

meta_entry \
    DTYPE_PROB32, DFAMILY_NORMALIZED, 32, 4, 4, 8, 23, \
    DTYPE_FLAG_IS_FLOAT, 0, 16, 127, \
    "prob32"

meta_entry \
    DTYPE_LOG_PROB32, DFAMILY_NORMALIZED, 32, 4, 4, 8, 23, \
    DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_IS_SIGNED, 0, 16, 127, \
    "log_prob32"

meta_entry \
    DTYPE_FUZZY, DFAMILY_NORMALIZED, 32, 4, 4, 8, 23, \
    DTYPE_FLAG_IS_FLOAT, 0, 16, 127, \
    "fuzzy"

; 9 padding
times 9 db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ---------- complex ----------------------------------------------------------
%define F_CPX   DTYPE_FLAG_IS_COMPLEX|DTYPE_FLAG_IS_SIGNED

meta_entry \
    DTYPE_CI8, DFAMILY_COMPLEX, 16, 2, 2, 0, 0, \
    F_CPX, 0, 32, 0, \
    "ci8"

meta_entry \
    DTYPE_CI16, DFAMILY_COMPLEX, 32, 4, 4, 0, 0, \
    F_CPX, 0, 16, 0, \
    "ci16"

meta_entry \
    DTYPE_CI32, DFAMILY_COMPLEX, 64, 8, 8, 0, 0, \
    F_CPX, 0, 8, 0, \
    "ci32"

meta_entry \
    DTYPE_CF16, DFAMILY_COMPLEX, 32, 4, 4, 5, 10, \
    F_CPX|DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_HAS_NAN|DTYPE_FLAG_HAS_INF, \
    0, 16, 15, \
    "cf16"

meta_entry \
    DTYPE_CBF16, DFAMILY_COMPLEX, 32, 4, 4, 8, 7, \
    F_CPX|DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_HAS_NAN|DTYPE_FLAG_HAS_INF, \
    0, 16, 127, \
    "cbf16"

meta_entry \
    DTYPE_CF32, DFAMILY_COMPLEX, 64, 8, 8, 8, 23, \
    F_CPX|DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_HAS_NAN|DTYPE_FLAG_HAS_INF|\
    DTYPE_FLAG_HAS_SUBNORMAL, 0, 8, 127, \
    "cf32"

meta_entry \
    DTYPE_CF64, DFAMILY_COMPLEX, 128, 16, 16, 11, 52, \
    F_CPX|DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_HAS_NAN|DTYPE_FLAG_HAS_INF|\
    DTYPE_FLAG_HAS_SUBNORMAL, 0, 4, 1023, \
    "cf64"

meta_entry \
    DTYPE_CF128, DFAMILY_COMPLEX, 255, 32, 32, 15, 112, \
    F_CPX|DTYPE_FLAG_IS_FLOAT|DTYPE_FLAG_HAS_NAN|DTYPE_FLAG_HAS_INF|\
    DTYPE_FLAG_HAS_SUBNORMAL, 0, 2, 16383, \
    "cf128"

meta_entry \
    DTYPE_CI64, DFAMILY_COMPLEX, 128, 16, 16, 0, 0, \
    F_CPX, 0, 4, 0, \
    "ci64"

; 7 padding
times 7 db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

dtype_meta_table_end:

section .text

; -----------------------------------------------------------------------------
; umath_dtype_meta_ptr - get pointer to dtype metadata entry
; args:    edi = dtype_id
; returns: rax = pointer to dtype_meta_entry, NULL if invalid
; -----------------------------------------------------------------------------
global umath_dtype_meta_ptr
umath_dtype_meta_ptr:
    cmp     edi, (dtype_meta_table_end - dtype_meta_table) / META_ENTRY_SIZE
    jae     .null
    lea     rax, [rel dtype_meta_table]
    imul    edi, META_ENTRY_SIZE
    add     rax, rdi
    ret
.null:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_get_flags - get dtype flags
; args:    edi = dtype_id
; returns: eax = flags (u16), 0 if invalid
; -----------------------------------------------------------------------------
global umath_dtype_meta_get_flags
umath_dtype_meta_get_flags:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .zero
    movzx   eax, word [rax + META_OFF_FLAGS]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_has_flag - check if dtype has specific flag
; args:    edi = dtype_id
;          esi = flag (DTYPE_FLAG_*)
; returns: eax = 1 if flag set, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_meta_has_flag
umath_dtype_meta_has_flag:
    push    rbx
    mov     ebx, esi
    call    umath_dtype_meta_get_flags
    test    eax, ebx
    setnz   al
    movzx   eax, al
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_get_size_bits - get size in bits from meta table
; args:    edi = dtype_id
; returns: eax = size_bits, 0 if variable or invalid
; -----------------------------------------------------------------------------
global umath_dtype_meta_get_size_bits
umath_dtype_meta_get_size_bits:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .zero
    movzx   eax, byte [rax + META_OFF_SIZE_BITS]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_get_size_bytes - get size in bytes from meta table
; args:    edi = dtype_id
; returns: eax = size_bytes, 0 if variable or invalid
; -----------------------------------------------------------------------------
global umath_dtype_meta_get_size_bytes
umath_dtype_meta_get_size_bytes:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .zero
    movzx   eax, byte [rax + META_OFF_SIZE_BYTES]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_get_family - get family from meta table
; args:    edi = dtype_id
; returns: eax = family_id
; -----------------------------------------------------------------------------
global umath_dtype_meta_get_family
umath_dtype_meta_get_family:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .unknown
    movzx   eax, byte [rax + META_OFF_FAMILY]
    ret
.unknown:
    mov     eax, DFAMILY_UNKNOWN
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_get_exp_bits - get exponent bits from meta table
; args:    edi = dtype_id
; returns: eax = exponent bits (0 for non-float)
; -----------------------------------------------------------------------------
global umath_dtype_meta_get_exp_bits
umath_dtype_meta_get_exp_bits:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .zero
    movzx   eax, byte [rax + META_OFF_EXP_BITS]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_get_man_bits - get mantissa bits from meta table
; args:    edi = dtype_id
; returns: eax = mantissa bits (0 for non-float)
; -----------------------------------------------------------------------------
global umath_dtype_meta_get_man_bits
umath_dtype_meta_get_man_bits:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .zero
    movzx   eax, byte [rax + META_OFF_MAN_BITS]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_get_elems_zmm - get elements per ZMM from meta table
; args:    edi = dtype_id
; returns: eax = elements per ZMM register (0 if variable or > 512-bit)
; -----------------------------------------------------------------------------
global umath_dtype_meta_get_elems_zmm
umath_dtype_meta_get_elems_zmm:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .zero
    movzx   eax, byte [rax + META_OFF_ELEMS_ZMM]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_meta_get_name - get short ASCII name pointer
; args:    edi = dtype_id
; returns: rax = pointer to null-terminated ASCII name string
;               returns pointer to "unknown" if invalid
; -----------------------------------------------------------------------------
section .rodata
str_unknown: db "unknown", 0

section .text
global umath_dtype_meta_get_name
umath_dtype_meta_get_name:
    call    umath_dtype_meta_ptr
    test    rax, rax
    jz      .unknown
    add     rax, META_OFF_NAME
    ret
.unknown:
    lea     rax, [rel str_unknown]
    ret