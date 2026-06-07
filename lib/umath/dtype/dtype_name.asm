; =============================================================================
; umath - unified math library
; dtype/dtype_name.asm - dtype string name lookup
; =============================================================================
; dependencies:
;   dtype_id.asm
;   charset/ (for UTF-8 name output)
;
; description:
;   bidirectional mapping between dtype_id and string names
;   supports multiple name formats:
;     short:  "fp32", "i8", "bf16"
;     full:   "float32", "int8", "bfloat16"
;     torch:  "torch.float32", "torch.int8"
;     numpy:  "float32", "int8", "complex64"
;     pretty: "FP32", "INT8", "BF16"
;     utf8:   "FP32", "ℝ³²" etc (future)
;
; functions:
;   umath_dtype_name_short     (dtype_id → *char) "fp32"
;   umath_dtype_name_full      (dtype_id → *char) "float32"
;   umath_dtype_name_pretty    (dtype_id → *char) "FP32"
;   umath_dtype_name_torch     (dtype_id → *char) "torch.float32"
;   umath_dtype_name_numpy     (dtype_id → *char) "float32"
;   umath_dtype_from_name      (*char → dtype_id) parse any format
;   umath_dtype_from_name_len  (*char, len → dtype_id) bounded parse
; =============================================================================

%include "dtype_id.asm"

bits 64

; =============================================================================
; string data section
; =============================================================================

section .rodata
align 8

; =============================================================================
; short name table (pointer per dtype_id)
; =============================================================================

