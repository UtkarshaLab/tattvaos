; =============================================================================
; str/search/ends.asm
; Check if a StrSlice ends with a given suffix.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/cmp.asm  (str_eq_bytes)
;
; -----------------------------------------------------------------------------
; Functions:
;   str_ends_with         — exact suffix match
;   str_ends_with_nocase  — case-insensitive suffix match
;   str_ends_with_byte    — single byte suffix
;   str_strip_suffix      — if suffix matches, return slice without it
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_eq_bytes

section .text

; -----------------------------------------------------------------------------
; str_ends_with
;
; Check if haystack ends with suffix.
;
; Signature:
;   int64_t str_ends_with(const StrSlice *haystack, const StrSlice *suffix)
;
; Returns:
;   RAX  = 1  ends with suffix
;   RAX  = 0  does not end with suffix (or null)
; -----------------------------------------------------------------------------

STR_FUNC str_ends_with

    test    rdi, rdi
    jz      .false_ew
    test    rsi, rsi
    jz      .false_ew

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    mov     r8,  [r12 + StrSlice.len]   ; suffix.len

    ; empty suffix → always true
    test    r8, r8
    jz      .true_ew

    mov     r9, [rbx + StrSlice.len]    ; haystack.len

    ; suffix longer than haystack → false
    cmp     r8, r9
    ja      .false_ew_pop

    ; compare last suffix.len bytes of haystack
    ; haystack tail starts at: haystack.ptr + (haystack.len - suffix.len)
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rax, r9
    sub     rax, r8             ; offset = haystack.len - suffix.len
    add     rdi, rax            ; rdi = haystack.ptr + offset

    mov     rsi, r8             ; a_len = suffix.len
    mov     rdx, [r12 + StrSlice.ptr]
    mov     rcx, r8             ; b_len = suffix.len
    call    str_eq_bytes

    pop_regs r12, rbx
    pop     rbp
    ret

.true_ew:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false_ew_pop:
    pop_regs r12, rbx
.false_ew:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ends_with

; -----------------------------------------------------------------------------
; str_ends_with_byte
;
; Check if haystack ends with a specific byte.
;
; Signature:
;   int64_t str_ends_with_byte(const StrSlice *haystack, uint8_t byte_val)
; -----------------------------------------------------------------------------

STR_FUNC str_ends_with_byte

    test    rdi, rdi
    jz      .false_ewb

    mov     rax, [rdi + StrSlice.len]
    test    rax, rax
    jz      .false_ewb

    mov     rcx, [rdi + StrSlice.ptr]
    dec     rax
    movzx   eax, byte [rcx + rax]   ; last byte
    cmp     al, sil
    sete    al
    movzx   eax, al

    pop     rbp
    ret

.false_ewb:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ends_with_byte

; -----------------------------------------------------------------------------
; str_ends_with_nocase
;
; Case-insensitive suffix check (ASCII fold).
;
; Signature:
;   int64_t str_ends_with_nocase(const StrSlice *haystack,
;                                 const StrSlice *suffix)
; -----------------------------------------------------------------------------

STR_FUNC str_ends_with_nocase

    test    rdi, rdi
    jz      .false_enc
    test    rsi, rsi
    jz      .false_enc

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi

    mov     r13, [r12 + StrSlice.len]

    test    r13, r13
    jz      .true_enc

    mov     r9, [rbx + StrSlice.len]
    cmp     r13, r9
    ja      .false_enc_pop

    ; tail pointer
    mov     r8, [rbx + StrSlice.ptr]
    mov     rax, r9
    sub     rax, r13
    add     r8, rax             ; r8 = haystack tail

    mov     r9, [r12 + StrSlice.ptr]   ; suffix ptr
    xor     ecx, ecx

.enc_loop:
    cmp     rcx, r13
    jae     .true_enc

    movzx   eax, byte [r8 + rcx]
    movzx   edx, byte [r9 + rcx]

    cmp     al, 'A'
    jb      .enc_no_fold_a
    cmp     al, 'Z'
    ja      .enc_no_fold_a
    or      al, 0x20
.enc_no_fold_a:
    cmp     dl, 'A'
    jb      .enc_no_fold_b
    cmp     dl, 'Z'
    ja      .enc_no_fold_b
    or      dl, 0x20
.enc_no_fold_b:

    cmp     al, dl
    jne     .false_enc_pop

    inc     rcx
    jmp     .enc_loop

.true_enc:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false_enc_pop:
    pop_regs r13, r12, rbx
.false_enc:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ends_with_nocase

; -----------------------------------------------------------------------------
; str_strip_suffix
;
; If haystack ends with suffix, return the slice before it.
;
; Signature:
;   int64_t str_strip_suffix(const StrSlice *haystack,
;                             const StrSlice *suffix,
;                             StrSlice *out)
;
; Returns:
;   RAX  = STR_OK             suffix stripped, result in *out
;   RAX  = STR_ERR_NOT_FOUND  does not end with suffix
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_strip_suffix

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    call    str_ends_with
    test    eax, eax
    jz      .ss_not_found

    ; out.ptr = haystack.ptr
    ; out.len = haystack.len - suffix.len
    mov     rax, [rbx + StrSlice.ptr]
    mov     [r13 + StrSlice.ptr], rax

    mov     rax, [rbx + StrSlice.len]
    sub     rax, [r12 + StrSlice.len]
    mov     [r13 + StrSlice.len], rax

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ss_not_found:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_strip_suffix