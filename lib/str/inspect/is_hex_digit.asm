; =============================================================================
; str/inspect/is_hex_digit.asm
; Check whether a codepoint or string contains only hexadecimal digits.
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
; Hex digit ranges:
;   0-9  → 0x30..0x39
;   A-F  → 0x41..0x46  (uppercase)
;   a-f  → 0x61..0x66  (lowercase)
;
; Functions:
;   str_is_hex_digit_cp      — accepts 0-9, A-F, a-f
;   str_is_hex_digit_upper_cp — accepts 0-9, A-F only
;   str_is_hex_digit_lower_cp — accepts 0-9, a-f only
;   str_is_hex_digit          — full UTF-8 string check (mixed case)
;   str_is_hex_digit_upper    — full string, uppercase only
;   str_is_hex_digit_lower    — full string, lowercase only
;   str_is_hex_string         — alias for str_is_hex_digit
;   str_hex_digit_value       — codepoint → numeric value 0..15
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_is_hex_digit_cp
;
; Check if a codepoint is a hex digit (0-9, A-F, a-f).
;
; Signature:
;   int64_t str_is_hex_digit_cp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1  hex digit
;   RAX  = 0  not a hex digit
; -----------------------------------------------------------------------------

STR_FUNC str_is_hex_digit_cp

    ; 0-9
    cmp     edi, '0'
    jb      .check_upper
    cmp     edi, '9'
    jbe     .true

.check_upper:
    ; A-F
    cmp     edi, 'A'
    jb      .check_lower
    cmp     edi, 'F'
    jbe     .true

.check_lower:
    ; a-f
    cmp     edi, 'a'
    jb      .false
    cmp     edi, 'f'
    jbe     .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_hex_digit_cp

; -----------------------------------------------------------------------------
; str_is_hex_digit_upper_cp
;
; Check if a codepoint is an uppercase hex digit (0-9, A-F only).
;
; Signature:
;   int64_t str_is_hex_digit_upper_cp(uint32_t cp)
; -----------------------------------------------------------------------------

STR_FUNC str_is_hex_digit_upper_cp

    ; 0-9
    cmp     edi, '0'
    jb      .check_upper
    cmp     edi, '9'
    jbe     .true

.check_upper:
    ; A-F only
    cmp     edi, 'A'
    jb      .false
    cmp     edi, 'F'
    jbe     .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_hex_digit_upper_cp

; -----------------------------------------------------------------------------
; str_is_hex_digit_lower_cp
;
; Check if a codepoint is a lowercase hex digit (0-9, a-f only).
;
; Signature:
;   int64_t str_is_hex_digit_lower_cp(uint32_t cp)
; -----------------------------------------------------------------------------

STR_FUNC str_is_hex_digit_lower_cp

    ; 0-9
    cmp     edi, '0'
    jb      .check_lower
    cmp     edi, '9'
    jbe     .true

.check_lower:
    ; a-f only
    cmp     edi, 'a'
    jb      .false
    cmp     edi, 'f'
    jbe     .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_hex_digit_lower_cp

