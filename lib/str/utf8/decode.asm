; =============================================================================
; str/utf8/decode.asm
; Decode a UTF-8 byte sequence into a Unicode codepoint (u32).
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
; UTF-8 decoding bit extraction:
;
;   1-byte:  0xxxxxxx                          → U+0000..U+007F
;            codepoint = byte1 & 0x7F
;
;   2-byte:  110xxxxx 10yyyyyy                 → U+0080..U+07FF
;            codepoint = (byte1 & 0x1F) << 6
;                      | (byte2 & 0x3F)
;
;   3-byte:  1110xxxx 10yyyyyy 10zzzzzz        → U+0800..U+FFFF
;            codepoint = (byte1 & 0x0F) << 12
;                      | (byte2 & 0x3F) << 6
;                      | (byte3 & 0x3F)
;
;   4-byte:  11110xxx 10yyyyyy 10zzzzzz 10wwww → U+10000..U+10FFFF
;            codepoint = (byte1 & 0x07) << 18
;                      | (byte2 & 0x3F) << 12
;                      | (byte3 & 0x3F) << 6
;                      | (byte4 & 0x3F)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_utf8_decode
;
; Decode one UTF-8 codepoint from a byte buffer.
;
; Signature:
;   int64_t str_utf8_decode(const uint8_t *ptr, uint64_t remaining,
;                            uint32_t *out_cp, uint64_t *out_advance)
;
; Arguments:
;   RDI  — pointer to current position in UTF-8 buffer
;   RSI  — bytes remaining from ptr (must be >= 1)
;   RDX  — pointer to uint32_t to receive decoded codepoint
;   RCX  — pointer to uint64_t to receive bytes consumed (1..4)
;
; Returns:
;   RAX  = STR_OK               codepoint written to *out_cp, advance written
;   RAX  = STR_ERR_NULL         ptr, out_cp, or out_advance is null
;   RAX  = STR_ERR_INVALID_UTF8 bad leading byte or bad continuation byte
;   RAX  = STR_ERR_OVERLONG     overlong encoding
;   RAX  = STR_ERR_SURROGATE    surrogate codepoint U+D800..U+DFFF
;   RAX  = STR_ERR_TRUNCATED    sequence cut off (remaining < needed)
;
; Clobbers: RAX, R8, R9, R10, R11
; Preserves: RBX, RBP, RSI, RDI, R12..R15
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_decode

    ; null guards
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    test    rsi, rsi
    jz      .err_truncated

    push_regs rbx, r12, r13
    mov     rbx, rdx            ; rbx = out_cp
    mov     r12, rcx            ; r12 = out_advance
    mov     r13, rsi            ; r13 = remaining

    movzx   eax, byte [rdi]     ; load leading byte

    ; -------------------------------------------------------------------------
    ; 1-byte (ASCII)
    ; -------------------------------------------------------------------------
    test    al, 0x80
    jz      .one_byte

    ; -------------------------------------------------------------------------
    ; Reject continuation bytes as leading
    ; -------------------------------------------------------------------------
    cmp     al, 0xC0
    jb      .err_invalid

    ; -------------------------------------------------------------------------
    ; Reject overlong 2-byte prefixes
    ; -------------------------------------------------------------------------
    cmp     al, 0xC2
    jb      .err_overlong

    ; -------------------------------------------------------------------------
    ; 2-byte
    ; -------------------------------------------------------------------------
    cmp     al, 0xDF
    jbe     .two_byte

    ; -------------------------------------------------------------------------
    ; 3-byte
    ; -------------------------------------------------------------------------
    cmp     al, 0xEF
    jbe     .three_byte

    ; -------------------------------------------------------------------------
    ; 4-byte
    ; -------------------------------------------------------------------------
    cmp     al, 0xF4
    jbe     .four_byte

    jmp     .err_invalid

; ---------------------------------------------------------------------------
.one_byte:
    ; codepoint = byte1 & 0x7F  (top bit already 0, mask is optional)
    and     eax, 0x7F
    mov     dword [rbx], eax    ; *out_cp = codepoint
    mov     qword [r12], 1      ; *out_advance = 1
    jmp     .ok

; ---------------------------------------------------------------------------
.two_byte:
    cmp     r13, 2
    jb      .err_truncated

    movzx   r8d, byte [rdi + 1]

    ; byte2 must be 10xxxxxx
    mov     r9d, r8d
    and     r9d, 0xC0
    cmp     r9d, 0x80
    jne     .err_invalid

    ; codepoint = (byte1 & 0x1F) << 6 | (byte2 & 0x3F)
    and     eax, 0x1F
    shl     eax, 6
    and     r8d, 0x3F
    or      eax, r8d

    mov     dword [rbx], eax
    mov     qword [r12], 2
    jmp     .ok

; ---------------------------------------------------------------------------
.three_byte:
    cmp     r13, 3
    jb      .err_truncated

    movzx   r8d,  byte [rdi + 1]
    movzx   r9d,  byte [rdi + 2]

    ; Special: 0xE0 → byte2 must be 0xA0..0xBF (no overlong)
    cmp     al, 0xE0
    jne     .three_not_e0
    cmp     r8d, 0xA0
    jb      .err_overlong
    cmp     r8d, 0xBF
    ja      .err_invalid
    jmp     .three_check_cont2

.three_not_e0:
    ; Special: 0xED → byte2 must be 0x80..0x9F (no surrogates)
    cmp     al, 0xED
    jne     .three_normal
    cmp     r8d, 0x80
    jb      .err_invalid
    cmp     r8d, 0x9F
    ja      .err_surrogate
    jmp     .three_check_cont2

