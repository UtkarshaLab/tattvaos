; =============================================================================
; umath - unified math library
; dtype/dtype_promote.asm - dtype promotion rules
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_family.asm
;   dtype_size.asm
;
; description:
;   defines the result dtype when two dtypes are used together in an operation
;   follows standard numeric promotion rules with umath extensions:
;     - float always wins over integer
;     - higher precision wins
;     - signed wins over unsigned when same size
;     - complex wins over real
;     - special types (bignum, posit) win over standard types
;
;   promotion is symmetric: promote(a,b) == promote(b,a)
;
; functions:
;   umath_dtype_promote          (dtype_id_a, dtype_id_b → dtype_id)
;   umath_dtype_promote_chain    (*dtype_ids, count → dtype_id)
;   umath_dtype_promote_to_float (dtype_id → dtype_id) int → float upgrade
;   umath_dtype_common_real      (dtype_id_a, dtype_id_b → dtype_id)
;   umath_dtype_accumulator      (dtype_id → dtype_id) safe accumulator type
;
; promotion rules summary:
;   INT4  + INT4   → INT4
;   INT4  + INT8   → INT8
;   INT8  + INT16  → INT16
;   INT8  + FP32   → FP32
;   INT8  + FP16   → FP16
;   FP16  + FP32   → FP32
;   FP16  + BF16   → FP32   (mixed float → next up)
;   FP8   + FP16   → FP16
;   FP8   + FP32   → FP32
;   BF16  + FP32   → FP32
;   FP32  + FP64   → FP64
;   CF32  + FP32   → CF32   (complex absorbs real)
;   CF32  + CF64   → CF64
;   BIGINT + INT64 → BIGINT
;   BIGINT + FP64  → BIGFLOAT
; =============================================================================

%include "dtype_id.asm"
%include "dtype_family.asm"

bits 64
section .text

; =============================================================================
; rank table for promotion ordering
; higher rank wins
; =============================================================================

section .rodata
align 8