; --- string pool ---
str_none:           db "none",0
str_int1:           db "int1",0
str_int2:           db "int2",0
str_int4:           db "int4",0
str_int8:           db "int8",0
str_int16:          db "int16",0
str_int32:          db "int32",0
str_int64:          db "int64",0
str_int128:         db "int128",0
str_int256:         db "int256",0
str_uint4:          db "uint4",0
str_uint8:          db "uint8",0
str_uint16:         db "uint16",0
str_uint32:         db "uint32",0
str_uint64:         db "uint64",0
str_uint128:        db "uint128",0
str_uint256:        db "uint256",0
str_uint512:        db "uint512",0
str_uint1024:       db "uint1024",0
str_uint2048:       db "uint2048",0
str_fp8_e4m3:       db "fp8_e4m3",0
str_fp8_e5m2:       db "fp8_e5m2",0
str_fp16:           db "fp16",0
str_bf16:           db "bf16",0
str_tf32:           db "tf32",0
str_fp32:           db "fp32",0
str_fp64:           db "fp64",0
str_fp128:          db "fp128",0
str_fp8e4m3fnuz:    db "fp8_e4m3_fnuz",0
str_fp8e5m2fnuz:    db "fp8_e5m2_fnuz",0
str_bfloat8:        db "bfloat8",0
str_minifloat:      db "minifloat",0
str_fp6_e2m3:       db "fp6_e2m3",0
str_fp6_e3m2:       db "fp6_e3m2",0
str_mxfp8_e4m3:     db "mxfp8_e4m3",0
str_mxfp8_e5m2:     db "mxfp8_e5m2",0
str_mxfp6_e2m3:     db "mxfp6_e2m3",0
str_mxfp6_e3m2:     db "mxfp6_e3m2",0
str_mxfp4_e2m1:     db "mxfp4_e2m1",0
str_mxint8:         db "mxint8",0
str_mxint6:         db "mxint6",0
str_mxint4:         db "mxint4",0
str_ue8m0:          db "ue8m0",0
str_nvfp4:          db "nvfp4",0
str_nvint4:         db "nvint4",0
str_nvfp8:          db "nvfp8",0
str_q4_0:           db "q4_0",0
str_q4_1:           db "q4_1",0
str_q5_0:           db "q5_0",0
str_q5_1:           db "q5_1",0
str_q8_0:           db "q8_0",0
str_bit_packed:     db "bit_packed",0
str_delta_enc:      db "delta_enc",0
str_unorm8:         db "unorm8",0
str_unorm16:        db "unorm16",0
str_snorm8:         db "snorm8",0
str_snorm16:        db "snorm16",0
str_prob32:         db "prob32",0
str_log_prob32:     db "log_prob32",0
str_fuzzy:          db "fuzzy",0
str_ci8:            db "ci8",0
str_ci16:           db "ci16",0
str_ci32:           db "ci32",0
str_cf16:           db "cf16",0
str_cbf16:          db "cbf16",0
str_cf32:           db "cf32",0
str_cf64:           db "cf64",0
str_cf128:          db "cf128",0
str_ci64:           db "ci64",0
str_pack_int4x2:    db "int4x2",0
str_pack_int4x8:    db "int4x8",0
str_pack_int4x16:   db "int4x16",0
str_pack_fp8x2:     db "fp8x2",0
str_pack_fp8x4:     db "fp8x4",0
str_pack_bf16x2:    db "bf16x2",0
str_pack_int8x4:    db "int8x4",0
str_pack_int16x2:   db "int16x2",0
str_gf2:            db "gf2",0
str_gfp:            db "gfp",0
str_gf2n:           db "gf2n",0
str_gf2_128:        db "gf2_128",0
str_gf2_256:        db "gf2_256",0
str_gf2_poly:       db "gf2_poly",0
str_gfq_elem:       db "gfq_elem",0
str_zmod:           db "zmod",0
str_montgomery:     db "montgomery",0
str_barrett:        db "barrett",0
str_scalar_field:   db "scalar_field",0
str_base_field:     db "base_field",0
str_proj_coord:     db "proj_coord",0
str_ext_coord:      db "ext_coord",0
str_jacobian:       db "jacobian",0
str_kyber_poly:     db "kyber_poly",0
str_dilith_poly:    db "dilith_poly",0
str_ntru_poly:      db "ntru_poly",0
str_falcon_poly:    db "falcon_poly",0
str_rlwe_poly:      db "rlwe_poly",0
str_lwe_sample:     db "lwe_sample",0
str_rs_symbol:      db "rs_symbol",0
str_bch_word:       db "bch_word",0
str_ldpc_bit:       db "ldpc_bit",0
str_llr:            db "llr",0
str_polar_bit:      db "polar_bit",0
str_turbo_symbol:   db "turbo_symbol",0
str_viterbi_state:  db "viterbi_state",0
str_hamming_word:   db "hamming_word",0
str_bigint:         db "bigint",0
str_bigfloat:       db "bigfloat",0
str_rational:       db "rational",0
str_padic:          db "padic",0
str_surreal:        db "surreal",0
str_hyperreal:      db "hyperreal",0
str_ordinal:        db "ordinal",0
str_cardinal:       db "cardinal",0
str_posit8:         db "posit8",0
str_posit16:        db "posit16",0
str_posit32:        db "posit32",0
str_posit64:        db "posit64",0
str_posit128:       db "posit128",0
str_posit256:       db "posit256",0
str_unum1:          db "unum1",0
str_unum2:          db "unum2",0
str_valid:          db "valid",0
str_lns8:           db "lns8",0
str_lns16:          db "lns16",0
str_lns32:          db "lns32",0
str_dbns:           db "dbns",0
str_stochastic:     db "stochastic",0
str_interval_f32:   db "interval_f32",0
str_interval_f64:   db "interval_f64",0
str_interval_int:   db "interval_int",0
str_dual:           db "dual",0
str_hyperdual:      db "hyperdual",0
str_multidual:      db "multidual",0
str_trop_int:       db "trop_int",0
str_trop_float:     db "trop_float",0
str_quat_f32:       db "quat_f32",0
str_quat_f64:       db "quat_f64",0
str_dual_quat:      db "dual_quat",0
str_octonion:       db "octonion",0
str_sedenion:       db "sedenion",0
str_bivector:       db "bivector",0
str_trivector:      db "trivector",0
str_multivec:       db "multivec",0
str_rotor:          db "rotor",0
str_spinor:         db "spinor",0
str_versor:         db "versor",0
str_tangent:        db "tangent",0
str_cotangent:      db "cotangent",0
str_form_1:         db "form_1",0
str_form_2:         db "form_2",0
str_form_3:         db "form_3",0
str_csr_val:        db "csr_val",0
str_csr_idx:        db "csr_idx",0
str_csc_val:        db "csc_val",0
str_csc_idx:        db "csc_idx",0
str_coo_val:        db "coo_val",0
str_coo_row:        db "coo_row",0
str_coo_col:        db "coo_col",0
str_bsr_val:        db "bsr_val",0
str_ell_val:        db "ell_val",0
str_dia_val:        db "dia_val",0
str_sparse_val:     db "sparse_val",0
str_sparse_idx:     db "sparse_idx",0
str_gguf_q2k:       db "gguf_q2k",0
str_gguf_q3k:       db "gguf_q3k",0
str_gguf_q4k:       db "gguf_q4k",0
str_gguf_q5k:       db "gguf_q5k",0
str_gguf_q6k:       db "gguf_q6k",0
str_gguf_q8k:       db "gguf_q8k",0
str_gguf_iq1s:      db "gguf_iq1s",0
str_gguf_iq2xxs:    db "gguf_iq2xxs",0
str_gguf_iq3xxs:    db "gguf_iq3xxs",0
str_gguf_iq4nl:     db "gguf_iq4nl",0
str_blocked_fp8:    db "blocked_fp8",0
str_amx_tile:       db "amx_tile",0
str_vnni_block:     db "vnni_block",0
str_qbit:           db "qbit",0
str_density:        db "density",0
str_ket:            db "ket",0
str_rgb8:           db "rgb8",0
str_rgba8:          db "rgba8",0
str_rgb16f:         db "rgb16f",0
str_rgba16f:        db "rgba16f",0
str_r11g11b10f:     db "r11g11b10f",0
str_rgb9e5:         db "rgb9e5",0
str_depth16:        db "depth16",0
str_depth32f:       db "depth32f",0
str_depth24s8:      db "depth24s8",0
str_half4:          db "half4",0
str_byte4:          db "byte4",0
str_half2:          db "half2",0
str_pcm8:           db "pcm8",0
str_pcm16:          db "pcm16",0
str_pcm24:          db "pcm24",0
str_pcm32:          db "pcm32",0
str_float_audio:    db "float_audio",0
str_ulaw:           db "ulaw",0
str_alaw:           db "alaw",0
str_timestamp:      db "timestamp",0
str_frequency:      db "frequency",0
str_phase:          db "phase",0
str_morphism:       db "morphism",0
str_functor_val:    db "functor_val",0
str_nat_trans:      db "nat_trans",0
str_measure:        db "measure",0
str_signed_meas:    db "signed_meas",0
str_prob_meas:      db "prob_meas",0
str_utility:        db "utility",0
str_strategy:       db "strategy",0
str_payoff:         db "payoff",0
str_sample_path:    db "sample_path",0
str_transition:     db "transition",0
str_generator:      db "generator",0
str_type_idx:       db "type_idx",0
str_universe:       db "universe",0
str_identity:       db "identity",0
str_rle_block:      db "rle_block",0
str_zstd_block:     db "zstd_block",0
str_dict_enc:       db "dict_enc",0
str_bit_packed_blk: db "bit_packed_blk",0
str_unknown_dtype:  db "unknown",0
str_user_dtype:     db "user",0

