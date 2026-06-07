# dtype — umath Data Type System

**Module:** `dtype/`
**Tier:** 0 (no dependencies)
**Part of:** umath — unified math library

---

## Overview

`dtype` is the foundational type system for umath. Every module in the entire
mathkernel stack depends on this module. It defines, classifies, and describes
every numeric data type that umath operates on — from single-bit booleans to
arbitrary-precision complex numbers.

No runtime. No OS. No libc. Pure assembly data tables and lookup logic.

---

## Why dtype exists

Every math operation in umath needs to answer these questions:

```
What type is this value?
How many bits does it occupy?
How should it be aligned?
What are its special values (NaN, inf, zero)?
Can it be safely cast to another type?
What type does this operation produce?
Is this type supported on the current CPU?
```

Without a centralized answer to these questions, every module would define
its own ad-hoc type handling. dtype solves this once, correctly, for all 235
types across the entire library.

---

## Dtype families

```
Family          IDs         Types
─────────────────────────────────────────────────────────────────
Integer signed  0x01–0x09   INT1/2/4/8/16/32/64/128/256
Integer unsigned 0x10–0x19  UINT4/8/16/32/64/128/256/512/1024/2048
IEEE float      0x20–0x27   FP8_E4M3/E5M2, FP16, BF16, TF32,
                            FP32, FP64, FP128
FP6 scalar      0x2C–0x2D   FP6_E2M3, FP6_E3M2
OCP MX          0x30–0x3B   MXFP8/6/4, MXINT8/6/4,
                            NVFP4, NVINT4, UE8M0
Fixed point     0x40–0x46   Q4_0/1, Q5_0/1, Q8_0,
                            BIT_PACKED, DELTA_ENC
Normalized      0x50–0x56   UNORM8/16, SNORM8/16,
                            PROB32, LOG_PROB32, FUZZY
Complex         0x60–0x68   CI8/16/32, CF16, CBF16,
                            CF32, CF64, CF128
Packed SIMD     0x70–0x77   INT4x2/x8/x16, FP8x2/x4, BF16x2
Galois fields   0x80–0x8F   GF2, GFP, GF2N, GF2_128/256,
                            ZMOD, MONTGOMERY, BARRETT
PQ crypto       0x90–0x97   KYBER_POLY, DILITH_POLY,
                            NTRU_POLY, FALCON_POLY, RLWE_POLY
Coding theory   0xA0–0xA7   RS_SYMBOL, BCH_WORD, LDPC_BIT,
                            LLR, GFQ_ELEM
Arbitrary prec  0xB0–0xB9   BIGINT, BIGFLOAT, RATIONAL,
                            PADIC, SURREAL, HYPERREAL,
                            ORDINAL, CARDINAL
Alternative     0xC0–0xC9   POSIT8/16/32/64/128/256,
                            UNUM1, UNUM2, VALID,
                            LNS8/16/32, DBNS, STOCHASTIC
Interval        0xD0–0xD6   INTERVAL_F32/F64/INT,
                            DUAL, HYPERDUAL, MULTIDUAL
Geometric       0xE0–0xEF   QUAT_F32/F64, DUAL_QUAT,
                            OCTONION, SEDENION,
                            BIVECTOR, TRIVECTOR, MULTIVEC,
                            ROTOR, SPINOR, VERSOR,
                            TANGENT, COTANGENT,
                            FORM_1/2/3
Sparse          0xF0–0xFB   CSR/CSC/COO/BSR/ELL/DIA
                            VAL/IDX variants
GGUF quant      0x100–0x10F Q2K/Q3K/Q4K/Q5K/Q6K/Q8K,
                            IQ1S/IQ2XXS/IQ3XXS/IQ4NL
Quantum         0x110–0x112 QBIT, DENSITY, KET
Graphics        0x120–0x12B RGB8, RGBA8, RGB16F, RGBA16F,
                            R11G11B10F, RGB9E5,
                            DEPTH16/32F/24S8, HALF4, BYTE4
Audio/signal    0x130–0x139 PCM8/16/24/32, FLOAT_AUDIO,
                            ULAW, ALAW, TIMESTAMP,
                            FREQUENCY, PHASE
Abstract math   0x140–0x14F MORPHISM, FUNCTOR_VAL, NAT_TRANS,
                            MEASURE, PROB_MEAS,
                            UTILITY, STRATEGY, PAYOFF
Compressed      0x150–0x153 RLE_BLOCK, ZSTD_BLOCK,
                            DICT_ENC, BIT_PACKED_BLK
─────────────────────────────────────────────────────────────────
Reserved        0x154–0xEFF future defined types
Reserved        0xF00–0xFF0 future hardware formats
User defined    0xFF1–0xFFE user custom types
Sentinels       0xFFE–0xFFF DTYPE_UNKNOWN, DTYPE_MAX
─────────────────────────────────────────────────────────────────
Total           235 defined types
```

