; =============================================================================
; str/utf8/validate.asm
; Validate a UTF-8 byte sequence — reject all malformed input.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/charlen.asm  (str_utf8_charlen_safe)
;
; -----------------------------------------------------------------------------
; Validation rules enforced (per RFC 3629 / Unicode 15.0):
;
;   1. No continuation bytes (0x80..0xBF) as leading bytes
;   2. No overlong encodings (0xC0, 0xC1 prefixes)
;   3. No sequences beyond U+10FFFF (prefix > 0xF4)
;   4. No surrogate codepoints (U+D800..U+DFFF)
;   5. Each multi-byte sequence must have correct number of 10xxxxxx bytes
;   6. Specific range checks on second byte for 0xE0, 0xED, 0xF0, 0xF4
;   7. No truncated sequences at end of buffer
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_charlen_safe

section .text

; -----------------------------------------------------------------------------
; str_utf8_validate
;
; Validate an entire UTF-8 string. Returns STR_OK if valid, error otherwise.
;
; Signature:
;   int64_t str_utf8_validate(const uint8_t *ptr, uint64_t len)
;
; Arguments:
;   RDI  — pointer to byte buffer
;   RSI  — byte length
;
; Returns:
;   RAX  = STR_OK                 entire buffer is valid UTF-8
;   RAX  = STR_ERR_NULL           ptr is null
;   RAX  = STR_ERR_INVALID_UTF8   invalid leading byte or bad continuation
;   RAX  = STR_ERR_OVERLONG       overlong encoding detected
;   RAX  = STR_ERR_SURROGATE      surrogate codepoint detected
;   RAX  = STR_ERR_TRUNCATED      sequence cut off at end of buffer
;
; Clobbers: RAX, RCX, RDX, R8, R9, R10
; Preserves: RBX, RBP, RSI, RDI, R12..R15
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_validate

    guard_null rdi, STR_ERR_NULL

    ; empty string is valid UTF-8
    test    rsi, rsi
    jz      .valid

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; rbx = current ptr
    mov     r12, rsi            ; r12 = total length
    mov     r13, rdi            ; r13 = base ptr (rbx + r12 = end)
    add     r13, rsi            ; r13 = one past end

.loop:
    ; check if done
    cmp     rbx, r13
    jae     .done

    ; remaining = end - current
    mov     r14, r13
    sub     r14, rbx            ; r14 = bytes remaining

    movzx   eax, byte [rbx]     ; load leading byte

    ; -------------------------------------------------------------------------
    ; 1-byte (ASCII): 0x00..0x7F — fast path
    ; -------------------------------------------------------------------------
    test    al, 0x80
    jz      .ascii

    ; -------------------------------------------------------------------------
    ; Reject continuation bytes as leading: 0x80..0xBF
    ; -------------------------------------------------------------------------
    cmp     al, 0xC0
    jb      .err_invalid

    ; -------------------------------------------------------------------------
    ; Reject overlong 2-byte prefixes: 0xC0..0xC1
    ; -------------------------------------------------------------------------
    cmp     al, 0xC2
    jb      .err_overlong

    ; -------------------------------------------------------------------------
    ; 2-byte sequence: 0xC2..0xDF
    ; -------------------------------------------------------------------------
    cmp     al, 0xDF
    jbe     .two_byte

    ; -------------------------------------------------------------------------
    ; 3-byte sequence: 0xE0..0xEF
    ; -------------------------------------------------------------------------
    cmp     al, 0xEF
    jbe     .three_byte

    ; -------------------------------------------------------------------------
    ; 4-byte sequence: 0xF0..0xF4
    ; -------------------------------------------------------------------------
    cmp     al, 0xF4
    jbe     .four_byte

    ; 0xF5..0xFF → invalid
    jmp     .err_invalid

; --- ASCII fast path ----------------------------------------------------------
.ascii:
    inc     rbx
    jmp     .loop

; --- 2-byte sequence ----------------------------------------------------------
.two_byte:
    cmp     r14, 2
    jb      .err_truncated

    movzx   ecx, byte [rbx + 1]
    ; byte 2 must be 10xxxxxx (0x80..0xBF)
    and     ecx, 0xC0
    cmp     ecx, 0x80
    jne     .err_invalid

    add     rbx, 2
    jmp     .loop

; --- 3-byte sequence ----------------------------------------------------------
.three_byte:
    cmp     r14, 3
    jb      .err_truncated

    movzx   ecx, byte [rbx]     ; leading byte (already in eax too)
    movzx   edx, byte [rbx + 1] ; second byte
    movzx   r8d, byte [rbx + 2] ; third byte

    ; Special case: 0xE0 — second byte must be 0xA0..0xBF (not 0x80..0x9F)
    ; to avoid overlong encodings of U+0000..U+07FF
    cmp     al, 0xE0
    jne     .three_not_e0
    cmp     dl, 0xA0
    jb      .err_overlong
    cmp     dl, 0xBF
    ja      .err_invalid
    jmp     .three_check_b3