; =============================================================================
; short name pointer table indexed by dtype_id
; =============================================================================

align 8
dtype_short_name_table:
    dq str_none                 ; 0x000 NONE
    dq str_int1                 ; 0x001
    dq str_int2                 ; 0x002
    dq str_int4                 ; 0x003
    dq str_int8                 ; 0x004
    dq str_int16                ; 0x005
    dq str_int32                ; 0x006
    dq str_int64                ; 0x007
    dq str_int128               ; 0x008
    dq str_int256               ; 0x009
    times 6 dq str_unknown_dtype ; 0x00A-0x00F
    dq str_uint4                ; 0x010
    dq str_uint8                ; 0x011
    dq str_uint16               ; 0x012
    dq str_uint32               ; 0x013
    dq str_uint64               ; 0x014
    dq str_uint128              ; 0x015
    dq str_uint256              ; 0x016
    dq str_uint512              ; 0x017
    dq str_uint1024             ; 0x018
    dq str_uint2048             ; 0x019
    times 6 dq str_unknown_dtype ; 0x01A-0x01F
    dq str_fp8_e4m3             ; 0x020
    dq str_fp8_e5m2             ; 0x021
    dq str_fp16                 ; 0x022
    dq str_bf16                 ; 0x023
    dq str_tf32                 ; 0x024
    dq str_fp32                 ; 0x025
    dq str_fp64                 ; 0x026
    dq str_fp128                ; 0x027
    dq str_fp8e4m3fnuz          ; 0x028
    dq str_fp8e5m2fnuz          ; 0x029
    dq str_bfloat8              ; 0x02A
    dq str_minifloat            ; 0x02B
    dq str_fp6_e2m3             ; 0x02C
    dq str_fp6_e3m2             ; 0x02D
    times 2 dq str_unknown_dtype ; 0x02E-0x02F
    dq str_mxfp8_e4m3           ; 0x030
    dq str_mxfp8_e5m2           ; 0x031
    dq str_mxfp6_e2m3           ; 0x032
    dq str_mxfp6_e3m2           ; 0x033
    dq str_mxfp4_e2m1           ; 0x034
    dq str_mxint8               ; 0x035
    dq str_mxint6               ; 0x036
    dq str_mxint4               ; 0x037
    dq str_ue8m0                ; 0x038
    dq str_nvfp4                ; 0x039
    dq str_nvint4               ; 0x03A
    dq str_nvfp8                ; 0x03B
    times 4 dq str_unknown_dtype ; 0x03C-0x03F
    dq str_q4_0                 ; 0x040
    dq str_q4_1                 ; 0x041
    dq str_q5_0                 ; 0x042
    dq str_q5_1                 ; 0x043
    dq str_q8_0                 ; 0x044
    dq str_bit_packed           ; 0x045
    dq str_delta_enc            ; 0x046
    times 9 dq str_unknown_dtype ; 0x047-0x04F
    dq str_unorm8               ; 0x050
    dq str_unorm16              ; 0x051
    dq str_snorm8               ; 0x052
    dq str_snorm16              ; 0x053
    dq str_prob32               ; 0x054
    dq str_log_prob32           ; 0x055
    dq str_fuzzy                ; 0x056
    times 9 dq str_unknown_dtype ; 0x057-0x05F
    dq str_ci8                  ; 0x060
    dq str_ci16                 ; 0x061
    dq str_ci32                 ; 0x062
    dq str_cf16                 ; 0x063
    dq str_cbf16                ; 0x064
    dq str_cf32                 ; 0x065
    dq str_cf64                 ; 0x066
    dq str_cf128                ; 0x067
    dq str_ci64                 ; 0x068
    times 7 dq str_unknown_dtype ; 0x069-0x06F
    dq str_pack_int4x2          ; 0x070
    dq str_pack_int4x8          ; 0x071
    dq str_pack_int4x16         ; 0x072
    dq str_pack_fp8x2           ; 0x073
    dq str_pack_fp8x4           ; 0x074
    dq str_pack_bf16x2          ; 0x075
    dq str_pack_int8x4          ; 0x076
    dq str_pack_int16x2         ; 0x077
    times 8 dq str_unknown_dtype ; 0x078-0x07F
    dq str_gf2                  ; 0x080
    dq str_gfp                  ; 0x081
    dq str_gf2n                 ; 0x082
    dq str_gf2_128              ; 0x083
    dq str_gf2_256              ; 0x084
    dq str_gf2_poly             ; 0x085
    dq str_gfq_elem             ; 0x086
    dq str_zmod                 ; 0x087
    dq str_montgomery           ; 0x088
    dq str_barrett              ; 0x089
    dq str_scalar_field         ; 0x08A
    dq str_base_field           ; 0x08B
    times 4 dq str_unknown_dtype ; 0x08C-0x08F
    dq str_proj_coord           ; 0x090
    dq str_ext_coord            ; 0x091
    dq str_jacobian             ; 0x092
    dq str_kyber_poly           ; 0x093
    dq str_dilith_poly          ; 0x094
    dq str_ntru_poly            ; 0x095
    dq str_falcon_poly          ; 0x096
    dq str_rlwe_poly            ; 0x097
    dq str_lwe_sample           ; 0x098
    times 7 dq str_unknown_dtype ; 0x099-0x09F
    dq str_rs_symbol            ; 0x0A0
    dq str_bch_word             ; 0x0A1
    dq str_ldpc_bit             ; 0x0A2
    dq str_llr                  ; 0x0A3
    dq str_polar_bit            ; 0x0A4
    dq str_turbo_symbol         ; 0x0A5
    dq str_viterbi_state        ; 0x0A6
    dq str_hamming_word         ; 0x0A7
    times 8 dq str_unknown_dtype ; 0x0A8-0x0AF
    dq str_bigint               ; 0x0B0
    dq str_bigfloat             ; 0x0B1
    dq str_rational             ; 0x0B2
    dq str_padic                ; 0x0B3
    dq str_surreal              ; 0x0B4
    dq str_hyperreal            ; 0x0B5
    dq str_ordinal              ; 0x0B6
    dq str_cardinal             ; 0x0B7
    times 8 dq str_unknown_dtype ; 0x0B8-0x0BF
    dq str_posit8               ; 0x0C0
    dq str_posit16              ; 0x0C1
    dq str_posit32              ; 0x0C2
    dq str_posit64              ; 0x0C3
    dq str_posit128             ; 0x0C4
    dq str_posit256             ; 0x0C5
    dq str_unum1                ; 0x0C6
    dq str_unum2                ; 0x0C7
    dq str_valid                ; 0x0C8
    dq str_lns8                 ; 0x0C9
    dq str_lns16                ; 0x0CA
    dq str_lns32                ; 0x0CB
    dq str_dbns                 ; 0x0CC
    dq str_stochastic           ; 0x0CD
    times 2 dq str_unknown_dtype ; 0x0CE-0x0CF
    dq str_interval_f32         ; 0x0D0
    dq str_interval_f64         ; 0x0D1
    dq str_interval_int         ; 0x0D2
    dq str_dual                 ; 0x0D3
    dq str_hyperdual            ; 0x0D4
    dq str_multidual            ; 0x0D5
    dq str_trop_int             ; 0x0D6
    dq str_trop_float           ; 0x0D7
    times 8 dq str_unknown_dtype ; 0x0D8-0x0DF
    dq str_quat_f32             ; 0x0E0
    dq str_quat_f64             ; 0x0E1
    dq str_dual_quat            ; 0x0E2
    dq str_octonion             ; 0x0E3
    dq str_sedenion             ; 0x0E4
    dq str_bivector             ; 0x0E5
    dq str_trivector            ; 0x0E6
    dq str_multivec             ; 0x0E7
    dq str_rotor                ; 0x0E8
    dq str_spinor               ; 0x0E9
    dq str_versor               ; 0x0EA
    dq str_tangent              ; 0x0EB
    dq str_cotangent            ; 0x0EC
    dq str_form_1               ; 0x0ED
    dq str_form_2               ; 0x0EE
    dq str_form_3               ; 0x0EF
    dq str_csr_val              ; 0x0F0
    dq str_csr_idx              ; 0x0F1
    dq str_csc_val              ; 0x0F2
    dq str_csc_idx              ; 0x0F3
    dq str_coo_val              ; 0x0F4
    dq str_coo_row              ; 0x0F5
    dq str_coo_col              ; 0x0F6
    dq str_bsr_val              ; 0x0F7
    dq str_ell_val              ; 0x0F8
    dq str_dia_val              ; 0x0F9
    dq str_sparse_val           ; 0x0FA
    dq str_sparse_idx           ; 0x0FB
    times 4 dq str_unknown_dtype ; 0x0FC-0x0FF
    dq str_gguf_q2k             ; 0x100
    dq str_gguf_q3k             ; 0x101
    dq str_gguf_q4k             ; 0x102
    dq str_gguf_q5k             ; 0x103
    dq str_gguf_q6k             ; 0x104
    dq str_gguf_q8k             ; 0x105
    dq str_gguf_iq1s            ; 0x106
    dq str_gguf_iq2xxs          ; 0x107
    dq str_gguf_iq3xxs          ; 0x108
    dq str_gguf_iq4nl           ; 0x109
    dq str_blocked_fp8          ; 0x10A
    dq str_amx_tile             ; 0x10B
    dq str_vnni_block           ; 0x10C
    times 3 dq str_unknown_dtype ; 0x10D-0x10F
    dq str_qbit                 ; 0x110
    dq str_density              ; 0x111
    dq str_ket                  ; 0x112
    times 13 dq str_unknown_dtype ; 0x113-0x11F
    dq str_rgb8                 ; 0x120
    dq str_rgba8                ; 0x121
    dq str_rgb16f               ; 0x122
    dq str_rgba16f              ; 0x123
    dq str_r11g11b10f           ; 0x124
    dq str_rgb9e5               ; 0x125
    dq str_depth16              ; 0x126
    dq str_depth32f             ; 0x127
    dq str_depth24s8            ; 0x128
    dq str_half4                ; 0x129
    dq str_byte4                ; 0x12A
    dq str_half2                ; 0x12B
    times 4 dq str_unknown_dtype ; 0x12C-0x12F
    dq str_pcm8                 ; 0x130
    dq str_pcm16                ; 0x131
    dq str_pcm24                ; 0x132
    dq str_pcm32                ; 0x133
    dq str_float_audio          ; 0x134
    dq str_ulaw                 ; 0x135
    dq str_alaw                 ; 0x136
    dq str_timestamp            ; 0x137
    dq str_frequency            ; 0x138
    dq str_phase                ; 0x139
    times 6 dq str_unknown_dtype ; 0x13A-0x13F
    dq str_morphism             ; 0x140
    dq str_functor_val          ; 0x141
    dq str_nat_trans            ; 0x142
    dq str_measure              ; 0x143
    dq str_signed_meas          ; 0x144
    dq str_prob_meas            ; 0x145
    dq str_utility              ; 0x146
    dq str_strategy             ; 0x147
    dq str_payoff               ; 0x148
    dq str_sample_path          ; 0x149
    dq str_transition           ; 0x14A
    dq str_generator            ; 0x14B
    dq str_type_idx             ; 0x14C
    dq str_universe             ; 0x14D
    dq str_identity             ; 0x14E
    dq str_unknown_dtype        ; 0x14F padding
    dq str_rle_block            ; 0x150
    dq str_zstd_block           ; 0x151
    dq str_dict_enc             ; 0x152
    dq str_bit_packed_blk       ; 0x153