; rank per dtype_id — promotion picks higher rank
; 0 = unknown/none, higher = stronger type
dtype_promote_rank:
    db 0        ; DTYPE_NONE

    ; integer signed (rank by width)
    db 10       ; INT1
    db 11       ; INT2
    db 12       ; INT4
    db 13       ; INT8
    db 14       ; INT16
    db 15       ; INT32
    db 16       ; INT64
    db 17       ; INT128
    db 18       ; INT256

    times 6 db 0  ; padding

    ; integer unsigned (slightly lower rank than signed same width)
    db 9        ; UINT4
    db 10       ; UINT8
    db 11       ; UINT16
    db 12       ; UINT32
    db 13       ; UINT64
    db 14       ; UINT128
    db 15       ; UINT256
    db 16       ; UINT512
    db 17       ; UINT1024
    db 18       ; UINT2048

    times 6 db 0  ; padding

    ; IEEE float (rank above integers)
    db 25       ; FP8_E4M3
    db 25       ; FP8_E5M2
    db 30       ; FP16
    db 30       ; BF16
    db 32       ; TF32
    db 35       ; FP32
    db 40       ; FP64
    db 45       ; FP128

    ; FP8 variants
    db 25       ; FP8_E4M3_FNUZ
    db 25       ; FP8_E5M2_FNUZ
    db 25       ; BFLOAT8
    db 25       ; MINIFLOAT

    ; FP6
    db 23       ; FP6_E2M3
    db 23       ; FP6_E3M2

    times 2 db 0

    ; OCP MX (same base rank as element type)
    db 25       ; MXFP8_E4M3
    db 25       ; MXFP8_E5M2
    db 23       ; MXFP6_E2M3
    db 23       ; MXFP6_E3M2
    db 20       ; MXFP4_E2M1
    db 13       ; MXINT8
    db 11       ; MXINT6
    db 9        ; MXINT4
    db 22       ; UE8M0
    db 20       ; NVFP4
    db 9        ; NVINT4
    db 25       ; NVFP8

    times 4 db 0

    ; fixed point
    db 12       ; Q4_0
    db 12       ; Q4_1
    db 13       ; Q5_0
    db 13       ; Q5_1
    db 13       ; Q8_0
    db 0        ; BIT_PACKED variable
    db 0        ; DELTA_ENC variable

    times 9 db 0

    ; normalized
    db 13       ; UNORM8
    db 14       ; UNORM16
    db 13       ; SNORM8
    db 14       ; SNORM16
    db 35       ; PROB32
    db 35       ; LOG_PROB32
    db 35       ; FUZZY

    times 9 db 0

    ; complex (rank = element rank + 50)
    db 63       ; CI8
    db 64       ; CI16
    db 65       ; CI32
    db 80       ; CF16
    db 80       ; CBF16
    db 85       ; CF32
    db 90       ; CF64
    db 95       ; CF128
    db 66       ; CI64

    times 7 db 0

    ; packed SIMD (use element rank)
    db 12       ; PACK_INT4x2
    db 12       ; PACK_INT4x8
    db 12       ; PACK_INT4x16
    db 25       ; PACK_FP8x2
    db 25       ; PACK_FP8x4
    db 30       ; PACK_BF16x2
    db 13       ; PACK_INT8x4
    db 14       ; PACK_INT16x2

    times 8 db 0

    ; Galois / modular
    db 50       ; GF2
    db 50       ; GFP
    db 50       ; GF2N
    db 50       ; GF2_128
    db 50       ; GF2_256
    db 50       ; GF2_POLY
    db 50       ; GFQ_ELEM
    db 50       ; ZMOD
    db 50       ; MONTGOMERY
    db 50       ; BARRETT
    db 50       ; SCALAR_FIELD
    db 50       ; BASE_FIELD

    times 4 db 0

    ; PQ crypto
    times 9 db 60

    times 7 db 0

    ; coding theory
    times 8 db 55

    times 8 db 0

    ; arbitrary precision (highest rank for numerics)
    db 100      ; BIGINT
    db 110      ; BIGFLOAT
    db 105      ; RATIONAL
    db 108      ; PADIC
    db 120      ; SURREAL
    db 120      ; HYPERREAL
    db 125      ; ORDINAL
    db 125      ; CARDINAL

    times 8 db 0

    ; alternative number systems
    db 36       ; POSIT8
    db 37       ; POSIT16
    db 38       ; POSIT32
    db 39       ; POSIT64
    db 40       ; POSIT128
    db 41       ; POSIT256
    db 42       ; UNUM1
    db 42       ; UNUM2
    db 42       ; VALID
    db 35       ; LNS8
    db 36       ; LNS16
    db 37       ; LNS32
    db 38       ; DBNS
    db 35       ; STOCHASTIC

dtype_promote_rank_end:

section .text

; =============================================================================
; promotion result table for common pairs
; for full generality, use rank-based promotion
; =============================================================================

; -----------------------------------------------------------------------------
; dtype_get_rank - get promotion rank for dtype
; args:    edi = dtype_id
; returns: eax = rank (0 if unknown)
; -----------------------------------------------------------------------------
dtype_get_rank:
    cmp     edi, dtype_promote_rank_end - dtype_promote_rank
    jae     .zero
    lea     rax, [rel dtype_promote_rank]
    movzx   eax, byte [rax + rdi]
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_promote - get promotion result of two dtypes
; args:    edi = dtype_id_a
;          esi = dtype_id_b
; returns: eax = result dtype_id
;
; algorithm:
;   1. same dtype → return that dtype
;   2. one is NONE → return the other
;   3. both integer: return higher rank
;   4. one float, one int: return float (at least FP32)
;   5. both float: return higher rank
;   6. one complex: return complex of higher component type
;   7. bignum family: return higher rank
;   8. default: return higher rank winner
; -----------------------------------------------------------------------------
global umath_dtype_promote
umath_dtype_promote:
    push    rbx
    push    r12
    push    r13

    mov     ebx, edi                ; save a
    mov     r12d, esi               ; save b

    ; 1. same dtype
    cmp     edi, esi
    je      .return_a

    ; 2. either is NONE
    test    edi, edi
    jz      .return_b
    test    esi, esi
    jz      .return_a

    ; get families
    call    umath_dtype_get_family
    mov     r13d, eax               ; family_a

    mov     edi, r12d
    call    umath_dtype_get_family
    ; eax = family_b, r13d = family_a

    ; 3. complex promotion
    cmp     r13d, DFAMILY_COMPLEX
    je      .complex_a
    cmp     eax, DFAMILY_COMPLEX
    je      .complex_b

    ; 4. bignum wins over everything else
    cmp     r13d, DFAMILY_BIGNUM
    je      .bignum_a
    cmp     eax, DFAMILY_BIGNUM
    je      .bignum_b

    ; 5. float + integer: float wins, minimum FP32
    cmp     r13d, DFAMILY_INT_SIGNED
    je      .check_b_float
    cmp     r13d, DFAMILY_INT_UNSIGNED
    je      .check_b_float
    jmp     .rank_compare