---

## Files

```
dtype/
├── dtype_id.asm        ← master enum, all 235 IDs + reserved space
├── dtype_family.asm    ← family classification, is_int/float/complex etc
├── dtype_size.asm      ← size in bits and bytes, packed size
├── dtype_align.asm     ← alignment for scalar/XMM/YMM/ZMM/cache
├── dtype_meta.asm      ← combined metadata table, O(1) lookup
├── dtype_traits.asm    ← has_nan/inf/neg_zero/subnormal, ieee754 etc
├── dtype_patterns.asm  ← bit patterns for zero/one/nan/inf/max/min/eps
├── dtype_range.asm     ← min/max/smallest representable values
├── dtype_epsilon.asm   ← machine epsilon, ULP, decimal digits
├── dtype_promote.asm   ← promotion rules, 235×235 lookup table
├── dtype_cast.asm      ← cast safety, overflow/underflow behavior
├── dtype_support.asm   ← CPUID runtime support check per dtype
├── dtype_name.asm      ← dtype ↔ string name, ASCII + UTF-8
├── dtype_valid.asm     ← validate values and bit patterns
├── dtype_pack.asm      ← sub-byte packing/unpacking rules
└── dtype_endian.asm    ← endianness per dtype, byte swap ops
```

---

## Build order

```
dtype_id.asm            ← 1st  no deps, pure constants
dtype_family.asm        ← 2nd  needs dtype_id
dtype_size.asm          ← 3rd  needs dtype_id
dtype_align.asm         ← 4th  needs dtype_id, dtype_size
dtype_traits.asm        ← 5th  needs dtype_id, dtype_family
dtype_patterns.asm      ← 6th  needs dtype_id, dtype_traits
dtype_range.asm         ← 7th  needs dtype_patterns
dtype_epsilon.asm       ← 8th  needs dtype_id, dtype_traits
dtype_meta.asm          ← 9th  needs all above
dtype_pack.asm          ← 10th needs dtype_size, dtype_traits
dtype_endian.asm        ← 11th needs dtype_size
dtype_promote.asm       ← 12th needs dtype_family, dtype_traits
dtype_cast.asm          ← 13th needs dtype_promote, dtype_range
dtype_support.asm       ← 14th needs dtype_id + cpuid/ module
dtype_valid.asm         ← 15th needs dtype_patterns, dtype_range
dtype_name.asm          ← 16th needs dtype_id + charset/ module
```

---

## Calling convention

All dtype functions follow System V AMD64 ABI:

```
args     → rdi, rsi, rdx, rcx, r8, r9
return   → rax
dtype_id → always passed as u32 in edi/rdi
bool     → returned as 0 or 1 in eax
```

---

## Key design decisions

**Flat ID space**
All 235 types share a single u32 ID namespace. No hierarchy at runtime.
Family, traits, size — all looked up from flat tables indexed by ID.

**Read-only tables**
All metadata is compile-time constant. No heap allocation. No runtime
initialization required. Tables live in `.rodata` section. CPU cache
friendly — hot paths fit in L1.

**O(1) everything**
Every query is a table lookup or trivial arithmetic.
`dtype_promote(a, b)` → single indexed read from 235×235 table.
`dtype_size_bytes(id)` → single indexed read from 235-entry table.

**Sub-byte types**
INT1, INT2, INT4 are valid dtypes. `dtype_size_bits` returns 1, 2, 4.
`dtype_size_bytes` returns 0 with fractional encoding in high bits.
`dtype_pack` module handles actual packing/unpacking logic.

**Reserved space**
ID ranges 0x154–0xEFF reserved for future defined types.
ID range 0xF00–0xFF0 reserved for future hardware formats
(e.g. FP3, FP2, neuromorphic types, quantum hardware types).
User types start at 0xFF1.
Never need to renumber existing types.

**No OS dependency**
`dtype_support.asm` calls into `cpuid/` module directly via CPUID
instruction. No syscalls. No OS feature query. Runs in ring 0.

---

## Usage examples

```nasm
; get size of FP16 in bytes
mov     edi, DTYPE_FP16
call    umath_dtype_size_bytes      ; returns 2 in eax

; check if FP8_E4M3 is supported on this CPU
mov     edi, DTYPE_FP8_E4M3
call    umath_dtype_supported       ; returns 1/0 in eax

; get promotion result of INT8 + FP32
mov     edi, DTYPE_INT8
mov     esi, DTYPE_FP32
call    umath_dtype_promote         ; returns DTYPE_FP32 in eax

; get NaN bit pattern for FP16
mov     edi, DTYPE_FP16
call    umath_dtype_pattern_nan     ; returns 0x7E00 in eax

; check if BF16 has infinity
mov     edi, DTYPE_BF16
call    umath_dtype_has_inf         ; returns 1 in eax

; get machine epsilon for FP32
mov     edi, DTYPE_FP32
call    umath_dtype_epsilon_f64     ; returns ~1.19e-7 in xmm0

; get dtype name string
mov     edi, DTYPE_MXFP8_E4M3
call    umath_dtype_name_ascii      ; returns ptr to "mxfp8_e4m3"
```

