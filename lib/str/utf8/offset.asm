; =============================================================================
; str/utf8/offset.asm
; Byte offset of the Nth codepoint in a UTF-8 string, and related
; byte↔codepoint index conversion utilities.
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
; Why this module exists:
;   StrSlice.len is always a byte length.
;   All slicing and substring ops work in bytes internally.
;   But callers often think in codepoint indices.
;
;   offset.asm bridges the two worlds:
;     str_utf8_cp_to_byte_offset  — codepoint index → byte offset
;     str_utf8_byte_to_cp_index   — byte offset → codepoint index
;     str_utf8_offset_slice       — slice by codepoint range → StrSlice
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_utf8_cp_to_byte_offset
;
; Given a codepoint index N, return the byte offset of that codepoint.
; Equivalent to: how many bytes are before the Nth codepoint?
;
; Signature:
;   int64_t str_utf8_cp_to_byte_offset(const uint8_t *ptr,
;                                        uint64_t byte_len,
;                                        uint64_t cp_index,
;                                        uint64_t *out_byte_offset)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length of buffer
;   RDX  — codepoint index (0-based)
;   RCX  — pointer to uint64_t to receive byte offset
;
; Returns:
;   RAX  = STR_OK               byte offset written to *out_byte_offset
;   RAX  = STR_ERR_NULL         ptr or out is null
;   RAX  = STR_ERR_OUT_OF_BOUNDS cp_index >= codepoint count
;   RAX  = STR_ERR_INVALID_UTF8  malformed input
;
; Note: offset of cp_index == 0 is always 0 (no walk needed).
;       offset of cp_index == cp_count returns byte_len (one past end).
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_cp_to_byte_offset

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; cp_index == 0 → byte offset is always 0
    test    rdx, rdx
    jz      .zero_offset

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi                ; rbx = current ptr
    mov     r12, rsi                ; r12 = byte_len
    add     r12, rdi                ; r12 = end ptr
    mov     r13, rdx                ; r13 = target cp_index
    mov     r14, rcx                ; r14 = out_byte_offset
    mov     r15, rdi                ; r15 = base ptr
    xor     ecx, ecx                ; ecx = current cp index

.walk:
    cmp     rbx, r12
    jae     .check_end

    cmp     rcx, r13
    je      .found

    ; determine sequence length inline
    movzx   eax, byte [rbx]

    test    al, 0x80
    jz      .adv1

    cmp     al, 0xC2
    jb      .bad_utf8
    cmp     al, 0xDF
    jbe     .adv2

    cmp     al, 0xEF
    jbe     .adv3

    cmp     al, 0xF4
    jbe     .adv4

    jmp     .bad_utf8

.adv1: add rbx, 1 ; jmp .step
       jmp .step
.adv2: add rbx, 2
       jmp .step
.adv3: add rbx, 3
       jmp .step
.adv4: add rbx, 4

.step:
    inc     rcx
    jmp     .walk

.check_end:
    ; allow cp_index == cp_count (offset = byte_len)
    cmp     rcx, r13
    jne     .out_of_bounds

.found:
    mov     rax, rbx
    sub     rax, r15                ; byte offset = current - base
    mov     [r14], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax                ; STR_OK
    pop     rbp
    ret

.zero_offset:
    mov     qword [rcx], 0
    xor     eax, eax
    pop     rbp
    ret

.out_of_bounds:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

.bad_utf8:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

STR_ENDFUNC str_utf8_cp_to_byte_offset

; -----------------------------------------------------------------------------
; str_utf8_byte_to_cp_index
;
; Given a byte offset, return the codepoint index at that offset.
; The byte offset must land exactly on a codepoint boundary.
;
; Signature:
;   int64_t str_utf8_byte_to_cp_index(const uint8_t *ptr,
;                                      uint64_t byte_len,
;                                      uint64_t byte_offset,
;                                      uint64_t *out_cp_index)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length
;   RDX  — byte offset (must be on a codepoint boundary, 0..byte_len)
;   RCX  — pointer to uint64_t to receive codepoint index
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          ptr or out is null
;   RAX  = STR_ERR_OUT_OF_BOUNDS byte_offset > byte_len
;   RAX  = STR_ERR_INVALID_UTF8  byte_offset not on a codepoint boundary
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_byte_to_cp_index

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; byte_offset > byte_len → out of bounds
    cmp     rdx, rsi
    ja      .out_of_bounds

    ; byte_offset == 0 → cp_index 0
    test    rdx, rdx
    jz      .zero_index

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi                ; rbx = current ptr
    mov     r12, rdi
    add     r12, rdx                ; r12 = target ptr (base + byte_offset)
    mov     r13, rcx                ; r13 = out_cp_index
    xor     r14, r14                ; r14 = cp counter

