; =============================================================================
; str/search/find.asm
; Find first and last occurrence of a substring in a StrSlice.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   search/bmh.asm  (str_bmh_build_table, str_bmh_search,
;                    str_bmh_search_from, str_bmh_build_table_nocase)
;
; -----------------------------------------------------------------------------
; Functions:
;   str_find            — first occurrence, returns byte offset
;   str_find_from       — first occurrence starting at offset
;   str_find_last       — last occurrence (reverse search)
;   str_find_byte       — find first occurrence of a single byte
;   str_find_byte_last  — find last occurrence of a single byte
;   str_find_nocase     — case-insensitive first occurrence
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_bmh_build_table
extern str_bmh_build_table_nocase
extern str_bmh_search
extern str_bmh_search_from

; Stack space for BMH shift table: 256 * 8 = 2048 bytes
BMH_TABLE_BYTES equ 2048

section .text

; -----------------------------------------------------------------------------
; str_find
;
; Find the first occurrence of needle in haystack.
;
; Signature:
;   int64_t str_find(const StrSlice *haystack, const StrSlice *needle)
;
; Arguments:
;   RDI  — haystack StrSlice
;   RSI  — needle StrSlice
;
; Returns:
;   RAX >= 0   byte offset of first match
;   RAX  = STR_ERR_NOT_FOUND   not found
;   RAX  = STR_ERR_NULL        null pointer
;   RAX  = STR_ERR_INVALID_ARG needle is empty
; -----------------------------------------------------------------------------

STR_FUNC str_find

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; haystack
    mov     r12, rsi            ; needle

    mov     r13, [rbx + StrSlice.len]   ; haystack.len
    mov     r14, [r12 + StrSlice.len]   ; needle.len

    ; empty needle → always found at 0
    test    r14, r14
    jz      .find_zero

    ; needle longer than haystack → not found
    cmp     r14, r13
    ja      .not_found_f

    ; single byte needle → fast linear scan
    cmp     r14, 1
    je      .single_byte_f

    ; allocate shift table on stack
    sub     rsp, BMH_TABLE_BYTES
    and     rsp, -16

    ; build table
    mov     rdi, [r12 + StrSlice.ptr]
    mov     rsi, r14
    mov     rdx, rsp
    call    str_bmh_build_table
    test    rax, rax
    jnz     .find_err

    ; search
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r13
    mov     rdx, [r12 + StrSlice.ptr]
    mov     rcx, r14
    mov     r8,  rsp
    call    str_bmh_search

    mov     rsp, rbp
    sub     rsp, 0

    pop_regs r15, r14, r13, r12, rbx
    ; rax = offset or STR_ERR_NOT_FOUND
    pop     rbp
    ret

.single_byte_f:
    mov     r15, [r12 + StrSlice.ptr]
    movzx   ecx, byte [r15]     ; needle byte
    mov     r15, [rbx + StrSlice.ptr]
    xor     r9, r9

.sf_loop:
    cmp     r9, r13
    jae     .not_found_pop_f

    movzx   eax, byte [r15 + r9]
    cmp     al, cl
    je      .sf_found

    inc     r9
    jmp     .sf_loop

.sf_found:
    mov     rax, r9
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.find_zero:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.find_err:
    mov     rsp, rbp
    sub     rsp, 0
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.not_found_pop_f:
    pop_regs r15, r14, r13, r12, rbx
.not_found_f:
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_find

; -----------------------------------------------------------------------------
; str_find_from
;
; Find first occurrence of needle starting at byte offset `from`.
;
; Signature:
;   int64_t str_find_from(const StrSlice *haystack, const StrSlice *needle,
;                          uint64_t from)
;
; Arguments:
;   RDI  — haystack
;   RSI  — needle
;   RDX  — from (byte offset)
;
; Returns:
;   RAX >= 0   absolute byte offset of match
;   RAX  = STR_ERR_NOT_FOUND
; -----------------------------------------------------------------------------