.check_b_float:
    cmp     eax, DFAMILY_FLOAT_IEEE
    je      .float_wins_b
    cmp     eax, DFAMILY_FLOAT_FP8_VAR
    je      .float_wins_b
    cmp     eax, DFAMILY_FLOAT_FP6
    je      .float_wins_b
    cmp     eax, DFAMILY_FLOAT_OCP
    je      .float_wins_b
    cmp     eax, DFAMILY_FLOAT_NV
    je      .float_wins_b
    cmp     eax, DFAMILY_ALTERNATIVE
    je      .float_wins_b
    jmp     .rank_compare

.float_wins_b:
    ; float b wins, but enforce minimum FP32 for int+float mix
    mov     edi, r12d
    call    dtype_get_rank
    cmp     eax, 35                 ; FP32 rank
    jge     .return_b
    ; upgrade to FP32
    mov     eax, DTYPE_FP32
    jmp     .done

.rank_compare:
    ; compare ranks, return higher
    mov     edi, ebx
    call    dtype_get_rank
    mov     r13d, eax               ; rank_a

    mov     edi, r12d
    call    dtype_get_rank
    ; eax = rank_b

    cmp     r13d, eax
    jge     .return_a
    jmp     .return_b

.complex_a:
    ; a is complex, promote b to match a's component
    ; CF32 + FP64 → CF64
    cmp     ebx, DTYPE_CF32
    je      .cf32_a
    cmp     ebx, DTYPE_CF64
    je      .return_a               ; CF64 absorbs all
    cmp     ebx, DTYPE_CF16
    je      .cf16_a
    jmp     .return_a

.cf32_a:
    ; if b is FP64 or CF64 → CF64
    cmp     r12d, DTYPE_FP64
    je      .ret_cf64
    cmp     r12d, DTYPE_CF64
    je      .ret_cf64
    jmp     .return_a

.cf16_a:
    ; if b is FP32+ → CF32
    mov     edi, r12d
    call    dtype_get_rank
    cmp     eax, 35                 ; FP32 rank
    jge     .ret_cf32
    jmp     .return_a

.complex_b:
    ; symmetric: swap a and b and re-run complex_a logic
    xchg    ebx, r12d
    jmp     .complex_a

.bignum_a:
    ; a is bignum — if b is also bignum, higher rank wins
    cmp     eax, DFAMILY_BIGNUM
    je      .rank_compare
    ; bignum a absorbs non-bignum b
    ; except: bignum + float → bigfloat
    cmp     eax, DFAMILY_FLOAT_IEEE
    je      .ret_bigfloat
    cmp     eax, DFAMILY_ALTERNATIVE
    je      .ret_bigfloat
    jmp     .return_a

.bignum_b:
    xchg    ebx, r12d
    jmp     .bignum_a

.ret_cf32:
    mov     eax, DTYPE_CF32
    jmp     .done

.ret_cf64:
    mov     eax, DTYPE_CF64
    jmp     .done

.ret_bigfloat:
    mov     eax, DTYPE_BIGFLOAT
    jmp     .done

.return_a:
    mov     eax, ebx
    jmp     .done

.return_b:
    mov     eax, r12d

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_promote_chain - promote a list of dtypes
; args:    rdi = pointer to dtype_id array (u32 array)
;          esi = count
; returns: eax = result dtype_id (DTYPE_NONE if count=0)
; -----------------------------------------------------------------------------
global umath_dtype_promote_chain
umath_dtype_promote_chain:
    test    esi, esi
    jz      .empty
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi                ; array ptr
    mov     r13d, esi               ; count
    mov     eax, dword [rbx]        ; first element
    mov     r12d, eax               ; result so far
    dec     r13d
    jz      .chain_done
    add     rbx, 4
.chain_loop:
    mov     edi, r12d
    mov     esi, dword [rbx]
    call    umath_dtype_promote
    mov     r12d, eax
    add     rbx, 4
    dec     r13d
    jnz     .chain_loop
