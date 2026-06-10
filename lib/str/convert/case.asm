; =============================================================================
; str/convert/case.asm
; Unicode-aware case conversion for StrSlice.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;   utf8/encode.asm  (str_utf8_encode_unchecked)
;   inspect/is_upper.asm (str_is_upper_cp)
;   inspect/is_lower.asm (str_is_lower_cp)
;   inspect/is_alpha.asm (str_is_alpha_cp)
;
; -----------------------------------------------------------------------------
; Case conversion ranges:
;
;   ASCII:     A-Z ↔ a-z  (XOR 0x20)
;   Latin-1:   0xC0-0xD6 ↔ 0xE0-0xF6
;              0xD8-0xDE ↔ 0xF8-0xFE
;   Greek:     0x0391-0x03A9 ↔ 0x03B1-0x03C9
;   Cyrillic:  0x0410-0x042F ↔ 0x0430-0x044F
;
; For full Unicode case mapping see unicode/tables/case_table.s
; This module handles the most common scripts inline for speed.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_utf8_encode_unchecked
extern str_is_alpha_cp

section .text

; -----------------------------------------------------------------------------
; str_cp_to_upper
;
; Convert a single codepoint to uppercase. Returns codepoint unchanged
; if it has no uppercase form.
;
; Signature:
;   uint32_t str_cp_to_upper(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   EAX  — uppercase codepoint
; -----------------------------------------------------------------------------

STR_FUNC str_cp_to_upper

    ; ASCII a-z → A-Z
    cmp     edi, 'a'
    jb      .check_latin1_lo
    cmp     edi, 'z'
    ja      .check_latin1_lo
    mov     eax, edi
    and     al, 0xDF            ; clear bit 5
    pop     rbp
    ret

.check_latin1_lo:
    ; Latin-1 lowercase: 0xE0..0xF6 → 0xC0..0xD6
    cmp     edi, 0xE0
    jb      .check_latin1_lo2
    cmp     edi, 0xF6
    ja      .check_latin1_lo2
    mov     eax, edi
    sub     eax, 0x20
    pop     rbp
    ret

.check_latin1_lo2:
    ; Latin-1 lowercase: 0xF8..0xFE → 0xD8..0xDE
    cmp     edi, 0xF8
    jb      .check_greek_lo
    cmp     edi, 0xFE
    ja      .check_greek_lo
    mov     eax, edi
    sub     eax, 0x20
    pop     rbp
    ret

.check_greek_lo:
    ; Greek lowercase: 0x03B1..0x03C9 → 0x0391..0x03A9
    cmp     edi, 0x03B1
    jb      .check_cyrillic_lo
    cmp     edi, 0x03C9
    ja      .check_cyrillic_lo
    mov     eax, edi
    sub     eax, 0x20
    pop     rbp
    ret

.check_cyrillic_lo:
    ; Cyrillic lowercase: 0x0430..0x044F → 0x0410..0x042F
    cmp     edi, 0x0430
    jb      .check_latin_ext_lo
    cmp     edi, 0x044F
    ja      .check_latin_ext_lo
    mov     eax, edi
    sub     eax, 0x20
    pop     rbp
    ret

.check_latin_ext_lo:
    ; Latin Extended-A: odd codepoints → subtract 1
    cmp     edi, 0x0101
    jb      .no_upper
    cmp     edi, 0x017F
    ja      .no_upper
    test    edi, 1
    jz      .no_upper           ; even → already uppercase
    mov     eax, edi
    dec     eax
    pop     rbp
    ret

.no_upper:
    mov     eax, edi            ; return unchanged
    pop     rbp
    ret

STR_ENDFUNC str_cp_to_upper

; -----------------------------------------------------------------------------
; str_cp_to_lower
;
; Convert a single codepoint to lowercase.
;
; Signature:
;   uint32_t str_cp_to_lower(uint32_t cp)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_to_lower

    ; ASCII A-Z → a-z
    cmp     edi, 'A'
    jb      .check_latin1_up
    cmp     edi, 'Z'
    ja      .check_latin1_up
    mov     eax, edi
    or      al, 0x20
    pop     rbp
    ret

.check_latin1_up:
    ; Latin-1 uppercase: 0xC0..0xD6 → 0xE0..0xF6
    cmp     edi, 0xC0
    jb      .check_latin1_up2
    cmp     edi, 0xD6
    ja      .check_latin1_up2
    mov     eax, edi
    add     eax, 0x20
    pop     rbp
    ret

.check_latin1_up2:
    ; Latin-1 uppercase: 0xD8..0xDE → 0xF8..0xFE
    cmp     edi, 0xD8
    jb      .check_greek_up
    cmp     edi, 0xDE
    ja      .check_greek_up
    mov     eax, edi
    add     eax, 0x20
    pop     rbp
    ret

.check_greek_up:
    ; Greek uppercase: 0x0391..0x03A9 → 0x03B1..0x03C9
    cmp     edi, 0x0391
    jb      .check_cyrillic_up
    cmp     edi, 0x03A9
    ja      .check_cyrillic_up
    mov     eax, edi
    add     eax, 0x20
    pop     rbp
    ret

.check_cyrillic_up:
    ; Cyrillic uppercase: 0x0410..0x042F → 0x0430..0x044F
    cmp     edi, 0x0410
    jb      .check_latin_ext_up
    cmp     edi, 0x042F
    ja      .check_latin_ext_up
    mov     eax, edi
    add     eax, 0x20
    pop     rbp
    ret

.check_latin_ext_up:
    ; Latin Extended-A: even codepoints → add 1
    cmp     edi, 0x0100
    jb      .no_lower
    cmp     edi, 0x017E
    ja      .no_lower
    test    edi, 1
    jnz     .no_lower           ; odd → already lowercase
    mov     eax, edi
    inc     eax
    pop     rbp
    ret

.no_lower:
    mov     eax, edi
    pop     rbp
    ret

STR_ENDFUNC str_cp_to_lower

; -----------------------------------------------------------------------------
; str_to_upper
;
; Convert all codepoints in a UTF-8 string to uppercase.
; Writes result into caller-supplied buffer.
;
; Signature:
;   int64_t str_to_upper(const StrSlice *src, uint8_t *buf,
;                         uint64_t buf_cap, StrSlice *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — output buffer
;   RDX  — buffer capacity
;   RCX  — output StrSlice
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL
; -----------------------------------------------------------------------------

STR_FUNC str_to_upper

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out

    mov     r15, [rbx + StrSlice.ptr]   ; src ptr
    mov     r9,  [rbx + StrSlice.len]   ; src len
    mov     r10, r15
    add     r10, r9             ; end ptr
    mov     r11, r12            ; write cursor

.tu_loop:
    cmp     r15, r10
    jae     .tu_done

    ; decode codepoint
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, r15
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r8, [rsp]           ; advance
    mov     rsp, rbp

    add     r15, r8

    ; convert to upper
    mov     edi, eax
    push    r15
    push    r10
    push    r11
    call    str_cp_to_upper
    pop     r11
    pop     r10
    pop     r15

    ; encode result
    ; check we have room (worst case 4 bytes)
    mov     rcx, r11
    sub     rcx, r12
    mov     rdx, r13
    sub     rdx, rcx
    cmp     rdx, 4
    jb      .tu_too_small

    mov     edi, eax
    mov     rsi, r11
    push    r15
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r15
    ; rax = bytes written

    add     r11, rax
    jmp     .tu_loop

.tu_done:
    ; write output slice
    mov     [r14 + StrSlice.ptr], r12
    mov     rax, r11
    sub     rax, r12
    mov     [r14 + StrSlice.len], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tu_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_to_upper

; -----------------------------------------------------------------------------
; str_to_lower
;
; Convert all codepoints to lowercase.
;
; Signature:
;   int64_t str_to_lower(const StrSlice *src, uint8_t *buf,
;                         uint64_t buf_cap, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_to_lower

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    mov     r15, [rbx + StrSlice.ptr]
    mov     r9,  [rbx + StrSlice.len]
    mov     r10, r15
    add     r10, r9
    mov     r11, r12

.tl_loop:
    cmp     r15, r10
    jae     .tl_done

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, r15
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r8, [rsp]
    mov     rsp, rbp
    add     r15, r8

    mov     edi, eax
    push    r15
    push    r10
    push    r11
    call    str_cp_to_lower
    pop     r11
    pop     r10
    pop     r15

    mov     rcx, r11
    sub     rcx, r12
    mov     rdx, r13
    sub     rdx, rcx
    cmp     rdx, 4
    jb      .tl_too_small

    mov     edi, eax
    mov     rsi, r11
    push    r15
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r15

    add     r11, rax
    jmp     .tl_loop

.tl_done:
    mov     [r14 + StrSlice.ptr], r12
    mov     rax, r11
    sub     rax, r12
    mov     [r14 + StrSlice.len], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tl_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_to_lower

; -----------------------------------------------------------------------------
; str_to_title
;
; Convert string to title case: first codepoint of each word uppercase,
; rest lowercase. Words are delimited by whitespace.
;
; Signature:
;   int64_t str_to_title(const StrSlice *src, uint8_t *buf,
;                         uint64_t buf_cap, StrSlice *out)
; -----------------------------------------------------------------------------

extern str_is_space_cp

STR_FUNC str_to_title

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    mov     r15, [rbx + StrSlice.ptr]
    mov     r9,  [rbx + StrSlice.len]
    mov     r10, r15
    add     r10, r9
    mov     r11, r12

    mov     r8b, 1              ; at_word_start = true

.tt_loop:
    cmp     r15, r10
    jae     .tt_done

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, r15
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     rcx, [rsp]          ; advance
    mov     rsp, rbp
    add     r15, rcx

    ; check if space
    mov     edi, eax
    push    rax
    push    r15
    push    r10
    push    r11
    push    r8
    call    str_is_space_cp
    pop     r8
    pop     r11
    pop     r10
    pop     r15
    pop     rcx                 ; rcx = original codepoint

    test    eax, eax
    jnz     .tt_is_space

    ; not space: apply case based on at_word_start
    test    r8b, r8b
    jnz     .tt_do_upper

    ; lowercase
    mov     edi, ecx
    push    r15
    push    r10
    push    r11
    push    r8
    call    str_cp_to_lower
    pop     r8
    pop     r11
    pop     r10
    pop     r15
    xor     r8b, r8b            ; at_word_start = false
    jmp     .tt_encode

.tt_do_upper:
    mov     edi, ecx
    push    r15
    push    r10
    push    r11
    push    r8
    call    str_cp_to_upper
    pop     r8
    pop     r11
    pop     r10
    pop     r15
    xor     r8b, r8b
    jmp     .tt_encode

.tt_is_space:
    mov     eax, ecx            ; keep space as-is
    mov     r8b, 1              ; next char starts a word

.tt_encode:
    ; check capacity
    mov     rdx, r11
    sub     rdx, r12
    mov     rcx, r13
    sub     rcx, rdx
    cmp     rcx, 4
    jb      .tt_too_small

    mov     edi, eax
    mov     rsi, r11
    push    r15
    push    r10
    push    r8
    call    str_utf8_encode_unchecked
    pop     r8
    pop     r10
    pop     r15

    add     r11, rax
    jmp     .tt_loop

.tt_done:
    mov     [r14 + StrSlice.ptr], r12
    mov     rax, r11
    sub     rax, r12
    mov     [r14 + StrSlice.len], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tt_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_to_title
