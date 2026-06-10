; =============================================================================
; str/inspect/is_blank.asm
; Check whether a codepoint or string contains only blank characters.
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
; Blank = horizontal whitespace only.
; Stricter than is_space — excludes newlines, vertical tab, form feed.
;
;   ASCII blank:
;     0x09  HT   horizontal tab
;     0x20  SP   space
;
;   Unicode blank (additional horizontal space):
;     0x00A0  NO-BREAK SPACE
;     0x1680  OGHAM SPACE MARK
;     0x2000..0x200A  (en quad, em quad, en space, em space, etc.)
;     0x202F  NARROW NO-BREAK SPACE
;     0x205F  MEDIUM MATHEMATICAL SPACE
;     0x3000  IDEOGRAPHIC SPACE
;
; Explicitly NOT blank (vertical/line-breaking):
;     0x0A LF, 0x0B VT, 0x0C FF, 0x0D CR
;     0x2028 LINE SEPARATOR, 0x2029 PARAGRAPH SEPARATOR
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_is_blank_cp
;
; Check if a codepoint is a blank (horizontal whitespace).
;
; Signature:
;   int64_t str_is_blank_cp(uint32_t cp)
;
; Returns:
;   RAX  = 1  blank
;   RAX  = 0  not blank
; -----------------------------------------------------------------------------

STR_FUNC str_is_blank_cp

    ; HT = 0x09
    cmp     edi, 0x09
    je      .true

    ; SP = 0x20
    cmp     edi, 0x20
    je      .true

    ; U+00A0 NO-BREAK SPACE
    cmp     edi, 0x00A0
    je      .true

    ; U+1680 OGHAM SPACE MARK
    cmp     edi, 0x1680
    je      .true

    ; U+2000..U+200A typographic spaces
    cmp     edi, 0x2000
    jb      .check_narrow
    cmp     edi, 0x200A
    jbe     .true

.check_narrow:
    ; U+202F NARROW NO-BREAK SPACE
    cmp     edi, 0x202F
    je      .true

    ; U+205F MEDIUM MATHEMATICAL SPACE
    cmp     edi, 0x205F
    je      .true

    ; U+3000 IDEOGRAPHIC SPACE
    cmp     edi, 0x3000
    je      .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_blank_cp

; -----------------------------------------------------------------------------
; str_is_ascii_blank_byte
;
; Fast ASCII blank check — only HT (0x09) and SP (0x20).
; Equivalent to C isblank() in the C locale.
;
; Signature:
;   int64_t str_is_ascii_blank_byte(uint8_t byte)
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_blank_byte

    movzx   eax, dil

    cmp     al, 0x20
    je      .true
    cmp     al, 0x09
    je      .true

    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_blank_byte

; -----------------------------------------------------------------------------
; str_is_blank
;
; Check if every codepoint in a UTF-8 string is blank.
; Empty string returns 0.
;
; Signature:
;   int64_t str_is_blank(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  all blank, non-empty
;   RAX  = 0  empty or contains non-blank codepoint
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_is_blank

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.blank_loop:
    cmp     rbx, r12
    jae     .all_blank

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
    call    str_is_blank_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .not_blank

    jmp     .blank_loop

.all_blank:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_blank:
    pop_regs r13, r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_blank

; -----------------------------------------------------------------------------
; str_is_ascii_blank
;
; ASCII-only blank check (HT and SP only). No UTF-8 decoding.
;
; Signature:
;   int64_t str_is_ascii_blank(const uint8_t *ptr, uint64_t byte_len)
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_blank

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.ab_loop:
    cmp     rbx, r12
    jae     .ab_true

    movzx   eax, byte [rbx]
    inc     rbx

    cmp     al, 0x20
    je      .ab_loop
    cmp     al, 0x09
    je      .ab_loop

    pop_regs r12, rbx
    mov     eax, STR_FALSE
    pop     rbp
    ret

.ab_true:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_blank

; -----------------------------------------------------------------------------
; str_is_blank_slice / str_is_ascii_blank_slice — StrSlice wrappers
; -----------------------------------------------------------------------------

STR_FUNC str_is_blank_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_blank

STR_ENDFUNC str_is_blank_slice

STR_FUNC str_is_ascii_blank_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_ascii_blank

STR_ENDFUNC str_is_ascii_blank_slice