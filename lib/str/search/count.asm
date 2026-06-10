; =============================================================================
; str/search/count.asm
; Count occurrences of a substring, byte, or codepoint in a StrSlice.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   search/bmh.asm  (str_bmh_build_table, str_bmh_search_from)
;
; -----------------------------------------------------------------------------
; Functions:
;   str_count         — count non-overlapping occurrences of needle
;   str_count_overlap — count overlapping occurrences
;   str_count_byte    — count occurrences of a single byte (fast)
;   str_count_nocase  — case-insensitive count
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_bmh_build_table
extern str_bmh_search_from
extern str_bmh_build_table_nocase

BMH_TABLE_BYTES equ 2048

section .text

; -----------------------------------------------------------------------------
; str_count
;
; Count non-overlapping occurrences of needle in haystack.
;
; Signature:
;   int64_t str_count(const StrSlice *haystack, const StrSlice *needle)
;
; Returns:
;   RAX >= 0   occurrence count (0 if not found)
;   RAX  = STR_ERR_NULL        null pointer
;   RAX  = STR_ERR_INVALID_ARG needle is empty
; -----------------------------------------------------------------------------

STR_FUNC str_count

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi

    mov     r13, [rbx + StrSlice.len]   ; haystack.len
    mov     r14, [r12 + StrSlice.len]   ; needle.len

    test    r14, r14
    jz      .err_empty_needle

    ; needle longer than haystack → 0
    cmp     r14, r13
    ja      .count_zero

    ; single byte needle → fast linear scan
    cmp     r14, 1
    je      .count_single_byte

    ; build BMH table
    sub     rsp, BMH_TABLE_BYTES
    and     rsp, -16

    mov     rdi, [r12 + StrSlice.ptr]
    mov     rsi, r14
    mov     rdx, rsp
    call    str_bmh_build_table
    test    rax, rax
    jnz     .count_err

    xor     r15, r15            ; count = 0
    xor     r9,  r9             ; pos = 0

.count_loop:
    ; search from current pos
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r13
    mov     rdx, [r12 + StrSlice.ptr]
    mov     rcx, r14
    mov     r8,  rsp
    call    str_bmh_search_from
    ; r9 passed as 6th arg — but str_bmh_search_from takes it as arg

    ; re-call with from parameter properly
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r13
    mov     rdx, [r12 + StrSlice.ptr]
    mov     rcx, r14
    mov     r8,  rsp
    ; r9 already set as from
    call    str_bmh_search_from

    test    rax, rax
    js      .count_done         ; not found

    inc     r15
    mov     r9, rax
    add     r9, r14             ; advance past match (non-overlapping)
    jmp     .count_loop

.count_done:
    mov     rax, r15
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.count_single_byte:
    movzx   ecx, byte [r12 + StrSlice.ptr]
    ; actually load the byte from the slice ptr
    mov     r9, [r12 + StrSlice.ptr]
    movzx   ecx, byte [r9]

    mov     r9, [rbx + StrSlice.ptr]
    xor     r15, r15
    xor     r10, r10

.csb_loop:
    cmp     r10, r13
    jae     .csb_done

    movzx   eax, byte [r9 + r10]
    cmp     al, cl
    jne     .csb_next
    inc     r15

.csb_next:
    inc     r10
    jmp     .csb_loop

.csb_done:
    mov     rax, r15
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.count_zero:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.count_err:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.err_empty_needle:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_count

; -----------------------------------------------------------------------------
; str_count_byte
;
; Count occurrences of a single byte in a StrSlice. Fast path.
;
; Signature:
;   int64_t str_count_byte(const StrSlice *haystack, uint8_t byte_val)
;
; Returns:
;   RAX >= 0  count
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_count_byte

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    movzx   ecx, sil            ; byte to count

    xor     r9, r9              ; count
    xor     r10, r10            ; index

.cb_loop:
    cmp     r10, r12
    jae     .cb_done

    movzx   eax, byte [rbx + r10]
    cmp     al, cl
    jne     .cb_next
    inc     r9

.cb_next:
    inc     r10
    jmp     .cb_loop

.cb_done:
    mov     rax, r9
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_count_byte