dtype_short_name_table_end:
DTYPE_SHORT_NAME_COUNT equ (dtype_short_name_table_end - dtype_short_name_table) / 8

section .text

; -----------------------------------------------------------------------------
; umath_dtype_name_short - get short name string pointer
; args:    edi = dtype_id
; returns: rax = pointer to null-terminated ASCII string
; -----------------------------------------------------------------------------
global umath_dtype_name_short
umath_dtype_name_short:
    cmp     edi, DTYPE_USER_BASE
    jae     .user
    cmp     edi, DTYPE_SHORT_NAME_COUNT
    jae     .unknown
    lea     rax, [rel dtype_short_name_table]
    mov     rax, [rax + rdi*8]
    ret
.user:
    lea     rax, [rel str_user_dtype]
    ret
.unknown:
    lea     rax, [rel str_unknown_dtype]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_name_pretty - get pretty uppercase name
; args:    edi = dtype_id
; returns: rax = pointer to null-terminated ASCII string
; note:    for now same as short name, uppercased version in future
; -----------------------------------------------------------------------------
global umath_dtype_name_pretty
umath_dtype_name_pretty:
    jmp     umath_dtype_name_short

; -----------------------------------------------------------------------------
; umath_dtype_name_full - get full descriptive name
; args:    edi = dtype_id
; returns: rax = pointer to null-terminated ASCII string
; note:    returns short name for now (full names are alias strings)
; -----------------------------------------------------------------------------
global umath_dtype_name_full
umath_dtype_name_full:
    ; For key types, return full names
    cmp     edi, DTYPE_FP32
    je      .float32
    cmp     edi, DTYPE_FP64
    je      .float64
    cmp     edi, DTYPE_FP16
    je      .float16
    cmp     edi, DTYPE_BF16
    je      .bfloat16
    cmp     edi, DTYPE_INT8
    je      .int8_full
    cmp     edi, DTYPE_INT16
    je      .int16_full
    cmp     edi, DTYPE_INT32
    je      .int32_full
    cmp     edi, DTYPE_INT64
    je      .int64_full
    cmp     edi, DTYPE_UINT8
    je      .uint8_full
    cmp     edi, DTYPE_UINT32
    je      .uint32_full
    ; default: short name
    jmp     umath_dtype_name_short