STR_FUNC str_find_from

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx            ; from

    mov     r14, [rbx + StrSlice.len]
    mov     r15, [r12 + StrSlice.len]

    ; from >= haystack.len → not found
    cmp     r13, r14
    jae     .ff_not_found

    test    r15, r15
    jz      .ff_zero

    cmp     r15, 1
    je      .ff_single_byte

    sub     rsp, BMH_TABLE_BYTES
    and     rsp, -16

    mov     rdi, [r12 + StrSlice.ptr]
    mov     rsi, r15
    mov     rdx, rsp
    call    str_bmh_build_table
    test    rax, rax
    jnz     .ff_err

    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r14
    mov     rdx, [r12 + StrSlice.ptr]
    mov     rcx, r15
    mov     r8,  rsp
    mov     r9,  r13
    call    str_bmh_search_from

    mov     rsp, rbp
    sub     rsp, 0

    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.ff_single_byte:
    mov     rdi, [r12 + StrSlice.ptr]
    movzx   ecx, byte [rdi]
    mov     rdi, [rbx + StrSlice.ptr]
    mov     r9, r13

.ff_sb_loop:
    cmp     r9, r14
    jae     .ff_not_found_pop

    movzx   eax, byte [rdi + r9]
    cmp     al, cl
    je      .ff_sb_found

    inc     r9
    jmp     .ff_sb_loop

.ff_sb_found:
    mov     rax, r9
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.ff_zero:
    mov     rax, r13
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.ff_err:
    mov     rsp, rbp
    sub     rsp, 0
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.ff_not_found_pop:
    pop_regs r15, r14, r13, r12, rbx
.ff_not_found:
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_find_from

; -----------------------------------------------------------------------------
; str_find_last
;
; Find the LAST occurrence of needle in haystack.
; Scans backward from end.
;
; Signature:
;   int64_t str_find_last(const StrSlice *haystack, const StrSlice *needle)
;
; Returns:
;   RAX >= 0   byte offset of last match
;   RAX  = STR_ERR_NOT_FOUND
; -----------------------------------------------------------------------------

STR_FUNC str_find_last

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi

    mov     r13, [rbx + StrSlice.len]
    mov     r14, [r12 + StrSlice.len]

    test    r14, r14
    jz      .fl_zero

    cmp     r14, r13
    ja      .fl_not_found

    mov     r15, [rbx + StrSlice.ptr]   ; haystack ptr
    mov     r9,  [r12 + StrSlice.ptr]   ; needle ptr

    ; start scanning from last possible position
    mov     r10, r13
    sub     r10, r14            ; last valid start = haystack.len - needle.len
    ; r10 = scan index (moves left)

.fl_loop:
    ; compare needle at position r10
    xor     r11, r11            ; j = 0

.fl_inner:
    cmp     r11, r14
    jae     .fl_match

    movzx   eax, byte [r15 + r10 + r11]
    cmp     al, byte [r9 + r11]
    jne     .fl_no_match

    inc     r11
    jmp     .fl_inner

.fl_match:
    mov     rax, r10
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.fl_no_match:
    test    r10, r10
    jz      .fl_not_found_pop

    dec     r10
    jmp     .fl_loop

.fl_zero:
    ; empty needle → last position = haystack.len
    mov     rax, r13
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.fl_not_found_pop:
    pop_regs r15, r14, r13, r12, rbx
.fl_not_found:
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_find_last

; -----------------------------------------------------------------------------
; str_find_byte
;
; Find first occurrence of a single byte in a StrSlice.
;
; Signature:
;   int64_t str_find_byte(const StrSlice *haystack, uint8_t byte_val)
;
; Returns:
;   RAX >= 0   byte offset
;   RAX  = STR_ERR_NOT_FOUND
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_find_byte

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    movzx   ecx, sil            ; byte_val
    xor     r9, r9

.fb_loop:
    cmp     r9, r12
    jae     .fb_not_found

    movzx   eax, byte [rbx + r9]
    cmp     al, cl
    je      .fb_found

    inc     r9
    jmp     .fb_loop

