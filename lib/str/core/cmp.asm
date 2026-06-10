; =============================================================================
; str/core/cmp.asm
; Equality and ordering comparisons for StrSlice.
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
; Comparison functions:
;
;   str_eq          — byte-for-byte equality
;   str_eq_ignore_case — ASCII case-insensitive equality
;   str_cmp         — lexicographic ordering (like memcmp + length)
;   str_cmp_ignore_case — case-insensitive ordering
;   str_eq_bytes    — compare raw ptr+len pairs directly
;
; Return convention for ordering:
;   RAX < 0  → a < b
;   RAX = 0  → a == b
;   RAX > 0  → a > b
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_eq
;
; Test two StrSlices for byte-for-byte equality.
;
; Signature:
;   int64_t str_eq(const StrSlice *a, const StrSlice *b)
;
; Arguments:
;   RDI  — pointer to StrSlice a
;   RSI  — pointer to StrSlice b
;
; Returns:
;   RAX  = 1   a and b are equal
;   RAX  = 0   not equal (or either is null)
; -----------------------------------------------------------------------------

STR_FUNC str_eq

    ; null → not equal
    test    rdi, rdi
    jz      .false
    test    rsi, rsi
    jz      .false

    mov     rax, [rdi + StrSlice.len]
    mov     rcx, [rsi + StrSlice.len]

    ; different lengths → not equal
    cmp     rax, rcx
    jne     .false

    ; same pointer → equal (same memory)
    mov     rdx, [rdi + StrSlice.ptr]
    mov     r8,  [rsi + StrSlice.ptr]
    cmp     rdx, r8
    je      .true

    ; zero length → equal
    test    rax, rax
    jz      .true

    push_regs rbx, r12

    mov     rbx, rdx            ; a ptr
    mov     r12, r8             ; b ptr
    ; rcx = rax = length (same)

    ; compare 8 bytes at a time
.qword_loop:
    cmp     rax, 8
    jb      .byte_loop

    mov     rdx, [rbx]
    cmp     rdx, [r12]
    jne     .not_eq

    add     rbx, 8
    add     r12, 8
    sub     rax, 8
    jmp     .qword_loop

.byte_loop:
    test    rax, rax
    jz      .eq_done

    movzx   edx, byte [rbx]
    movzx   ecx, byte [r12]
    cmp     dl, cl
    jne     .not_eq

    inc     rbx
    inc     r12
    dec     rax
    jmp     .byte_loop

.eq_done:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_eq:
    pop_regs r12, rbx

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_eq

; -----------------------------------------------------------------------------
; str_eq_bytes
;
; Compare raw ptr+len pairs for equality. No StrSlice struct needed.
;
; Signature:
;   int64_t str_eq_bytes(const uint8_t *a, uint64_t a_len,
;                         const uint8_t *b, uint64_t b_len)
;
; Arguments:
;   RDI  — pointer a
;   RSI  — length a
;   RDX  — pointer b
;   RCX  — length b
;
; Returns:
;   RAX  = 1  equal
;   RAX  = 0  not equal
; -----------------------------------------------------------------------------

STR_FUNC str_eq_bytes

    ; different lengths → not equal
    cmp     rsi, rcx
    jne     .false

    ; same pointer → equal
    cmp     rdi, rdx
    je      .true

    ; zero length → equal
    test    rsi, rsi
    jz      .true

    ; null check
    test    rdi, rdi
    jz      .false
    test    rdx, rdx
    jz      .false

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rdx
    mov     r13, rsi            ; length

.eq_bytes_qloop:
    cmp     r13, 8
    jb      .eq_bytes_bloop

    mov     rax, [rbx]
    cmp     rax, [r12]
    jne     .eq_bytes_ne

    add     rbx, 8
    add     r12, 8
    sub     r13, 8
    jmp     .eq_bytes_qloop

.eq_bytes_bloop:
    test    r13, r13
    jz      .eq_bytes_ok

    movzx   eax, byte [rbx]
    cmp     al, byte [r12]
    jne     .eq_bytes_ne

    inc     rbx
    inc     r12
    dec     r13
    jmp     .eq_bytes_bloop

.eq_bytes_ok:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.eq_bytes_ne:
    pop_regs r13, r12, rbx

.false:
    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_eq_bytes

; -----------------------------------------------------------------------------
; str_cmp
;
; Lexicographic comparison of two StrSlices.
;
; Signature:
;   int64_t str_cmp(const StrSlice *a, const StrSlice *b)
;
; Returns:
;   RAX < 0  a < b
;   RAX = 0  a == b
;   RAX > 0  a > b
;   RAX = STR_ERR_NULL  either pointer is null
; -----------------------------------------------------------------------------

