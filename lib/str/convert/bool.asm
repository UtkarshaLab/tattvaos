; =============================================================================
; str/convert/bool.asm
; Boolean ↔ string conversions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/cmp.asm  (str_eq_ignore_case)
;
; -----------------------------------------------------------------------------
; Accepted truthy strings:  "true", "yes", "1", "on", "t", "y"
; Accepted falsy strings:   "false", "no", "0", "off", "f", "n"
; All comparisons are case-insensitive.
;
; Functions:
;   str_parse_bool    — StrSlice → bool (1 or 0)
;   str_bool_to_str   — bool → "true" or "false" StrSlice
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_eq_ignore_case

section .rodata

; Static string literals for bool output
_str_true:  db "true",  0
_str_false: db "false", 0

; Static StrSlice structs
global str_bool_true_slice
global str_bool_false_slice

str_bool_true_slice:
    dq  _str_true
    dq  4

str_bool_false_slice:
    dq  _str_false
    dq  5

; Truthy/falsy string table
; Format: length, bytes (max 5 chars), value (0=false, 1=true)
_bool_table:
    db  4, 't', 'r', 'u', 'e',  0, 1   ; "true"  → 1
    db  5, 'f', 'a', 'l', 's', 'e', 0  ; "false" → 0
    db  3, 'y', 'e', 's', 0, 0, 0, 1   ; "yes"   → 1
    db  2, 'n', 'o',  0, 0, 0, 0, 0    ; "no"    → 0
    db  1, '1',  0, 0, 0, 0, 0, 1      ; "1"     → 1
    db  1, '0',  0, 0, 0, 0, 0, 0      ; "0"     → 0
    db  2, 'o', 'n', 0, 0, 0, 0, 1     ; "on"    → 1
    db  3, 'o', 'f', 'f', 0, 0, 0, 0   ; "off"   → 0
    db  1, 't',  0, 0, 0, 0, 0, 1      ; "t"     → 1
    db  1, 'f',  0, 0, 0, 0, 0, 0      ; "f"     → 0
    db  1, 'y',  0, 0, 0, 0, 0, 1      ; "y"     → 1
    db  1, 'n',  0, 0, 0, 0, 0, 0      ; "n"     → 0
    db  0                               ; terminator

section .text

; -----------------------------------------------------------------------------
; str_parse_bool
;
; Parse a StrSlice into a boolean value (1 or 0).
;
; Signature:
;   int64_t str_parse_bool(const StrSlice *src, int64_t *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — pointer to int64_t to receive 0 or 1
;
; Returns:
;   RAX  = STR_OK               value written to *out
;   RAX  = STR_ERR_NULL         src or out is null
;   RAX  = STR_ERR_PARSE        string not recognized as boolean
; -----------------------------------------------------------------------------

STR_FUNC str_parse_bool

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; out

    mov     r13, [rbx + StrSlice.len]   ; src.len
    mov     r14, [rbx + StrSlice.ptr]   ; src.ptr

    ; scan the bool table
    lea     r15, [rel _bool_table]

.bool_scan:
    movzx   eax, byte [r15]     ; entry length
    test    al, al
    jz      .bool_not_found     ; end of table

    ; compare src.len with entry length
    cmp     r13, rax
    jne     .bool_next_entry

    ; compare bytes case-insensitively
    ; entry bytes start at r15 + 1
    ; entry value is at r15 + 6

    xor     ecx, ecx

.bool_cmp_loop:
    cmp     rcx, r13
    jae     .bool_match

    movzx   edx, byte [r14 + rcx]   ; src byte
    movzx   r8d, byte [r15 + 1 + rcx] ; table byte

    ; fold both to lowercase
    cmp     dl, 'A'
    jb      .bool_no_fold_s
    cmp     dl, 'Z'
    ja      .bool_no_fold_s
    or      dl, 0x20
.bool_no_fold_s:
    cmp     r8b, 'A'
    jb      .bool_no_fold_t
    cmp     r8b, 'Z'
    ja      .bool_no_fold_t
    or      r8b, 0x20
.bool_no_fold_t:

    cmp     dl, r8b
    jne     .bool_next_entry

    inc     ecx
    jmp     .bool_cmp_loop

.bool_match:
    ; read value byte at offset 6
    movzx   eax, byte [r15 + 6]
    mov     [r12], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.bool_next_entry:
    add     r15, 7              ; each entry is 7 bytes
    jmp     .bool_scan

.bool_not_found:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

STR_ENDFUNC str_parse_bool

; -----------------------------------------------------------------------------
; str_bool_to_str
;
; Convert a boolean to a StrSlice pointing to "true" or "false".
; Returns a pointer to a static read-only StrSlice.
;
; Signature:
;   const StrSlice *str_bool_to_str(int64_t value)
;
; Arguments:
;   RDI  — boolean value (0 = false, non-zero = true)
;
; Returns:
;   RAX  — pointer to static str_bool_true_slice or str_bool_false_slice
; -----------------------------------------------------------------------------

STR_FUNC str_bool_to_str

    test    rdi, rdi
    jz      .b2s_false

    lea     rax, [rel str_bool_true_slice]
    pop     rbp
    ret

.b2s_false:
    lea     rax, [rel str_bool_false_slice]
    pop     rbp
    ret

STR_ENDFUNC str_bool_to_str

; -----------------------------------------------------------------------------
; str_bool_to_cstr
;
; Like str_bool_to_str but returns a null-terminated C string pointer.
;
; Signature:
;   const char *str_bool_to_cstr(int64_t value)
; -----------------------------------------------------------------------------

STR_FUNC str_bool_to_cstr

    test    rdi, rdi
    jz      .bc_false

    lea     rax, [rel _str_true]
    pop     rbp
    ret

.bc_false:
    lea     rax, [rel _str_false]
    pop     rbp
    ret

STR_ENDFUNC str_bool_to_cstr

; -----------------------------------------------------------------------------
; str_is_truthy
;
; Quickly check if a StrSlice represents a truthy value.
;
; Signature:
;   int64_t str_is_truthy(const StrSlice *src)
;
; Returns:
;   RAX  = 1   truthy
;   RAX  = 0   falsy or unrecognized
; -----------------------------------------------------------------------------

STR_FUNC str_is_truthy

    test    rdi, rdi
    jz      .it_false

    sub     rsp, 8
    and     rsp, -16

    mov     rsi, rsp            ; out
    call    str_parse_bool

    test    rax, rax
    jnz     .it_err             ; parse error → falsy

    mov     rax, [rsp]          ; value

    mov     rsp, rbp
    pop     rbp
    ret

.it_err:
    mov     rsp, rbp
.it_false:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_is_truthy