.three_not_e0:
    ; Special case: 0xED — second byte must be 0x80..0x9F
    ; to avoid surrogates U+D800..U+DFFF
    cmp     al, 0xED
    jne     .three_normal
    cmp     dl, 0x80
    jb      .err_invalid
    cmp     dl, 0x9F
    ja      .err_surrogate
    jmp     .three_check_b3

.three_normal:
    ; Second byte must be 10xxxxxx (0x80..0xBF)
    mov     ecx, edx
    and     ecx, 0xC0
    cmp     ecx, 0x80
    jne     .err_invalid

.three_check_b3:
    ; Third byte must be 10xxxxxx
    mov     ecx, r8d
    and     ecx, 0xC0
    cmp     ecx, 0x80
    jne     .err_invalid

    add     rbx, 3
    jmp     .loop

; --- 4-byte sequence ----------------------------------------------------------
.four_byte:
    cmp     r14, 4
    jb      .err_truncated

    movzx   ecx, byte [rbx]     ; leading (eax)
    movzx   edx, byte [rbx + 1] ; byte 2
    movzx   r8d, byte [rbx + 2] ; byte 3
    movzx   r9d, byte [rbx + 3] ; byte 4

    ; Special case: 0xF0 — byte 2 must be 0x90..0xBF (avoid overlong)
    cmp     al, 0xF0
    jne     .four_not_f0
    cmp     dl, 0x90
    jb      .err_overlong
    cmp     dl, 0xBF
    ja      .err_invalid
    jmp     .four_check_b3b4

.four_not_f0:
    ; Special case: 0xF4 — byte 2 must be 0x80..0x8F (max U+10FFFF)
    cmp     al, 0xF4
    jne     .four_normal
    cmp     dl, 0x80
    jb      .err_invalid
    cmp     dl, 0x8F
    ja      .err_invalid        ; would exceed U+10FFFF
    jmp     .four_check_b3b4

.four_normal:
    ; 0xF1..0xF3 — byte 2 must be 0x80..0xBF
    mov     ecx, edx
    and     ecx, 0xC0
    cmp     ecx, 0x80
    jne     .err_invalid

.four_check_b3b4:
    ; Byte 3 must be 10xxxxxx
    mov     ecx, r8d
    and     ecx, 0xC0
    cmp     ecx, 0x80
    jne     .err_invalid

    ; Byte 4 must be 10xxxxxx
    mov     ecx, r9d
    and     ecx, 0xC0
    cmp     ecx, 0x80
    jne     .err_invalid

    add     rbx, 4
    jmp     .loop

; --- Exit paths ---------------------------------------------------------------
.done:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax            ; STR_OK
    pop     rbp
    ret

.valid:
    xor     eax, eax
    pop     rbp
    ret

.err_invalid:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

.err_overlong:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERLONG
    pop     rbp
    ret

.err_surrogate:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_SURROGATE
    pop     rbp
    ret

.err_truncated:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_TRUNCATED
    pop     rbp
    ret

STR_ENDFUNC str_utf8_validate

; -----------------------------------------------------------------------------
; str_utf8_validate_slice
;
; Validate a StrSlice. Thin wrapper around str_utf8_validate.
;
; Signature:
;   int64_t str_utf8_validate_slice(const StrSlice *slice)
;
; Arguments:
;   RDI  — pointer to StrSlice
;
; Returns:
;   RAX  = STR_OK or error code (same as str_utf8_validate)
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_validate_slice

    guard_null rdi, STR_ERR_NULL

    mov     rsi, [rdi + StrSlice.len]   ; len
    mov     rdi, [rdi + StrSlice.ptr]   ; ptr
    ; tail-call into str_utf8_validate
    pop     rbp
    jmp     str_utf8_validate

STR_ENDFUNC str_utf8_validate_slice

; -----------------------------------------------------------------------------
; str_utf8_is_valid
;
; Predicate form — returns 1 if valid, 0 if not (never returns negative).
; Useful for boolean checks where error category doesn't matter.
;
; Signature:
;   int64_t str_utf8_is_valid(const uint8_t *ptr, uint64_t len)
;
; Arguments:
;   RDI  — pointer to byte buffer
;   RSI  — byte length
;
; Returns:
;   RAX  = 1  valid UTF-8
;   RAX  = 0  invalid (or null ptr or zero-length returns 1)
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_is_valid

    ; null → not valid
    test    rdi, rdi
    jz      .false

    call    str_utf8_validate

    test    rax, rax
    setz    al                  ; 1 if rax==0 (STR_OK), else 0
    movzx   eax, al
    pop     rbp
    ret

.false:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_utf8_is_valid