.count:
    cmp     rbx, r12
    jae     .done_count

    movzx   eax, byte [rbx]

    ; check byte at target offset is not a continuation byte
    ; (only relevant when rbx == r12, handled after loop)

    test    al, 0x80
    jz      .c1

    cmp     al, 0xC2
    jb      .bad_boundary
    cmp     al, 0xDF
    jbe     .c2

    cmp     al, 0xEF
    jbe     .c3

    cmp     al, 0xF4
    jbe     .c4

    jmp     .bad_boundary

.c1: add rbx, 1 ; jmp .cstep
     jmp .cstep
.c2: add rbx, 2
     jmp .cstep
.c3: add rbx, 3
     jmp .cstep
.c4: add rbx, 4

.cstep:
    inc     r14
    jmp     .count

.done_count:
    ; verify rbx landed exactly on r12 (on a boundary)
    cmp     rbx, r12
    jne     .bad_boundary

    mov     [r13], r14

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.zero_index:
    mov     qword [rcx], 0
    xor     eax, eax
    pop     rbp
    ret

.out_of_bounds:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

.bad_boundary:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

STR_ENDFUNC str_utf8_byte_to_cp_index

; -----------------------------------------------------------------------------
; str_utf8_offset_slice
;
; Produce a StrSlice covering codepoints [start, end) of a parent buffer.
; Both indices are codepoint-based (0-indexed). end is exclusive.
;
; Signature:
;   int64_t str_utf8_offset_slice(const uint8_t *ptr, uint64_t byte_len,
;                                  uint64_t cp_start, uint64_t cp_end,
;                                  StrSlice *out_slice)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length
;   RDX  — start codepoint index (inclusive)
;   RCX  — end codepoint index (exclusive)
;   R8   — pointer to StrSlice to receive result
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          ptr or out_slice is null
;   RAX  = STR_ERR_OUT_OF_BOUNDS cp_start or cp_end out of range
;   RAX  = STR_ERR_INVALID_ARG   cp_start > cp_end
;   RAX  = STR_ERR_INVALID_UTF8  malformed input
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_offset_slice

    guard_null rdi, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    ; cp_start > cp_end → invalid
    cmp     rdx, rcx
    ja      .err_arg

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi                ; rbx = current ptr
    mov     r12, rdi
    add     r12, rsi                ; r12 = end ptr
    mov     r13, rdx                ; r13 = cp_start
    mov     r14, rcx                ; r14 = cp_end
    mov     r15, r8                 ; r15 = out_slice

    xor     ecx, ecx                ; ecx = cp counter
    xor     r8,  r8                 ; r8  = start byte offset found flag
    xor     r9,  r9                 ; r9  = start byte ptr
    xor     r10, r10                ; r10 = end byte ptr

    ; cp_start == 0 → start immediately at base
    test    r13, r13
    jnz     .scan_loop
    mov     r9, rbx
    inc     r8                      ; mark start found

.scan_loop:
    cmp     rbx, r12
    jae     .scan_end

    ; check if we hit cp_start
    test    r8, r8
    jnz     .check_end_idx

    cmp     rcx, r13
    jne     .advance_seq
    mov     r9, rbx                 ; save start byte ptr
    inc     r8

.check_end_idx:
    cmp     rcx, r14
    jne     .advance_seq
    mov     r10, rbx                ; save end byte ptr
    jmp     .slice_ready

.advance_seq:
    movzx   eax, byte [rbx]

    test    al, 0x80
    jz      .s1

    cmp     al, 0xC2
    jb      .bad_utf8
    cmp     al, 0xDF
    jbe     .s2

    cmp     al, 0xEF
    jbe     .s3

    cmp     al, 0xF4
    jbe     .s4

    jmp     .bad_utf8

.s1: add rbx, 1 ; jmp .s_step
     jmp .s_step
.s2: add rbx, 2
     jmp .s_step
.s3: add rbx, 3
     jmp .s_step
.s4: add rbx, 4

.s_step:
    inc     rcx
    jmp     .scan_loop

.scan_end:
    ; if end == cp_end, end byte ptr is current (end of buffer)
    cmp     rcx, r14
    jne     .out_of_bounds
    mov     r10, rbx

    ; if start was never found
    test    r8, r8
    jz      .out_of_bounds

.slice_ready:
    ; out_slice.ptr = r9 (start byte ptr)
    ; out_slice.len = r10 - r9
    mov     [r15 + StrSlice.ptr], r9
    mov     rax, r10
    sub     rax, r9
    mov     [r15 + StrSlice.len], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.err_arg:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

.out_of_bounds:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

.bad_utf8:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

STR_ENDFUNC str_utf8_offset_slice