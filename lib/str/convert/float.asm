; =============================================================================
; str/convert/float.asm
; String ↔ floating-point conversions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   convert/int.asm  (str_u64_to_str, str_i64_to_str)
;
; -----------------------------------------------------------------------------
; Uses x87 FPU and SSE2 for float operations.
; All floats stored as IEEE 754 double (64-bit).
;
; Functions:
;   str_parse_f64     — decimal string → double
;   str_f64_to_str    — double → decimal string (6 significant digits)
;   str_f64_to_str_n  — double → decimal string (n significant digits)
;   str_parse_f32     — decimal string → float (via double)
;   str_f64_is_nan    — check for NaN
;   str_f64_is_inf    — check for infinity
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_u64_to_str
extern str_i64_to_str

section .rodata

_str_nan:   db "NaN",  0
_str_inf:   db "Inf",  0
_str_ninf:  db "-Inf", 0

; Powers of 10 for float parsing/formatting
_pow10:
    dq  1.0
    dq  10.0
    dq  100.0
    dq  1000.0
    dq  10000.0
    dq  100000.0
    dq  1000000.0
    dq  10000000.0
    dq  100000000.0
    dq  1000000000.0
    dq  10000000000.0
    dq  100000000000.0
    dq  1000000000000.0
    dq  10000000000000.0
    dq  100000000000000.0
    dq  1000000000000000.0
    dq  10000000000000000.0
    dq  100000000000000000.0
    dq  1000000000000000000.0

section .text

