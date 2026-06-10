; =============================================================================
; str/inspect/is_alpha.asm
; Check whether a codepoint or string contains only alphabetic characters.
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
; Alphabetic ranges covered:
;
;   ASCII:       A-Z (0x41..0x5A), a-z (0x61..0x7A)
;   Latin-1:     0xC0..0xD6, 0xD8..0xF6, 0xF8..0xFF
;   Greek:       0x0370..0x03FF
;   Cyrillic:    0x0400..0x04FF
;   Devanagari:  0x0900..0x097F  (covers Nepali/Hindi)
;   Hebrew:      0x05D0..0x05EA
;   Arabic:      0x0600..0x06FF
;   CJK:         0x4E00..0x9FFF
;   Hangul:      0xAC00..0xD7A3
;
; For full Unicode category support (Lu, Ll, Lt, Lm, Lo) see
; unicode/category.asm — that module uses the full category tables.
; This module covers the most common scripts with inline range checks
; for maximum speed without table lookups.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_is_alpha_cp
;
; Check if a single Unicode codepoint is alphabetic.
;
; Signature:
;   int64_t str_is_alpha_cp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint (u32)
;
; Returns:
;   RAX  = 1  alphabetic
;   RAX  = 0  not alphabetic
; -----------------------------------------------------------------------------

STR_FUNC str_is_alpha_cp

    ; --- ASCII fast path ---
    cmp     edi, 'Z'
    jbe     .check_upper
    cmp     edi, 'z'
    jbe     .check_lower_or_punct

    ; --- Latin-1 supplement: 0xC0..0xFF (minus 0xD7 × and 0xF7 ÷) ---
    cmp     edi, 0xC0
    jb      .check_extended
    cmp     edi, 0xFF
    ja      .check_extended
    cmp     edi, 0xD7
    je      .false              ; × multiplication sign
    cmp     edi, 0xF7
    je      .false              ; ÷ division sign
    jmp     .true

.check_upper:
    cmp     edi, 'A'
    jb      .false
    jmp     .true

.check_lower_or_punct:
    cmp     edi, 'a'
    jb      .false              ; 0x5B..0x60: [, \, ], ^, _, `
    jmp     .true

.check_extended:
    ; Greek: 0x0370..0x03FF
    cmp     edi, 0x0370
    jb      .check_cyrillic
    cmp     edi, 0x03FF
    jbe     .true

.check_cyrillic:
    ; Cyrillic: 0x0400..0x04FF
    cmp     edi, 0x0400
    jb      .check_hebrew
    cmp     edi, 0x04FF
    jbe     .true

.check_hebrew:
    ; Hebrew: 0x05D0..0x05EA
    cmp     edi, 0x05D0
    jb      .check_arabic
    cmp     edi, 0x05EA
    jbe     .true

.check_arabic:
    ; Arabic: 0x0600..0x06FF
    cmp     edi, 0x0600
    jb      .check_devanagari
    cmp     edi, 0x06FF
    jbe     .true

.check_devanagari:
    ; Devanagari: 0x0900..0x097F (Nepali, Hindi)
    cmp     edi, 0x0900
    jb      .check_latin_ext
    cmp     edi, 0x097F
    jbe     .true

.check_latin_ext:
    ; Latin Extended Additional: 0x1E00..0x1EFF
    cmp     edi, 0x1E00
    jb      .check_cjk
    cmp     edi, 0x1EFF
    jbe     .true

.check_cjk:
    ; CJK Unified Ideographs: 0x4E00..0x9FFF
    cmp     edi, 0x4E00
    jb      .check_hangul
    cmp     edi, 0x9FFF
    jbe     .true

.check_hangul:
    ; Hangul syllables: 0xAC00..0xD7A3
    cmp     edi, 0xAC00
    jb      .false
    cmp     edi, 0xD7A3
    jbe     .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_alpha_cp

; -----------------------------------------------------------------------------
; str_is_alpha
;
; Check if every codepoint in a UTF-8 string is alphabetic.
; Empty string returns 0 (no alphabetic characters present).
;
; Signature:
;   int64_t str_is_alpha(const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length
;
; Returns:
;   RAX  = 1   all codepoints are alphabetic (and string non-empty)
;   RAX  = 0   empty, or any codepoint is non-alphabetic
;   RAX  = STR_ERR_NULL  ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_is_alpha

    guard_null rdi, STR_ERR_NULL

    ; empty → false
    test    rsi, rsi
    jz      .false

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx            ; end ptr

.loop:
    cmp     rbx, r12
    jae     .all_alpha

    ; decode codepoint
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     r13, [rsp]          ; advance
    mov     rsp, rbp

    add     rbx, r13

    ; check alphabetic
    mov     edi, eax
    push    rbx
    push    r12
    call    str_is_alpha_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .not_alpha

    jmp     .loop

.all_alpha:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_alpha:
    pop_regs r13, r12, rbx
    mov     eax, STR_FALSE
    pop     rbp
    ret

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_alpha

; -----------------------------------------------------------------------------
; str_is_alpha_slice — StrSlice wrapper
; -----------------------------------------------------------------------------

STR_FUNC str_is_alpha_slice

    guard_null rdi, STR_ERR_NULL

    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]

    pop     rbp
    jmp     str_is_alpha

STR_ENDFUNC str_is_alpha_slice

; -----------------------------------------------------------------------------
; str_is_ascii_alpha_byte
;
; Fast single-byte ASCII-only alphabetic check. No UTF-8 decoding.
;
; Signature:
;   int64_t str_is_ascii_alpha_byte(uint8_t byte)
;
; Returns:
;   RAX  = 1  if byte in A-Z or a-z
;   RAX  = 0  otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_alpha_byte

    movzx   eax, dil
    or      al, 0x20            ; fold to lowercase
    sub     al, 'a'
    cmp     al, 25              ; 'z' - 'a' = 25
    setbe   al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_alpha_byte