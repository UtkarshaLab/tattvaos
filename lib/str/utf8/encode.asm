; =============================================================================
; str/utf8/encode.asm
; Encode a Unicode codepoint (u32) into UTF-8 bytes.
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
; UTF-8 encoding bit layout:
;
;   U+0000..U+007F   → 1 byte:  0xxxxxxx
;   U+0080..U+07FF   → 2 bytes: 110xxxxx 10yyyyyy
;   U+0800..U+FFFF   → 3 bytes: 1110xxxx 10yyyyyy 10zzzzzz
;   U+10000..U+10FFFF→ 4 bytes: 11110xxx 10yyyyyy 10zzzzzz 10wwwwww
;
; Surrogates U+D800..U+DFFF are rejected — invalid in UTF-8 (RFC 3629).
; Codepoints above U+10FFFF are rejected.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_utf8_encode
;
; Encode one Unicode codepoint into a caller-supplied byte buffer.
;
; Signature:
;   int64_t str_utf8_encode(uint32_t codepoint, uint8_t *buf,
;                            uint64_t buf_cap, uint64_t *out_written)
;
; Arguments:
;   EDI  — codepoint (u32, only low 32 bits used)
;   RSI  — pointer to output buffer
;   RDX  — buffer capacity in bytes (must be >= 1..4 as needed)
;   RCX  — pointer to uint64_t to receive bytes written
;
; Returns:
;   RAX  = STR_OK                bytes written to buf, count in *out_written
;   RAX  = STR_ERR_NULL          buf or out_written is null
;   RAX  = STR_ERR_INVALID_CODEPOINT  codepoint > U+10FFFF
;   RAX  = STR_ERR_SURROGATE     codepoint in surrogate range
;   RAX  = STR_ERR_BUF_TOO_SMALL buf_cap insufficient for this codepoint
;
; Clobbers: RAX, R8, R9
; Preserves: RBX, RBP, RDI, RSI, RDX, RCX, R12..R15
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_encode

    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; validate codepoint range
    cmp     edi, CODEPOINT_MAX
    ja      .err_invalid_cp

    ; reject surrogates U+D800..U+DFFF
    cmp     edi, SURROGATE_HIGH_MIN
    jb      .range_ok
    cmp     edi, SURROGATE_LOW_MAX
    jbe     .err_surrogate

.range_ok:
    ; -------------------------------------------------------------------------
    ; 1-byte: U+0000..U+007F
    ; -------------------------------------------------------------------------
    cmp     edi, 0x7F
    ja      .try_two

    ; need 1 byte
    cmp     rdx, 1
    jb      .err_buf_small

    mov     byte [rsi], dil     ; write single byte
    mov     qword [rcx], 1
    jmp     .ok

    ; -------------------------------------------------------------------------
    ; 2-byte: U+0080..U+07FF
    ; -------------------------------------------------------------------------
.try_two:
    cmp     edi, 0x7FF
    ja      .try_three

    ; need 2 bytes
    cmp     rdx, 2
    jb      .err_buf_small

    ; byte1 = 0xC0 | (cp >> 6)
    mov     eax, edi
    shr     eax, 6
    or      al,  0xC0
    mov     byte [rsi], al

    ; byte2 = 0x80 | (cp & 0x3F)
    mov     eax, edi
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 1], al

    mov     qword [rcx], 2
    jmp     .ok

    ; -------------------------------------------------------------------------
    ; 3-byte: U+0800..U+FFFF
    ; -------------------------------------------------------------------------
.try_three:
    cmp     edi, 0xFFFF
    ja      .four_byte

    ; need 3 bytes
    cmp     rdx, 3
    jb      .err_buf_small

    ; byte1 = 0xE0 | (cp >> 12)
    mov     eax, edi
    shr     eax, 12
    or      al,  0xE0
    mov     byte [rsi], al

    ; byte2 = 0x80 | ((cp >> 6) & 0x3F)
    mov     eax, edi
    shr     eax, 6
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 1], al

    ; byte3 = 0x80 | (cp & 0x3F)
    mov     eax, edi
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 2], al

    mov     qword [rcx], 3
    jmp     .ok

    ; -------------------------------------------------------------------------
    ; 4-byte: U+10000..U+10FFFF
    ; -------------------------------------------------------------------------
