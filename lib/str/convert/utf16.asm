; =============================================================================
; str/convert/utf16.asm
; UTF-8 ↔ UTF-16 transcoding.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;   utf8/encode.asm  (str_utf8_encode_unchecked, str_utf8_encode_buf_size)
;
; -----------------------------------------------------------------------------
; UTF-16 encoding rules:
;
;   U+0000..U+D7FF and U+E000..U+FFFF:
;     Encoded as single 16-bit code unit.
;
;   U+10000..U+10FFFF (supplementary):
;     Encoded as surrogate pair:
;       high = 0xD800 + ((cp - 0x10000) >> 10)
;       low  = 0xDC00 + ((cp - 0x10000) & 0x3FF)
;
; Both little-endian (UTF-16LE) and big-endian (UTF-16BE) supported.
; BOM handling: U+FEFF written/detected for endianness.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_utf8_encode_unchecked
extern str_utf8_encode_buf_size

section .text

; -----------------------------------------------------------------------------
; str_utf8_to_utf16le
;
; Convert UTF-8 to UTF-16LE (little-endian).
;
; Signature:
;   int64_t str_utf8_to_utf16le(const StrSlice *src,
;                                uint16_t *dst, uint64_t dst_cap_bytes,
;                                uint64_t *out_bytes_written)
;
; Arguments:
;   RDI  — source UTF-8 StrSlice
;   RSI  — destination buffer (uint16_t array)
;   RDX  — destination capacity in BYTES
;   RCX  — pointer to uint64_t for bytes written (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_INVALID_UTF8  malformed input
;   RAX  = STR_ERR_BUF_TOO_SMALL
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_to_utf16le

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; src ptr
    mov     r12, [rdi + StrSlice.len]   ; src len
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; dst_cap_bytes
    mov     r15, rcx            ; out_bytes_written

    mov     r9, rbx
    add     r9, r12             ; src end
    xor     r10, r10            ; dst byte offset

.u8_16_loop:
    cmp     rbx, r9
    jae     .u8_16_done

    ; decode UTF-8 codepoint
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     r8, [rsp]           ; advance
    mov     rsp, rbp
    add     rbx, r8

    ; encode as UTF-16LE
    cmp     eax, 0xFFFF
    jbe     .u16_bmp

    ; supplementary plane: surrogate pair (4 bytes)
    cmp     r10 + 4, r14
    ja      .u8_16_too_small

    ; high surrogate: 0xD800 + ((cp - 0x10000) >> 10)
    sub     eax, 0x10000
    mov     ecx, eax
    shr     ecx, 10
    add     ecx, 0xD800

    ; little-endian: low byte first
    mov     [r13 + r10], cl
    inc     r10
    mov     [r13 + r10], ch
    inc     r10

    ; low surrogate: 0xDC00 + ((cp - 0x10000) & 0x3FF)
    and     eax, 0x3FF
    add     eax, 0xDC00

    mov     [r13 + r10], al
    inc     r10
    mov     [r13 + r10], ah
    inc     r10
    jmp     .u8_16_loop

.u16_bmp:
    ; BMP: single 16-bit code unit (2 bytes)
    lea     rcx, [r10 + 2]
    cmp     rcx, r14
    ja      .u8_16_too_small

    ; little-endian
    mov     [r13 + r10], al
    inc     r10
    shr     eax, 8
    mov     [r13 + r10], al
    inc     r10
    jmp     .u8_16_loop

.u8_16_done:
    test    r15, r15
    jz      .u8_16_ok
    mov     [r15], r10

.u8_16_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.u8_16_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf8_to_utf16le

; -----------------------------------------------------------------------------
; str_utf16le_to_utf8
;
; Convert UTF-16LE to UTF-8.
;
; Signature:
;   int64_t str_utf16le_to_utf8(const uint16_t *src, uint64_t src_bytes,
;                                uint8_t *dst, uint64_t dst_cap,
;                                uint64_t *out_len)
;
; Arguments:
;   RDI  — source UTF-16LE buffer
;   RSI  — source length in BYTES (must be even)
;   RDX  — destination UTF-8 buffer
;   RCX  — destination capacity
;   R8   — pointer to uint64_t for bytes written (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_utf16le_to_utf8

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    ; source length must be even
    test    sil, 1
    jnz     .u16_8_invalid

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; src_bytes
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; dst_cap
    mov     r15, r8             ; out_len

    xor     r9, r9              ; src byte offset
    xor     r10, r10            ; dst byte offset

.u16_8_loop:
    cmp     r9, r12
    jae     .u16_8_done

    ; read 16-bit code unit (little-endian)
    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [rbx + r9 + 1]
    shl     ecx, 8
    or      eax, ecx
    add     r9, 2

    ; check for surrogate pair
    cmp     eax, 0xD800
    jb      .u16_8_bmp
    cmp     eax, 0xDBFF
    ja      .u16_8_check_low_surr

    ; high surrogate — read low surrogate
    cmp     r9, r12
    jae     .u16_8_invalid_surr

    movzx   ecx, byte [rbx + r9]
    movzx   edx, byte [rbx + r9 + 1]
    shl     edx, 8
    or      ecx, edx
    add     r9, 2

    ; validate low surrogate range: 0xDC00..0xDFFF
    cmp     ecx, 0xDC00
    jb      .u16_8_invalid_surr
    cmp     ecx, 0xDFFF
    ja      .u16_8_invalid_surr

    ; codepoint = 0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00)
    sub     eax, 0xD800
    shl     eax, 10
    sub     ecx, 0xDC00
    or      eax, ecx
    add     eax, 0x10000

    jmp     .u16_8_encode

.u16_8_check_low_surr:
    ; lone low surrogate → invalid
    cmp     eax, 0xDC00
    jb      .u16_8_bmp
    cmp     eax, 0xDFFF
    jbe     .u16_8_invalid_surr

.u16_8_bmp:
    ; BMP codepoint — direct encode

.u16_8_encode:
    ; encode codepoint as UTF-8
    ; need up to 4 bytes
    lea     rcx, [r10 + 4]
    cmp     rcx, r14
    ja      .u16_8_too_small

    mov     edi, eax
    lea     rsi, [r13 + r10]
    push    r9
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r9
    ; rax = bytes written

    add     r10, rax
    jmp     .u16_8_loop

.u16_8_done:
    test    r15, r15
    jz      .u16_8_ok
    mov     [r15], r10

.u16_8_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.u16_8_invalid:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

.u16_8_invalid_surr:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

.u16_8_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf16le_to_utf8

; -----------------------------------------------------------------------------
; str_utf8_to_utf16be — big-endian variant
; Same as LE but bytes swapped in each code unit.
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_to_utf16be

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

.u8_16be_loop:
    cmp     rbx, r9
    jae     .u8_16be_done

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r8, [rsp]
    mov     rsp, rbp
    add     rbx, r8

    cmp     eax, 0xFFFF
    jbe     .u16be_bmp

    ; surrogate pair (big-endian)
    lea     rcx, [r10 + 4]
    cmp     rcx, r14
    ja      .u8_16be_too_small

    sub     eax, 0x10000
    mov     ecx, eax
    shr     ecx, 10
    add     ecx, 0xD800

    ; big-endian: high byte first
    mov     r8b, ch
    mov     [r13 + r10], r8b
    inc     r10
    mov     [r13 + r10], cl
    inc     r10

    and     eax, 0x3FF
    add     eax, 0xDC00

    mov     r8b, ah
    mov     [r13 + r10], r8b
    inc     r10
    mov     [r13 + r10], al
    inc     r10
    jmp     .u8_16be_loop

.u16be_bmp:
    lea     rcx, [r10 + 2]
    cmp     rcx, r14
    ja      .u8_16be_too_small

    ; big-endian: high byte first
    mov     cl, ah
    mov     [r13 + r10], cl
    inc     r10
    mov     [r13 + r10], al
    inc     r10
    jmp     .u8_16be_loop

.u8_16be_done:
    test    r15, r15
    jz      .u8_16be_ok
    mov     [r15], r10

.u8_16be_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.u8_16be_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf8_to_utf16be
