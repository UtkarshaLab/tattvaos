; =============================================================================
; str/inspect/is_utf8.asm
; Check whether a byte buffer is valid UTF-8.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/validate.asm  (str_utf8_validate)
;
; -----------------------------------------------------------------------------
; Thin predicate wrappers around str_utf8_validate.
; Returns 1/0 instead of STR_OK/error — for boolean call sites
; that don't need to know the specific failure reason.
;
; For the specific error (overlong, surrogate, truncated etc.)
; call str_utf8_validate directly.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_validate

section .text

; -----------------------------------------------------------------------------
; str_is_utf8
;
; Check if a byte buffer is valid UTF-8.
;
; Signature:
;   int64_t str_is_utf8(const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to byte buffer
;   RSI  — byte length
;
; Returns:
;   RAX  = 1   valid UTF-8
;   RAX  = 0   invalid (or null ptr)
; -----------------------------------------------------------------------------

STR_FUNC str_is_utf8

    test    rdi, rdi
    jz      .false

    ; empty string is valid UTF-8
    test    rsi, rsi
    jz      .true

    call    str_utf8_validate   ; RAX = 0 on success, negative on error

    test    rax, rax
    setz    al
    movzx   eax, al
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_utf8

; -----------------------------------------------------------------------------
; str_is_utf8_slice
;
; Check a StrSlice for valid UTF-8.
;
; Signature:
;   int64_t str_is_utf8_slice(const StrSlice *slice)
; -----------------------------------------------------------------------------

STR_FUNC str_is_utf8_slice

    test    rdi, rdi
    jz      .false

    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]

    pop     rbp
    jmp     str_is_utf8

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_utf8_slice

; -----------------------------------------------------------------------------
; str_is_utf8_strict
;
; Like str_is_utf8 but also rejects ASCII-only strings that contain
; null bytes (0x00). Useful when treating strings as C-compatible.
;
; Signature:
;   int64_t str_is_utf8_strict(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1   valid UTF-8, no interior null bytes
;   RAX  = 0   invalid UTF-8 or contains 0x00
; -----------------------------------------------------------------------------

STR_FUNC str_is_utf8_strict

    test    rdi, rdi
    jz      .false

    test    rsi, rsi
    jz      .true

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx            ; end ptr

    ; first validate UTF-8
    call    str_utf8_validate
    test    rax, rax
    jnz     .invalid

    ; then scan for null bytes
    mov     rdi, rbx

.null_scan:
    cmp     rbx, r12
    jae     .ok_strict

    movzx   eax, byte [rbx]
    test    al, al
    jz      .invalid

    inc     rbx
    jmp     .null_scan

.ok_strict:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.invalid:
    pop_regs r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_utf8_strict