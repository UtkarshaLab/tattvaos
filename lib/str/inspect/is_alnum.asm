; =============================================================================
; str/inspect/is_alnum.asm
; Check whether a codepoint or string is alphanumeric (alpha OR numeric).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_alpha.asm   (str_is_alpha_cp)
;   inspect/is_numeric.asm (str_is_decimal_cp)
;   utf8/decode.asm        (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; Alphanumeric = alphabetic OR decimal digit.
; Uses str_is_alpha_cp and str_is_decimal_cp — no duplication.
;
; ASCII fast path: byte in A-Z, a-z, or 0-9.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_is_alpha_cp
extern str_is_decimal_cp

section .text

; -----------------------------------------------------------------------------
; str_is_alnum_cp
;
; Check if a codepoint is alphanumeric.
;
; Signature:
;   int64_t str_is_alnum_cp(uint32_t cp)
;
; Returns:
;   RAX  = 1  alphanumeric
;   RAX  = 0  not alphanumeric
; -----------------------------------------------------------------------------

STR_FUNC str_is_alnum_cp

    push_regs rbx
    mov     ebx, edi

    call    str_is_alpha_cp
    test    eax, eax
    jnz     .true_alnum

    mov     edi, ebx
    call    str_is_decimal_cp
    test    eax, eax
    jnz     .true_alnum

    pop_regs rbx
    xor     eax, eax
    pop     rbp
    ret

.true_alnum:
    pop_regs rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_alnum_cp

; -----------------------------------------------------------------------------
; str_is_ascii_alnum_byte
;
; Fast ASCII-only alphanumeric check for a single byte.
;
; Signature:
;   int64_t str_is_ascii_alnum_byte(uint8_t byte)
;
; Returns:
;   RAX  = 1  byte in A-Z, a-z, or 0-9
;   RAX  = 0  otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_alnum_byte

    movzx   eax, dil

    ; 0-9
    cmp     al, '0'
    jb      .check_alpha
    cmp     al, '9'
    jbe     .true

.check_alpha:
    ; A-Z
    cmp     al, 'A'
    jb      .check_lower
    cmp     al, 'Z'
    jbe     .true

.check_lower:
    ; a-z
    cmp     al, 'a'
    jb      .false
    cmp     al, 'z'
    jbe     .true

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_alnum_byte

; -----------------------------------------------------------------------------
; str_is_alnum
;
; Check if every codepoint in a UTF-8 string is alphanumeric.
; Empty string returns 0.
;
; Signature:
;   int64_t str_is_alnum(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  all alphanumeric, non-empty
;   RAX  = 0  empty or contains non-alphanumeric codepoint
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_is_alnum

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.alnum_loop:
    cmp     rbx, r12
    jae     .all_alnum

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
    call    str_is_alnum_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .not_alnum

    jmp     .alnum_loop

.all_alnum:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_alnum:
    pop_regs r13, r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_alnum

; -----------------------------------------------------------------------------
; str_is_ascii_alnum
;
; ASCII-only alphanumeric check over a buffer. No UTF-8 decoding.
;
; Signature:
;   int64_t str_is_ascii_alnum(const uint8_t *ptr, uint64_t byte_len)
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_alnum

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.aa_loop:
    cmp     rbx, r12
    jae     .aa_true

    movzx   eax, byte [rbx]
    inc     rbx

    ; 0-9
    cmp     al, '0'
    jb      .aa_check_upper
    cmp     al, '9'
    jbe     .aa_loop

.aa_check_upper:
    ; A-Z
    cmp     al, 'A'
    jb      .aa_check_lower
    cmp     al, 'Z'
    jbe     .aa_loop

.aa_check_lower:
    ; a-z
    cmp     al, 'a'
    jb      .aa_false
    cmp     al, 'z'
    jbe     .aa_loop

.aa_false:
    pop_regs r12, rbx
    mov     eax, STR_FALSE
    pop     rbp
    ret

.aa_true:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_alnum

; -----------------------------------------------------------------------------
; str_is_alnum_slice / str_is_ascii_alnum_slice — StrSlice wrappers
; -----------------------------------------------------------------------------

STR_FUNC str_is_alnum_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_alnum

STR_ENDFUNC str_is_alnum_slice

STR_FUNC str_is_ascii_alnum_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_ascii_alnum

STR_ENDFUNC str_is_ascii_alnum_slice