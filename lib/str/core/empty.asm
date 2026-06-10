; =============================================================================
; str/core/empty.asm
; Empty string constants, predicates, and zero-length operations.
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
; The canonical empty StrSlice has ptr pointing to a static null byte
; and len == 0. This means dereferencing ptr is always safe — you never
; get a null pointer dereference from an empty string.
;
; Convention:
;   empty  → ptr != null, len == 0
;   null   → ptr == null  (invalid / uninitialized)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata

; Canonical single null byte backing store for empty strings
_str_empty_backing: db 0

; Canonical empty StrSlice — read-only, always valid
; Other modules can extern this and use it directly
global str_empty_slice
str_empty_slice:
    dq  _str_empty_backing  ; .ptr
    dq  0                   ; .len

section .text

; -----------------------------------------------------------------------------
; str_empty
;
; Initialize a StrSlice as the canonical empty string.
; ptr points to _str_empty_backing (not null), len = 0.
;
; Signature:
;   int64_t str_empty(StrSlice *out)
;
; Arguments:
;   RDI  — pointer to StrSlice to initialize
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  out is null
; -----------------------------------------------------------------------------

STR_FUNC str_empty

    guard_null rdi, STR_ERR_NULL

    lea     rax, [rel _str_empty_backing]
    mov     [rdi + StrSlice.ptr], rax
    mov     qword [rdi + StrSlice.len], 0

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_empty

; -----------------------------------------------------------------------------
; str_is_empty
;
; Check if a StrSlice is empty (len == 0).
; A null slice is NOT considered empty — it is invalid.
;
; Signature:
;   int64_t str_is_empty(const StrSlice *slice)
;
; Arguments:
;   RDI  — pointer to StrSlice
;
; Returns:
;   RAX  = 1   slice is non-null AND len == 0
;   RAX  = 0   slice is null OR len > 0
; -----------------------------------------------------------------------------

STR_FUNC str_is_empty

    test    rdi, rdi
    jz      .false

    mov     rax, [rdi + StrSlice.len]
    test    rax, rax
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
; str_is_null
;
; Check if a StrSlice pointer is null (uninitialized/invalid).
;
; Signature:
;   int64_t str_is_null(const StrSlice *slice)
;
; Returns:
;   RAX  = 1  slice == null
;   RAX  = 0  slice != null
; -----------------------------------------------------------------------------

STR_FUNC str_is_null

    test    rdi, rdi
    setz    al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_is_null

; -----------------------------------------------------------------------------
; str_is_null_or_empty
;
; Check if a StrSlice is null OR empty.
; Most commonly used entry guard in core/.
;
; Signature:
;   int64_t str_is_null_or_empty(const StrSlice *slice)
;
; Returns:
;   RAX  = 1  slice == null OR slice->len == 0
;   RAX  = 0  slice is valid and non-empty
; -----------------------------------------------------------------------------

STR_FUNC str_is_null_or_empty

    test    rdi, rdi
    jz      .true

    mov     rax, [rdi + StrSlice.len]
    test    rax, rax
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
; str_empty_if_null
;
; If slice is null, initialize it as empty. Otherwise no-op.
; Useful for defensive init at function boundaries.
;
; Signature:
;   int64_t str_empty_if_null(StrSlice *slice)
; -----------------------------------------------------------------------------

STR_FUNC str_empty_if_null

    test    rdi, rdi
    jz      .null_self

    ; slice struct exists — check if ptr is null
    mov     rax, [rdi + StrSlice.ptr]
    test    rax, rax
    jnz     .already_ok

    ; ptr is null — set to empty backing
    lea     rax, [rel _str_empty_backing]
    mov     [rdi + StrSlice.ptr], rax
    mov     qword [rdi + StrSlice.len], 0

.already_ok:
    xor     eax, eax
    pop     rbp
    ret

.null_self:
    mov     rax, STR_ERR_NULL
    pop     rbp
    ret

STR_ENDFUNC str_empty_if_null

; -----------------------------------------------------------------------------
; str_or_empty
;
; Return the slice if non-null and non-empty, otherwise return
; a pointer to the canonical empty slice.
;
; Signature:
;   const StrSlice *str_or_empty(const StrSlice *slice)
;
; Arguments:
;   RDI  — pointer to StrSlice (may be null)
;
; Returns:
;   RAX  — RDI if valid and non-empty, else &str_empty_slice
; -----------------------------------------------------------------------------

STR_FUNC str_or_empty

    test    rdi, rdi
    jz      .give_empty

    mov     rax, [rdi + StrSlice.len]
    test    rax, rax
    jz      .give_empty

    mov     rax, rdi
    pop     rbp
    ret

.give_empty:
    lea     rax, [rel str_empty_slice]
    pop     rbp
    ret

STR_ENDFUNC str_or_empty
