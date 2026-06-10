; =============================================================================
; str/core/concat.asm
; Concatenate two or more StrSlices into a caller-supplied buffer.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm  (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; concat never allocates. Caller supplies the output buffer.
; For allocation-based concat use buf/strbuf.asm (str_buf_append).
;
; Functions:
;   str_concat        — join two slices into a buffer → StrSlice
;   str_concat3       — join three slices
;   str_concat_many   — join N slices (array + count)
;   str_concat_sep    — join N slices with a separator between each
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes

section .text

; -----------------------------------------------------------------------------
; str_concat
;
; Concatenate two StrSlices into a caller-supplied buffer.
;
; Signature:
;   int64_t str_concat(const StrSlice *a, const StrSlice *b,
;                       uint8_t *buf, uint64_t buf_cap,
;                       StrSlice *out)
;
; Arguments:
;   RDI  — pointer to StrSlice a
;   RSI  — pointer to StrSlice b
;   RDX  — output buffer
;   RCX  — buffer capacity
;   R8   — pointer to output StrSlice
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          any required pointer is null
;   RAX  = STR_ERR_BUF_TOO_SMALL buf_cap < a.len + b.len
;   RAX  = STR_ERR_OVERFLOW      a.len + b.len overflows uint64
; -----------------------------------------------------------------------------

STR_FUNC str_concat

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; a
    mov     r12, rsi            ; b
    mov     r13, rdx            ; buf
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out

    mov     r9,  [rbx + StrSlice.len]   ; a.len
    mov     r10, [r12 + StrSlice.len]   ; b.len

    ; overflow check: a.len + b.len
    mov     rax, r9
    add     rax, r10
    jc      .overflow

    ; capacity check
    cmp     rax, r14
    ja      .too_small

    mov     r11, rax            ; total len

    ; copy a into buf
    mov     rdi, r13
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, r9
    call    str_copy_bytes
    test    rax, rax
    jnz     .err_concat

    ; copy b into buf + a.len
    mov     rdi, r13
    add     rdi, r9
    mov     rsi, [r12 + StrSlice.ptr]
    mov     rdx, r10
    call    str_copy_bytes
    test    rax, rax
    jnz     .err_concat

    ; write output slice
    mov     [r15 + StrSlice.ptr], r13
    mov     [r15 + StrSlice.len], r11

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.err_concat:
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_concat

; -----------------------------------------------------------------------------
; str_concat3
;
; Concatenate three StrSlices into a buffer.
;
; Signature:
;   int64_t str_concat3(const StrSlice *a, const StrSlice *b,
;                        const StrSlice *c, uint8_t *buf,
;                        uint64_t buf_cap, StrSlice *out)
;
; Arguments:
;   RDI  — a
;   RSI  — b
;   RDX  — c
;   RCX  — buf
;   R8   — cap
;   R9   — out
; -----------------------------------------------------------------------------

STR_FUNC str_concat3

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx            ; buf
    mov     r15, r8             ; cap
    ; r9 = out (on stack after push)
    push    r9

    mov     rax, [rbx + StrSlice.len]
    mov     rcx, [r12 + StrSlice.len]
    mov     rdx, [r13 + StrSlice.len]

    ; total = a.len + b.len + c.len (check overflow)
    add     rax, rcx
    jc      .overflow3
    add     rax, rdx
    jc      .overflow3

    cmp     rax, r15
    ja      .too_small3

    mov     r8, rax             ; total len
    mov     r9, r14             ; write cursor

    ; copy a
    mov     rdi, r9
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, [rbx + StrSlice.len]
    call    str_copy_bytes
    test    rax, rax
    jnz     .err3

    add     r9, [rbx + StrSlice.len]

    ; copy b
    mov     rdi, r9
    mov     rsi, [r12 + StrSlice.ptr]
    mov     rdx, [r12 + StrSlice.len]
    call    str_copy_bytes
    test    rax, rax
    jnz     .err3

    add     r9, [r12 + StrSlice.len]

    ; copy c
    mov     rdi, r9
    mov     rsi, [r13 + StrSlice.ptr]
    mov     rdx, [r13 + StrSlice.len]
    call    str_copy_bytes
    test    rax, rax
    jnz     .err3

    ; write out
    pop     r9
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.overflow3:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.too_small3:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.err3:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_concat3

; -----------------------------------------------------------------------------
; str_concat_many
;
; Concatenate an array of N StrSlices into a buffer.
;
; Signature:
;   int64_t str_concat_many(const StrSlice **slices, uint64_t count,
;                            uint8_t *buf, uint64_t buf_cap,
;                            StrSlice *out)
;
; Arguments:
;   RDI  — pointer to array of StrSlice pointers
;   RSI  — number of slices
;   RDX  — output buffer
;   RCX  — buffer capacity
;   R8   — output StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_concat_many

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    ; zero slices → empty output
    test    rsi, rsi
    jz      .empty_many

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; slice array
    mov     r12, rsi            ; count
    mov     r13, rdx            ; buf
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out

    ; first pass: compute total length
    xor     r8, r8              ; total = 0
    xor     r9, r9              ; i = 0

.len_pass:
    cmp     r9, r12
    jae     .len_done

    mov     rax, [rbx + r9 * 8]         ; slices[i]
    test    rax, rax
    jz      .err_null_slice

    mov     rax, [rax + StrSlice.len]
    add     r8, rax
    jc      .overflow_many

    inc     r9
    jmp     .len_pass

.len_done:
    ; check capacity
    cmp     r8, r14
    ja      .too_small_many

    ; second pass: copy each slice
    mov     r11, r13            ; write cursor
    xor     r9, r9              ; i = 0

.copy_pass:
    cmp     r9, r12
    jae     .copy_done

    mov     rax, [rbx + r9 * 8]
    mov     rdi, r11
    mov     rsi, [rax + StrSlice.ptr]
    mov     rdx, [rax + StrSlice.len]
    push    r8
    push    r9
    call    str_copy_bytes
    pop     r9
    pop     r8
    test    rax, rax
    jnz     .err_many

    mov     rax, [rbx + r9 * 8]
    add     r11, [rax + StrSlice.len]

    inc     r9
    jmp     .copy_pass

.copy_done:
    mov     [r15 + StrSlice.ptr], r13
    mov     [r15 + StrSlice.len], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.empty_many:
    ; write empty slice into out
    test    r8, r8
    jz      .ok_empty
    mov     qword [r8 + StrSlice.ptr], 0
    mov     qword [r8 + StrSlice.len], 0
.ok_empty:
    xor     eax, eax
    pop     rbp
    ret

.err_null_slice:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_NULL
    pop     rbp
    ret

.overflow_many:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.too_small_many:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.err_many:
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_concat_many

; -----------------------------------------------------------------------------
; str_concat_sep
;
; Join N slices with a separator StrSlice between each pair.
; Result: a[0] + sep + a[1] + sep + ... + a[N-1]
;
; Signature:
;   int64_t str_concat_sep(const StrSlice **slices, uint64_t count,
;                           const StrSlice *sep, uint8_t *buf,
;                           uint64_t buf_cap, StrSlice *out)
;
; Arguments:
;   RDI  — slice array
;   RSI  — count
;   RDX  — separator StrSlice
;   RCX  — buf
;   R8   — buf_cap
;   R9   — out
; -----------------------------------------------------------------------------

STR_FUNC str_concat_sep

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    test    rsi, rsi
    jz      .empty_sep

    push_regs rbx, r12, r13, r14, r15
    push    r9                  ; save out

    mov     rbx, rdi            ; slice array
    mov     r12, rsi            ; count
    mov     r13, rdx            ; sep
    mov     r14, rcx            ; buf
    mov     r15, r8             ; cap

    mov     r10, [r13 + StrSlice.len]   ; sep.len

    ; compute total = sum(slice[i].len) + sep.len * (count-1)
    xor     r8,  r8
    xor     r9,  r9

.sep_len_pass:
    cmp     r9, r12
    jae     .sep_len_done

    mov     rax, [rbx + r9 * 8]
    test    rax, rax
    jz      .err_null_sep

    mov     rax, [rax + StrSlice.len]
    add     r8, rax
    jc      .overflow_sep

    ; add separator length (not after last element)
    mov     rax, r9
    inc     rax
    cmp     rax, r12
    jae     .sep_no_add

    add     r8, r10
    jc      .overflow_sep

.sep_no_add:
    inc     r9
    jmp     .sep_len_pass

.sep_len_done:
    cmp     r8, r15
    ja      .too_small_sep

    ; copy pass
    mov     r11, r14            ; write cursor
    xor     r9,  r9

.sep_copy_pass:
    cmp     r9, r12
    jae     .sep_copy_done

    ; copy slice[i]
    mov     rax, [rbx + r9 * 8]
    mov     rdi, r11
    mov     rsi, [rax + StrSlice.ptr]
    mov     rdx, [rax + StrSlice.len]
    push    r8
    push    r9
    call    str_copy_bytes
    pop     r9
    pop     r8
    test    rax, rax
    jnz     .err_sep

    mov     rax, [rbx + r9 * 8]
    add     r11, [rax + StrSlice.len]

    ; copy separator if not last
    mov     rax, r9
    inc     rax
    cmp     rax, r12
    jae     .sep_skip

    mov     rdi, r11
    mov     rsi, [r13 + StrSlice.ptr]
    mov     rdx, r10
    push    r8
    push    r9
    call    str_copy_bytes
    pop     r9
    pop     r8
    test    rax, rax
    jnz     .err_sep

    add     r11, r10

.sep_skip:
    inc     r9
    jmp     .sep_copy_pass

.sep_copy_done:
    pop     r9
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.empty_sep:
    xor     eax, eax
    pop     rbp
    ret

.err_null_sep:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_NULL
    pop     rbp
    ret

.overflow_sep:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.too_small_sep:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.err_sep:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_concat_sep
