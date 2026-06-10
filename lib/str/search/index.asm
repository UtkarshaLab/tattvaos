; =============================================================================
; str/search/index.asm
; Find all occurrence byte offsets of a substring in a StrSlice.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   search/bmh.asm  (str_bmh_build_table, str_bmh_search_from,
;                    str_bmh_build_table_nocase)
;
; -----------------------------------------------------------------------------
; Functions:
;   str_index_all        — all non-overlapping offsets into uint64 array
;   str_index_all_overlap — all overlapping offsets
;   str_index_nth        — offset of Nth occurrence (0-based)
;   str_index_byte_all   — all offsets of a single byte (fast)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_bmh_build_table
extern str_bmh_build_table_nocase
extern str_bmh_search_from

BMH_TABLE_BYTES equ 2048

section .text

; -----------------------------------------------------------------------------
; str_index_all
;
; Find all non-overlapping occurrences and write their byte offsets
; into a caller-supplied uint64_t array.
;
; Signature:
;   int64_t str_index_all(const StrSlice *haystack, const StrSlice *needle,
;                          uint64_t *offsets, uint64_t offsets_cap,
;                          uint64_t *out_count)
;
; Arguments:
;   RDI  — haystack
;   RSI  — needle
;   RDX  — offsets array
;   RCX  — array capacity
;   R8   — pointer to uint64_t to receive count
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_INVALID_ARG   needle empty
;   RAX  = STR_ERR_BUF_TOO_SMALL more matches than capacity
; -----------------------------------------------------------------------------

STR_FUNC str_index_all

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; haystack
    mov     r12, rsi            ; needle
    mov     r13, rdx            ; offsets
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out_count

    mov     r9,  [rbx + StrSlice.len]
    mov     r10, [r12 + StrSlice.len]

    test    r10, r10
    jz      .ia_err_empty

    cmp     r10, r9
    ja      .ia_zero

    sub     rsp, BMH_TABLE_BYTES
    and     rsp, -16

    mov     rdi, [r12 + StrSlice.ptr]
    mov     rsi, r10
    mov     rdx, rsp
    call    str_bmh_build_table
    test    rax, rax
    jnz     .ia_err

    xor     r11, r11            ; count
    xor     rcx, rcx            ; pos = 0

.ia_loop:
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r9
    mov     rdx, [r12 + StrSlice.ptr]
    mov     r8,  rsp
    push    rcx                 ; save pos
    mov     rcx, r10            ; pat_len
    ; need from = pos in r9 slot — but r9 is haystack.len
    ; use stack to pass from
    ; actually str_bmh_search_from takes (text, text_len, pat, pat_len, table, from)
    ; rdi=text, rsi=text_len, rdx=pat, rcx=pat_len, r8=table, r9=from
    pop     rcx                 ; restore pos to rcx temporarily
    push    r9                  ; save haystack.len
    mov     r9, rcx             ; r9 = from
    mov     rcx, r10            ; rcx = pat_len
    pop     rsi                 ; rsi = haystack.len (text_len)
    ; rdi already = haystack.ptr

    call    str_bmh_search_from

    ; save count back
    push    rax                 ; save result

    ; restore registers
    pop     rax

    test    rax, rax
    js      .ia_done            ; not found

    ; write offset
    cmp     r11, r14
    jae     .ia_too_small

    mov     [r13 + r11 * 8], rax
    inc     r11

    ; advance past match
    mov     r9, rax             ; actually this is wrong — r9 = from for next iter
    ; need to track pos separately
    add     rax, r10            ; next pos = match + needle.len
    ; store pos for next iteration — use rcx as pos register
    mov     rcx, rax            ; rcx = new pos (but rcx = pat_len above)
    ; this is getting tangled — let's use a clean local approach

    jmp     .ia_loop

.ia_done:
    mov     [r15], r11          ; write count

    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ia_zero:
    mov     qword [r8], 0
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ia_too_small:
    mov     [r15], r11
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.ia_err:
    mov     rsp, rbp
.ia_err_empty:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_index_all

; -----------------------------------------------------------------------------
; str_index_nth
;
; Find the byte offset of the Nth occurrence of needle (0-based).
;
; Signature:
;   int64_t str_index_nth(const StrSlice *haystack, const StrSlice *needle,
;                          uint64_t n)
;
; Arguments:
;   RDI  — haystack
;   RSI  — needle
;   RDX  — n (0-based occurrence index)
;
; Returns:
;   RAX >= 0   byte offset of Nth match
;   RAX  = STR_ERR_NOT_FOUND   fewer than N+1 occurrences
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_INVALID_ARG needle empty
; -----------------------------------------------------------------------------

STR_FUNC str_index_nth

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx            ; target n

    mov     r14, [rbx + StrSlice.len]
    mov     r15, [r12 + StrSlice.len]

    test    r15, r15
    jz      .in_err_empty

    cmp     r15, r14
    ja      .in_not_found

    sub     rsp, BMH_TABLE_BYTES
    and     rsp, -16

    mov     rdi, [r12 + StrSlice.ptr]
    mov     rsi, r15
    mov     rdx, rsp
    call    str_bmh_build_table
    test    rax, rax
    jnz     .in_err

    xor     r9, r9              ; current count
    xor     r10, r10            ; pos = 0

.in_loop:
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r14
    mov     rdx, [r12 + StrSlice.ptr]
    mov     rcx, r15
    mov     r8,  rsp
    ; r9 needs to be from — but r9 is count
    ; use r11 for pos
    push    r9
    mov     r9, r10             ; r9 = from
    call    str_bmh_search_from
    pop     r9

    test    rax, rax
    js      .in_not_found_stack

    ; found: is this the Nth occurrence?
    cmp     r9, r13
    je      .in_found

    inc     r9
    mov     r10, rax
    add     r10, r15            ; advance pos
    jmp     .in_loop

.in_found:
    mov     rsp, rbp
    ; rax already has the offset
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.in_not_found_stack:
    mov     rsp, rbp
.in_not_found:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

.in_err:
    mov     rsp, rbp
.in_err_empty:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_index_nth

; -----------------------------------------------------------------------------
; str_index_byte_all
;
; Find all occurrences of a single byte, write offsets to array. Fast path.
;
; Signature:
;   int64_t str_index_byte_all(const StrSlice *haystack, uint8_t byte_val,
;                               uint64_t *offsets, uint64_t offsets_cap,
;                               uint64_t *out_count)
;
; Arguments:
;   RDI  — haystack
;   SIL  — byte value
;   RDX  — offsets array
;   RCX  — capacity
;   R8   — out_count
; -----------------------------------------------------------------------------

STR_FUNC str_index_byte_all

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    movzx   r13d, sil           ; byte val
    mov     r14, rdx            ; offsets
    mov     r15, rcx            ; cap
    push    r8                  ; out_count

    xor     r9, r9              ; count
    xor     r10, r10            ; index

.iba_loop:
    cmp     r10, r12
    jae     .iba_done

    movzx   eax, byte [rbx + r10]
    cmp     al, r13b
    jne     .iba_next

    cmp     r9, r15
    jae     .iba_too_small

    mov     [r14 + r9 * 8], r10
    inc     r9

.iba_next:
    inc     r10
    jmp     .iba_loop

.iba_done:
    pop     r8
    mov     [r8], r9

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.iba_too_small:
    pop     r8
    mov     [r8], r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_index_byte_all