.three_normal:
    ; byte2 must be 10xxxxxx
    mov     r10d, r8d
    and     r10d, 0xC0
    cmp     r10d, 0x80
    jne     .err_invalid

.three_check_cont2:
    ; byte3 must be 10xxxxxx
    mov     r10d, r9d
    and     r10d, 0xC0
    cmp     r10d, 0x80
    jne     .err_invalid

    ; codepoint = (b1 & 0x0F) << 12 | (b2 & 0x3F) << 6 | (b3 & 0x3F)
    and     eax,  0x0F
    shl     eax,  12
    and     r8d,  0x3F
    shl     r8d,  6
    and     r9d,  0x3F
    or      eax,  r8d
    or      eax,  r9d

    mov     dword [rbx], eax
    mov     qword [r12], 3
    jmp     .ok

; ---------------------------------------------------------------------------
.four_byte:
    cmp     r13, 4
    jb      .err_truncated

    movzx   r8d,  byte [rdi + 1]
    movzx   r9d,  byte [rdi + 2]
    movzx   r10d, byte [rdi + 3]

    ; Special: 0xF0 → byte2 must be 0x90..0xBF (no overlong)
    cmp     al, 0xF0
    jne     .four_not_f0
    cmp     r8d, 0x90
    jb      .err_overlong
    cmp     r8d, 0xBF
    ja      .err_invalid
    jmp     .four_check_cont2

.four_not_f0:
    ; Special: 0xF4 → byte2 must be 0x80..0x8F (max U+10FFFF)
    cmp     al, 0xF4
    jne     .four_normal
    cmp     r8d, 0x80
    jb      .err_invalid
    cmp     r8d, 0x8F
    ja      .err_invalid
    jmp     .four_check_cont2

.four_normal:
    ; 0xF1..0xF3: byte2 must be 10xxxxxx
    mov     r11d, r8d
    and     r11d, 0xC0
    cmp     r11d, 0x80
    jne     .err_invalid

.four_check_cont2:
    ; byte3 must be 10xxxxxx
    mov     r11d, r9d
    and     r11d, 0xC0
    cmp     r11d, 0x80
    jne     .err_invalid

    ; byte4 must be 10xxxxxx
    mov     r11d, r10d
    and     r11d, 0xC0
    cmp     r11d, 0x80
    jne     .err_invalid

    ; codepoint = (b1 & 0x07) << 18 | (b2 & 0x3F) << 12
    ;           | (b3 & 0x3F) << 6  | (b4 & 0x3F)
    and     eax,  0x07
    shl     eax,  18
    and     r8d,  0x3F
    shl     r8d,  12
    and     r9d,  0x3F
    shl     r9d,  6
    and     r10d, 0x3F
    or      eax,  r8d
    or      eax,  r9d
    or      eax,  r10d

    mov     dword [rbx], eax
    mov     qword [r12], 4

; ---------------------------------------------------------------------------
.ok:
    pop_regs r13, r12, rbx
    xor     eax, eax            ; STR_OK
    pop     rbp
    ret

.err_invalid:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

.err_overlong:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_OVERLONG
    pop     rbp
    ret

.err_surrogate:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_SURROGATE
    pop     rbp
    ret

.err_truncated:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_TRUNCATED
    pop     rbp
    ret

STR_ENDFUNC str_utf8_decode

; -----------------------------------------------------------------------------
; str_utf8_decode_unchecked
;
; Decode one codepoint without any validation. Use ONLY on pre-validated input.
; Fastest path — no branch for error conditions.
;
; Signature:
;   uint32_t str_utf8_decode_unchecked(const uint8_t *ptr,
;                                       uint64_t *out_advance)
;
; Arguments:
;   RDI  — pointer to leading byte (must be valid UTF-8)
;   RSI  — pointer to uint64_t to receive bytes consumed
;
; Returns:
;   EAX  — decoded codepoint (always valid, caller guarantees input)
;
; Clobbers: RAX, RCX, RDX, R8
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_decode_unchecked

    movzx   eax, byte [rdi]

    test    al, 0x80
    jz      .unc_one

    cmp     al, 0xDF
    jbe     .unc_two

    cmp     al, 0xEF
    jbe     .unc_three

    ; 4-byte
    movzx   ecx,  byte [rdi + 1]
    movzx   edx,  byte [rdi + 2]
    movzx   r8d,  byte [rdi + 3]
    and     eax,  0x07
    shl     eax,  18
    and     ecx,  0x3F
    shl     ecx,  12
    and     edx,  0x3F
    shl     edx,  6
    and     r8d,  0x3F
    or      eax,  ecx
    or      eax,  edx
    or      eax,  r8d
    mov     qword [rsi], 4
    pop     rbp
    ret

.unc_one:
    ; eax already has the byte, top bit clear
    mov     qword [rsi], 1
    pop     rbp
    ret

.unc_two:
    movzx   ecx, byte [rdi + 1]
    and     eax, 0x1F
    shl     eax, 6
    and     ecx, 0x3F
    or      eax, ecx
    mov     qword [rsi], 2
    pop     rbp
    ret

.unc_three:
    movzx   ecx, byte [rdi + 1]
    movzx   edx, byte [rdi + 2]
    and     eax, 0x0F
    shl     eax, 12
    and     ecx, 0x3F
    shl     ecx, 6
    and     edx, 0x3F
    or      eax, ecx
    or      eax, edx
    mov     qword [rsi], 3
    pop     rbp
    ret

STR_ENDFUNC str_utf8_decode_unchecked