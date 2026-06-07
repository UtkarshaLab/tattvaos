; =============================================================================
; str/utf8/len.asm
; Count the number of Unicode codepoints in a UTF-8 string.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/charlen.asm  (inlined logic for speed)
;
; -----------------------------------------------------------------------------
; Key distinction:
;   byte length  — how many bytes the string occupies in memory
;   codepoint length — how many Unicode characters the string contains
;
;   "Ω"  → 2 bytes, 1 codepoint
;   "नम" → 6 bytes, 2 codepoints  (each Devanagari letter = 3 bytes)
;   "𝔤"  → 4 bytes, 1 codepoint   (Mathematical Fraktur small g)
;
; str_utf8_len returns codepoint count.
; StrSlice.len always stores byte count.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_utf8_len
;
; Count codepoints in a UTF-8 byte buffer. Does NOT validate — call
; str_utf8_validate first if input is untrusted.
;
; Fast path: counts by inspecting only leading bytes. Continuation bytes
; (0x80..0xBF) are skipped — only non-continuation bytes are counted.
; This is equivalent to counting bytes where (byte & 0xC0) != 0x80.
;
; Signature:
;   int64_t str_utf8_len(const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length of buffer
;
; Returns:
;   RAX  >= 0   codepoint count (0 for empty string)
;   RAX  = STR_ERR_NULL  if ptr is null
;
; Clobbers: RAX, RCX, RDX, R8
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_len

    guard_null rdi, STR_ERR_NULL

    ; empty string → 0 codepoints
    test    rsi, rsi
    jz      .empty

    push_regs rbx, r12

    mov     rbx, rdi            ; rbx = ptr
    mov     r12, rsi            ; r12 = byte_len
    add     r12, rbx            ; r12 = one past end
    xor     eax, eax            ; rax = codepoint count

    ; -------------------------------------------------------------------------
    ; Main loop: process 8 bytes at a time where possible
    ; Count non-continuation bytes: those where (byte & 0xC0) != 0x80
    ;
    ; Trick: a byte is a continuation byte if (byte & 0xC0) == 0x80
    ;        i.e. bits [7:6] == 10
    ;        We can check: (byte >> 6) == 2  → continuation
    ; -------------------------------------------------------------------------

    ; Scalar fallback loop (SIMD version lives in arch/x86_64/simd/scan.s)
.loop:
    cmp     rbx, r12
    jae     .done

    movzx   ecx, byte [rbx]
    inc     rbx

    ; if (byte & 0xC0) == 0x80 → continuation → don't count
    mov     edx, ecx
    and     edx, 0xC0
    cmp     edx, 0x80
    je      .loop               ; skip continuation bytes

    inc     rax                 ; leading byte → count it
    jmp     .loop

.done:
    pop_regs r12, rbx
    pop     rbp
    ret

.empty:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_utf8_len

; -----------------------------------------------------------------------------
; str_utf8_len_slice
;
; Count codepoints in a StrSlice.
;
; Signature:
;   int64_t str_utf8_len_slice(const StrSlice *slice)
;
; Arguments:
;   RDI  — pointer to StrSlice
;
; Returns:
;   RAX  >= 0   codepoint count
;   RAX  = STR_ERR_NULL  if slice or slice.ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_len_slice

    guard_null rdi, STR_ERR_NULL

    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]

    pop     rbp
    jmp     str_utf8_len        ; tail call

STR_ENDFUNC str_utf8_len_slice

; -----------------------------------------------------------------------------
; str_utf8_len_validated
;
; Validate first, then count. Returns error if input is malformed.
; Safer than str_utf8_len for untrusted input.
;
; Signature:
;   int64_t str_utf8_len_validated(const uint8_t *ptr, uint64_t byte_len,
;                                  uint64_t *out_cp_count)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length
;   RDX  — pointer to uint64_t to receive codepoint count
;
; Returns:
;   RAX  = STR_OK             count written to *out_cp_count
;   RAX  = STR_ERR_NULL       ptr or out_cp_count is null
;   RAX  = STR_ERR_INVALID_UTF8 / STR_ERR_OVERLONG / etc. on bad input
; -----------------------------------------------------------------------------

extern str_utf8_validate

STR_FUNC str_utf8_len_validated

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi            ; save ptr
    mov     r12, rsi            ; save byte_len
    mov     r13, rdx            ; save out pointer

    ; validate first
    ; rdi = ptr, rsi = byte_len already set
    call    str_utf8_validate
    test    rax, rax
    jnz     .err                ; propagate error

    ; now count
    mov     rdi, rbx
    mov     rsi, r12
    call    str_utf8_len
    test    rax, rax
    js      .err                ; should not happen after validation, but guard

    ; write result
    mov     [r13], rax
    xor     eax, eax            ; STR_OK

.err:
    pop_regs r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_utf8_len_validated

; -----------------------------------------------------------------------------
; str_utf8_byte_len_of_first_n
;
; Given a UTF-8 buffer, compute how many bytes the first N codepoints occupy.
; Useful for slicing: "give me a StrSlice of the first N characters."
;
; Signature:
;   int64_t str_utf8_byte_len_of_first_n(const uint8_t *ptr,
;                                         uint64_t byte_len,
;                                         uint64_t n)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — total byte length available
;   RDX  — number of codepoints N
;
; Returns:
;   RAX  >= 0   byte length of first N codepoints
;   RAX  = STR_ERR_NULL          ptr is null
;   RAX  = STR_ERR_OUT_OF_BOUNDS string has fewer than N codepoints
;   RAX  = STR_ERR_INVALID_UTF8  malformed sequence encountered
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_byte_len_of_first_n

    guard_null rdi, STR_ERR_NULL

    ; N == 0 → 0 bytes
    test    rdx, rdx
    jz      .zero

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; rbx = current ptr
    mov     r12, rsi            ; r12 = byte_len
    add     r12, rbx            ; r12 = end ptr
    mov     r13, rdx            ; r13 = codepoints remaining
    mov     r14, rdi            ; r14 = base ptr (for byte offset calc)

.scan:
    test    r13, r13
    jz      .found

    cmp     rbx, r12
    jae     .out_of_bounds

    movzx   eax, byte [rbx]

    ; determine sequence length inline
    test    al, 0x80
    jz      .cp_one

    cmp     al, 0xC2
    jb      .bad_utf8
    cmp     al, 0xDF
    jbe     .cp_two

    cmp     al, 0xEF
    jbe     .cp_three

    cmp     al, 0xF4
    jbe     .cp_four

    jmp     .bad_utf8

.cp_one:
    add     rbx, 1
    jmp     .next_cp
.cp_two:
    add     rbx, 2
    jmp     .next_cp
.cp_three:
    add     rbx, 3
    jmp     .next_cp
.cp_four:
    add     rbx, 4

.next_cp:
    dec     r13
    jmp     .scan

.found:
    ; byte offset = current ptr - base ptr
    mov     rax, rbx
    sub     rax, r14
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.zero:
    xor     eax, eax
    pop     rbp
    ret

.out_of_bounds:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

.bad_utf8:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

STR_ENDFUNC str_utf8_byte_len_of_first_n