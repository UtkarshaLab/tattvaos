; =============================================================================
; str/core/split.asm
; Split a StrSlice on a delimiter byte, string, or whitespace.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/cmp.asm    (str_eq_bytes)
;   inspect/is_space.asm (str_is_ascii_space_byte)
;
; -----------------------------------------------------------------------------
; All split functions write results into a caller-supplied StrSlice array.
; No allocation — results are sub-views of the input.
;
; Functions:
;   str_split_byte      — split on a single byte delimiter
;   str_split_str       — split on a StrSlice delimiter
;   str_split_whitespace — split on any ASCII whitespace run
;   str_split_lines     — split on LF or CRLF
;   str_split_once      — find first delimiter, return two halves
;   str_split_once_str  — split on first occurrence of string delimiter
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_eq_bytes
extern str_is_ascii_space_byte

section .text

; -----------------------------------------------------------------------------
; str_split_byte
;
; Split a StrSlice on a single byte delimiter.
; Results written into a caller-supplied StrSlice array.
;
; Signature:
;   int64_t str_split_byte(const StrSlice *src, uint8_t delim,
;                           StrSlice *out_array, uint64_t array_cap,
;                           uint64_t *out_count)
;
; Arguments:
;   RDI  — source StrSlice
;   SIL  — delimiter byte
;   RDX  — output StrSlice array
;   RCX  — array capacity (max number of slices)
;   R8   — pointer to uint64_t to receive actual count
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          src, out_array, or out_count is null
;   RAX  = STR_ERR_BUF_TOO_SMALL array_cap insufficient for all segments
; -----------------------------------------------------------------------------

STR_FUNC str_split_byte

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; current segment start
    mov     r12, [rdi + StrSlice.len]   ; remaining bytes
    movzx   r13d, sil                   ; delimiter
    mov     r14, rdx                    ; out array
    mov     r15, rcx                    ; array cap
    push    r8                          ; out_count

    xor     r9, r9                      ; segment count
    mov     r10, rbx                    ; scan ptr

.sb_loop:
    ; check if we've exhausted the input
    mov     r11, r10
    sub     r11, rbx                    ; bytes consumed so far
    cmp     r11, r12
    jae     .sb_flush

    movzx   eax, byte [r10]
    cmp     al, r13b
    jne     .sb_next

    ; found delimiter — emit segment [rbx, r10)
    cmp     r9, r15
    jae     .sb_too_small

    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.ptr], rbx
    mov     rax, r10
    sub     rax, rbx
    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.len], rax

    inc     r9
    inc     r10
    mov     rbx, r10             ; new segment start
    jmp     .sb_loop

.sb_next:
    inc     r10
    jmp     .sb_loop

.sb_flush:
    ; emit final segment
    cmp     r9, r15
    jae     .sb_too_small

    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.ptr], rbx
    mov     rax, r10
    sub     rax, rbx
    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9

    pop     r8
    mov     [r8], r9

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sb_too_small:
    pop     r8
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_split_byte

; -----------------------------------------------------------------------------
; str_split_once
;
; Find the first occurrence of delimiter byte and split into two halves.
; left  = before delimiter
; right = after delimiter
; If delimiter not found: left = entire src, right = empty
;
; Signature:
;   int64_t str_split_once(const StrSlice *src, uint8_t delim,
;                           StrSlice *left, StrSlice *right)
;
; Arguments:
;   RDI  — source StrSlice
;   SIL  — delimiter byte
;   RDX  — left StrSlice
;   RCX  — right StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_split_once

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    movzx   r13d, sil
    mov     r14, rdx            ; left
    ; rcx = right

    xor     r9, r9              ; scan index

.so_scan:
    cmp     r9, r12
    jae     .so_not_found

    movzx   eax, byte [rbx + r9]
    cmp     al, r13b
    je      .so_found

    inc     r9
    jmp     .so_scan

.so_found:
    ; left = [rbx, r9)
    mov     [r14 + StrSlice.ptr], rbx
    mov     [r14 + StrSlice.len], r9

    ; right = [rbx + r9 + 1, end)
    mov     rax, rbx
    add     rax, r9
    inc     rax
    mov     [rcx + StrSlice.ptr], rax
    mov     rax, r12
    sub     rax, r9
    dec     rax
    mov     [rcx + StrSlice.len], rax

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.so_not_found:
    ; left = full src, right = empty
    mov     [r14 + StrSlice.ptr], rbx
    mov     [r14 + StrSlice.len], r12

    mov     qword [rcx + StrSlice.ptr], 0
    mov     qword [rcx + StrSlice.len], 0

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_split_once

