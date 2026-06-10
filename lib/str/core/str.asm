; =============================================================================
; str/core/str.asm
; StrSlice constructor, init, and fundamental operations.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_null_or_empty.asm  (str_is_valid_slice)
;   utf8/validate.asm             (str_utf8_validate)
;
; -----------------------------------------------------------------------------
; StrSlice is a NON-OWNING view into a UTF-8 byte buffer.
; It never allocates or frees memory.
; Lifetime is always tied to the underlying buffer.
;
; For owning, growable strings use StrBuf (buf/strbuf.asm).
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_validate
extern str_is_valid_slice

section .rodata

; Empty string — single null byte, zero length
; Use str_empty() to get a StrSlice over this.
str_empty_bytes: db 0

section .text

; -----------------------------------------------------------------------------
; str_new
;
; Construct a StrSlice from a pointer and byte length.
; Does NOT validate UTF-8 — caller guarantees valid input.
;
; Signature:
;   int64_t str_new(StrSlice *out, const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to StrSlice to initialize
;   RSI  — pointer to UTF-8 byte buffer
;   RDX  — byte length
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  if out or ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_new

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     [rdi + StrSlice.ptr], rsi
    mov     [rdi + StrSlice.len], rdx

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_new

; -----------------------------------------------------------------------------
; str_new_validated
;
; Construct a StrSlice and validate the buffer is valid UTF-8.
;
; Signature:
;   int64_t str_new_validated(StrSlice *out, const uint8_t *ptr,
;                              uint64_t byte_len)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL         out or ptr is null
;   RAX  = STR_ERR_INVALID_UTF8 buffer is not valid UTF-8
; -----------------------------------------------------------------------------

STR_FUNC str_new_validated

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi            ; out
    mov     r12, rsi            ; ptr
    mov     r13, rdx            ; byte_len

    ; validate first
    mov     rdi, r12
    mov     rsi, r13
    call    str_utf8_validate
    test    rax, rax
    jnz     .err

    ; write slice
    mov     [rbx + StrSlice.ptr], r12
    mov     [rbx + StrSlice.len], r13

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.err:
    pop_regs r13, r12, rbx
    pop     rbp
    ret                         ; rax already has error code

STR_ENDFUNC str_new_validated

; -----------------------------------------------------------------------------
; str_from_cstr
;
; Construct a StrSlice from a null-terminated C string.
; Computes length by scanning for null byte.
; Does NOT validate UTF-8.
;
; Signature:
;   int64_t str_from_cstr(StrSlice *out, const char *cstr)
;
; Arguments:
;   RDI  — pointer to StrSlice
;   RSI  — pointer to null-terminated C string
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  out or cstr is null
; -----------------------------------------------------------------------------

STR_FUNC str_from_cstr

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi            ; out
    mov     r12, rsi            ; cstr base

    ; scan for null terminator
    mov     rdi, rsi
    xor     ecx, ecx            ; length counter

.scan:
    cmp     byte [rdi], 0
    je      .found_null
    inc     rdi
    inc     rcx
    jmp     .scan

.found_null:
    mov     [rbx + StrSlice.ptr], r12
    mov     [rbx + StrSlice.len], rcx

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_from_cstr

; -----------------------------------------------------------------------------
; str_from_cstr_validated
;
; Like str_from_cstr but also validates UTF-8.
;
; Signature:
;   int64_t str_from_cstr_validated(StrSlice *out, const char *cstr)
; -----------------------------------------------------------------------------

STR_FUNC str_from_cstr_validated

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi

    ; compute length
    mov     rdi, rsi
    xor     r13, r13

.scan_v:
    cmp     byte [rdi], 0
    je      .scanned
    inc     rdi
    inc     r13
    jmp     .scan_v

.scanned:
    ; validate
    mov     rdi, r12
    mov     rsi, r13
    call    str_utf8_validate
    test    rax, rax
    jnz     .err_v

    mov     [rbx + StrSlice.ptr], r12
    mov     [rbx + StrSlice.len], r13

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.err_v:
    pop_regs r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_from_cstr_validated

; -----------------------------------------------------------------------------
; str_to_cstr
;
; Copy a StrSlice into a caller-supplied buffer and null-terminate it.
; The buffer must have capacity >= slice.len + 1.
;
; Signature:
;   int64_t str_to_cstr(const StrSlice *slice, char *buf, uint64_t cap)
;
; Arguments:
;   RDI  — pointer to StrSlice
;   RSI  — output buffer
;   RDX  — buffer capacity (must be >= slice.len + 1)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          slice or buf is null
;   RAX  = STR_ERR_BUF_TOO_SMALL cap < slice.len + 1
; -----------------------------------------------------------------------------

STR_FUNC str_to_cstr

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap

    mov     rcx, [rbx + StrSlice.len]
    mov     rdi, [rbx + StrSlice.ptr]

    ; check capacity: need len + 1
    mov     rax, rcx
    inc     rax
    cmp     rax, r13
    ja      .too_small

    ; copy bytes
    mov     rsi, rdi
    mov     rdi, r12
    ; rcx already = len
    rep movsb

    ; null terminate
    mov     byte [rdi], 0

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.too_small:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_to_cstr

; -----------------------------------------------------------------------------
; str_ptr
;
; Get the pointer from a StrSlice.
;
; Signature:
;   const uint8_t *str_ptr(const StrSlice *slice)
;
; Returns:
;   RAX  — slice.ptr (may be null if slice is null)
; -----------------------------------------------------------------------------

STR_FUNC str_ptr

    test    rdi, rdi
    jz      .null

    mov     rax, [rdi + StrSlice.ptr]
    pop     rbp
    ret

.null:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ptr

; -----------------------------------------------------------------------------
; str_len
;
; Get the byte length of a StrSlice.
;
; Signature:
;   uint64_t str_len(const StrSlice *slice)
;
; Returns:
;   RAX  — slice.len (0 if slice is null)
; -----------------------------------------------------------------------------

STR_FUNC str_len

    test    rdi, rdi
    jz      .zero

    mov     rax, [rdi + StrSlice.len]
    pop     rbp
    ret

.zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_len

; -----------------------------------------------------------------------------
; str_reset
;
; Zero out a StrSlice (ptr=null, len=0). Does not free memory.
;
; Signature:
;   int64_t str_reset(StrSlice *slice)
; -----------------------------------------------------------------------------

STR_FUNC str_reset

    guard_null rdi, STR_ERR_NULL

    mov     qword [rdi + StrSlice.ptr], 0
    mov     qword [rdi + StrSlice.len], 0

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_reset

; -----------------------------------------------------------------------------
; str_assign
;
; Copy one StrSlice into another (shallow — shares the same buffer).
;
; Signature:
;   int64_t str_assign(StrSlice *dst, const StrSlice *src)
; -----------------------------------------------------------------------------

STR_FUNC str_assign

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rsi + StrSlice.ptr]
    mov     rcx, [rsi + StrSlice.len]
    mov     [rdi + StrSlice.ptr], rax
    mov     [rdi + StrSlice.len], rcx

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_assign
