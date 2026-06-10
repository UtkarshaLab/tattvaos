; =============================================================================
; str/inspect/is_numeric.asm
; Check whether a codepoint or string contains only numeric characters.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; Three levels of "numeric":
;
;   ASCII digit:     0x30..0x39  (0-9)  — str_is_digit_cp
;   Decimal digit:   Unicode Nd category — ASCII + Arabic-Indic + Devanagari
;                    + many other script digit ranges
;   Numeric:         Unicode Nd + No + Nl — includes fractions, Roman
;                    numerals, circled numbers etc.
;
; For the common case (ASCII 0-9) use str_is_digit_cp / str_is_digit.
; For Unicode decimal digits use str_is_decimal_cp.
; For full Unicode numeric category use str_is_numeric_cp.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_is_digit_cp
;
; ASCII digit check: codepoint in 0x30..0x39 (0-9).
;
; Signature:
;   int64_t str_is_digit_cp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1  cp is ASCII digit
;   RAX  = 0  not an ASCII digit
; -----------------------------------------------------------------------------

STR_FUNC str_is_digit_cp

    sub     edi, '0'
    cmp     edi, 9
    setbe   al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_is_digit_cp

; -----------------------------------------------------------------------------
; str_is_decimal_cp
;
; Unicode decimal digit check (category Nd).
; Covers all script decimal digit ranges — not just ASCII.
;
; Signature:
;   int64_t str_is_decimal_cp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1  decimal digit in any script
;   RAX  = 0  not a decimal digit
; -----------------------------------------------------------------------------

STR_FUNC str_is_decimal_cp

    ; ASCII 0-9
    cmp     edi, '0'
    jb      .check_arabic_indic
    cmp     edi, '9'
    jbe     .true

.check_arabic_indic:
    ; Arabic-Indic: 0x0660..0x0669
    cmp     edi, 0x0660
    jb      .check_extended_arabic
    cmp     edi, 0x0669
    jbe     .true

.check_extended_arabic:
    ; Extended Arabic-Indic: 0x06F0..0x06F9
    cmp     edi, 0x06F0
    jb      .check_devanagari
    cmp     edi, 0x06F9
    jbe     .true

.check_devanagari:
    ; Devanagari: 0x0966..0x096F (Nepali/Hindi digits)
    cmp     edi, 0x0966
    jb      .check_bengali
    cmp     edi, 0x096F
    jbe     .true

.check_bengali:
    ; Bengali: 0x09E6..0x09EF
    cmp     edi, 0x09E6
    jb      .check_gurmukhi
    cmp     edi, 0x09EF
    jbe     .true

.check_gurmukhi:
    ; Gurmukhi: 0x0A66..0x0A6F
    cmp     edi, 0x0A66
    jb      .check_gujarati
    cmp     edi, 0x0A6F
    jbe     .true

.check_gujarati:
    ; Gujarati: 0x0AE6..0x0AEF
    cmp     edi, 0x0AE6
    jb      .check_oriya
    cmp     edi, 0x0AEF
    jbe     .true

.check_oriya:
    ; Oriya: 0x0B66..0x0B6F
    cmp     edi, 0x0B66
    jb      .check_tamil
    cmp     edi, 0x0B6F
    jbe     .true

.check_tamil:
    ; Tamil: 0x0BE6..0x0BEF
    cmp     edi, 0x0BE6
    jb      .check_telugu
    cmp     edi, 0x0BEF
    jbe     .true

.check_telugu:
    ; Telugu: 0x0C66..0x0C6F
    cmp     edi, 0x0C66
    jb      .check_kannada
    cmp     edi, 0x0C6F
    jbe     .true

.check_kannada:
    ; Kannada: 0x0CE6..0x0CEF
    cmp     edi, 0x0CE6
    jb      .check_thai
    cmp     edi, 0x0CEF
    jbe     .true

.check_thai:
    ; Thai: 0x0E50..0x0E59
    cmp     edi, 0x0E50
    jb      .check_fullwidth
    cmp     edi, 0x0E59
    jbe     .true

