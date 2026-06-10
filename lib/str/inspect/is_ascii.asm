; =============================================================================
; str/inspect/is_ascii.asm
; Check whether a byte buffer or codepoint is pure ASCII.
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
; ASCII range: 0x00..0x7F (top bit clear)
; A string is ASCII if every byte has bit 7 == 0.
; Fast path: check 8 bytes at a time with a single OR + test.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_is_ascii
;
; Check if every byte in a buffer is ASCII (0x00..0x7F).
;
; Signature:
;   int64_t str_is_ascii(const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to byte buffer
;   RSI  — byte length
;
; Returns:
;   RAX  = 1   all bytes are ASCII
;   RAX  = 0   at least one byte is non-ASCII (>= 0x80)
;   RAX  = STR_ERR_NULL  ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii

    guard_null rdi, STR_ERR_NULL

    ; empty string → ASCII
    test    rsi, rsi
    jz      .true

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx            ; r12 = end ptr

    ; --- 8-bytes-at-a-time fast path ---
    ; need at least 8 bytes
    cmp     rsi, 8
    jb      .scalar

.qword_loop:
    lea     rax, [rbx + 8]
    cmp     rax, r12
    ja      .scalar

    mov     rax, [rbx]          ; load 8 bytes
    test    rax, 0x8080808080808080
    jnz     .false              ; any high bit set → not ASCII

    add     rbx, 8
    jmp     .qword_loop

    ; --- scalar tail ---
.scalar:
    cmp     rbx, r12
    jae     .true

    movzx   eax, byte [rbx]
    test    al, 0x80
    jnz     .false

    inc     rbx
    jmp     .scalar

.true:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    pop_regs r12, rbx
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii

; -----------------------------------------------------------------------------
; str_is_ascii_slice
;
; Check a StrSlice for pure ASCII.
;
; Signature:
;   int64_t str_is_ascii_slice(const StrSlice *slice)
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_slice

    guard_null rdi, STR_ERR_NULL

    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]

    pop     rbp
    jmp     str_is_ascii

STR_ENDFUNC str_is_ascii_slice

; -----------------------------------------------------------------------------
; str_is_ascii_byte
;
; Check a single byte.
;
; Signature:
;   int64_t str_is_ascii_byte(uint8_t byte)
;
; Arguments:
;   DIL  — byte to check
;
; Returns:
;   RAX  = 1 if byte <= 0x7F, else 0
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_byte

    movzx   eax, dil
    test    al, 0x80
    setz    al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_byte

; -----------------------------------------------------------------------------
; str_is_ascii_codepoint
;
; Check a Unicode codepoint is in ASCII range.
;
; Signature:
;   int64_t str_is_ascii_codepoint(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if cp <= U+007F, else 0
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_codepoint

    cmp     edi, ASCII_MAX
    setbe   al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_codepoint