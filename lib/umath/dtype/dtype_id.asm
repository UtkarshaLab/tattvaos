; =============================================================================
; umath - unified math library
; dtype/dtype_id.asm - master dtype ID enum
; =============================================================================
; defines:
;   DTYPE_NONE              = 0x000   null/unset dtype
;   DTYPE_*                 = 0x001   all 235 defined dtypes
;   DTYPE_UNKNOWN           = 0xFFE   unknown sentinel
;   DTYPE_MAX               = 0xFFF   range check sentinel
;
;   DTYPE_SPEC_VERSION      = 1       spec version
;   DTYPE_COUNT             = 235     total defined dtypes
;   DTYPE_ID_BITS           = 12      bits needed for ID
;   DTYPE_ID_MAX            = 0xFFF   maximum valid ID
;
; reserved ranges:
;   0x154–0xEFF  future defined types
;   0xF00–0xFF0  future hardware formats
;   0xFF1–0xFFD  user defined types
;   0xFFE–0xFFF  sentinels
; =============================================================================

bits 64

; =============================================================================
; version and counts
; =============================================================================

DTYPE_SPEC_VERSION      equ 1
DTYPE_COUNT             equ 235
DTYPE_ID_BITS           equ 12
DTYPE_ID_MAX            equ 0xFFF

; =============================================================================
; sentinel: null
; =============================================================================

DTYPE_NONE              equ 0x000

; =============================================================================
; integer signed family     0x001–0x009
; =============================================================================

DTYPE_INT1              equ 0x001   ; single bit boolean
DTYPE_INT2              equ 0x002   ; 2-bit signed integer
DTYPE_INT4              equ 0x003   ; 4-bit signed integer (nibble)
DTYPE_INT8              equ 0x004   ; 8-bit signed integer
DTYPE_INT16             equ 0x005   ; 16-bit signed integer
DTYPE_INT32             equ 0x006   ; 32-bit signed integer
DTYPE_INT64             equ 0x007   ; 64-bit signed integer
DTYPE_INT128            equ 0x008   ; 128-bit signed integer
DTYPE_INT256            equ 0x009   ; 256-bit signed integer (ECC ops)

; =============================================================================
; integer unsigned family   0x010–0x019
; =============================================================================

DTYPE_UINT4             equ 0x010   ; 4-bit unsigned integer
DTYPE_UINT8             equ 0x011   ; 8-bit unsigned integer
DTYPE_UINT16            equ 0x012   ; 16-bit unsigned integer
DTYPE_UINT32            equ 0x013   ; 32-bit unsigned integer
DTYPE_UINT64            equ 0x014   ; 64-bit unsigned integer
DTYPE_UINT128           equ 0x015   ; 128-bit unsigned integer
DTYPE_UINT256           equ 0x016   ; 256-bit unsigned integer (ECC secp256k1)
DTYPE_UINT512           equ 0x017   ; 512-bit unsigned integer (RSA-512)
DTYPE_UINT1024          equ 0x018   ; 1024-bit unsigned integer (RSA-1024)
DTYPE_UINT2048          equ 0x019   ; 2048-bit unsigned integer (RSA-2048)

; =============================================================================
; IEEE 754 floating point   0x020–0x027
; =============================================================================

DTYPE_FP8_E4M3          equ 0x020   ; 8-bit float E4M3 (H100 inference)
DTYPE_FP8_E5M2          equ 0x021   ; 8-bit float E5M2 (H100 training)
DTYPE_FP16              equ 0x022   ; 16-bit half precision float
DTYPE_BF16              equ 0x023   ; 16-bit brain float (Google/Intel)
DTYPE_TF32              equ 0x024   ; 19-bit tensor float (NVIDIA Ampere+)
DTYPE_FP32              equ 0x025   ; 32-bit single precision float
DTYPE_FP64              equ 0x026   ; 64-bit double precision float
DTYPE_FP128             equ 0x027   ; 128-bit quad precision float

; =============================================================================
; FP8 FNUZ variants         0x028–0x02B
; =============================================================================