section .rodata
str_float32:    db "float32",0
str_float64:    db "float64",0
str_float16:    db "float16",0
str_bfloat16:   db "bfloat16",0
str_int8_full:  db "int8",0
str_int16_full: db "int16",0
str_int32_full: db "int32",0
str_int64_full: db "int64",0
str_uint8_full: db "uint8",0
str_uint32_full:db "uint32",0

section .text
.float32:   lea rax, [rel str_float32]    ; ret
            ret
.float64:   lea rax, [rel str_float64]
            ret
.float16:   lea rax, [rel str_float16]
            ret
.bfloat16:  lea rax, [rel str_bfloat16]
            ret
.int8_full: lea rax, [rel str_int8_full]
            ret
.int16_full:lea rax, [rel str_int16_full]
            ret
.int32_full:lea rax, [rel str_int32_full]
            ret
.int64_full:lea rax, [rel str_int64_full]
            ret
.uint8_full:lea rax, [rel str_uint8_full]
            ret
.uint32_full:lea rax, [rel str_uint32_full]
            ret

; -----------------------------------------------------------------------------
; umath_dtype_name_torch - get PyTorch dtype name
; args:    edi = dtype_id
; returns: rax = pointer to null-terminated ASCII string
; -----------------------------------------------------------------------------
section .rodata
str_torch_float:    db "torch.float32",0
str_torch_double:   db "torch.float64",0
str_torch_half:     db "torch.float16",0
str_torch_bf16:     db "torch.bfloat16",0
str_torch_int8:     db "torch.int8",0
str_torch_int16:    db "torch.int16",0
str_torch_int32:    db "torch.int32",0
str_torch_int64:    db "torch.int64",0
str_torch_bool:     db "torch.bool",0
str_torch_cfloat:   db "torch.complex64",0
str_torch_cdouble:  db "torch.complex128",0
str_torch_uint8:    db "torch.uint8",0

