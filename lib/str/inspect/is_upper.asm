; =============================================================================
; str/inspect/is_upper.asm
; Check whether a codepoint or string contains only uppercase characters.
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
; Uppercase ranges covered:
;
;   ASCII:        A-Z  (0x41..0x5A)
;   Latin-1:      0xC0..0xD6, 0xD8..0xDE
;   Greek upper:  0x0391..0x03A9
;   Cyrillic up:  0x0410..0x042F
;   Latin Ext-A:  selected ranges 0x0100..0x017E (even codepoints)
;
; str_is_upper_cp    — Unicode-aware codepoint check
; str_is_upper       — full UTF-8 string (all cased chars must be upper)
; str_is_ascii_upper — ASCII-only fast path
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_is_upper_cp
;
; Check if a codepoint is uppercase.
;
; Signature:
;   int64_t str_is_upper_cp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1  uppercase
;   RAX  = 0  not uppercase (includes non-cased codepoints)
; -----------------------------------------------------------------------------

STR_FUNC str_is_upper_cp

    ; ASCII A-Z
    cmp     edi, 'A'
    jb      .check_latin1
    cmp     edi, 'Z'
    jbe     .true

.check_latin1:
    ; Latin-1 uppercase: 0xC0..0xD6
    cmp     edi, 0xC0
    jb      .check_latin1_2
    cmp     edi, 0xD6
    jbe     .true

.check_latin1_2:
    ; Latin-1 uppercase: 0xD8..0xDE (skip 0xD7 × )
    cmp     edi, 0xD8
    jb      .check_greek
    cmp     edi, 0xDE
    jbe     .true

.check_greek:
    ; Greek uppercase: 0x0391..0x03A9
    cmp     edi, 0x0391
    jb      .check_cyrillic
    cmp     edi, 0x03A9
    jbe     .true

.check_cyrillic:
    ; Cyrillic uppercase: 0x0410..0x042F
    cmp     edi, 0x0410
    jb      .check_latin_ext
    cmp     edi, 0x042F
    jbe     .true

.check_latin_ext:
    ; Latin Extended-A uppercase pairs start at even codepoints
    ; 0x0100..0x012E, 0x0130, 0x0132..0x0136, 0x0139..0x013E (odd)
    ; Simplified: check block and even/odd heuristic
    cmp     edi, 0x0100
    jb      .check_armenian
    cmp     edi, 0x017E
    ja      .check_armenian
    ; In Ext-A, uppercase letters are generally even-valued
    test    edi, 1
    jz      .true               ; even → likely uppercase
    jmp     .false

.check_armenian:
    ; Armenian uppercase: 0x0531..0x0556
    cmp     edi, 0x0531
    jb      .false
    cmp     edi, 0x0556
    jbe     .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_upper_cp

; -----------------------------------------------------------------------------
; str_is_upper
;
; Check if all cased codepoints in a UTF-8 string are uppercase.
; Non-cased codepoints (digits, punctuation, spaces) are ignored —
; only letters are checked. Empty string or all-non-cased → 0.
;
; Signature:
;   int64_t str_is_upper(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  at least one cased char, all cased chars are uppercase
;   RAX  = 0  otherwise
;   RAX  = STR_ERR_NULL  ptr is null
; -----------------------------------------------------------------------------

extern str_is_alpha_cp

STR_FUNC str_is_upper

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx
    xor     r14, r14            ; r14 = found_cased flag

.upper_loop:
    cmp     rbx, r12
    jae     .done_upper

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r13, [rsp]
    mov     rsp, rbp
    add     rbx, r13

    mov     r13d, eax           ; save codepoint

    ; is it alphabetic (cased)?
    mov     edi, r13d
    push    rbx
    push    r12
    call    str_is_alpha_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .upper_loop         ; not cased — skip

    inc     r14                 ; mark cased found

    ; is it uppercase?
    mov     edi, r13d
    push    rbx
    push    r12
    call    str_is_upper_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .not_upper

    jmp     .upper_loop

.done_upper:
    test    r14, r14
    jz      .not_upper          ; no cased chars found

    pop_regs r14, r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_upper:
    pop_regs r14, r13, r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_upper

; -----------------------------------------------------------------------------
; str_is_ascii_upper — ASCII-only fast path
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_upper

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx
    xor     ecx, ecx            ; found_upper flag

.au_loop:
    cmp     rbx, r12
    jae     .au_done

    movzx   eax, byte [rbx]
    inc     rbx

    ; lowercase a-z → fail
    cmp     al, 'a'
    jb      .au_check_upper
    cmp     al, 'z'
    jbe     .au_not_upper

.au_check_upper:
    cmp     al, 'A'
    jb      .au_loop
    cmp     al, 'Z'
    ja      .au_loop
    inc     ecx                 ; is uppercase letter
    jmp     .au_loop

.au_done:
    test    ecx, ecx
    jz      .au_not_upper

    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.au_not_upper:
    pop_regs r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_upper

; -----------------------------------------------------------------------------
; str_is_upper_slice — StrSlice wrapper
; -----------------------------------------------------------------------------

STR_FUNC str_is_upper_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_upper

STR_ENDFUNC str_is_upper_slice