---

## Dtype promotion rules summary

```
Operation           Result dtype
───────────────────────────────────────────────
INT8  + INT8    →   INT8
INT8  + INT16   →   INT16
INT8  + FP32    →   FP32
INT8  + FP64    →   FP64
FP16  + FP16    →   FP16
FP16  + FP32    →   FP32
FP16  + BF16    →   FP32
BF16  + BF16    →   BF16
BF16  + FP32    →   FP32
FP8   + FP16    →   FP16
FP8   + FP32    →   FP32
FP8   + BF16    →   BF16
INT4  + INT4    →   INT4
INT4  + FP32    →   FP32
CF32  + CF32    →   CF32
CF32  + CF64    →   CF64
CF32  + FP32    →   CF32
BIGINT + INT64  →   BIGINT
BIGINT + FP64   →   BIGFLOAT
```

Full 235×235 table in `dtype_promote.asm`.

---

## Cast safety levels

```
Level 0 — LOSSLESS
  INT8  → INT16, INT32, INT64
  FP32  → FP64
  FP16  → FP32, FP64

Level 1 — SAFE (possible precision loss, no overflow)
  FP64  → FP32   (precision loss only)
  FP32  → FP16   (precision + range loss)
  FP32  → BF16   (precision loss only)

Level 2 — OVERFLOW POSSIBLE
  INT32 → INT8   (overflow if > 127)
  FP32  → INT8   (overflow + truncation)
  FP64  → FP8    (extreme range loss)

Level 3 — UNSAFE (undefined for some inputs)
  FP32  → INT32  (NaN/inf undefined)
  FP16  → INT4   (most values overflow)

Level 4 — REQUIRES QUANTIZATION
  FP32  → Q4_0   (needs scale computation)
  FP32  → MXFP4  (needs block scale)
  FP32  → INT8   (needs zero point)
```

---

## Special value bit patterns

```
dtype        zero      one       nan       +inf      max
──────────────────────────────────────────────────────────────
FP32         0x00000000 0x3F800000 0x7FC00000 0x7F800000 0x7F7FFFFF
FP64         0x0000...  0x3FF0...  0x7FF8...  0x7FF0...  0x7FEF...
FP16         0x0000     0x3C00     0x7E00     0x7C00     0x7BFF
BF16         0x0000     0x3F80     0x7FC0     0x7F80     0x7F7F
FP8_E4M3     0x00       0x38       0x7F       N/A        0x7E
FP8_E5M2     0x00       0x3C       0x7F       0x7C       0x7B
INT8         0x00       0x01       N/A        N/A        0x7F
UINT8        0x00       0x01       N/A        N/A        0xFF
INT4         0x0        0x1        N/A        N/A        0x7
UINT4        0x0        0x1        N/A        N/A        0xF
```

Full table in `dtype_patterns.asm`.

---

## Notes on sub-byte types

INT1, INT2, INT4 cannot be addressed individually in x86-64.
They always live packed inside larger types.

```
INT4 storage:
  Two INT4 per byte
  Low nibble  = element 0 (bits 0-3)
  High nibble = element 1 (bits 4-7)

INT2 storage:
  Four INT2 per byte
  Bits 0-1 = element 0
  Bits 2-3 = element 1
  Bits 4-5 = element 2
  Bits 6-7 = element 3

INT1 storage:
  Eight INT1 per byte
  Standard LSB-first bit ordering
```

`dtype_pack.asm` handles all extract/insert operations.

---

## Dependencies

```
dtype/ depends on:
  → nothing         (Tier 0, self-contained)

dtype/ is depended on by:
  → charset/        (dtype_name needs UTF-8)
  → bits/           (all bit ops are dtype-aware)
  → memory/         (alloc needs alignment info)
  → scalar/         (scalar ops need type info)
  → convert/        (all conversions need dtype)
  → simd/           (SIMD ops need dtype width)
  → gemm/           (dispatch needs dtype)
  → every other module in mathkernel
```

---

## Version

```
DTYPE_SPEC_VERSION  equ 1       ← increment on breaking changes
DTYPE_COUNT         equ 235     ← total defined dtypes
DTYPE_ID_MAX        equ 0xFFF   ← maximum valid ID
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*