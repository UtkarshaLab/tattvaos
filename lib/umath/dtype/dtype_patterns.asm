; =============================================================================
; umath - unified math library
; dtype/dtype_patterns.asm - special value bit patterns
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_traits.asm
;
; description:
;   compile-time bit patterns for special values in each float dtype
;   all patterns stored as u64 (right-justified for sub-64-bit types)
;   integer dtypes: patterns are trivial (0=zero, max=all bits set etc)
;
; functions:
;   umath_dtype_pattern_pos_zero   (dtype_id → u64)
;   umath_dtype_pattern_neg_zero   (dtype_id → u64)
;   umath_dtype_pattern_pos_inf    (dtype_id → u64)
;   umath_dtype_pattern_neg_inf    (dtype_id → u64)
;   umath_dtype_pattern_qnan       (dtype_id → u64) quiet NaN
;   umath_dtype_pattern_snan       (dtype_id → u64) signaling NaN
;   umath_dtype_pattern_pos_max    (dtype_id → u64)
;   umath_dtype_pattern_neg_max    (dtype_id → u64)
;   umath_dtype_pattern_pos_min    (dtype_id → u64) smallest positive normal
;   umath_dtype_pattern_one        (dtype_id → u64)
;   umath_dtype_pattern_neg_one    (dtype_id → u64)
;   umath_dtype_pattern_eps        (dtype_id → u64) machine epsilon bit pattern
; =============================================================================

%include "dtype_id.asm"

bits 64

; =============================================================================
; pattern table struct (10 entries × 8 bytes = 80 bytes per dtype)
; only covers float dtypes — others computed inline
; =============================================================================

PATT_IDX_POS_ZERO   equ 0
PATT_IDX_NEG_ZERO   equ 1
PATT_IDX_POS_INF    equ 2
PATT_IDX_NEG_INF    equ 3
PATT_IDX_QNAN       equ 4
PATT_IDX_SNAN       equ 5
PATT_IDX_POS_MAX    equ 6
PATT_IDX_NEG_MAX    equ 7
PATT_IDX_POS_MIN    equ 8
PATT_IDX_ONE        equ 9
PATT_IDX_NEG_ONE    equ 10
PATT_IDX_EPS        equ 11
PATT_COUNT          equ 12
PATT_ENTRY_SIZE     equ PATT_COUNT * 8   ; 96 bytes per dtype

%macro patt_entry 12
    ; pos_zero, neg_zero, pos_inf, neg_inf,
    ; qnan, snan, pos_max, neg_max,
    ; pos_min, one, neg_one, eps
    dq %1, %2, %3, %4
    dq %5, %6, %7, %8
    dq %9, %10, %11, %12
%endmacro

section .rodata
align 64

dtype_patterns:

; FP8_E4M3  (0x020)
; S=1, E=4, M=3  bias=7
; pos_zero=0x00  neg_zero=0x80  pos_inf=N/A  neg_inf=N/A
; qnan=0x7F      snan=0x7E      pos_max=0x7E neg_max=0xFE
; pos_min=0x08   one=0x38       neg_one=0xB8 eps=0x20
patt_entry \
    0x00, 0x80, 0x7F, 0xFF, \
    0x7F, 0x7E, 0x7E, 0xFE, \
    0x08, 0x38, 0xB8, 0x20

; FP8_E5M2  (0x021)
; S=1, E=5, M=2  bias=15
; pos_zero=0x00  neg_zero=0x80  pos_inf=0x7C  neg_inf=0xFC
; qnan=0x7F      snan=0x7D      pos_max=0x7B  neg_max=0xFB
; pos_min=0x04   one=0x3C       neg_one=0xBC  eps=0x14
patt_entry \
    0x00, 0x80, 0x7C, 0xFC, \
    0x7F, 0x7D, 0x7B, 0xFB, \
    0x04, 0x3C, 0xBC, 0x14