DTYPE_FP8_E4M3_FNUZ     equ 0x028   ; FP8 E4M3 no-inf no-NaN unsigned-zero
DTYPE_FP8_E5M2_FNUZ     equ 0x029   ; FP8 E5M2 no-inf no-NaN unsigned-zero
DTYPE_BFLOAT8           equ 0x02A   ; 8-bit brain float variant
DTYPE_MINIFLOAT         equ 0x02B   ; generic minifloat placeholder

; =============================================================================
; scalar FP6                0x02C–0x02D
; =============================================================================

DTYPE_FP6_E2M3          equ 0x02C   ; 6-bit float E2M3 (mantissa focused)
DTYPE_FP6_E3M2          equ 0x02D   ; 6-bit float E3M2 (range focused)

; =============================================================================
; OCP microscaling family   0x030–0x03B
; =============================================================================

DTYPE_MXFP8_E4M3        equ 0x030   ; MX FP8 E4M3 block-scaled (block=32)
DTYPE_MXFP8_E5M2        equ 0x031   ; MX FP8 E5M2 block-scaled (block=32)
DTYPE_MXFP6_E2M3        equ 0x032   ; MX FP6 E2M3 block-scaled (block=32)
DTYPE_MXFP6_E3M2        equ 0x033   ; MX FP6 E3M2 block-scaled (block=32)
DTYPE_MXFP4_E2M1        equ 0x034   ; MX FP4 E2M1 block-scaled (block=32)
DTYPE_MXINT8            equ 0x035   ; MX INT8 block-scaled (block=32)
DTYPE_MXINT6            equ 0x036   ; MX INT6 block-scaled (block=32)
DTYPE_MXINT4            equ 0x037   ; MX INT4 block-scaled (block=32)
DTYPE_UE8M0             equ 0x038   ; unsigned E8M0 scale factor (MX scales)
DTYPE_NVFP4             equ 0x039   ; NVIDIA FP4 (block=16, E4M3 scale)
DTYPE_NVINT4            equ 0x03A   ; NVIDIA INT4 (block=16)
DTYPE_NVFP8             equ 0x03B   ; NVIDIA FP8 (OFP8 pre-MX)

; =============================================================================
; fixed point family        0x040–0x046
; =============================================================================

DTYPE_Q4_0              equ 0x040   ; 4-bit fixed point zero-centered
DTYPE_Q4_1              equ 0x041   ; 4-bit fixed point with offset
DTYPE_Q5_0              equ 0x042   ; 5-bit fixed point zero-centered
DTYPE_Q5_1              equ 0x043   ; 5-bit fixed point with offset
DTYPE_Q8_0              equ 0x044   ; 8-bit fixed point (llama.cpp style)
DTYPE_BIT_PACKED        equ 0x045   ; arbitrary bit-width packed value
DTYPE_DELTA_ENC         equ 0x046   ; delta encoded value

; =============================================================================
; normalized / probability  0x050–0x056
; =============================================================================

DTYPE_UNORM8            equ 0x050   ; unsigned normalized [0,1] 8-bit
DTYPE_UNORM16           equ 0x051   ; unsigned normalized [0,1] 16-bit
DTYPE_SNORM8            equ 0x052   ; signed normalized [-1,1] 8-bit
DTYPE_SNORM16           equ 0x053   ; signed normalized [-1,1] 16-bit
DTYPE_PROB32            equ 0x054   ; probability value [0,1] FP32
DTYPE_LOG_PROB32        equ 0x055   ; log probability (numerically stable)
DTYPE_FUZZY             equ 0x056   ; fuzzy logic value [0,1]

; =============================================================================
; complex family            0x060–0x068
; =============================================================================

DTYPE_CI8               equ 0x060   ; complex INT8  (re:i8,  im:i8)
DTYPE_CI16              equ 0x061   ; complex INT16 (re:i16, im:i16)
DTYPE_CI32              equ 0x062   ; complex INT32 (re:i32, im:i32)
DTYPE_CF16              equ 0x063   ; complex FP16  (re:f16, im:f16)
DTYPE_CBF16             equ 0x064   ; complex BF16  (re:bf16, im:bf16)
DTYPE_CF32              equ 0x065   ; complex FP32  (re:f32, im:f32)
DTYPE_CF64              equ 0x066   ; complex FP64  (re:f64, im:f64)
DTYPE_CF128             equ 0x067   ; complex FP128 (re:f128, im:f128)
DTYPE_CI64              equ 0x068   ; complex INT64 (re:i64, im:i64)

