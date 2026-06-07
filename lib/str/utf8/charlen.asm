; =============================================================================
; str/utf8/charlen.asm
; Given a UTF-8 leading byte, return the sequence length in bytes (1..4).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; %include "arch/common/types.inc"
; %include "arch/common/error.inc"
; %include "arch/common/macros.inc"
;
; -----------------------------------------------------------------------------
; UTF-8 leading byte encoding:
;
;   0xxxxxxx  → 1 byte   (ASCII, U+0000..U+007F)
;   110xxxxx  → 2 bytes  (U+0080..U+07FF)
;   1110xxxx  → 3 bytes  (U+0800..U+FFFF)
;   11110xxx  → 4 bytes  (U+10000..U+10FFFF)
;
;   10xxxxxx  → continuation byte — invalid as leading byte → error
;   11111xxx  → invalid UTF-8 prefix → error
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_utf8_charlen
;
; Given the first byte of a UTF-8 sequence, return the total byte length
; of that sequence (1, 2, 3, or 4).
;
; Signature:
;   int64_t str_utf8_charlen(uint8_t leading_byte)
;
; Arguments:
;   RDI  — leading byte (only low 8 bits used; caller may pass full register)
;
; Returns:
;   RAX  = 1, 2, 3, or 4     on success
;   RAX  = STR_ERR_INVALID_UTF8  if byte is a continuation or invalid prefix
;
; Clobbers: RAX, RCX
; Preserves: RBX, RDX, RSI, RDI, R8..R15
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_charlen

    movzx   eax, dil            ; zero-extend leading byte into EAX

    ; --- 1-byte sequence: top bit clear (0xxxxxxx) ---
    test    al, 0x80
    jz      .one

    ; --- Reject continuation bytes: 10xxxxxx (0x80..0xBF) ---
    ; These have bits [7:6] == 10
    cmp     al, 0xC0
    jb      .invalid            ; 0x80..0xBF → continuation byte

    ; --- 2-byte sequence: 110xxxxx (0xC0..0xDF) ---
    ; Minimum valid: 0xC2 (0xC0/0xC1 are overlong encodings of ASCII)
    cmp     al, 0xC2
    jb      .invalid            ; 0xC0..0xC1 → overlong
    cmp     al, 0xDF
    jbe     .two

    ; --- 3-byte sequence: 1110xxxx (0xE0..0xEF) ---
    cmp     al, 0xEF
    jbe     .three

    ; --- 4-byte sequence: 11110xxx (0xF0..0xF4) ---
    ; Max valid: 0xF4 (U+10FFFF encodes as F4 8F BF BF)
    cmp     al, 0xF4
    jbe     .four

    ; --- 0xF5..0xFF → invalid ---
    jmp     .invalid

.one:
    mov     rax, 1
    pop     rbp
    ret

.two:
    mov     rax, 2
    pop     rbp
    ret

.three:
    mov     rax, 3
    pop     rbp
    ret

.four:
    mov     rax, 4
    pop     rbp
    ret

.invalid:
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

STR_ENDFUNC str_utf8_charlen

; -----------------------------------------------------------------------------
; str_utf8_charlen_safe
;
; Like str_utf8_charlen but also validates that [ptr .. ptr+len) has enough
; bytes remaining to hold the full sequence. Prevents reads past end of input.
;
; Signature:
;   int64_t str_utf8_charlen_safe(const uint8_t *ptr, uint64_t remaining)
;
; Arguments:
;   RDI  — pointer to current position in UTF-8 string (leading byte)
;   RSI  — number of bytes remaining from ptr to end of buffer
;
; Returns:
;   RAX  = 1..4              sequence length (enough bytes available)
;   RAX  = STR_ERR_NULL      if ptr is null
;   RAX  = STR_ERR_TRUNCATED if remaining < sequence length
;   RAX  = STR_ERR_INVALID_UTF8 if leading byte is invalid
;
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_charlen_safe

    guard_null rdi, STR_ERR_NULL

    ; need at least 1 byte
    test    rsi, rsi
    jz      .truncated

    ; get sequence length from leading byte
    movzx   eax, byte [rdi]
    push    rsi                 ; save remaining count

    ; inline charlen logic (avoid call overhead)
    test    al, 0x80
    jz      .safe_one

    cmp     al, 0xC2
    jb      .safe_invalid
    cmp     al, 0xDF
    jbe     .safe_two

    cmp     al, 0xEF
    jbe     .safe_three

    cmp     al, 0xF4
    jbe     .safe_four

    jmp     .safe_invalid

.safe_one:
    pop     rsi
    mov     rax, 1
    pop     rbp
    ret

.safe_two:
    pop     rsi
    cmp     rsi, 2
    jb      .truncated
    mov     rax, 2
    pop     rbp
    ret

.safe_three:
    pop     rsi
    cmp     rsi, 3
    jb      .truncated
    mov     rax, 3
    pop     rbp
    ret

.safe_four:
    pop     rsi
    cmp     rsi, 4
    jb      .truncated
    mov     rax, 4
    pop     rbp
    ret

.safe_invalid:
    pop     rsi
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

.truncated:
    mov     rax, STR_ERR_TRUNCATED
    pop     rbp
    ret

STR_ENDFUNC str_utf8_charlen_safe