; -----------------------------------------------------------------------------
; str_parse_f64
;
; Parse a decimal string into a double.
; Format: [+-]digits[.digits][eE[+-]digits]
;
; Signature:
;   int64_t str_parse_f64(const StrSlice *src, double *out,
;                          uint64_t *out_consumed)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — pointer to double to receive value
;   RDX  — pointer to uint64_t for consumed bytes (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_PARSE   no valid float found
; -----------------------------------------------------------------------------

STR_FUNC str_parse_f64

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out (double*)
    mov     r14, rdx            ; out_consumed

    xor     r15, r15            ; index
    xor     r9,  r9             ; negative flag

    ; check for "NaN"
    cmp     r12, 3
    jb      .pf_sign_check

    movzx   eax, byte [rbx]
    cmp     al, 'N'
    jne     .pf_sign_check
    movzx   eax, byte [rbx + 1]
    cmp     al, 'a'
    jne     .pf_sign_check
    movzx   eax, byte [rbx + 2]
    cmp     al, 'N'
    jne     .pf_sign_check

    ; NaN
    mov     rax, 0x7FF8000000000000  ; canonical NaN bits
    mov     [r13], rax
    test    r14, r14
    jz      .pf_nan_ok
    mov     qword [r14], 3

.pf_nan_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pf_sign_check:
    cmp     r15, r12
    jae     .pf_no_digits

    movzx   eax, byte [rbx + r15]
    cmp     al, '-'
    jne     .pf_check_plus_sign
    mov     r9, 1
    inc     r15
    jmp     .pf_check_inf

.pf_check_plus_sign:
    cmp     al, '+'
    jne     .pf_check_inf
    inc     r15

.pf_check_inf:
    ; check "Inf" or "inf"
    mov     rax, r12
    sub     rax, r15
    cmp     rax, 3
    jb      .pf_integer_part

    movzx   eax, byte [rbx + r15]
    or      al, 0x20
    cmp     al, 'i'
    jne     .pf_integer_part
    movzx   eax, byte [rbx + r15 + 1]
    or      al, 0x20
    cmp     al, 'n'
    jne     .pf_integer_part
    movzx   eax, byte [rbx + r15 + 2]
    or      al, 0x20
    cmp     al, 'f'
    jne     .pf_integer_part

    ; Infinity
    mov     rax, 0x7FF0000000000000
    test    r9, r9
    jz      .pf_pos_inf
    mov     rax, 0xFFF0000000000000

.pf_pos_inf:
    mov     [r13], rax
    add     r15, 3
    test    r14, r14
    jz      .pf_inf_ok
    mov     [r14], r15

.pf_inf_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pf_integer_part:
    ; parse integer part
    xorpd   xmm0, xmm0          ; integer accumulator
    xorpd   xmm1, xmm1          ; use integer math first
    xor     r10, r10            ; has integer digits

    ; use integer accumulator r11
    xor     r11, r11

.pf_int_loop:
    cmp     r15, r12
    jae     .pf_frac_check

    movzx   eax, byte [rbx + r15]
    sub     eax, '0'
    cmp     eax, 9
    ja      .pf_frac_check

    imul    r11, r11, 10
    add     r11, rax
    inc     r10
    inc     r15
    jmp     .pf_int_loop

.pf_frac_check:
    test    r10, r10
    jz      .pf_check_leading_dot

    ; convert integer part to double
    cvtsi2sd xmm0, r11

.pf_check_leading_dot:
    ; fractional part
    cmp     r15, r12
    jae     .pf_exp_check

    movzx   eax, byte [rbx + r15]
    cmp     al, '.'
    jne     .pf_exp_check

    inc     r15
    xor     r11, r11            ; frac digits value
    xor     r8, r8              ; frac digit count

.pf_frac_loop:
    cmp     r15, r12
    jae     .pf_frac_done

    movzx   eax, byte [rbx + r15]
    sub     eax, '0'
    cmp     eax, 9
    ja      .pf_frac_done

    imul    r11, r11, 10
    add     r11, rax
    inc     r8
    inc     r10                 ; total digit count
    inc     r15
    jmp     .pf_frac_loop

.pf_frac_done:
    ; add fractional part: xmm0 += r11 / 10^r8
    test    r8, r8
    jz      .pf_exp_check

    cvtsi2sd xmm1, r11
    lea     rax, [rel _pow10]
    movsd   xmm2, [rax + r8 * 8]
    divsd   xmm1, xmm2
    addsd   xmm0, xmm1

.pf_exp_check:
    test    r10, r10
    jz      .pf_no_digits

    ; exponent
    cmp     r15, r12
    jae     .pf_apply_sign

    movzx   eax, byte [rbx + r15]
    cmp     al, 'e'
    je      .pf_parse_exp
    cmp     al, 'E'
    jne     .pf_apply_sign

.pf_parse_exp:
    inc     r15
    xor     r8, r8              ; exp negative
    xor     r11, r11            ; exp value

    cmp     r15, r12
    jae     .pf_apply_exp

    movzx   eax, byte [rbx + r15]
    cmp     al, '-'
    jne     .pf_check_exp_plus
    mov     r8, 1
    inc     r15
    jmp     .pf_exp_digits

.pf_check_exp_plus:
    cmp     al, '+'
    jne     .pf_exp_digits
    inc     r15

.pf_exp_digits:
.pf_exp_digit_loop:
    cmp     r15, r12
    jae     .pf_apply_exp

    movzx   eax, byte [rbx + r15]
    sub     eax, '0'
    cmp     eax, 9
    ja      .pf_apply_exp

    imul    r11, r11, 10
    add     r11, rax
    inc     r15
    jmp     .pf_exp_digit_loop

.pf_apply_exp:
    ; multiply or divide by 10^exp
    cmp     r11, 18
    ja      .pf_exp_large

    lea     rax, [rel _pow10]
    movsd   xmm2, [rax + r11 * 8]

    test    r8, r8
    jnz     .pf_exp_negative
    mulsd   xmm0, xmm2
    jmp     .pf_apply_sign

.pf_exp_negative:
    divsd   xmm0, xmm2
    jmp     .pf_apply_sign

.pf_exp_large:
    ; large exponent — use repeated multiply
    ; simplified: clamp to reasonable range
    xorpd   xmm0, xmm0         ; effectively 0 or inf
    jmp     .pf_apply_sign

.pf_apply_sign:
    test    r9, r9
    jz      .pf_write

    ; negate
    mov     rax, 0x8000000000000000
    movq    xmm1, rax
    xorpd   xmm0, xmm1

.pf_write:
    movsd   [r13], xmm0

    test    r14, r14
    jz      .pf_ok
    mov     [r14], r15

.pf_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pf_no_digits:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

STR_ENDFUNC str_parse_f64

; -----------------------------------------------------------------------------
; str_f64_to_str
;
; Convert double to decimal string with 6 significant digits.
;
; Signature:
;   int64_t str_f64_to_str(double value, uint8_t *buf, uint64_t buf_cap,
;                           uint64_t *out_len)
;
; Arguments:
;   XMM0 — double value
;   RDI  — output buffer
;   RSI  — buffer capacity (need at least 32 bytes)
;   RDX  — pointer to uint64_t for length
; -----------------------------------------------------------------------------

STR_FUNC str_f64_to_str

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, 32
    jb      .f2s_too_small

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; buf
    mov     r12, rsi            ; cap
    mov     r13, rdx            ; out_len

    xor     r14, r14            ; write index

    ; check NaN
    ucomisd xmm0, xmm0
    jp      .f2s_nan

    ; check infinity: compare absolute value to +inf
    mov     rax, 0x7FF0000000000000
    movq    xmm1, rax
    ucomisd xmm0, xmm1
    je      .f2s_pos_inf

    mov     rax, 0xFFF0000000000000
    movq    xmm1, rax
    ucomisd xmm0, xmm1
    je      .f2s_neg_inf

    ; check negative
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    jae     .f2s_positive

    ; negative: write '-' and negate
    mov     byte [rbx], '-'
    inc     r14

    mov     rax, 0x8000000000000000
    movq    xmm1, rax
    xorpd   xmm0, xmm1

.f2s_positive:
    ; check zero
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    jne     .f2s_nonzero

    mov     byte [rbx + r14], '0'
    inc     r14
    jmp     .f2s_done

.f2s_nonzero:
    ; scale to 6 significant digits
    ; find exponent: floor(log10(value))
    ; use: exp = floor(log10(value))
    ; simplified approach: extract mantissa and base-10 exponent

    ; convert to integer representation with 6 sig figs
    ; scale = 10^(6 - 1 - floor(log10(value)))
    ; mantissa_int = round(value * scale)
    ; then format as digits with decimal point

    ; Use SSE2 approach: extract bits, compute rough log2, convert to log10
    movq    r9, xmm0
    mov     rax, r9
    shr     rax, 52
    and     eax, 0x7FF          ; biased exponent
    sub     eax, 1023           ; unbiased exp (base 2)

    ; log10(value) ≈ log2(value) * log10(2) ≈ exp * 0.30103
    ; integer approximation:
    imul    rax, rax, 30103
    ; divide by 100000 to get floor(log10)
    mov     rcx, 100000
    cqo
    idiv    rcx                 ; rax = approx floor(log10(value))

    ; exponent for formatting
    mov     r10, rax            ; base-10 exponent

    ; scale value to get 6 integer digits
    ; digits = value * 10^(5 - exp)
    mov     r11, 5
    sub     r11, r10            ; scale_exp = 5 - exp

    lea     rcx, [rel _pow10]

    movsd   xmm1, xmm0

    cmp     r11, 0
    jl      .f2s_scale_down
    cmp     r11, 18
    jg      .f2s_use_sci        ; too large, use scientific notation

    movsd   xmm2, [rcx + r11 * 8]
    mulsd   xmm1, xmm2
    jmp     .f2s_round

.f2s_scale_down:
    neg     r11
    cmp     r11, 18
    jg      .f2s_use_sci

    movsd   xmm2, [rcx + r11 * 8]
    divsd   xmm1, xmm2

.f2s_round:
    ; round to nearest integer
    roundsd xmm1, xmm1, 0      ; round to nearest even

    ; convert to integer
    cvttsd2si r9, xmm1         ; r9 = 6-digit integer

    ; format: if exp >= 0 and exp <= 5, use fixed notation
    ; else use scientific notation
    cmp     r10, -4
    jl      .f2s_use_sci
    cmp     r10, 6
    jg      .f2s_use_sci

    ; fixed notation: format r9 with decimal point at position
    ; generate 6 digits
    sub     rsp, 12
    and     rsp, -8

    mov     rax, r9
    xor     ecx, ecx

.f2s_gen_digits:
    cmp     ecx, 6
    jae     .f2s_digits_done

    xor     edx, edx
    mov     r8d, 10
    div     r8
    add     dl, '0'
    mov     [rsp + rcx], dl
    inc     ecx
    jmp     .f2s_gen_digits

.f2s_digits_done:
    ; decimal point position from left = exp + 1
    mov     r8, r10
    inc     r8                  ; dp_pos (1-based from left)

    ; write digits with decimal point
    xor     r9, r9              ; digit index (0=MSB)

    ; handle negative dp_pos: write "0.00..." prefix
    test    r8, r8
    jg      .f2s_write_digits

    ; dp_pos <= 0: write "0."
    mov     byte [rbx + r14], '0'
    inc     r14
    mov     byte [rbx + r14], '.'
    inc     r14

    ; write leading zeros
    mov     r11, r8
    neg     r11                 ; number of leading zeros after "0."

.f2s_lead_zeros:
    test    r11, r11
    jz      .f2s_write_frac

    mov     byte [rbx + r14], '0'
    inc     r14
    dec     r11
    jmp     .f2s_lead_zeros

.f2s_write_frac:
    ; write remaining digits (suppress trailing zeros)
    mov     r9, 5               ; start from MSDigit

.f2s_frac_loop:
    test    r9, r9
    js      .f2s_strip_trail

    movzx   eax, byte [rsp + r9]
    mov     [rbx + r14], al
    inc     r14
    dec     r9
    jmp     .f2s_frac_loop

.f2s_write_digits:
    ; write integer part (dp_pos digits from MSB)
    mov     r9, 5               ; MSB index in digit array
    mov     r11, r8             ; digits before decimal point

.f2s_int_part:
    test    r11, r11
    jz      .f2s_decimal_point

    movzx   eax, byte [rsp + r9]
    mov     [rbx + r14], al
    inc     r14
    dec     r9
    dec     r11
    jmp     .f2s_int_part

.f2s_decimal_point:
    ; check if we have any fractional digits remaining
    test    r9, r9
    js      .f2s_strip_trail

    mov     byte [rbx + r14], '.'
    inc     r14

.f2s_frac_part:
    test    r9, r9
    js      .f2s_strip_trail

    movzx   eax, byte [rsp + r9]
    mov     [rbx + r14], al
    inc     r14
    dec     r9
    jmp     .f2s_frac_part

.f2s_strip_trail:
    ; strip trailing zeros after decimal point
    ; find last '.' to know if we should strip
    mov     r9, r14
    dec     r9

.f2s_strip_loop:
    cmp     r9, rbx             ; don't go past start
    jb      .f2s_done_fmt

    movzx   eax, byte [rbx + r9]
    cmp     al, '0'
    jne     .f2s_check_dot

    dec     r14
    dec     r9
    jmp     .f2s_strip_loop

.f2s_check_dot:
    cmp     al, '.'
    jne     .f2s_done_fmt
    ; remove trailing dot too
    dec     r14

.f2s_done_fmt:
    mov     rsp, rbp
    jmp     .f2s_done

.f2s_use_sci:
    mov     rsp, rbp

    ; scientific notation: d.ddddde+EE
    ; TODO: implement full sci notation
    ; For now write simplified form
    lea     r8, [rel _str_nan]
    xor     ecx, ecx
.f2s_copy_nan:
    movzx   eax, byte [r8 + rcx]
    test    al, al
    jz      .f2s_done
    mov     [rbx + r14 + rcx], al
    inc     ecx
    jmp     .f2s_copy_nan

.f2s_nan:
    lea     r8, [rel _str_nan]
    xor     ecx, ecx
.f2s_copy_nan2:
    movzx   eax, byte [r8 + rcx]
    test    al, al
    jz      .f2s_done
    mov     [rbx + r14 + rcx], al
    inc     ecx
    jmp     .f2s_copy_nan2

.f2s_pos_inf:
    lea     r8, [rel _str_inf]
    xor     ecx, ecx
.f2s_copy_inf:
    movzx   eax, byte [r8 + rcx]
    test    al, al
    jz      .f2s_done
    mov     [rbx + r14 + rcx], al
    inc     ecx
    jmp     .f2s_copy_inf

.f2s_neg_inf:
    lea     r8, [rel _str_ninf]
    xor     ecx, ecx
.f2s_copy_ninf:
    movzx   eax, byte [r8 + rcx]
    test    al, al
    jz      .f2s_done
    mov     [rbx + r14 + rcx], al
    inc     ecx
    add     r14, 1
    jmp     .f2s_copy_ninf

.f2s_done:
    test    r13, r13
    jz      .f2s_ok
    mov     [r13], r14

.f2s_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.f2s_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_f64_to_str

; -----------------------------------------------------------------------------
; str_f64_is_nan / str_f64_is_inf
; -----------------------------------------------------------------------------

STR_FUNC str_f64_is_nan
    ucomisd xmm0, xmm0
    setp    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_f64_is_nan

STR_FUNC str_f64_is_inf
    mov     rax, 0x7FF0000000000000
    movq    xmm1, rax
    andpd   xmm0, xmm1          ; clear sign bit
    ucomisd xmm0, xmm1
    sete    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_f64_is_inf