; =============================================================================
; packed SIMD family        0x070–0x077
; =============================================================================

DTYPE_PACK_INT4x2       equ 0x070   ; two  INT4  packed in INT8
DTYPE_PACK_INT4x8       equ 0x071   ; eight INT4  packed in INT32
DTYPE_PACK_INT4x16      equ 0x072   ; sixteen INT4 packed in INT64
DTYPE_PACK_FP8x2        equ 0x073   ; two  FP8   packed in INT16
DTYPE_PACK_FP8x4        equ 0x074   ; four FP8   packed in INT32
DTYPE_PACK_BF16x2       equ 0x075   ; two  BF16  packed in INT32
DTYPE_PACK_INT8x4       equ 0x076   ; four INT8  packed in INT32
DTYPE_PACK_INT16x2      equ 0x077   ; two  INT16 packed in INT32

; =============================================================================
; Galois fields / modular   0x080–0x08F
; =============================================================================

DTYPE_GF2               equ 0x080   ; GF(2) binary field element
DTYPE_GFP               equ 0x081   ; GF(p) prime field element
DTYPE_GF2N              equ 0x082   ; GF(2^n) extension field element
DTYPE_GF2_128           equ 0x083   ; GF(2^128) for AES-GCM
DTYPE_GF2_256           equ 0x084   ; GF(2^256)
DTYPE_GF2_POLY          equ 0x085   ; GF(2) polynomial
DTYPE_GFQ_ELEM          equ 0x086   ; GF(q) element generic
DTYPE_ZMOD              equ 0x087   ; Z/nZ residue class
DTYPE_MONTGOMERY        equ 0x088   ; Montgomery form element
DTYPE_BARRETT           equ 0x089   ; Barrett reduction form
DTYPE_SCALAR_FIELD      equ 0x08A   ; scalar field element (ECC)
DTYPE_BASE_FIELD        equ 0x08B   ; base field element (ECC)

; =============================================================================
; post-quantum crypto       0x090–0x097
; =============================================================================

DTYPE_PROJ_COORD        equ 0x090   ; projective coordinates (ECC)
DTYPE_EXT_COORD         equ 0x091   ; extended coordinates (ECC)
DTYPE_JACOBIAN          equ 0x092   ; Jacobian coordinates (ECC)
DTYPE_KYBER_POLY        equ 0x093   ; Kyber polynomial ring element
DTYPE_DILITH_POLY       equ 0x094   ; Dilithium polynomial
DTYPE_NTRU_POLY         equ 0x095   ; NTRU polynomial
DTYPE_FALCON_POLY       equ 0x096   ; Falcon polynomial
DTYPE_RLWE_POLY         equ 0x097   ; RLWE polynomial
DTYPE_LWE_SAMPLE        equ 0x098   ; LWE sample pair (a,b)

; =============================================================================
; coding theory             0x0A0–0x0A7
; =============================================================================

DTYPE_RS_SYMBOL         equ 0x0A0   ; Reed-Solomon symbol
DTYPE_BCH_WORD          equ 0x0A1   ; BCH codeword
DTYPE_LDPC_BIT          equ 0x0A2   ; LDPC bit (soft/hard decision)
DTYPE_LLR               equ 0x0A3   ; log-likelihood ratio
DTYPE_POLAR_BIT         equ 0x0A4   ; Polar code bit
DTYPE_TURBO_SYMBOL      equ 0x0A5   ; Turbo code symbol
DTYPE_VITERBI_STATE     equ 0x0A6   ; Viterbi trellis state
DTYPE_HAMMING_WORD      equ 0x0A7   ; Hamming codeword

; =============================================================================
; arbitrary precision       0x0B0–0x0B9
; =============================================================================

DTYPE_BIGINT            equ 0x0B0   ; arbitrary precision integer
DTYPE_BIGFLOAT          equ 0x0B1   ; arbitrary precision float
DTYPE_RATIONAL          equ 0x0B2   ; exact rational (p/q form)
DTYPE_PADIC             equ 0x0B3   ; p-adic number
DTYPE_SURREAL           equ 0x0B4   ; surreal number {L|R}
DTYPE_HYPERREAL         equ 0x0B5   ; hyperreal number
DTYPE_ORDINAL           equ 0x0B6   ; ordinal number
DTYPE_CARDINAL          equ 0x0B7   ; cardinal number