; FP16  (0x022)
; S=1, E=5, M=10  bias=15
; pos_zero=0x0000  neg_zero=0x8000  pos_inf=0x7C00  neg_inf=0xFC00
; qnan=0x7E00      snan=0x7C01      pos_max=0x7BFF  neg_max=0xFBFF
; pos_min=0x0400   one=0x3C00       neg_one=0xBC00  eps=0x1400
patt_entry \
    0x0000, 0x8000, 0x7C00, 0xFC00, \
    0x7E00, 0x7C01, 0x7BFF, 0xFBFF, \
    0x0400, 0x3C00, 0xBC00, 0x1400

; BF16  (0x023)
; S=1, E=8, M=7  bias=127
; pos_zero=0x0000  neg_zero=0x8000  pos_inf=0x7F80  neg_inf=0xFF80
; qnan=0x7FC0      snan=0x7F81      pos_max=0x7F7F  neg_max=0xFF7F
; pos_min=0x0080   one=0x3F80       neg_one=0xBF80  eps=0x3C00
patt_entry \
    0x0000, 0x8000, 0x7F80, 0xFF80, \
    0x7FC0, 0x7F81, 0x7F7F, 0xFF7F, \
    0x0080, 0x3F80, 0xBF80, 0x3C00

; TF32  (0x024) — stored as 32-bit, 19 significant bits
; Same exponent as FP32, mantissa truncated to 10 bits
; pos_zero=0x00000000  neg_zero=0x80000000  pos_inf=0x7F800000
; neg_inf=0xFF800000   qnan=0x7FC00000      snan=0x7F801000
; pos_max=0x7F7FF000   neg_max=0xFF7FF000
; pos_min=0x00800000   one=0x3F800000       neg_one=0xBF800000
; eps=0x3A000000
patt_entry \
    0x00000000, 0x80000000, 0x7F800000, 0xFF800000, \
    0x7FC00000, 0x7F801000, 0x7F7FF000, 0xFF7FF000, \
    0x00800000, 0x3F800000, 0xBF800000, 0x3A000000

; FP32  (0x025)
; S=1, E=8, M=23  bias=127
; pos_zero=0x00000000  neg_zero=0x80000000  pos_inf=0x7F800000
; neg_inf=0xFF800000   qnan=0x7FC00000      snan=0x7F800001
; pos_max=0x7F7FFFFF   neg_max=0xFF7FFFFF
; pos_min=0x00800000   one=0x3F800000       neg_one=0xBF800000
; eps=0x34000000 (2^-23 = machine epsilon)
patt_entry \
    0x00000000, 0x80000000, 0x7F800000, 0xFF800000, \
    0x7FC00000, 0x7F800001, 0x7F7FFFFF, 0xFF7FFFFF, \
    0x00800000, 0x3F800000, 0xBF800000, 0x34000000

; FP64  (0x026)
; S=1, E=11, M=52  bias=1023
patt_entry \
    0x0000000000000000, 0x8000000000000000, \
    0x7FF0000000000000, 0xFFF0000000000000, \
    0x7FF8000000000000, 0x7FF0000000000001, \
    0x7FEFFFFFFFFFFFFF, 0xFFEFFFFFFFFFFFFF, \
    0x0010000000000000, 0x3FF0000000000000, \
    0xBFF0000000000000, 0x3CB0000000000000

; FP128  (0x027) — stored as two u64 [hi, lo]
; machine epsilon = 2^-112
; pos_zero: hi=0 lo=0
; one: hi=0x3FFF000000000000 lo=0
patt_entry \
    0x0000000000000000, 0x8000000000000000, \
    0x7FFF000000000000, 0xFFFF000000000000, \
    0x7FFF800000000000, 0x7FFF000000000001, \
    0x7FFEFFFFFFFFFFFF, 0xFFFEFFFFFFFFFFFF, \
    0x0001000000000000, 0x3FFF000000000000, \
    0xBFFF000000000000, 0x3F8F000000000000

; FP8_E4M3_FNUZ  (0x028) — no inf, NaN=0x80 (neg zero is NaN)
patt_entry \
    0x00, 0x80, 0x00, 0x00, \
    0x80, 0x80, 0x7F, 0xFF, \
    0x08, 0x38, 0xB8, 0x20