; -----------------------------------------------------------------------------
; str_hex_digit_value
;
; Convert a hex digit codepoint to its numeric value (0..15).
;
; Signature:
;   int64_t str_hex_digit_value(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint (must be valid hex digit)
;
; Returns:
;   RAX  = 0..15             numeric value
;   RAX  = STR_ERR_INVALID_ARG  not a hex digit
; -----------------------------------------------------------------------------

STR_FUNC str_hex_digit_value

    ; 0-9 → value = cp - '0'
    cmp     edi, '0'
    jb      .check_upper_val
    cmp     edi, '9'
    ja      .check_upper_val
    movzx   eax, dil
    sub     eax, '0'
    pop     rbp
    ret

.check_upper_val:
    ; A-F → value = cp - 'A' + 10
    cmp     edi, 'A'
    jb      .check_lower_val
    cmp     edi, 'F'
    ja      .check_lower_val
    movzx   eax, dil
    sub     eax, 'A'
    add     eax, 10
    pop     rbp
    ret

.check_lower_val:
    ; a-f → value = cp - 'a' + 10
    cmp     edi, 'a'
    jb      .invalid_val
    cmp     edi, 'f'
    ja      .invalid_val
    movzx   eax, dil
    sub     eax, 'a'
    add     eax, 10
    pop     rbp
    ret

.invalid_val:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_hex_digit_value

; -----------------------------------------------------------------------------
; str_is_hex_digit
;
; Check if every byte in a buffer is a hex digit (0-9, A-F, a-f).
; ASCII-only fast path — no UTF-8 decoding needed (hex is always ASCII).
; Empty string returns 0.
;
; Signature:
;   int64_t str_is_hex_digit(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  all hex digits, non-empty
;   RAX  = 0  empty or any non-hex byte
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_is_hex_digit

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.hex_loop:
    cmp     rbx, r12
    jae     .all_hex

    movzx   eax, byte [rbx]
    inc     rbx

    ; 0-9
    cmp     al, '0'
    jb      .check_hex_upper
    cmp     al, '9'
    jbe     .hex_loop

.check_hex_upper:
    ; A-F
    cmp     al, 'A'
    jb      .check_hex_lower
    cmp     al, 'F'
    jbe     .hex_loop

.check_hex_lower:
    ; a-f
    cmp     al, 'a'
    jb      .not_hex
    cmp     al, 'f'
    jbe     .hex_loop

.not_hex:
    pop_regs r12, rbx
    mov     eax, STR_FALSE
    pop     rbp
    ret

.all_hex:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_hex_digit

; -----------------------------------------------------------------------------
; str_is_hex_digit_upper — 0-9, A-F only string check
; -----------------------------------------------------------------------------

STR_FUNC str_is_hex_digit_upper

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.hxu_loop:
    cmp     rbx, r12
    jae     .hxu_true

    movzx   eax, byte [rbx]
    inc     rbx

    cmp     al, '0'
    jb      .hxu_check_af
    cmp     al, '9'
    jbe     .hxu_loop

.hxu_check_af:
    cmp     al, 'A'
    jb      .hxu_false
    cmp     al, 'F'
    jbe     .hxu_loop

.hxu_false:
    pop_regs r12, rbx
    mov     eax, STR_FALSE
    pop     rbp
    ret

.hxu_true:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_hex_digit_upper

; -----------------------------------------------------------------------------
; str_is_hex_digit_lower — 0-9, a-f only string check
; -----------------------------------------------------------------------------

STR_FUNC str_is_hex_digit_lower

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.hxl_loop:
    cmp     rbx, r12
    jae     .hxl_true

    movzx   eax, byte [rbx]
    inc     rbx

    cmp     al, '0'
    jb      .hxl_check_af
    cmp     al, '9'
    jbe     .hxl_loop

.hxl_check_af:
    cmp     al, 'a'
    jb      .hxl_false
    cmp     al, 'f'
    jbe     .hxl_loop

.hxl_false:
    pop_regs r12, rbx
    mov     eax, STR_FALSE
    pop     rbp
    ret

.hxl_true:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_hex_digit_lower

; -----------------------------------------------------------------------------
; str_is_hex_digit_slice / str_is_hex_digit_upper_slice
; str_is_hex_digit_lower_slice — StrSlice wrappers
; -----------------------------------------------------------------------------

STR_FUNC str_is_hex_digit_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_hex_digit

STR_ENDFUNC str_is_hex_digit_slice

STR_FUNC str_is_hex_digit_upper_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_hex_digit_upper

STR_ENDFUNC str_is_hex_digit_upper_slice

STR_FUNC str_is_hex_digit_lower_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_hex_digit_lower

STR_ENDFUNC str_is_hex_digit_lower_slice