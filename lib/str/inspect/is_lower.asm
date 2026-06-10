; =============================================================================
; str/inspect/is_lower.asm
; Check whether a codepoint or string contains only lowercase characters.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm      (str_utf8_decode_unchecked)
;   inspect/is_alpha.asm (str_is_alpha_cp)
;
; -----------------------------------------------------------------------------
; Lowercase ranges covered:
;
;   ASCII:        a-z  (0x61..0x7A)
;   Latin-1:      0xDF..0xF6, 0xF8..0xFF
;   Greek lower:  0x03B1..0x03C9
;   Cyrillic low: 0x0430..0x044F
;   Latin Ext-A:  odd codepoints 0x0101..0x017F
;   Armenian low: 0x0561..0x0587
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_is_alpha_cp

section .text

; -----------------------------------------------------------------------------
; str_is_lower_cp
;
; Check if a codepoint is lowercase.
;
; Signature:
;   int64_t str_is_lower_cp(uint32_t cp)
;
; Returns:
;   RAX  = 1  lowercase
;   RAX  = 0  not lowercase
; -----------------------------------------------------------------------------

STR_FUNC str_is_lower_cp

    ; ASCII a-z
    cmp     edi, 'a'
    jb      .check_latin1
    cmp     edi, 'z'
    jbe     .true

.check_latin1:
    ; Latin-1 lowercase: 0xDF..0xF6
    cmp     edi, 0xDF
    jb      .check_latin1_2
    cmp     edi, 0xF6
    jbe     .true

.check_latin1_2:
    ; Latin-1 lowercase: 0xF8..0xFF
    cmp     edi, 0xF8
    jb      .check_greek
    cmp     edi, 0xFF
    jbe     .true

.check_greek:
    ; Greek lowercase: 0x03B1..0x03C9
    cmp     edi, 0x03B1
    jb      .check_cyrillic
    cmp     edi, 0x03C9
    jbe     .true

.check_cyrillic:
    ; Cyrillic lowercase: 0x0430..0x044F
    cmp     edi, 0x0430
    jb      .check_latin_ext
    cmp     edi, 0x044F
    jbe     .true

.check_latin_ext:
    ; Latin Extended-A: odd codepoints are lowercase
    cmp     edi, 0x0101
    jb      .check_armenian
    cmp     edi, 0x017F
    ja      .check_armenian
    test    edi, 1
    jnz     .true               ; odd → likely lowercase
    jmp     .false

.check_armenian:
    ; Armenian lowercase: 0x0561..0x0587
    cmp     edi, 0x0561
    jb      .false
    cmp     edi, 0x0587
    jbe     .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_lower_cp

; -----------------------------------------------------------------------------
; str_is_lower
;
; Check if all cased codepoints in a UTF-8 string are lowercase.
; Non-cased codepoints are ignored.
;
; Signature:
;   int64_t str_is_lower(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  at least one cased char, all lowercase
;   RAX  = 0  otherwise
;   RAX  = STR_ERR_NULL  ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_is_lower

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx
    xor     r14, r14            ; found_cased flag

.lower_loop:
    cmp     rbx, r12
    jae     .done_lower

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r13, [rsp]
    mov     rsp, rbp
    add     rbx, r13

    mov     r13d, eax

    ; is cased?
    mov     edi, r13d
    push    rbx
    push    r12
    call    str_is_alpha_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .lower_loop

    inc     r14

    ; is lowercase?
    mov     edi, r13d
    push    rbx
    push    r12
    call    str_is_lower_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .not_lower

    jmp     .lower_loop

.done_lower:
    test    r14, r14
    jz      .not_lower

    pop_regs r14, r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_lower:
    pop_regs r14, r13, r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_lower

; -----------------------------------------------------------------------------
; str_is_ascii_lower — ASCII-only fast path
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_lower

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx
    xor     ecx, ecx

.al_loop:
    cmp     rbx, r12
    jae     .al_done

    movzx   eax, byte [rbx]
    inc     rbx

    ; uppercase A-Z → fail
    cmp     al, 'A'
    jb      .al_check_lower
    cmp     al, 'Z'
    jbe     .al_not_lower

.al_check_lower:
    cmp     al, 'a'
    jb      .al_loop
    cmp     al, 'z'
    ja      .al_loop
    inc     ecx
    jmp     .al_loop

.al_done:
    test    ecx, ecx
    jz      .al_not_lower

    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.al_not_lower:
    pop_regs r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_lower

; -----------------------------------------------------------------------------
; str_is_lower_slice — StrSlice wrapper
; -----------------------------------------------------------------------------

STR_FUNC str_is_lower_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_lower

STR_ENDFUNC str_is_lower_slice