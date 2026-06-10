; =============================================================================
; str/inspect/is_space.asm
; Check whether a codepoint or string contains only whitespace characters.
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
; Whitespace codepoints covered:
;
;   ASCII whitespace (C isspace):
;     0x09  HT   horizontal tab
;     0x0A  LF   line feed
;     0x0B  VT   vertical tab
;     0x0C  FF   form feed
;     0x0D  CR   carriage return
;     0x20  SP   space
;
;   Unicode whitespace (additional):
;     0x00A0  NBSP    no-break space
;     0x1680  OGHAM SPACE MARK
;     0x2000..0x200A  various typographic spaces (en, em, thin, etc.)
;     0x2028  LINE SEPARATOR
;     0x2029  PARAGRAPH SEPARATOR
;     0x202F  NARROW NO-BREAK SPACE
;     0x205F  MEDIUM MATHEMATICAL SPACE
;     0x3000  IDEOGRAPHIC SPACE
;     0xFEFF  ZERO WIDTH NO-BREAK SPACE (BOM — treated as space here)
;
; str_is_space_cp    — Unicode-aware
; str_is_ascii_space — ASCII-only (faster, for pure ASCII input)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_is_ascii_space_byte
;
; Fast ASCII whitespace check for a single byte.
; Equivalent to C isspace() in the C locale.
;
; Signature:
;   int64_t str_is_ascii_space_byte(uint8_t byte)
;
; Returns:
;   RAX  = 1  byte is ASCII whitespace (0x09,0x0A,0x0B,0x0C,0x0D,0x20)
;   RAX  = 0  not whitespace
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_space_byte

    movzx   eax, dil

    ; SP (0x20)
    cmp     al, 0x20
    je      .true

    ; HT..CR (0x09..0x0D) — 5 control chars
    sub     al, 0x09
    cmp     al, 4           ; 0x09..0x0D → sub 9 → 0..4
    setbe   al
    movzx   eax, al
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_space_byte

; -----------------------------------------------------------------------------
; str_is_space_cp
;
; Unicode-aware whitespace check for a single codepoint.
;
; Signature:
;   int64_t str_is_space_cp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1  whitespace
;   RAX  = 0  not whitespace
; -----------------------------------------------------------------------------

STR_FUNC str_is_space_cp

    ; --- ASCII whitespace fast path ---
    ; SP = 0x20
    cmp     edi, 0x20
    je      .true

    ; HT..CR = 0x09..0x0D
    cmp     edi, 0x09
    jb      .check_nbsp
    cmp     edi, 0x0D
    jbe     .true

.check_nbsp:
    ; U+00A0 NO-BREAK SPACE
    cmp     edi, 0x00A0
    je      .true

    ; U+1680 OGHAM SPACE MARK
    cmp     edi, 0x1680
    je      .true

    ; U+2000..U+200A (various typographic spaces)
    cmp     edi, 0x2000
    jb      .check_line_sep
    cmp     edi, 0x200A
    jbe     .true

.check_line_sep:
    ; U+2028 LINE SEPARATOR
    cmp     edi, 0x2028
    je      .true

    ; U+2029 PARAGRAPH SEPARATOR
    cmp     edi, 0x2029
    je      .true

    ; U+202F NARROW NO-BREAK SPACE
    cmp     edi, 0x202F
    je      .true

    ; U+205F MEDIUM MATHEMATICAL SPACE
    cmp     edi, 0x205F
    je      .true

    ; U+3000 IDEOGRAPHIC SPACE
    cmp     edi, 0x3000
    je      .true

    ; U+FEFF ZERO WIDTH NO-BREAK SPACE (BOM)
    cmp     edi, 0xFEFF
    je      .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_space_cp

; -----------------------------------------------------------------------------
; str_is_space
;
; Check if every codepoint in a UTF-8 string is whitespace.
; Empty string returns 0.
;
; Signature:
;   int64_t str_is_space(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  all whitespace, non-empty
;   RAX  = 0  empty or contains non-whitespace
;   RAX  = STR_ERR_NULL  ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_is_space

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.space_loop:
    cmp     rbx, r12
    jae     .all_space

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
    call    str_is_space_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .not_space

    jmp     .space_loop

.all_space:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_space:
    pop_regs r13, r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_space

; -----------------------------------------------------------------------------
; str_is_ascii_space
;
; ASCII-only whitespace check over a buffer. Faster than str_is_space
; since no UTF-8 decoding is needed — just byte-level checks.
;
; Signature:
;   int64_t str_is_ascii_space(const uint8_t *ptr, uint64_t byte_len)
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_space

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.ascii_space_loop:
    cmp     rbx, r12
    jae     .all_ascii_space

    movzx   eax, byte [rbx]
    inc     rbx

    cmp     al, 0x20
    je      .ascii_space_loop

    sub     al, 0x09
    cmp     al, 4
    jbe     .ascii_space_loop

    ; non-whitespace byte found
    pop_regs r12, rbx
    mov     eax, STR_FALSE
    pop     rbp
    ret

.all_ascii_space:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_space

; -----------------------------------------------------------------------------
; str_is_space_slice / str_is_ascii_space_slice — StrSlice wrappers
; -----------------------------------------------------------------------------

STR_FUNC str_is_space_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_space

STR_ENDFUNC str_is_space_slice

STR_FUNC str_is_ascii_space_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_ascii_space

STR_ENDFUNC str_is_ascii_space_slice