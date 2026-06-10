; =============================================================================
; str/convert/int.asm
; String ↔ integer conversions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; Functions:
;   str_parse_u64     — parse unsigned decimal string → uint64
;   str_parse_i64     — parse signed decimal string → int64
;   str_parse_u64_hex — parse hex string → uint64
;   str_parse_u64_bin — parse binary string → uint64
;   str_u64_to_str    — uint64 → decimal string
;   str_i64_to_str    — int64 → decimal string (with sign)
;   str_u64_to_hex    — uint64 → hex string (lowercase)
;   str_u64_to_hex_up — uint64 → hex string (uppercase)
;   str_u64_to_bin    — uint64 → binary string
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_parse_u64
;
; Parse a decimal string into a uint64_t.
; Accepts optional leading whitespace. Stops at first non-digit.
;
; Signature:
;   int64_t str_parse_u64(const StrSlice *src, uint64_t *out,
;                          uint64_t *out_consumed)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — pointer to uint64_t to receive value
;   RDX  — pointer to uint64_t to receive bytes consumed (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          src or out is null
;   RAX  = STR_ERR_PARSE         no digits found
;   RAX  = STR_ERR_OVERFLOW      value exceeds UINT64_MAX
; -----------------------------------------------------------------------------

STR_FUNC str_parse_u64

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out
    mov     r14, rdx            ; out_consumed (may be null)

    ; skip leading whitespace
    xor     r15, r15            ; index

.pu_skip_ws:
    cmp     r15, r12
    jae     .pu_no_digits

    movzx   eax, byte [rbx + r15]
    cmp     al, 0x20
    je      .pu_ws_next
    cmp     al, 0x09
    jb      .pu_start_digits
    cmp     al, 0x0D
    jbe     .pu_ws_next
    jmp     .pu_start_digits

.pu_ws_next:
    inc     r15
    jmp     .pu_skip_ws

.pu_start_digits:
    xor     r9, r9              ; accumulator
    mov     r10, r15            ; digit start index
    mov     r11, 0              ; has_digits flag

.pu_digit_loop:
    cmp     r15, r12
    jae     .pu_done

    movzx   eax, byte [rbx + r15]
    sub     eax, '0'
    cmp     eax, 9
    ja      .pu_done            ; not a digit — stop

    ; check overflow: r9 * 10 + digit > UINT64_MAX
    ; UINT64_MAX = 18446744073709551615
    ; if r9 > 1844674407370955161 → definitely overflow
    ; if r9 == 1844674407370955161 and digit > 5 → overflow
    mov     r8, 1844674407370955161
    cmp     r9, r8
    ja      .pu_overflow

    je      .pu_check_last_digit

.pu_safe_mul:
    ; r9 = r9 * 10 + digit
    imul    r9, r9, 10
    add     r9, rax
    inc     r11                 ; has_digits = true
    inc     r15
    jmp     .pu_digit_loop

.pu_check_last_digit:
    cmp     eax, 5
    ja      .pu_overflow
    jmp     .pu_safe_mul

.pu_done:
    test    r11, r11
    jz      .pu_no_digits

    mov     [r13], r9

    test    r14, r14
    jz      .pu_ok
    mov     [r14], r15

.pu_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pu_no_digits:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.pu_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

STR_ENDFUNC str_parse_u64

; -----------------------------------------------------------------------------
; str_parse_i64
;
; Parse a signed decimal string into an int64_t.
; Accepts optional leading '+' or '-'.
;
; Signature:
;   int64_t str_parse_i64(const StrSlice *src, int64_t *out,
;                          uint64_t *out_consumed)
; -----------------------------------------------------------------------------

STR_FUNC str_parse_i64

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx

    xor     r15, r15            ; index
    xor     r9,  r9             ; negative flag

    ; skip whitespace
.pi_skip_ws:
    cmp     r15, r12
    jae     .pi_no_digits

    movzx   eax, byte [rbx + r15]
    cmp     al, 0x20
    je      .pi_ws_adv
    cmp     al, 0x09
    jb      .pi_sign_check
    cmp     al, 0x0D
    jbe     .pi_ws_adv
    jmp     .pi_sign_check

.pi_ws_adv:
    inc     r15
    jmp     .pi_skip_ws

.pi_sign_check:
    movzx   eax, byte [rbx + r15]
    cmp     al, '-'
    jne     .pi_check_plus
    mov     r9, 1               ; negative
    inc     r15
    jmp     .pi_parse_digits

.pi_check_plus:
    cmp     al, '+'
    jne     .pi_parse_digits
    inc     r15

.pi_parse_digits:
    xor     r10, r10            ; accumulator
    xor     r11, r11            ; has_digits

.pi_digit_loop:
    cmp     r15, r12
    jae     .pi_done

    movzx   eax, byte [rbx + r15]
    sub     eax, '0'
    cmp     eax, 9
    ja      .pi_done

    ; overflow check for signed
    ; INT64_MAX = 9223372036854775807
    ; INT64_MIN = -9223372036854775808
    mov     r8, 922337203685477580
    cmp     r10, r8
    ja      .pi_overflow

    je      .pi_check_last

.pi_safe:
    imul    r10, r10, 10
    add     r10, rax
    inc     r11
    inc     r15
    jmp     .pi_digit_loop

.pi_check_last:
    ; if negative: can go to 8, else only 7
    test    r9, r9
    jnz     .pi_check_neg_last
    cmp     eax, 7
    ja      .pi_overflow
    jmp     .pi_safe

.pi_check_neg_last:
    cmp     eax, 8
    ja      .pi_overflow
    jmp     .pi_safe

.pi_done:
    test    r11, r11
    jz      .pi_no_digits

    ; apply sign
    test    r9, r9
    jz      .pi_positive
    neg     r10

.pi_positive:
    mov     [r13], r10

    test    r14, r14
    jz      .pi_ok
    mov     [r14], r15

.pi_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pi_no_digits:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.pi_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

STR_ENDFUNC str_parse_i64

; -----------------------------------------------------------------------------
; str_parse_u64_hex
;
; Parse a hex string (with or without "0x"/"0X" prefix) → uint64_t.
;
; Signature:
;   int64_t str_parse_u64_hex(const StrSlice *src, uint64_t *out,
;                              uint64_t *out_consumed)
; -----------------------------------------------------------------------------

STR_FUNC str_parse_u64_hex

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx

    xor     r15, r15            ; index

    ; skip "0x" or "0X" prefix
    cmp     r12, 2
    jb      .phx_digits

    movzx   eax, byte [rbx]
    cmp     al, '0'
    jne     .phx_digits

    movzx   eax, byte [rbx + 1]
    cmp     al, 'x'
    je      .phx_skip_prefix
    cmp     al, 'X'
    jne     .phx_digits

.phx_skip_prefix:
    add     r15, 2

.phx_digits:
    xor     r9, r9              ; accumulator
    xor     r10, r10            ; has_digits

.phx_loop:
    cmp     r15, r12
    jae     .phx_done

    movzx   eax, byte [rbx + r15]

    ; 0-9
    cmp     al, '0'
    jb      .phx_check_upper
    cmp     al, '9'
    ja      .phx_check_upper
    sub     al, '0'
    jmp     .phx_shift

.phx_check_upper:
    cmp     al, 'A'
    jb      .phx_check_lower
    cmp     al, 'F'
    ja      .phx_check_lower
    sub     al, 'A'
    add     al, 10
    jmp     .phx_shift

.phx_check_lower:
    cmp     al, 'a'
    jb      .phx_done
    cmp     al, 'f'
    ja      .phx_done
    sub     al, 'a'
    add     al, 10

.phx_shift:
    ; overflow: if top 4 bits of r9 are set, shifting left 4 would overflow
    mov     r8, r9
    shr     r8, 60
    test    r8, r8
    jnz     .phx_overflow

    shl     r9, 4
    or      r9b, al
    inc     r10
    inc     r15
    jmp     .phx_loop

.phx_done:
    test    r10, r10
    jz      .phx_no_digits

    mov     [r13], r9

    test    r14, r14
    jz      .phx_ok
    mov     [r14], r15

.phx_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.phx_no_digits:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.phx_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

STR_ENDFUNC str_parse_u64_hex

; -----------------------------------------------------------------------------
; str_u64_to_str
;
; Convert uint64_t to decimal string.
;
; Signature:
;   int64_t str_u64_to_str(uint64_t value, uint8_t *buf, uint64_t buf_cap,
;                           uint64_t *out_len)
;
; Arguments:
;   RDI  — value
;   RSI  — output buffer (must be >= 20 bytes for UINT64_MAX)
;   RDX  — buffer capacity
;   RCX  — pointer to uint64_t to receive string length
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL  (need at least 20 bytes)
; -----------------------------------------------------------------------------

STR_FUNC str_u64_to_str

    guard_null rsi, STR_ERR_NULL

    ; need at least 20 bytes for UINT64_MAX (20 digits)
    cmp     rdx, 20
    jb      .u2s_too_small

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; value
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    ; special case: 0
    test    rbx, rbx
    jnz     .u2s_nonzero

    mov     byte [r12], '0'
    test    r14, r14
    jz      .u2s_zero_ok
    mov     qword [r14], 1

.u2s_zero_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.u2s_nonzero:
    ; generate digits in reverse into a temp buffer on stack
    sub     rsp, 24
    and     rsp, -8

    mov     r9, rbx             ; value
    xor     r10, r10            ; digit count

.u2s_gen:
    test    r9, r9
    jz      .u2s_gen_done

    ; digit = value % 10
    mov     rax, r9
    xor     edx, edx
    mov     ecx, 10
    div     rcx                 ; rax = quotient, rdx = remainder
    add     dl, '0'
    mov     [rsp + r10], dl
    mov     r9, rax
    inc     r10
    jmp     .u2s_gen

.u2s_gen_done:
    ; reverse digits into output buffer
    xor     r11, r11

.u2s_reverse:
    cmp     r11, r10
    jae     .u2s_written

    mov     al, [rsp + r10 - r11 - 1]
    mov     [r12 + r11], al
    inc     r11
    jmp     .u2s_reverse

.u2s_written:
    mov     rsp, rbp

    test    r14, r14
    jz      .u2s_ok
    mov     [r14], r10

.u2s_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.u2s_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_u64_to_str

; -----------------------------------------------------------------------------
; str_i64_to_str
;
; Convert int64_t to decimal string (with '-' for negative).
;
; Signature:
;   int64_t str_i64_to_str(int64_t value, uint8_t *buf, uint64_t buf_cap,
;                           uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_i64_to_str

    guard_null rsi, STR_ERR_NULL

    ; need at least 21 bytes: '-' + 19 digits + null possible
    cmp     rdx, 21
    jb      .i2s_too_small

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    xor     r9, r9              ; write offset
    xor     r10, r10            ; negative flag

    ; check sign
    test    rbx, rbx
    jns     .i2s_positive

    mov     r10, 1
    neg     rbx                 ; make positive (careful: INT64_MIN)
    mov     byte [r12], '-'
    inc     r9

.i2s_positive:
    ; generate digits
    sub     rsp, 24
    and     rsp, -8

    mov     r11, rbx
    xor     ecx, ecx            ; digit count

.i2s_gen:
    test    r11, r11
    jnz     .i2s_gen_nonzero
    ; value is 0 and no digits yet → write '0'
    test    rcx, rcx
    jnz     .i2s_gen_done
    mov     byte [rsp], '0'
    mov     ecx, 1
    jmp     .i2s_gen_done

.i2s_gen_nonzero:
    mov     rax, r11
    xor     edx, edx
    mov     r8d, 10
    div     r8
    add     dl, '0'
    mov     [rsp + rcx], dl
    mov     r11, rax
    inc     ecx
    jmp     .i2s_gen

.i2s_gen_done:
    ; reverse into buf + r9
    xor     r11, r11

.i2s_reverse:
    cmp     r11, rcx
    jae     .i2s_write_done

    movzx   eax, byte [rsp + rcx - r11 - 1]
    mov     [r12 + r9 + r11], al
    inc     r11
    jmp     .i2s_reverse

.i2s_write_done:
    add     r9, rcx
    mov     rsp, rbp

    test    r14, r14
    jz      .i2s_ok
    mov     [r14], r9

.i2s_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.i2s_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_i64_to_str

; -----------------------------------------------------------------------------
; str_u64_to_hex
;
; Convert uint64_t to lowercase hex string (no "0x" prefix).
;
; Signature:
;   int64_t str_u64_to_hex(uint64_t value, uint8_t *buf, uint64_t buf_cap,
;                           uint64_t *out_len)
; -----------------------------------------------------------------------------

section .rodata
_hex_lower: db "0123456789abcdef"
_hex_upper: db "0123456789ABCDEF"

section .text

STR_FUNC str_u64_to_hex

    guard_null rsi, STR_ERR_NULL

    ; max 16 hex digits for uint64
    cmp     rdx, 16
    jb      .h2s_too_small

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; value
    mov     r12, rsi            ; buf
    mov     r13, rdx
    mov     r14, rcx            ; out_len

    lea     r9, [rel _hex_lower]

    ; special case: 0
    test    rbx, rbx
    jnz     .h2s_nonzero

    mov     byte [r12], '0'
    test    r14, r14
    jz      .h2s_zero_ok
    mov     qword [r14], 1

.h2s_zero_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.h2s_nonzero:
    ; find highest non-zero nibble
    mov     r10, 15             ; nibble index (0 = lowest)
    mov     r11, rbx

.h2s_find_top:
    mov     rax, r11
    shr     rax, cl             ; shift by nibble*4... wrong approach
    ; use a different approach: generate all 16 nibbles, skip leading zeros

    ; generate from most significant nibble
    xor     r10, r10            ; output index
    xor     r11, r11            ; leading zeros flag
    mov     ecx, 60             ; start shift

.h2s_nibble_loop:
    ; extract nibble at shift position
    mov     rax, rbx
    shr     rax, cl
    and     eax, 0xF

    ; skip leading zeros
    test    r11, r11
    jnz     .h2s_write_nibble

    test    eax, eax
    jz      .h2s_next_nibble

    mov     r11, 1              ; end of leading zeros

.h2s_write_nibble:
    movzx   eax, byte [r9 + rax]
    mov     [r12 + r10], al
    inc     r10

.h2s_next_nibble:
    sub     ecx, 4
    cmp     ecx, 0
    jge     .h2s_nibble_loop

    ; last nibble (shift 0)
    mov     rax, rbx
    and     eax, 0xF
    test    r11, r11
    jnz     .h2s_write_last

    ; value was 0 - already handled
    test    eax, eax
    jz      .h2s_done_hex

.h2s_write_last:
    movzx   eax, byte [r9 + rax]
    mov     [r12 + r10], al
    inc     r10

.h2s_done_hex:
    test    r14, r14
    jz      .h2s_ok
    mov     [r14], r10

.h2s_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.h2s_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_u64_to_hex

; -----------------------------------------------------------------------------
; str_u64_to_hex_up — uppercase hex variant
; -----------------------------------------------------------------------------

STR_FUNC str_u64_to_hex_up

    guard_null rsi, STR_ERR_NULL

    cmp     rdx, 16
    jb      .hu_too_small

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    lea     r9, [rel _hex_upper]

    test    rbx, rbx
    jnz     .hu_nonzero

    mov     byte [r12], '0'
    test    r14, r14
    jz      .hu_zero_ok
    mov     qword [r14], 1

.hu_zero_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.hu_nonzero:
    xor     r10, r10
    xor     r11, r11
    mov     ecx, 60

.hu_nibble_loop:
    mov     rax, rbx
    shr     rax, cl
    and     eax, 0xF

    test    r11, r11
    jnz     .hu_write

    test    eax, eax
    jz      .hu_next

    mov     r11, 1

.hu_write:
    movzx   eax, byte [r9 + rax]
    mov     [r12 + r10], al
    inc     r10

.hu_next:
    sub     ecx, 4
    cmp     ecx, 0
    jge     .hu_nibble_loop

    mov     rax, rbx
    and     eax, 0xF
    test    r11, r11
    jnz     .hu_last_write
    test    eax, eax
    jz      .hu_done

.hu_last_write:
    movzx   eax, byte [r9 + rax]
    mov     [r12 + r10], al
    inc     r10

.hu_done:
    test    r14, r14
    jz      .hu_ok
    mov     [r14], r10

.hu_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.hu_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_u64_to_hex_up

; -----------------------------------------------------------------------------
; str_parse_u64_bin
;
; Parse a binary string ("0b" prefix optional) → uint64_t.
;
; Signature:
;   int64_t str_parse_u64_bin(const StrSlice *src, uint64_t *out,
;                              uint64_t *out_consumed)
; -----------------------------------------------------------------------------

STR_FUNC str_parse_u64_bin

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx

    xor     r15, r15

    ; skip "0b" or "0B"
    cmp     r12, 2
    jb      .pbin_digits

    movzx   eax, byte [rbx]
    cmp     al, '0'
    jne     .pbin_digits
    movzx   eax, byte [rbx + 1]
    cmp     al, 'b'
    je      .pbin_skip
    cmp     al, 'B'
    jne     .pbin_digits

.pbin_skip:
    add     r15, 2

.pbin_digits:
    xor     r9, r9              ; accumulator
    xor     r10, r10            ; has_digits

.pbin_loop:
    cmp     r15, r12
    jae     .pbin_done

    movzx   eax, byte [rbx + r15]
    cmp     al, '0'
    je      .pbin_zero
    cmp     al, '1'
    jne     .pbin_done
    ; bit = 1

    ; overflow: if bit 63 set, shifting left would overflow
    bt      r9, 63
    jc      .pbin_overflow

    shl     r9, 1
    or      r9, 1
    jmp     .pbin_cont

.pbin_zero:
    bt      r9, 63
    jc      .pbin_overflow
    shl     r9, 1

.pbin_cont:
    inc     r10
    inc     r15
    jmp     .pbin_loop

.pbin_done:
    test    r10, r10
    jz      .pbin_no_digits

    mov     [r13], r9

    test    r14, r14
    jz      .pbin_ok
    mov     [r14], r15

.pbin_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pbin_no_digits:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.pbin_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

STR_ENDFUNC str_parse_u64_bin