.fb_found:
    mov     rax, r9
    pop_regs r12, rbx
    pop     rbp
    ret

.fb_not_found:
    pop_regs r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_find_byte

; -----------------------------------------------------------------------------
; str_find_byte_last
;
; Find last occurrence of a single byte.
;
; Signature:
;   int64_t str_find_byte_last(const StrSlice *haystack, uint8_t byte_val)
; -----------------------------------------------------------------------------

STR_FUNC str_find_byte_last

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    movzx   ecx, sil

    test    r12, r12
    jz      .fbl_not_found

    mov     r9, r12
    dec     r9

.fbl_loop:
    movzx   eax, byte [rbx + r9]
    cmp     al, cl
    je      .fbl_found

    test    r9, r9
    jz      .fbl_not_found

    dec     r9
    jmp     .fbl_loop

.fbl_found:
    mov     rax, r9
    pop_regs r12, rbx
    pop     rbp
    ret

.fbl_not_found:
    pop_regs r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_find_byte_last

; -----------------------------------------------------------------------------
; str_find_nocase
;
; Case-insensitive find (ASCII fold only).
;
; Signature:
;   int64_t str_find_nocase(const StrSlice *haystack, const StrSlice *needle)
; -----------------------------------------------------------------------------

STR_FUNC str_find_nocase

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi

    mov     r13, [rbx + StrSlice.len]
    mov     r14, [r12 + StrSlice.len]

    test    r14, r14
    jz      .fnc_zero

    cmp     r14, r13
    ja      .fnc_not_found

    sub     rsp, BMH_TABLE_BYTES
    and     rsp, -16

    ; build nocase table
    mov     rdi, [r12 + StrSlice.ptr]
    mov     rsi, r14
    mov     rdx, rsp
    call    str_bmh_build_table_nocase
    test    rax, rax
    jnz     .fnc_err

    ; manual nocase search (BMH table alone isn't enough — need nocase compare)
    mov     r15, [rbx + StrSlice.ptr]
    mov     r9,  [r12 + StrSlice.ptr]

    ; last valid window start
    mov     r10, r13
    sub     r10, r14
    xor     r11, r11            ; pos = 0

.fnc_outer:
    cmp     r11, r10
    ja      .fnc_not_found_stack

    ; compare r14 bytes case-insensitively
    xor     ecx, ecx

.fnc_inner:
    cmp     rcx, r14
    jae     .fnc_match

    movzx   eax, byte [r15 + r11 + rcx]
    movzx   edx, byte [r9  + rcx]

    ; fold both to lowercase
    cmp     al, 'A'
    jb      .fnc_no_fold_a
    cmp     al, 'Z'
    ja      .fnc_no_fold_a
    or      al, 0x20
.fnc_no_fold_a:
    cmp     dl, 'A'
    jb      .fnc_no_fold_b
    cmp     dl, 'Z'
    ja      .fnc_no_fold_b
    or      dl, 0x20
.fnc_no_fold_b:

    cmp     al, dl
    jne     .fnc_shift

    inc     rcx
    jmp     .fnc_inner

.fnc_match:
    mov     rax, r11
    mov     rsp, rbp
    sub     rsp, 0
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.fnc_shift:
    movzx   eax, byte [r15 + r11 + r14 - 1]
    ; fold for table lookup
    cmp     al, 'A'
    jb      .fnc_no_fold_shift
    cmp     al, 'Z'
    ja      .fnc_no_fold_shift
    or      al, 0x20
.fnc_no_fold_shift:
    mov     rax, [rsp + rax * 8]
    add     r11, rax
    jmp     .fnc_outer

.fnc_zero:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.fnc_err:
.fnc_not_found_stack:
    mov     rsp, rbp
    sub     rsp, 0
    pop_regs r15, r14, r13, r12, rbx
.fnc_not_found:
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_find_nocase