.chain_done:
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret
.empty:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_promote_to_float - upgrade integer dtype to float equivalent
; args:    edi = dtype_id
; returns: eax = float dtype_id
;          returns same if already float
;          INT4/8  → FP16
;          INT16   → FP32
;          INT32   → FP64
;          INT64   → FP64
;          INT128+ → BIGFLOAT
; -----------------------------------------------------------------------------
global umath_dtype_promote_to_float
umath_dtype_promote_to_float:
    ; check if already float
    push    rbx
    mov     ebx, edi
    call    umath_dtype_get_family
    cmp     eax, DFAMILY_FLOAT_IEEE
    je      .already_float
    cmp     eax, DFAMILY_FLOAT_FP8_VAR
    je      .already_float
    cmp     eax, DFAMILY_FLOAT_FP6
    je      .already_float
    cmp     eax, DFAMILY_FLOAT_OCP
    je      .already_float
    cmp     eax, DFAMILY_FLOAT_NV
    je      .already_float
    cmp     eax, DFAMILY_ALTERNATIVE
    je      .already_float
    cmp     eax, DFAMILY_COMPLEX
    je      .already_float

    ; map integer to float
    cmp     ebx, DTYPE_INT4
    jle     .to_fp16
    cmp     ebx, DTYPE_UINT4
    je      .to_fp16
    cmp     ebx, DTYPE_INT8
    je      .to_fp16
    cmp     ebx, DTYPE_UINT8
    je      .to_fp16
    cmp     ebx, DTYPE_INT16
    je      .to_fp32
    cmp     ebx, DTYPE_UINT16
    je      .to_fp32
    cmp     ebx, DTYPE_INT32
    je      .to_fp64
    cmp     ebx, DTYPE_UINT32
    je      .to_fp64
    cmp     ebx, DTYPE_INT64
    je      .to_fp64
    cmp     ebx, DTYPE_UINT64
    je      .to_fp64
    ; INT128+ → BIGFLOAT
    mov     eax, DTYPE_BIGFLOAT
    pop     rbx
    ret

.to_fp16:
    mov     eax, DTYPE_FP16
    pop     rbx
    ret
.to_fp32:
    mov     eax, DTYPE_FP32
    pop     rbx
    ret
.to_fp64:
    mov     eax, DTYPE_FP64
    pop     rbx
    ret
.already_float:
    mov     eax, ebx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_common_real - find common real type for mixed real/complex
; args:    edi = dtype_id_a
;          esi = dtype_id_b
; returns: eax = common real component dtype (strips complex if needed)
; -----------------------------------------------------------------------------
global umath_dtype_common_real
umath_dtype_common_real:
    push    rbx
    mov     ebx, esi
    ; strip complex from a
    cmp     edi, DTYPE_CF16
    je      .a_fp16
    cmp     edi, DTYPE_CBF16
    je      .a_bf16
    cmp     edi, DTYPE_CF32
    je      .a_fp32
    cmp     edi, DTYPE_CF64
    je      .a_fp64
    cmp     edi, DTYPE_CI8
    je      .a_int8
    cmp     edi, DTYPE_CI16
    je      .a_int16
    cmp     edi, DTYPE_CI32
    je      .a_int32
    cmp     edi, DTYPE_CI64
    je      .a_int64
    jmp     .a_done
.a_fp16:  mov edi, DTYPE_FP16   ; jmp .a_done
          jmp .a_done
.a_bf16:  mov edi, DTYPE_BF16   ; jmp .a_done
          jmp .a_done
.a_fp32:  mov edi, DTYPE_FP32   ; jmp .a_done
          jmp .a_done
.a_fp64:  mov edi, DTYPE_FP64   ; jmp .a_done
          jmp .a_done
.a_int8:  mov edi, DTYPE_INT8   ; jmp .a_done
          jmp .a_done
.a_int16: mov edi, DTYPE_INT16  ; jmp .a_done
          jmp .a_done
.a_int32: mov edi, DTYPE_INT32  ; jmp .a_done
          jmp .a_done