.four_byte:
    ; need 4 bytes
    cmp     rdx, 4
    jb      .err_buf_small

    ; byte1 = 0xF0 | (cp >> 18)
    mov     eax, edi
    shr     eax, 18
    or      al,  0xF0
    mov     byte [rsi], al

    ; byte2 = 0x80 | ((cp >> 12) & 0x3F)
    mov     eax, edi
    shr     eax, 12
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 1], al

    ; byte3 = 0x80 | ((cp >> 6) & 0x3F)
    mov     eax, edi
    shr     eax, 6
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 2], al

    ; byte4 = 0x80 | (cp & 0x3F)
    mov     eax, edi
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 3], al

    mov     qword [rcx], 4

.ok:
    xor     eax, eax            ; STR_OK
    pop     rbp
    ret

.err_invalid_cp:
    mov     rax, STR_ERR_INVALID_CODEPOINT
    pop     rbp
    ret

.err_surrogate:
    mov     rax, STR_ERR_SURROGATE
    pop     rbp
    ret

.err_buf_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf8_encode

; -----------------------------------------------------------------------------
; str_utf8_encode_unchecked
;
; Encode a codepoint with no validation. Caller guarantees:
;   - codepoint is valid (0x0000..0x10FFFF, not a surrogate)
;   - buf has at least 4 bytes available
;
; Signature:
;   uint64_t str_utf8_encode_unchecked(uint32_t codepoint, uint8_t *buf)
;
; Arguments:
;   EDI  — codepoint (u32)
;   RSI  — output buffer (must have >= 4 bytes)
;
; Returns:
;   RAX  — bytes written (1, 2, 3, or 4)
;
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_encode_unchecked

    cmp     edi, 0x7F
    ja      .unc_try_two

    ; 1-byte
    mov     byte [rsi], dil
    mov     eax, 1
    pop     rbp
    ret

.unc_try_two:
    cmp     edi, 0x7FF
    ja      .unc_try_three

    ; 2-byte
    mov     eax, edi
    shr     eax, 6
    or      al,  0xC0
    mov     byte [rsi], al

    mov     eax, edi
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 1], al

    mov     eax, 2
    pop     rbp
    ret

.unc_try_three:
    cmp     edi, 0xFFFF
    ja      .unc_four

    ; 3-byte
    mov     eax, edi
    shr     eax, 12
    or      al,  0xE0
    mov     byte [rsi], al

    mov     eax, edi
    shr     eax, 6
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 1], al

    mov     eax, edi
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 2], al

    mov     eax, 3
    pop     rbp
    ret

.unc_four:
    ; 4-byte
    mov     eax, edi
    shr     eax, 18
    or      al,  0xF0
    mov     byte [rsi], al

    mov     eax, edi
    shr     eax, 12
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 1], al

    mov     eax, edi
    shr     eax, 6
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 2], al

    mov     eax, edi
    and     al,  0x3F
    or      al,  0x80
    mov     byte [rsi + 3], al

    mov     eax, 4
    pop     rbp
    ret

STR_ENDFUNC str_utf8_encode_unchecked

; -----------------------------------------------------------------------------
; str_utf8_encode_buf_size
;
; Return how many bytes are needed to encode a given codepoint.
; Does NOT write anything — purely a capacity query.
;
; Signature:
;   int64_t str_utf8_encode_buf_size(uint32_t codepoint)
;
; Arguments:
;   EDI  — codepoint (u32)
;
; Returns:
;   RAX  = 1, 2, 3, or 4         bytes needed
;   RAX  = STR_ERR_INVALID_CODEPOINT  if codepoint > U+10FFFF
;   RAX  = STR_ERR_SURROGATE          if surrogate
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_encode_buf_size

    cmp     edi, CODEPOINT_MAX
    ja      .err_invalid_cp

    cmp     edi, SURROGATE_HIGH_MIN
    jb      .size_ok
    cmp     edi, SURROGATE_LOW_MAX
    jbe     .err_surrogate

.size_ok:
    cmp     edi, 0x7F
    jbe     .s1
    cmp     edi, 0x7FF
    jbe     .s2
    cmp     edi, 0xFFFF
    jbe     .s3

    mov     eax, 4
    pop     rbp
    ret
.s1:
    mov     eax, 1
    pop     rbp
    ret
.s2:
    mov     eax, 2
    pop     rbp
    ret
.s3:
    mov     eax, 3
    pop     rbp
    ret

.err_invalid_cp:
    mov     rax, STR_ERR_INVALID_CODEPOINT
    pop     rbp
    ret

.err_surrogate:
    mov     rax, STR_ERR_SURROGATE
    pop     rbp
    ret

STR_ENDFUNC str_utf8_encode_buf_size