section .text
global umath_dtype_name_torch
umath_dtype_name_torch:
    cmp     edi, DTYPE_FP32
    je      .tf
    cmp     edi, DTYPE_FP64
    je      .td
    cmp     edi, DTYPE_FP16
    je      .th
    cmp     edi, DTYPE_BF16
    je      .tbf16
    cmp     edi, DTYPE_INT8
    je      .ti8
    cmp     edi, DTYPE_INT16
    je      .ti16
    cmp     edi, DTYPE_INT32
    je      .ti32
    cmp     edi, DTYPE_INT64
    je      .ti64
    cmp     edi, DTYPE_INT1
    je      .tbool
    cmp     edi, DTYPE_CF32
    je      .tcf
    cmp     edi, DTYPE_CF64
    je      .tcd
    cmp     edi, DTYPE_UINT8
    je      .tu8
    jmp     umath_dtype_name_short
.tf:    lea rax, [rel str_torch_float]
        ret
.td:    lea rax, [rel str_torch_double]
        ret
.th:    lea rax, [rel str_torch_half]
        ret
.tbf16: lea rax, [rel str_torch_bf16]
        ret
.ti8:   lea rax, [rel str_torch_int8]
        ret
.ti16:  lea rax, [rel str_torch_int16]
        ret
.ti32:  lea rax, [rel str_torch_int32]
        ret
