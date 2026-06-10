; =============================================================================
; str/convert/utf32.asm
; UTF-8 ↔ UTF-32 transcoding.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;   utf8/encode.asm  (str_utf8_encode_unchecked)
;
; -----------------------------------------------------------------------------
; UTF-32 encoding:
;   Each codepoint stored as a 32-bit integer.
;   Valid range: U+0000..U+10FFFF (excluding surrogates U+D800..U+DFFF).
;   Little-endian (UTF-32LE) and big-endian (UTF-32BE) supported.
;   4 bytes per codepoint always — simple, no variable-length encoding.
;
; UTF-32 is mainly used for:
;   - In-memory codepoint arrays (fast random access)
;   - Interop with older systems
;   - Unicode algorithm implementations
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_utf8_encode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_utf8_to_utf32le
;
; Convert UTF-8 to UTF-32LE (little-endian, 4 bytes per codepoint).
;
; Signature:
;   int64_t str_utf8_to_utf32le(const StrSlice *src,
;                                uint32_t *dst, uint64_t dst_cap_bytes,
;                                uint64_t *out_bytes_written)
;
; Arguments:
;   RDI  — source UTF-8 StrSlice
;   RSI  — destination buffer
;   RDX  — destination capacity in BYTES (must be >= cp_count * 4)
;   RCX  — pointer to uint64_t for bytes written (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL
;   RAX  = STR_ERR_INVALID_UTF8
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_to_utf32le

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; dst_cap_bytes
    mov     r15, rcx            ; out_bytes_written

    mov     r9, rbx
    add     r9, r12             ; end ptr
    xor     r10, r10            ; dst byte offset

.u8_32_loop:
    cmp     rbx, r9
    jae     .u8_32_done

    ; need 4 bytes for each codepoint
    lea     rcx, [r10 + 4]
    cmp     rcx, r14
    ja      .u8_32_too_small

    ; decode codepoint
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     r8, [rsp]           ; advance
    mov     rsp, rbp
    add     rbx, r8

    ; validate: reject surrogates
    cmp     eax, SURROGATE_HIGH_MIN
    jb      .u8_32_write
    cmp     eax, SURROGATE_LOW_MAX
    jbe     .u8_32_surrogate

.u8_32_write:
    ; write 4 bytes little-endian
    mov     [r13 + r10],     al
    shr     eax, 8
    mov     [r13 + r10 + 1], al
    shr     eax, 8
    mov     [r13 + r10 + 2], al
    shr     eax, 8
    mov     [r13 + r10 + 3], al
    add     r10, 4
    jmp     .u8_32_loop

.u8_32_done:
    test    r15, r15
    jz      .u8_32_ok
    mov     [r15], r10

.u8_32_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.u8_32_surrogate:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_SURROGATE
    pop     rbp
    ret

.u8_32_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf8_to_utf32le

; -----------------------------------------------------------------------------
; str_utf32le_to_utf8
;
; Convert UTF-32LE to UTF-8.
;
; Signature:
;   int64_t str_utf32le_to_utf8(const uint32_t *src, uint64_t src_bytes,
;                                uint8_t *dst, uint64_t dst_cap,
;                                uint64_t *out_len)
;
; Arguments:
;   RDI  — source UTF-32LE buffer
;   RSI  — source length in BYTES (must be multiple of 4)
;   RDX  — destination UTF-8 buffer
;   RCX  — destination capacity
;   R8   — pointer to uint64_t for bytes written (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_utf32le_to_utf8

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    ; source length must be multiple of 4
    test    sil, 3
    jnz     .u32_8_invalid

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; src_bytes
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; dst_cap
    mov     r15, r8             ; out_len

    xor     r9, r9              ; src byte offset
    xor     r10, r10            ; dst byte offset

.u32_8_loop:
    cmp     r9, r12
    jae     .u32_8_done

    ; read 32-bit codepoint (little-endian)
    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [rbx + r9 + 1]
    shl     ecx, 8
    or      eax, ecx
    movzx   ecx, byte [rbx + r9 + 2]
    shl     ecx, 16
    or      eax, ecx
    movzx   ecx, byte [rbx + r9 + 3]
    shl     ecx, 24
    or      eax, ecx
    add     r9, 4

    ; validate codepoint
    cmp     eax, CODEPOINT_MAX
    ja      .u32_8_invalid_cp

    cmp     eax, SURROGATE_HIGH_MIN
    jb      .u32_8_encode
    cmp     eax, SURROGATE_LOW_MAX
    jbe     .u32_8_invalid_cp

.u32_8_encode:
    ; ensure 4 bytes available in dst
    lea     rcx, [r10 + 4]
    cmp     rcx, r14
    ja      .u32_8_too_small

    mov     edi, eax
    lea     rsi, [r13 + r10]
    push    r9
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r9
    ; rax = bytes written

    add     r10, rax
    jmp     .u32_8_loop

.u32_8_done:
    test    r15, r15
    jz      .u32_8_ok
    mov     [r15], r10

.u32_8_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.u32_8_invalid:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

.u32_8_invalid_cp:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_CODEPOINT
    pop     rbp
    ret

.u32_8_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf32le_to_utf8

; -----------------------------------------------------------------------------
; str_utf8_to_utf32be — big-endian variant
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_to_utf32be

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    mov     r9, rbx
    add     r9, r12
    xor     r10, r10

.u8_32be_loop:
    cmp     rbx, r9
    jae     .u8_32be_done

    lea     rcx, [r10 + 4]
    cmp     rcx, r14
    ja      .u8_32be_too_small

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r8, [rsp]
    mov     rsp, rbp
    add     rbx, r8

    ; reject surrogates
    cmp     eax, SURROGATE_HIGH_MIN
    jb      .u8_32be_write
    cmp     eax, SURROGATE_LOW_MAX
    jbe     .u8_32be_surr

.u8_32be_write:
    ; write 4 bytes big-endian (most significant byte first)
    mov     ecx, eax

    shr     ecx, 24
    mov     [r13 + r10], cl
    mov     ecx, eax
    shr     ecx, 16
    mov     [r13 + r10 + 1], cl
    mov     ecx, eax
    shr     ecx, 8
    mov     [r13 + r10 + 2], cl
    mov     [r13 + r10 + 3], al
    add     r10, 4
    jmp     .u8_32be_loop

.u8_32be_done:
    test    r15, r15
    jz      .u8_32be_ok
    mov     [r15], r10

.u8_32be_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.u8_32be_surr:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_SURROGATE
    pop     rbp
    ret

.u8_32be_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf8_to_utf32be

; -----------------------------------------------------------------------------
; str_utf32_cp_count
;
; Count codepoints in a UTF-32 buffer (trivial: src_bytes / 4).
;
; Signature:
;   uint64_t str_utf32_cp_count(uint64_t src_bytes)
; -----------------------------------------------------------------------------

STR_FUNC str_utf32_cp_count

    mov     rax, rdi
    shr     rax, 2              ; divide by 4
    pop     rbp
    ret

STR_ENDFUNC str_utf32_cp_count

; -----------------------------------------------------------------------------
; str_utf32le_cp_at
;
; Get the codepoint at index N from a UTF-32LE buffer (O(1) random access).
;
; Signature:
;   int64_t str_utf32le_cp_at(const uint32_t *src, uint64_t src_bytes,
;                              uint64_t index, uint32_t *out_cp)
;
; Arguments:
;   RDI  — source buffer
;   RSI  — source length in bytes
;   RDX  — codepoint index (0-based)
;   RCX  — pointer to uint32_t to receive codepoint
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_OUT_OF_BOUNDS
; -----------------------------------------------------------------------------

STR_FUNC str_utf32le_cp_at

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; byte offset = index * 4
    mov     rax, rdx
    shl     rax, 2

    ; check bounds: offset + 4 <= src_bytes
    lea     r8, [rax + 4]
    cmp     r8, rsi
    ja      .cp_at_oob

    ; read codepoint (little-endian)
    movzx   r8d, byte [rdi + rax]
    movzx   r9d, byte [rdi + rax + 1]
    shl     r9d, 8
    or      r8d, r9d
    movzx   r9d, byte [rdi + rax + 2]
    shl     r9d, 16
    or      r8d, r9d
    movzx   r9d, byte [rdi + rax + 3]
    shl     r9d, 24
    or      r8d, r9d

    mov     [rcx], r8d

    xor     eax, eax
    pop     rbp
    ret

.cp_at_oob:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

STR_ENDFUNC str_utf32le_cp_at