; -----------------------------------------------------------------------------
; str_split_whitespace
;
; Split on any run of ASCII whitespace. Consecutive whitespace is treated
; as a single delimiter. Leading/trailing whitespace produces no empty tokens.
;
; Signature:
;   int64_t str_split_whitespace(const StrSlice *src,
;                                 StrSlice *out_array, uint64_t array_cap,
;                                 uint64_t *out_count)
; -----------------------------------------------------------------------------

STR_FUNC str_split_whitespace

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out array
    mov     r14, rdx            ; cap
    push    rcx                 ; out_count

    add     r12, rbx            ; end ptr
    mov     r15, rbx            ; scan ptr
    xor     r9, r9              ; count
    mov     r10, rbx            ; segment start (invalid until in_word)
    xor     r11, r11            ; in_word flag

.sw_loop:
    cmp     r15, r12
    jae     .sw_flush_word

    movzx   edi, byte [r15]
    push    r15
    push    r12
    push    r9
    push    r10
    push    r11
    call    str_is_ascii_space_byte
    pop     r11
    pop     r10
    pop     r9
    pop     r12
    pop     r15

    test    eax, eax
    jnz     .sw_is_space

    ; not space
    test    r11, r11
    jnz     .sw_in_word_cont

    ; start of new word
    mov     r10, r15
    mov     r11, 1

.sw_in_word_cont:
    inc     r15
    jmp     .sw_loop

.sw_is_space:
    test    r11, r11
    jz      .sw_skip_space      ; consecutive spaces

    ; end of word
    cmp     r9, r14
    jae     .sw_too_small

    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.ptr], r10
    mov     rax, r15
    sub     rax, r10
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9
    xor     r11, r11

.sw_skip_space:
    inc     r15
    jmp     .sw_loop

.sw_flush_word:
    test    r11, r11
    jz      .sw_done

    cmp     r9, r14
    jae     .sw_too_small

    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.ptr], r10
    mov     rax, r15
    sub     rax, r10
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9

.sw_done:
    pop     rcx
    mov     [rcx], r9

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sw_too_small:
    pop     rcx
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_split_whitespace

; -----------------------------------------------------------------------------
; str_split_lines
;
; Split on LF (0x0A) or CRLF (0x0D 0x0A). CR is stripped.
;
; Signature:
;   int64_t str_split_lines(const StrSlice *src,
;                            StrSlice *out_array, uint64_t array_cap,
;                            uint64_t *out_count)
; -----------------------------------------------------------------------------

STR_FUNC str_split_lines

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out_array
    mov     r14, rdx            ; cap
    push    rcx                 ; out_count

    add     r12, rbx            ; end ptr
    mov     r15, rbx            ; scan ptr
    xor     r9, r9              ; count
    mov     r10, rbx            ; segment start

.sl_loop:
    cmp     r15, r12
    jae     .sl_flush

    movzx   eax, byte [r15]

    cmp     al, 0x0A            ; LF
    je      .sl_newline

    cmp     al, 0x0D            ; CR
    jne     .sl_next

    ; CR: check for CRLF
    mov     rax, r15
    inc     rax
    cmp     rax, r12
    jae     .sl_cr_only

    movzx   eax, byte [r15 + 1]
    cmp     al, 0x0A
    jne     .sl_cr_only

    ; CRLF: emit segment [r10, r15), skip 2 bytes
    cmp     r9, r14
    jae     .sl_too_small

    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.ptr], r10
    mov     rax, r15
    sub     rax, r10
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9
    add     r15, 2
    mov     r10, r15
    jmp     .sl_loop

.sl_cr_only:
    ; treat lone CR as newline
.sl_newline:
    cmp     r9, r14
    jae     .sl_too_small

    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.ptr], r10
    mov     rax, r15
    sub     rax, r10
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9
    inc     r15
    mov     r10, r15
    jmp     .sl_loop

.sl_next:
    inc     r15
    jmp     .sl_loop

.sl_flush:
    ; emit final segment (may be empty if input ends with newline)
    cmp     r15, r10
    je      .sl_done            ; skip empty trailing segment

    cmp     r9, r14
    jae     .sl_too_small

    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.ptr], r10
    mov     rax, r15
    sub     rax, r10
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9

.sl_done:
    pop     rcx
    mov     [rcx], r9

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sl_too_small:
    pop     rcx
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_split_lines