.ti64:  lea rax, [rel str_torch_int64]
        ret
.tbool: lea rax, [rel str_torch_bool]
        ret
.tcf:   lea rax, [rel str_torch_cfloat]
        ret
.tcd:   lea rax, [rel str_torch_cdouble]
        ret
.tu8:   lea rax, [rel str_torch_uint8]
        ret

; -----------------------------------------------------------------------------
; umath_dtype_name_numpy - get NumPy dtype name
; args:    edi = dtype_id
; returns: rax = pointer to null-terminated ASCII string
; -----------------------------------------------------------------------------
global umath_dtype_name_numpy
umath_dtype_name_numpy:
    ; NumPy uses same names as full names for standard types
    jmp     umath_dtype_name_full

; -----------------------------------------------------------------------------
; str_len - compute length of null-terminated string
; args:    rdi = string pointer
; returns: rax = length (not including null)
; clobbers: rcx
; -----------------------------------------------------------------------------
str_len:
    xor     eax, eax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; str_eq_len - compare string with known-length string
; args:    rdi = str1 (null-terminated)
;          rsi = str2 (null-terminated)
;          rdx = max length to compare
; returns: eax = 1 if equal, 0 otherwise
; -----------------------------------------------------------------------------
str_eq_n:
    push    rbx
    mov     rbx, rdx
    xor     ecx, ecx
.loop:
    cmp     rcx, rbx
    jge     .equal
    movzx   eax, byte [rdi + rcx]
    movzx   edx, byte [rsi + rcx]
    cmp     al, dl
    jne     .not_equal
    test    al, al
    jz      .equal
    inc     rcx
    jmp     .loop