; =============================================================================
; alternative number systems 0x0C0–0x0C9
; =============================================================================

DTYPE_POSIT8            equ 0x0C0   ; Posit 8-bit
DTYPE_POSIT16           equ 0x0C1   ; Posit 16-bit
DTYPE_POSIT32           equ 0x0C2   ; Posit 32-bit
DTYPE_POSIT64           equ 0x0C3   ; Posit 64-bit
DTYPE_POSIT128          equ 0x0C4   ; Posit 128-bit
DTYPE_POSIT256          equ 0x0C5   ; Posit 256-bit
DTYPE_UNUM1             equ 0x0C6   ; Unum Type 1 (Gustafson)
DTYPE_UNUM2             equ 0x0C7   ; Unum Type 2
DTYPE_VALID             equ 0x0C8   ; Valid (interval posit)
DTYPE_LNS8              equ 0x0C9   ; Logarithmic Number System 8-bit
DTYPE_LNS16             equ 0x0CA   ; Logarithmic Number System 16-bit
DTYPE_LNS32             equ 0x0CB   ; Logarithmic Number System 32-bit
DTYPE_DBNS              equ 0x0CC   ; Double Base Number System
DTYPE_STOCHASTIC        equ 0x0CD   ; stochastic number [0,1]

; =============================================================================
; interval / differential   0x0D0–0x0D6
; =============================================================================

DTYPE_INTERVAL_F32      equ 0x0D0   ; FP32 interval [lo, hi]
DTYPE_INTERVAL_F64      equ 0x0D1   ; FP64 interval [lo, hi]
DTYPE_INTERVAL_INT      equ 0x0D2   ; integer interval [lo, hi]
DTYPE_DUAL              equ 0x0D3   ; dual number (forward AD order 1)
DTYPE_HYPERDUAL         equ 0x0D4   ; hyperdual (forward AD order 2)
DTYPE_MULTIDUAL         equ 0x0D5   ; multi-variable dual number
DTYPE_TROPICAL_INT      equ 0x0D6   ; tropical integer (min,+) semiring
DTYPE_TROPICAL_FLOAT    equ 0x0D7   ; tropical float

; =============================================================================
; geometric types           0x0E0–0x0EF
; =============================================================================

DTYPE_QUAT_F32          equ 0x0E0   ; quaternion (4×FP32)
DTYPE_QUAT_F64          equ 0x0E1   ; quaternion (4×FP64)
DTYPE_DUAL_QUAT         equ 0x0E2   ; dual quaternion (8×FP32)
DTYPE_OCTONION          equ 0x0E3   ; octonion (8×FP64)
DTYPE_SEDENION          equ 0x0E4   ; sedenion (16×FP64)
DTYPE_BIVECTOR          equ 0x0E5   ; geometric algebra bivector
DTYPE_TRIVECTOR         equ 0x0E6   ; geometric algebra trivector
DTYPE_MULTIVEC          equ 0x0E7   ; full multivector
DTYPE_ROTOR             equ 0x0E8   ; rotor (even subalgebra)
DTYPE_SPINOR            equ 0x0E9   ; spinor
DTYPE_VERSOR            equ 0x0EA   ; versor
DTYPE_TANGENT           equ 0x0EB   ; tangent vector
DTYPE_COTANGENT         equ 0x0EC   ; cotangent vector
DTYPE_FORM_1            equ 0x0ED   ; differential 1-form
DTYPE_FORM_2            equ 0x0EE   ; differential 2-form
DTYPE_FORM_3            equ 0x0EF   ; differential 3-form

; =============================================================================
; sparse formats            0x0F0–0x0FB
; =============================================================================