.a_int64: mov edi, DTYPE_INT64
.a_done:
    ; strip complex from b
    mov     esi, ebx
    cmp     esi, DTYPE_CF16
    je      .b_fp16
    cmp     esi, DTYPE_CBF16
    je      .b_bf16
    cmp     esi, DTYPE_CF32
    je      .b_fp32
    cmp     esi, DTYPE_CF64
    je      .b_fp64
    cmp     esi, DTYPE_CI8
    je      .b_int8
    cmp     esi, DTYPE_CI16
    je      .b_int16
    cmp     esi, DTYPE_CI32
    je      .b_int32
    cmp     esi, DTYPE_CI64
    je      .b_int64
    jmp     .promote
.b_fp16:  mov esi, DTYPE_FP16   ; jmp .promote
          jmp .promote
.b_bf16:  mov esi, DTYPE_BF16
          jmp .promote
.b_fp32:  mov esi, DTYPE_FP32
          jmp .promote
.b_fp64:  mov esi, DTYPE_FP64
          jmp .promote
.b_int8:  mov esi, DTYPE_INT8
          jmp .promote
.b_int16: mov esi, DTYPE_INT16
          jmp .promote
.b_int32: mov esi, DTYPE_INT32
          jmp .promote
.b_int64: mov esi, DTYPE_INT64
.promote:
    pop     rbx
    jmp     umath_dtype_promote

; -----------------------------------------------------------------------------
; umath_dtype_accumulator - get safe accumulator dtype for given input dtype
; args:    edi = input dtype_id
; returns: eax = accumulator dtype_id
;
; accumulator rules:
;   INT4/INT8   → INT32   (avoid overflow during sum)
;   INT16       → INT32
;   INT32       → INT64
;   INT64       → INT64   (best we can do in hardware)
;   FP8/FP16/BF16 → FP32 (accumulate in higher precision)
;   FP32        → FP32
;   FP64        → FP64
;   CF16/CBF16  → CF32
;   CF32        → CF32
;   CF64        → CF64
; -----------------------------------------------------------------------------
global umath_dtype_accumulator
umath_dtype_accumulator:
    cmp     edi, DTYPE_INT1
    jle     .int32
    cmp     edi, DTYPE_INT4
    je      .int32
    cmp     edi, DTYPE_INT8
    je      .int32
    cmp     edi, DTYPE_INT16
    je      .int32
    cmp     edi, DTYPE_INT32
    je      .int64
    cmp     edi, DTYPE_INT64
    je      .int64
    cmp     edi, DTYPE_UINT4
    je      .int32
    cmp     edi, DTYPE_UINT8
    je      .int32
    cmp     edi, DTYPE_UINT16
    je      .int32
    cmp     edi, DTYPE_UINT32
    je      .int64
    cmp     edi, DTYPE_UINT64
    je      .int64
    cmp     edi, DTYPE_FP8_E4M3
    je      .fp32
    cmp     edi, DTYPE_FP8_E5M2
    je      .fp32
    cmp     edi, DTYPE_FP16
    je      .fp32
    cmp     edi, DTYPE_BF16
    je      .fp32
    cmp     edi, DTYPE_TF32
    je      .fp32
    cmp     edi, DTYPE_FP32
    je      .fp32
    cmp     edi, DTYPE_FP64
    je      .fp64
    cmp     edi, DTYPE_FP128
    je      .fp128
    cmp     edi, DTYPE_CF16
    je      .cf32
    cmp     edi, DTYPE_CBF16
    je      .cf32
    cmp     edi, DTYPE_CF32
    je      .cf32
    cmp     edi, DTYPE_CF64
    je      .cf64
    ; MXFP8, MXFP4 etc → FP32
    cmp     edi, DTYPE_MXFP8_E4M3
    je      .fp32
    cmp     edi, DTYPE_MXFP4_E2M1
    je      .fp32
    cmp     edi, DTYPE_NVFP4
    je      .fp32
    ; INT8 accumulate into INT32 for GEMM
    cmp     edi, DTYPE_MXINT8
    je      .int32
    ; default: return same
    mov     eax, edi
    ret
.int32:  mov eax, DTYPE_INT32   ; ret
         ret
.int64:  mov eax, DTYPE_INT64   ; ret
         ret
.fp32:   mov eax, DTYPE_FP32    ; ret
         ret
.fp64:   mov eax, DTYPE_FP64    ; ret
         ret
.fp128:  mov eax, DTYPE_FP128   ; ret
         ret
.cf32:   mov eax, DTYPE_CF32    ; ret
         ret
.cf64:   mov eax, DTYPE_CF64
         ret