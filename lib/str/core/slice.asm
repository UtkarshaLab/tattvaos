; =============================================================================
; str/core/slice.asm
; Subslice, windowing, and byte-level slice operations.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/offset.asm  (str_utf8_cp_to_byte_offset)
;
; -----------------------------------------------------------------------------
; All slice operations work in BYTES internally.
; For codepoint-based slicing see utf8/offset.asm str_utf8_offset_slice.
;
; A slice is always a non-owning view — no allocation, no copy.
; The result slice shares memory with the source.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_cp_to_byte_offset

section .text

; -----------------------------------------------------------------------------
; str_slice
;
; Return a subslice of [byte_start, byte_end) from a StrSlice.
; Both indices are byte offsets. end is exclusive.
;
; Signature:
;   int64_t str_slice(const StrSlice *src, uint64_t byte_start,
;                     uint64_t byte_end, StrSlice *out)
;
; Arguments:
;   RDI  — pointer to source StrSlice
;   RSI  — byte start offset (inclusive)
;   RDX  — byte end offset (exclusive)
;   RCX  — pointer to output StrSlice
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          src or out is null
;   RAX  = STR_ERR_OUT_OF_BOUNDS start > end or end > src.len
;   RAX  = STR_ERR_INVALID_ARG   start > end
; -----------------------------------------------------------------------------

STR_FUNC str_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; byte_start
    mov     r13, rdx            ; byte_end
    mov     r14, rcx            ; out

    ; start > end → invalid
    cmp     r12, r13
    ja      .err_arg

    mov     rcx, [rbx + StrSlice.len]

    ; end > src.len → out of bounds
    cmp     r13, rcx
    ja      .err_bounds

    ; out.ptr = src.ptr + start
    mov     rax, [rbx + StrSlice.ptr]
    add     rax, r12
    mov     [r14 + StrSlice.ptr], rax

    ; out.len = end - start
    mov     rax, r13
    sub     rax, r12
    mov     [r14 + StrSlice.len], rax

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.err_arg:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

.err_bounds:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

STR_ENDFUNC str_slice