.equal:
    mov     eax, 1
    pop     rbx
    ret
.not_equal:
    xor     eax, eax
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_from_name - parse dtype name string to dtype_id
; args:    rdi = pointer to null-terminated name string
; returns: eax = dtype_id (DTYPE_UNKNOWN if not recognized)
;
; supports: "fp32","float32","FP32","torch.float32","f32" → DTYPE_FP32
;           "fp16","float16","half" → DTYPE_FP16
;           "bf16","bfloat16" → DTYPE_BF16
;           "int8","i8" → DTYPE_INT8
;           etc.
; -----------------------------------------------------------------------------
global umath_dtype_from_name
umath_dtype_from_name:
    push    rbx
    mov     rbx, rdi

    ; linear search through name table
    ; check common names first for speed
    lea     rsi, [rel str_fp32]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_fp32

    lea     rsi, [rel str_float32]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_fp32

    lea     rsi, [rel str_fp16]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_fp16

    lea     rsi, [rel str_float16]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_fp16

    lea     rsi, [rel str_bf16]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_bf16

    lea     rsi, [rel str_bfloat16]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_bf16

    lea     rsi, [rel str_fp64]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_fp64

    lea     rsi, [rel str_float64]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_fp64

    lea     rsi, [rel str_int8]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_int8

    lea     rsi, [rel str_int16]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_int16

    lea     rsi, [rel str_int32]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_int32

    lea     rsi, [rel str_int64]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_int64

    lea     rsi, [rel str_uint8]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_uint8

    lea     rsi, [rel str_uint32]
    call    str_eq_n_null
    test    eax, eax
    jnz     .ret_uint32

    ; scan full table
    xor     ecx, ecx
.scan_loop:
    cmp     ecx, DTYPE_SHORT_NAME_COUNT
    jge     .not_found
    mov     rdi, rbx
    lea     rax, [rel dtype_short_name_table]
    mov     rsi, [rax + rcx*8]
    push    rcx
    call    str_eq_n_null
    pop     rcx
    test    eax, eax
    jnz     .found
    inc     ecx
    jmp     .scan_loop

.found:
    mov     eax, ecx
    pop     rbx
    ret

.not_found:
    mov     eax, DTYPE_UNKNOWN
    pop     rbx
    ret

.ret_fp32:  mov eax, DTYPE_FP32    ; pop rbx / ret
            pop rbx
            ret
.ret_fp16:  mov eax, DTYPE_FP16
            pop rbx
            ret
.ret_bf16:  mov eax, DTYPE_BF16
            pop rbx
            ret
.ret_fp64:  mov eax, DTYPE_FP64
            pop rbx
            ret
.ret_int8:  mov eax, DTYPE_INT8
            pop rbx
            ret
.ret_int16: mov eax, DTYPE_INT16
            pop rbx
            ret
.ret_int32: mov eax, DTYPE_INT32
            pop rbx
            ret
.ret_int64: mov eax, DTYPE_INT64
            pop rbx
            ret
.ret_uint8: mov eax, DTYPE_UINT8
            pop rbx
            ret
.ret_uint32: mov eax, DTYPE_UINT32
             pop rbx
             ret

; -----------------------------------------------------------------------------
; str_eq_n_null - compare two null-terminated strings
; args:    rdi = str1
;          rsi = str2
; returns: eax = 1 if equal, 0 otherwise
; note:    case-sensitive
; -----------------------------------------------------------------------------
str_eq_n_null:
    xor     ecx, ecx
.loop:
    movzx   eax, byte [rdi + rcx]
    movzx   edx, byte [rsi + rcx]
    cmp     al, dl
    jne     .no
    test    al, al
    jz      .yes
    inc     rcx
    jmp     .loop
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_from_name_len - parse dtype from bounded string
; args:    rdi = string pointer
;          rsi = length (not including null, max 64)
; returns: eax = dtype_id
; -----------------------------------------------------------------------------
global umath_dtype_from_name_len
umath_dtype_from_name_len:
    ; copy to temp buffer and null-terminate, then call from_name
    ; for now, just delegate (assumes string is accessible)
    ; TODO: implement bounded compare
    jmp     umath_dtype_from_name