.check_fullwidth:
    ; Fullwidth digits: 0xFF10..0xFF19
    cmp     edi, 0xFF10
    jb      .false
    cmp     edi, 0xFF19
    jbe     .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_decimal_cp

; -----------------------------------------------------------------------------
; str_is_numeric_cp
;
; Broader numeric check — decimal digits + fractions + Roman numerals
; + circled/superscript/subscript numbers (Unicode Nd + No + Nl).
;
; Signature:
;   int64_t str_is_numeric_cp(uint32_t cp)
; -----------------------------------------------------------------------------

STR_FUNC str_is_numeric_cp

    push_regs rbx
    mov     ebx, edi

    ; first check decimal
    call    str_is_decimal_cp
    test    eax, eax
    jnz     .true_numeric

    mov     edi, ebx

    ; Vulgar fractions: 0x00BC..0x00BE (¼ ½ ¾)
    cmp     edi, 0x00BC
    jb      .check_superscript_nums
    cmp     edi, 0x00BE
    jbe     .true_numeric

.check_superscript_nums:
    ; Superscript 2,3,1: 0x00B2, 0x00B3, 0x00B9
    cmp     edi, 0x00B2
    je      .true_numeric
    cmp     edi, 0x00B3
    je      .true_numeric
    cmp     edi, 0x00B9
    je      .true_numeric

    ; Superscript digits: 0x2070..0x2079
    cmp     edi, 0x2070
    jb      .check_subscript_nums
    cmp     edi, 0x2079
    jbe     .true_numeric

.check_subscript_nums:
    ; Subscript digits: 0x2080..0x2089
    cmp     edi, 0x2080
    jb      .check_circled
    cmp     edi, 0x2089
    jbe     .true_numeric

.check_circled:
    ; Circled digits: 0x2460..0x2473
    cmp     edi, 0x2460
    jb      .check_roman
    cmp     edi, 0x2473
    jbe     .true_numeric

.check_roman:
    ; Roman numerals: 0x2160..0x2188
    cmp     edi, 0x2160
    jb      .false_numeric
    cmp     edi, 0x2188
    jbe     .true_numeric

.false_numeric:
    pop_regs rbx
    xor     eax, eax
    pop     rbp
    ret

.true_numeric:
    pop_regs rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_numeric_cp

; -----------------------------------------------------------------------------
; str_is_digit
;
; Check if every codepoint in a UTF-8 string is an ASCII digit (0-9).
; Empty string returns 0.
;
; Signature:
;   int64_t str_is_digit(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  all codepoints are ASCII digits, string non-empty
;   RAX  = 0  empty or any codepoint is not 0-9
;   RAX  = STR_ERR_NULL  ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_is_digit

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.digit_loop:
    cmp     rbx, r12
    jae     .all_digit

    movzx   eax, byte [rbx]

    ; fast ASCII check: subtract '0', compare <= 9
    sub     eax, '0'
    cmp     eax, 9
    ja      .not_digit

    inc     rbx
    jmp     .digit_loop

.all_digit:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_digit:
    pop_regs r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_digit

; -----------------------------------------------------------------------------
; str_is_numeric
;
; Check if every codepoint in a UTF-8 string is numeric (Unicode Nd/No/Nl).
;
; Signature:
;   int64_t str_is_numeric(const uint8_t *ptr, uint64_t byte_len)
; -----------------------------------------------------------------------------

STR_FUNC str_is_numeric

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.num_loop:
    cmp     rbx, r12
    jae     .all_numeric

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r13, [rsp]
    mov     rsp, rbp
    add     rbx, r13

    mov     edi, eax
    push    rbx
    push    r12
    call    str_is_numeric_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .not_numeric

    jmp     .num_loop

.all_numeric:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_numeric:
    pop_regs r13, r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_numeric

; -----------------------------------------------------------------------------
; str_is_digit_slice / str_is_numeric_slice — StrSlice wrappers
; -----------------------------------------------------------------------------

STR_FUNC str_is_digit_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_digit

STR_ENDFUNC str_is_digit_slice

STR_FUNC str_is_numeric_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_numeric

STR_ENDFUNC str_is_numeric_slice