DTYPE_CSR_VAL           equ 0x0F0   ; CSR format value array element
DTYPE_CSR_IDX           equ 0x0F1   ; CSR format index array element
DTYPE_CSC_VAL           equ 0x0F2   ; CSC format value
DTYPE_CSC_IDX           equ 0x0F3   ; CSC format index
DTYPE_COO_VAL           equ 0x0F4   ; COO format value
DTYPE_COO_ROW           equ 0x0F5   ; COO format row index
DTYPE_COO_COL           equ 0x0F6   ; COO format col index
DTYPE_BSR_VAL           equ 0x0F7   ; Block Sparse Row value
DTYPE_ELL_VAL           equ 0x0F8   ; ELLPACK format value
DTYPE_DIA_VAL           equ 0x0F9   ; Diagonal format value
DTYPE_SPARSE_VAL        equ 0x0FA   ; generic sparse value
DTYPE_SPARSE_IDX        equ 0x0FB   ; generic sparse index

; =============================================================================
; GGUF quantization         0x100–0x10F
; =============================================================================

DTYPE_GGUF_Q2K          equ 0x100   ; GGUF Q2_K quantization
DTYPE_GGUF_Q3K          equ 0x101   ; GGUF Q3_K quantization
DTYPE_GGUF_Q4K          equ 0x102   ; GGUF Q4_K quantization
DTYPE_GGUF_Q5K          equ 0x103   ; GGUF Q5_K quantization
DTYPE_GGUF_Q6K          equ 0x104   ; GGUF Q6_K quantization
DTYPE_GGUF_Q8K          equ 0x105   ; GGUF Q8_K quantization
DTYPE_GGUF_IQ1S         equ 0x106   ; importance-quantized 1-bit
DTYPE_GGUF_IQ2XXS       equ 0x107   ; importance-quantized 2-bit
DTYPE_GGUF_IQ3XXS       equ 0x108   ; importance-quantized 3-bit
DTYPE_GGUF_IQ4NL        equ 0x109   ; importance-quantized 4-bit non-linear
DTYPE_BLOCKED_FP8       equ 0x10A   ; block-scaled FP8 (generic)
DTYPE_AMX_TILE          equ 0x10B   ; Intel AMX tile format
DTYPE_VNNI_BLOCK        equ 0x10C   ; VNNI computation block

; =============================================================================
; quantum computing         0x110–0x112
; =============================================================================

DTYPE_QBIT              equ 0x110   ; qubit state (CF64 pair α,β)
DTYPE_DENSITY           equ 0x111   ; density matrix element
DTYPE_KET               equ 0x112   ; quantum state vector dtype

; =============================================================================
; graphics / pixel          0x120–0x12B
; =============================================================================

DTYPE_RGB8              equ 0x120   ; 3×UINT8 packed RGB
DTYPE_RGBA8             equ 0x121   ; 4×UINT8 packed RGBA
DTYPE_RGB16F            equ 0x122   ; 3×FP16 packed RGB
DTYPE_RGBA16F           equ 0x123   ; 4×FP16 packed RGBA
DTYPE_R11G11B10F        equ 0x124   ; packed float GPU format
DTYPE_RGB9E5            equ 0x125   ; shared exponent float
DTYPE_DEPTH16           equ 0x126   ; depth buffer 16-bit
DTYPE_DEPTH32F          equ 0x127   ; depth buffer FP32
DTYPE_DEPTH24S8         equ 0x128   ; depth 24-bit + stencil 8-bit
DTYPE_HALF4             equ 0x129   ; packed 4×FP16 (RGBA)
DTYPE_BYTE4             equ 0x12A   ; packed 4×UINT8 (RGBA)
DTYPE_HALF2             equ 0x12B   ; packed 2×FP16

; =============================================================================
; audio / signal            0x130–0x139
; =============================================================================

DTYPE_PCM8              equ 0x130   ; 8-bit PCM audio sample
DTYPE_PCM16             equ 0x131   ; 16-bit PCM audio sample
DTYPE_PCM24             equ 0x132   ; 24-bit PCM audio sample
DTYPE_PCM32             equ 0x133   ; 32-bit PCM audio sample
DTYPE_FLOAT_AUDIO       equ 0x134   ; normalized FP32 audio [-1,1]
DTYPE_ULAW              equ 0x135   ; μ-law compressed audio
DTYPE_ALAW              equ 0x136   ; A-law compressed audio
DTYPE_TIMESTAMP         equ 0x137   ; nanosecond timestamp
DTYPE_FREQUENCY         equ 0x138   ; frequency value (Hz)
DTYPE_PHASE             equ 0x139   ; phase angle (radians)

; =============================================================================
; abstract math             0x140–0x14F
; =============================================================================