STR_FUNC str_cmp

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, [rsi + StrSlice.ptr]
    mov     r14, [rsi + StrSlice.len]

    ; min_len = min(a.len, b.len)
    mov     rcx, r12
    cmp     rcx, r14
    jbe     .got_min
    mov     rcx, r14

.got_min:
    ; compare min_len bytes
    xor     edx, edx

.cmp_loop:
    test    rcx, rcx
    jz      .cmp_by_len

    movzx   eax, byte [rbx + rdx]
    movzx   r8d, byte [r13 + rdx]
    cmp     al, r8b
    jne     .cmp_diff

    inc     rdx
    dec     rcx
    jmp     .cmp_loop

.cmp_diff:
    ; return a[i] - b[i]
    sub     eax, r8d
    ; sign-extend to 64-bit
    movsx   rax, eax
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.cmp_by_len:
    ; all common bytes equal — longer string is greater
    mov     rax, r12
    sub     rax, r14            ; a.len - b.len

    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_cmp

; -----------------------------------------------------------------------------
; str_eq_ignore_case
;
; ASCII case-insensitive equality check.
; Only folds A-Z / a-z — non-ASCII bytes compared as-is.
;
; Signature:
;   int64_t str_eq_ignore_case(const StrSlice *a, const StrSlice *b)
;
; Returns:
;   RAX  = 1  equal ignoring ASCII case
;   RAX  = 0  not equal
; -----------------------------------------------------------------------------

STR_FUNC str_eq_ignore_case

    test    rdi, rdi
    jz      .false_ic
    test    rsi, rsi
    jz      .false_ic

    mov     rax, [rdi + StrSlice.len]
    cmp     rax, [rsi + StrSlice.len]
    jne     .false_ic

    test    rax, rax
    jz      .true_ic

    push_regs rbx, r12, r13

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rsi + StrSlice.ptr]
    mov     r13, rax            ; length

.ic_loop:
    test    r13, r13
    jz      .ic_equal

    movzx   eax, byte [rbx]
    movzx   ecx, byte [r12]

    ; fold both to lowercase: if A-Z, or 0x20
    cmp     al, 'A'
    jb      .ic_no_fold_a
    cmp     al, 'Z'
    ja      .ic_no_fold_a
    or      al, 0x20
.ic_no_fold_a:
    cmp     cl, 'A'
    jb      .ic_no_fold_b
    cmp     cl, 'Z'
    ja      .ic_no_fold_b
    or      cl, 0x20
.ic_no_fold_b:

    cmp     al, cl
    jne     .ic_not_eq

    inc     rbx
    inc     r12
    dec     r13
    jmp     .ic_loop

.ic_equal:
    pop_regs r13, r12, rbx
.true_ic:
    mov     eax, STR_TRUE
    pop     rbp
    ret

.ic_not_eq:
    pop_regs r13, r12, rbx
.false_ic:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_eq_ignore_case

; -----------------------------------------------------------------------------
; str_cmp_ignore_case
;
; ASCII case-insensitive lexicographic ordering.
;
; Signature:
;   int64_t str_cmp_ignore_case(const StrSlice *a, const StrSlice *b)
;
; Returns:
;   RAX < 0  a < b  (case-insensitive)
;   RAX = 0  a == b (case-insensitive)
;   RAX > 0  a > b  (case-insensitive)
;   RAX = STR_ERR_NULL  null input
; -----------------------------------------------------------------------------

STR_FUNC str_cmp_ignore_case

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, [rsi + StrSlice.ptr]
    mov     r14, [rsi + StrSlice.len]

    mov     rcx, r12
    cmp     rcx, r14
    jbe     .got_min_ic
    mov     rcx, r14

.got_min_ic:
    xor     edx, edx

.cmpic_loop:
    test    rcx, rcx
    jz      .cmpic_by_len

    movzx   eax, byte [rbx + rdx]
    movzx   r8d, byte [r13 + rdx]

    ; fold to lowercase
    cmp     al, 'A'
    jb      .no_fold_a_ic
    cmp     al, 'Z'
    ja      .no_fold_a_ic
    or      al, 0x20
.no_fold_a_ic:
    cmp     r8b, 'A'
    jb      .no_fold_b_ic
    cmp     r8b, 'Z'
    ja      .no_fold_b_ic
    or      r8b, 0x20
.no_fold_b_ic:

    cmp     al, r8b
    jne     .cmpic_diff

    inc     rdx
    dec     rcx
    jmp     .cmpic_loop

.cmpic_diff:
    sub     eax, r8d
    movsx   rax, eax
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.cmpic_by_len:
    mov     rax, r12
    sub     rax, r14
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_cmp_ignore_case