; -----------------------------------------------------------------------------
; str_count_overlap
;
; Count overlapping occurrences of needle in haystack.
; e.g. "aa" in "aaa" → 2 (positions 0 and 1)
;
; Signature:
;   int64_t str_count_overlap(const StrSlice *haystack,
;                              const StrSlice *needle)
; -----------------------------------------------------------------------------

STR_FUNC str_count_overlap

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi

    mov     r13, [rbx + StrSlice.len]
    mov     r14, [r12 + StrSlice.len]

    test    r14, r14
    jz      .ov_err_empty

    cmp     r14, r13
    ja      .ov_zero

    sub     rsp, BMH_TABLE_BYTES
    and     rsp, -16

    mov     rdi, [r12 + StrSlice.ptr]
    mov     rsi, r14
    mov     rdx, rsp
    call    str_bmh_build_table
    test    rax, rax
    jnz     .ov_err

    xor     r15, r15            ; count
    xor     r9, r9              ; pos

.ov_loop:
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r13
    mov     rdx, [r12 + StrSlice.ptr]
    mov     rcx, r14
    mov     r8,  rsp
    call    str_bmh_search_from

    test    rax, rax
    js      .ov_done

    inc     r15
    mov     r9, rax
    inc     r9                  ; advance by 1 (overlapping)
    jmp     .ov_loop

.ov_done:
    mov     rax, r15
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.ov_zero:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ov_err:
    mov     rsp, rbp
.ov_err_empty:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_count_overlap

; -----------------------------------------------------------------------------
; str_count_nocase
;
; Case-insensitive count (ASCII fold).
;
; Signature:
;   int64_t str_count_nocase(const StrSlice *haystack,
;                             const StrSlice *needle)
; -----------------------------------------------------------------------------

STR_FUNC str_count_nocase

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi

    mov     r13, [rbx + StrSlice.len]
    mov     r14, [r12 + StrSlice.len]

    test    r14, r14
    jz      .cnc_err

    cmp     r14, r13
    ja      .cnc_zero

    sub     rsp, BMH_TABLE_BYTES
    and     rsp, -16

    mov     rdi, [r12 + StrSlice.ptr]
    mov     rsi, r14
    mov     rdx, rsp
    call    str_bmh_build_table_nocase
    test    rax, rax
    jnz     .cnc_err2

    xor     r15, r15            ; count
    xor     r9, r9              ; pos

    mov     r10, [rbx + StrSlice.ptr]   ; haystack ptr
    mov     r11, [r12 + StrSlice.ptr]   ; needle ptr

.cnc_outer:
    ; check if enough room remains
    mov     rax, r13
    sub     rax, r9
    cmp     rax, r14
    jb      .cnc_done

    ; compare r14 bytes at r10+r9 vs r11
    xor     ecx, ecx

.cnc_inner:
    cmp     rcx, r14
    jae     .cnc_match

    movzx   eax, byte [r10 + r9 + rcx]
    movzx   edx, byte [r11 + rcx]

    cmp     al, 'A'
    jb      .cnc_nf_a
    cmp     al, 'Z'
    ja      .cnc_nf_a
    or      al, 0x20
.cnc_nf_a:
    cmp     dl, 'A'
    jb      .cnc_nf_b
    cmp     dl, 'Z'
    ja      .cnc_nf_b
    or      dl, 0x20
.cnc_nf_b:

    cmp     al, dl
    jne     .cnc_shift

    inc     rcx
    jmp     .cnc_inner

.cnc_match:
    inc     r15
    add     r9, r14             ; non-overlapping advance
    jmp     .cnc_outer

.cnc_shift:
    ; shift by table[haystack[pos + pat_len - 1]] (nocase)
    movzx   eax, byte [r10 + r9 + r14 - 1]
    cmp     al, 'A'
    jb      .cnc_no_fold_s
    cmp     al, 'Z'
    ja      .cnc_no_fold_s
    or      al, 0x20
.cnc_no_fold_s:
    mov     rax, [rsp + rax * 8]
    add     r9, rax
    jmp     .cnc_outer

.cnc_done:
    mov     rax, r15
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.cnc_zero:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.cnc_err2:
    mov     rsp, rbp
.cnc_err:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_count_nocase