DTYPE_MORPHISM          equ 0x140   ; morphism representation
DTYPE_FUNCTOR_VAL       equ 0x141   ; functor value
DTYPE_NAT_TRANS         equ 0x142   ; natural transformation
DTYPE_MEASURE           equ 0x143   ; measure value
DTYPE_SIGNED_MEAS       equ 0x144   ; signed measure
DTYPE_PROB_MEAS         equ 0x145   ; probability measure
DTYPE_UTILITY           equ 0x146   ; game theory utility value
DTYPE_STRATEGY          equ 0x147   ; game theory strategy
DTYPE_PAYOFF            equ 0x148   ; game theory payoff element
DTYPE_SAMPLE_PATH       equ 0x149   ; stochastic sample path element
DTYPE_TRANSITION        equ 0x14A   ; transition probability
DTYPE_GENERATOR         equ 0x14B   ; infinitesimal generator
DTYPE_TYPE_IDX          equ 0x14C   ; type theory type index
DTYPE_UNIVERSE          equ 0x14D   ; universe level (HoTT)
DTYPE_IDENTITY          equ 0x14E   ; identity type element

; =============================================================================
; compressed storage        0x150–0x153
; =============================================================================

DTYPE_RLE_BLOCK         equ 0x150   ; run-length encoded block
DTYPE_ZSTD_BLOCK        equ 0x151   ; Zstd compressed block
DTYPE_DICT_ENC          equ 0x152   ; dictionary encoded value
DTYPE_BIT_PACKED_BLK    equ 0x153   ; arbitrary bit-width packed block

; =============================================================================
; reserved ranges
; =============================================================================

; 0x154–0xEFF  future defined types         (do not use)
; 0xF00–0xFF0  future hardware formats      (do not use)
; 0xFF1–0xFFD  user defined types
DTYPE_USER_BASE         equ 0xFF1   ; start of user-defined range

; =============================================================================
; sentinels
; =============================================================================

DTYPE_UNKNOWN           equ 0xFFE   ; unknown / unrecognized dtype
DTYPE_MAX               equ 0xFFF   ; range check sentinel (exclusive)

; =============================================================================
; convenience aliases
; =============================================================================

; common ML aliases
DTYPE_HALF              equ DTYPE_FP16
DTYPE_FLOAT             equ DTYPE_FP32
DTYPE_DOUBLE            equ DTYPE_FP64
DTYPE_BYTE              equ DTYPE_INT8
DTYPE_UBYTE             equ DTYPE_UINT8
DTYPE_SHORT             equ DTYPE_INT16
DTYPE_INT               equ DTYPE_INT32
DTYPE_LONG              equ DTYPE_INT64
DTYPE_BOOL              equ DTYPE_INT1

; numpy-style aliases
DTYPE_FLOAT16           equ DTYPE_FP16
DTYPE_FLOAT32           equ DTYPE_FP32
DTYPE_FLOAT64           equ DTYPE_FP64
DTYPE_INT8_T            equ DTYPE_INT8
DTYPE_INT16_T           equ DTYPE_INT16
DTYPE_INT32_T           equ DTYPE_INT32
DTYPE_INT64_T           equ DTYPE_INT64
DTYPE_UINT8_T           equ DTYPE_UINT8
DTYPE_UINT16_T          equ DTYPE_UINT16
DTYPE_UINT32_T          equ DTYPE_UINT32
DTYPE_UINT64_T          equ DTYPE_UINT64

; PyTorch-style aliases
DTYPE_TORCH_FLOAT       equ DTYPE_FP32
DTYPE_TORCH_DOUBLE      equ DTYPE_FP64
DTYPE_TORCH_HALF        equ DTYPE_FP16
DTYPE_TORCH_BFLOAT16    equ DTYPE_BF16
DTYPE_TORCH_INT8        equ DTYPE_INT8
DTYPE_TORCH_INT16       equ DTYPE_INT16
DTYPE_TORCH_INT32       equ DTYPE_INT32
DTYPE_TORCH_INT64       equ DTYPE_INT64
DTYPE_TORCH_BOOL        equ DTYPE_INT1
DTYPE_TORCH_CFLOAT      equ DTYPE_CF32
DTYPE_TORCH_CDOUBLE     equ DTYPE_CF64