; FP8_E5M2_FNUZ  (0x029)
patt_entry \
    0x00, 0x80, 0x00, 0x00, \
    0x80, 0x80, 0x7B, 0xFB, \
    0x04, 0x3C, 0xBC, 0x14

; BFLOAT8  (0x02A) — same as FP8_E5M2 for now
patt_entry \
    0x00, 0x80, 0x7C, 0xFC, \
    0x7F, 0x7D, 0x7B, 0xFB, \
    0x04, 0x3C, 0xBC, 0x14

; MINIFLOAT (0x02B) — E4M3 layout default
patt_entry \
    0x00, 0x80, 0x7C, 0xFC, \
    0x7F, 0x7E, 0x7B, 0xFB, \
    0x08, 0x38, 0xB8, 0x20

; FP6_E2M3  (0x02C)  bias=1
; pos_zero=0x00  neg_zero=0x20  no inf  qnan=0x1F
; pos_max=0x1F   neg_max=0x3F   pos_min=0x04  one=0x08
patt_entry \
    0x00, 0x20, 0x00, 0x00, \
    0x1F, 0x1E, 0x1B, 0x3B, \
    0x04, 0x08, 0x28, 0x04

; FP6_E3M2  (0x02D) bias=3
patt_entry \
    0x00, 0x20, 0x00, 0x00, \
    0x1F, 0x1E, 0x1B, 0x3B, \
    0x04, 0x0C, 0x2C, 0x04

dtype_patterns_end:

section .text

; =============================================================================
; dispatch table indexed by dtype_id - float dtype → pattern table index
; =============================================================================

section .rodata
align 8
dtype_patt_index:
    ; indexed by dtype_id, value = index into dtype_patterns
    ; -1 (0xFF) means no pattern table (integer or variable type)
    times 0x020 db 0xFF          ; 0x000–0x01F no pattern table
    db 0                         ; FP8_E4M3     index 0
    db 1                         ; FP8_E5M2     index 1
    db 2                         ; FP16          index 2
    db 3                         ; BF16          index 3
    db 4                         ; TF32          index 4
    db 5                         ; FP32          index 5
    db 6                         ; FP64          index 6
    db 7                         ; FP128         index 7
    db 8                         ; FP8_E4M3_FNUZ index 8
    db 9                         ; FP8_E5M2_FNUZ index 9
    db 10                        ; BFLOAT8       index 10
    db 11                        ; MINIFLOAT     index 11
    db 12                        ; FP6_E2M3      index 12
    db 13                        ; FP6_E3M2      index 13
    times 2 db 0xFF              ; padding
    ; MX formats use same base patterns as their element type
    db 0                         ; MXFP8_E4M3  → same as FP8_E4M3
    db 1                         ; MXFP8_E5M2
    db 12                        ; MXFP6_E2M3
    db 13                        ; MXFP6_E3M2
    times 0xFF db 0xFF           ; rest = no pattern table
dtype_patt_index_end:

section .text

; -----------------------------------------------------------------------------
; internal helper: get pointer to pattern row for dtype
; args:    edi = dtype_id
;          esi = pattern index (PATT_IDX_*)
; returns: rax = pointer to u64 value, NULL if not applicable
; -----------------------------------------------------------------------------
dtype_pattern_ptr:
    ; get table index for this dtype
    cmp     edi, dtype_patt_index_end - dtype_patt_index
    jae     .null
    lea     rax, [rel dtype_patt_index]
    movzx   ecx, byte [rax + rdi]
    cmp     ecx, 0xFF
    je      .null
    ; compute address: table_base + index * PATT_ENTRY_SIZE + field * 8
    lea     rax, [rel dtype_patterns]
    imul    ecx, PATT_ENTRY_SIZE
    add     rax, rcx
    lea     rcx, [rsi * 8]
    add     rax, rcx
    ret