; -----------------------------------------------------------------------------
; str_slice_from
;
; Return a subslice from byte_start to end of string.
;
; Signature:
;   int64_t str_slice_from(const StrSlice *src, uint64_t byte_start,
;                           StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_slice_from

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    mov     rcx, [rdi + StrSlice.len]

    ; start > len → out of bounds
    cmp     rsi, rcx
    ja      .err_bounds

    ; out.ptr = src.ptr + start
    mov     rax, [rdi + StrSlice.ptr]
    add     rax, rsi
    mov     [rdx + StrSlice.ptr], rax

    ; out.len = src.len - start
    sub     rcx, rsi
    mov     [rdx + StrSlice.len], rcx

    xor     eax, eax
    pop     rbp
    ret

.err_bounds:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

STR_ENDFUNC str_slice_from

; -----------------------------------------------------------------------------
; str_slice_to
;
; Return a subslice from start of string to byte_end (exclusive).
;
; Signature:
;   int64_t str_slice_to(const StrSlice *src, uint64_t byte_end,
;                         StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_slice_to

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    mov     rcx, [rdi + StrSlice.len]

    ; end > len → out of bounds
    cmp     rsi, rcx
    ja      .err_bounds

    ; out.ptr = src.ptr (same start)
    mov     rax, [rdi + StrSlice.ptr]
    mov     [rdx + StrSlice.ptr], rax

    ; out.len = end
    mov     [rdx + StrSlice.len], rsi

    xor     eax, eax
    pop     rbp
    ret

.err_bounds:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

STR_ENDFUNC str_slice_to

; -----------------------------------------------------------------------------
; str_slice_cp
;
; Return a subslice using codepoint indices instead of byte offsets.
; cp_end is exclusive.
;
; Signature:
;   int64_t str_slice_cp(const StrSlice *src, uint64_t cp_start,
;                         uint64_t cp_end, StrSlice *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — codepoint start (inclusive)
;   RDX  — codepoint end (exclusive)
;   RCX  — output StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_slice_cp

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi            ; cp_start
    mov     r13, rdx            ; cp_end
    mov     r14, rcx            ; out

    mov     r15, [rbx + StrSlice.ptr]   ; base ptr
    mov     rcx, [rbx + StrSlice.len]   ; byte_len

    ; get byte offset of cp_start
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, r15
    mov     rsi, rcx
    mov     rdx, r12
    lea     rcx, [rsp]
    call    str_utf8_cp_to_byte_offset
    test    rax, rax
    jnz     .err_cp

    mov     r12, [rsp]          ; r12 = byte_start

    ; get byte offset of cp_end
    mov     rdi, r15
    mov     rsi, [rbx + StrSlice.len]
    mov     rdx, r13
    lea     rcx, [rsp]
    call    str_utf8_cp_to_byte_offset
    test    rax, rax
    jnz     .err_cp

    mov     r13, [rsp]          ; r13 = byte_end

    mov     rsp, rbp

    ; build output slice
    mov     rax, r15
    add     rax, r12
    mov     [r14 + StrSlice.ptr], rax

    mov     rax, r13
    sub     rax, r12
    mov     [r14 + StrSlice.len], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.err_cp:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret                         ; rax has error from cp_to_byte_offset

STR_ENDFUNC str_slice_cp

; -----------------------------------------------------------------------------
; str_split_at
;
; Split a StrSlice at a byte offset into two non-overlapping slices.
; left  = [0, byte_offset)
; right = [byte_offset, len)
;
; Signature:
;   int64_t str_split_at(const StrSlice *src, uint64_t byte_offset,
;                         StrSlice *left, StrSlice *right)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — byte offset to split at
;   RDX  — pointer to left StrSlice
;   RCX  — pointer to right StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_split_at

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]

    ; offset > len → out of bounds
    cmp     rsi, rax
    ja      .err_bounds

    mov     r8, [rdi + StrSlice.ptr]

    ; left: ptr = src.ptr, len = offset
    mov     [rdx + StrSlice.ptr], r8
    mov     [rdx + StrSlice.len], rsi

    ; right: ptr = src.ptr + offset, len = src.len - offset
    add     r8, rsi
    mov     [rcx + StrSlice.ptr], r8
    sub     rax, rsi
    mov     [rcx + StrSlice.len], rax

    xor     eax, eax
    pop     rbp
    ret

.err_bounds:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

STR_ENDFUNC str_split_at

; -----------------------------------------------------------------------------
; str_window
;
; Slide a fixed-size window of byte_size over a StrSlice.
; Returns the Nth window (0-indexed) as a slice.
; Windows do NOT overlap.
;
; Signature:
;   int64_t str_window(const StrSlice *src, uint64_t window_size,
;                       uint64_t n, StrSlice *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — window size in bytes
;   RDX  — window index N (0-based)
;   RCX  — output StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_window

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; window_size == 0 → invalid
    test    rsi, rsi
    jz      .err_arg

    push_regs rbx, r12, r13, r14

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; window_size
    mov     r14, rdx            ; n

    ; byte_start = n * window_size
    mov     rax, r14
    mul     r13                 ; rax = n * window_size (rdx:rax)
    ; check overflow
    test    rdx, rdx
    jnz     .err_bounds_win

    mov     r14, rax            ; r14 = byte_start

    ; byte_end = byte_start + window_size
    mov     rax, r14
    add     rax, r13

    ; both must be <= src.len
    cmp     rax, r12
    ja      .err_bounds_win

    ; build output
    mov     r8, rbx
    add     r8, r14
    mov     [rcx + StrSlice.ptr], r8
    mov     [rcx + StrSlice.len], r13

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.err_arg:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

.err_bounds_win:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

STR_ENDFUNC str_window
