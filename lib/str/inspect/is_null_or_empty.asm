; =============================================================================
; str/inspect/is_null_or_empty.asm
; Null pointer and empty string guard predicates.
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
; These are the most-called predicates in the entire library.
; Every core/ function calls one of these at entry.
;
; Definitions:
;   null        — ptr == 0
;   empty       — ptr != null AND byte_len == 0
;   null_or_empty — ptr == null OR byte_len == 0
;   blank       — null, empty, or all-whitespace (see is_space.asm)
;
; All functions are branchless or near-branchless for speed.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_is_null
;
; Check if a pointer is null.
;
; Signature:
;   int64_t str_is_null(const void *ptr)
;
; Arguments:
;   RDI  — pointer
;
; Returns:
;   RAX  = 1  ptr == null
;   RAX  = 0  ptr != null
; -----------------------------------------------------------------------------

STR_FUNC str_is_null

    test    rdi, rdi
    setz    al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_is_null

; -----------------------------------------------------------------------------
; str_is_empty
;
; Check if a UTF-8 buffer is empty (non-null ptr, zero byte length).
;
; Signature:
;   int64_t str_is_empty(const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer (may be null — returns 0 if null, not 1)
;   RSI  — byte length
;
; Returns:
;   RAX  = 1  ptr != null AND byte_len == 0
;   RAX  = 0  ptr == null OR byte_len > 0
; -----------------------------------------------------------------------------

STR_FUNC str_is_empty

    ; null ptr → not empty (it's null, different thing)
    test    rdi, rdi
    jz      .false

    test    rsi, rsi
    setz    al
    movzx   eax, al

    pop     rbp
    ret

.false:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_is_empty

; -----------------------------------------------------------------------------
; str_is_null_or_empty
;
; Check if a buffer is null OR empty. The most common entry guard.
;
; Signature:
;   int64_t str_is_null_or_empty(const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer
;   RSI  — byte length
;
; Returns:
;   RAX  = 1  ptr == null OR byte_len == 0
;   RAX  = 0  ptr != null AND byte_len > 0
; -----------------------------------------------------------------------------

STR_FUNC str_is_null_or_empty

    ; null → true
    test    rdi, rdi
    jz      .true

    ; zero length → true
    test    rsi, rsi
    jz      .true

    xor     eax, eax
    pop     rbp
    ret

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_null_or_empty

; -----------------------------------------------------------------------------
; str_is_null_or_empty_slice
;
; Check a StrSlice for null or empty.
;
; Signature:
;   int64_t str_is_null_or_empty_slice(const StrSlice *slice)
;
; Arguments:
;   RDI  — pointer to StrSlice (may itself be null)
;
; Returns:
;   RAX  = 1  slice is null, OR slice.ptr is null, OR slice.len == 0
;   RAX  = 0  slice is valid and non-empty
; -----------------------------------------------------------------------------

STR_FUNC str_is_null_or_empty_slice

    ; slice ptr itself null
    test    rdi, rdi
    jz      .true

    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]

    pop     rbp
    jmp     str_is_null_or_empty

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

STR_ENDFUNC str_is_null_or_empty_slice

; -----------------------------------------------------------------------------
; str_is_valid_slice
;
; Check that a StrSlice is fully valid:
;   - slice ptr is not null
;   - slice.ptr is not null
;   - slice.len > 0
;   - slice.ptr + slice.len does not overflow (no wrap-around)
;
; Signature:
;   int64_t str_is_valid_slice(const StrSlice *slice)
;
; Returns:
;   RAX  = 1  slice is valid and non-empty
;   RAX  = 0  any condition fails
; -----------------------------------------------------------------------------

STR_FUNC str_is_valid_slice

    ; null slice struct
    test    rdi, rdi
    jz      .false

    mov     rsi, [rdi + StrSlice.len]
    mov     rax, [rdi + StrSlice.ptr]

    ; null ptr
    test    rax, rax
    jz      .false

    ; zero length
    test    rsi, rsi
    jz      .false

    ; overflow check: ptr + len must not wrap
    add     rax, rsi
    jc      .false              ; carry → overflow

    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_is_valid_slice

; -----------------------------------------------------------------------------
; str_is_valid_buf
;
; Check that ptr + byte_len is a valid non-wrapping range.
;
; Signature:
;   int64_t str_is_valid_buf(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  non-null, non-empty, no overflow
;   RAX  = 0  null, zero-length, or ptr+len wraps
; -----------------------------------------------------------------------------

STR_FUNC str_is_valid_buf

    test    rdi, rdi
    jz      .false

    test    rsi, rsi
    jz      .false

    ; overflow check
    mov     rax, rdi
    add     rax, rsi
    jc      .false

    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_is_valid_buf

; -----------------------------------------------------------------------------
; str_ptr_in_range
;
; Check that a pointer falls within [base, base+len).
; Used to validate that a slice or iterator position is still in bounds.
;
; Signature:
;   int64_t str_ptr_in_range(const uint8_t *ptr,
;                             const uint8_t *base,
;                             uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to check
;   RSI  — base pointer
;   RDX  — byte length of range
;
; Returns:
;   RAX  = 1  base <= ptr < base + len
;   RAX  = 0  out of range
; -----------------------------------------------------------------------------

STR_FUNC str_ptr_in_range

    ; ptr >= base?
    cmp     rdi, rsi
    jb      .false

    ; ptr < base + len?
    mov     rax, rsi
    add     rax, rdx
    cmp     rdi, rax
    jae     .false

    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ptr_in_range