.null:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; generic pattern getter
; args:    edi = dtype_id
;          esi = PATT_IDX_*
; returns: rax = bit pattern as u64, 0 if not applicable
; -----------------------------------------------------------------------------
dtype_get_pattern:
    call    dtype_pattern_ptr
    test    rax, rax
    jz      .zero
    mov     rax, [rax]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_pattern_pos_zero - positive zero bit pattern
; args:    edi = dtype_id
; returns: rax = bit pattern
; -----------------------------------------------------------------------------
global umath_dtype_pattern_pos_zero
umath_dtype_pattern_pos_zero:
    mov     esi, PATT_IDX_POS_ZERO
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_neg_zero - negative zero bit pattern (-0.0)
; args:    edi = dtype_id
; returns: rax = bit pattern (0 if dtype has no -0)
; -----------------------------------------------------------------------------
global umath_dtype_pattern_neg_zero
umath_dtype_pattern_neg_zero:
    mov     esi, PATT_IDX_NEG_ZERO
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_pos_inf - positive infinity bit pattern
; args:    edi = dtype_id
; returns: rax = bit pattern (0 if dtype has no infinity)
; -----------------------------------------------------------------------------
global umath_dtype_pattern_pos_inf
umath_dtype_pattern_pos_inf:
    mov     esi, PATT_IDX_POS_INF
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_neg_inf - negative infinity bit pattern
; args:    edi = dtype_id
; returns: rax = bit pattern (0 if dtype has no infinity)
; -----------------------------------------------------------------------------
global umath_dtype_pattern_neg_inf
umath_dtype_pattern_neg_inf:
    mov     esi, PATT_IDX_NEG_INF
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_qnan - quiet NaN bit pattern
; args:    edi = dtype_id
; returns: rax = bit pattern (0 if dtype has no NaN)
; -----------------------------------------------------------------------------
global umath_dtype_pattern_qnan
umath_dtype_pattern_qnan:
    mov     esi, PATT_IDX_QNAN
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_snan - signaling NaN bit pattern
; args:    edi = dtype_id
; returns: rax = bit pattern (0 if dtype has no NaN)
; -----------------------------------------------------------------------------
global umath_dtype_pattern_snan
umath_dtype_pattern_snan:
    mov     esi, PATT_IDX_SNAN
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_pos_max - maximum positive finite value
; args:    edi = dtype_id
; returns: rax = bit pattern
; -----------------------------------------------------------------------------
global umath_dtype_pattern_pos_max
umath_dtype_pattern_pos_max:
    mov     esi, PATT_IDX_POS_MAX
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_neg_max - maximum negative finite value
; args:    edi = dtype_id
; returns: rax = bit pattern
; -----------------------------------------------------------------------------
global umath_dtype_pattern_neg_max
umath_dtype_pattern_neg_max:
    mov     esi, PATT_IDX_NEG_MAX
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_pos_min - smallest positive normal value
; args:    edi = dtype_id
; returns: rax = bit pattern
; -----------------------------------------------------------------------------
global umath_dtype_pattern_pos_min
umath_dtype_pattern_pos_min:
    mov     esi, PATT_IDX_POS_MIN
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_one - bit pattern for the value 1.0
; args:    edi = dtype_id
; returns: rax = bit pattern
; -----------------------------------------------------------------------------
global umath_dtype_pattern_one
umath_dtype_pattern_one:
    mov     esi, PATT_IDX_ONE
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_neg_one - bit pattern for the value -1.0
; args:    edi = dtype_id
; returns: rax = bit pattern
; -----------------------------------------------------------------------------
global umath_dtype_pattern_neg_one
umath_dtype_pattern_neg_one:
    mov     esi, PATT_IDX_NEG_ONE
    jmp     dtype_get_pattern

; -----------------------------------------------------------------------------
; umath_dtype_pattern_eps - machine epsilon bit pattern
; args:    edi = dtype_id
; returns: rax = bit pattern for smallest value s.t. 1.0 + eps != 1.0
; -----------------------------------------------------------------------------
global umath_dtype_pattern_eps
umath_dtype_pattern_eps:
    mov     esi, PATT_IDX_EPS
    jmp     dtype_get_pattern