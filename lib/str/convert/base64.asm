; =============================================================================
; str/convert/base64.asm
; Base64 encode and decode (RFC 4648).
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
; Standard Base64 alphabet (RFC 4648 §4):
;   A-Z (0-25), a-z (26-51), 0-9 (52-61), + (62), / (63)
;   Padding: '='
;
; URL-safe Base64 alphabet (RFC 4648 §5):
;   Same as standard but + → -, / → _
;   No padding required.
;
; Functions:
;   str_base64_encode        — bytes → base64 string (standard, padded)
;   str_base64_decode        — base64 string → bytes
;   str_base64_encode_url    — bytes → URL-safe base64 (no padding)
;   str_base64_decode_url    — URL-safe base64 → bytes
;   str_base64_encoded_len   — compute output length for encoding
;   str_base64_decoded_len   — compute max output length for decoding
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata

; Standard Base64 alphabet
_b64_std_enc:
    db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

; URL-safe Base64 alphabet
_b64_url_enc:
    db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

; Decode table for standard Base64 (256 entries)
; 0xFF = invalid, 0xFE = padding '='
_b64_std_dec:
    times 256 db 0xFF           ; initialized to invalid

section .text

; -----------------------------------------------------------------------------
; _b64_init_decode_table  (internal, called once)
; Build the decode table at runtime since data section init is complex.
; Actually we hardcode via macro — but for simplicity, inline decode logic.
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; str_base64_encoded_len
;
; Compute the output length for encoding src_len bytes.
; Standard (padded): ceil(src_len / 3) * 4
; URL-safe (no pad): ceil(src_len * 4 / 3) — varies
;
; Signature:
;   uint64_t str_base64_encoded_len(uint64_t src_len, int64_t url_safe)
;
; Arguments:
;   RDI  — source byte count
;   RSI  — 0 = standard (padded), 1 = URL-safe (no padding)
;
; Returns:
;   RAX  — encoded length in bytes
; -----------------------------------------------------------------------------

STR_FUNC str_base64_encoded_len

    ; ceil(n / 3) * 4
    mov     rax, rdi
    xor     edx, edx
    mov     ecx, 3
    div     rcx                 ; rax = n/3, rdx = n%3

    ; groups = rax + (rdx ? 1 : 0)
    test    rdx, rdx
    jz      .bel_no_partial
    inc     rax

.bel_no_partial:
    shl     rax, 2              ; * 4

    ; for URL-safe without padding: subtract padding bytes
    test    rsi, rsi
    jz      .bel_done

    ; URL-safe: no padding. partial group of 1 → 2 chars, of 2 → 3 chars
    mov     rcx, rdi
    xor     edx, edx
    mov     r8d, 3
    div     r8                  ; rdx = src_len % 3
    test    rdx, rdx
    jz      .bel_done

    ; subtract 2 - rdx padding chars? Actually:
    ; r%3==1 → 2 output + 2 pad → minus 2
    ; r%3==2 → 3 output + 1 pad → minus 1
    mov     rcx, 3
    sub     rcx, rdx            ; 3 - (src_len % 3) = pad count
    sub     rax, rcx

.bel_done:
    pop     rbp
    ret

STR_ENDFUNC str_base64_encoded_len

; -----------------------------------------------------------------------------
; str_base64_encode
;
; Encode src_len bytes into standard Base64 (padded).
;
; Signature:
;   int64_t str_base64_encode(const uint8_t *src, uint64_t src_len,
;                              uint8_t *dst, uint64_t dst_cap,
;                              uint64_t *out_len)
;
; Arguments:
;   RDI  — source bytes
;   RSI  — source length
;   RDX  — destination buffer
;   RCX  — destination capacity
;   R8   — pointer to uint64_t for written length (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_base64_encode

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    ; compute required output length
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    push    r8

    mov     rdi, rsi
    xor     esi, esi            ; standard (padded)
    call    str_base64_encoded_len
    mov     r9, rax             ; required length

    pop     r8
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi

    cmp     r9, rcx
    ja      .b64e_too_small

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; src_len
    mov     r13, rdx            ; dst
    mov     r14, r8             ; out_len

    lea     r15, [rel _b64_std_enc]

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index

.b64e_loop:
    ; process 3 bytes at a time
    mov     rax, r12
    sub     rax, r9
    cmp     rax, 3
    jb      .b64e_partial

    ; full 3-byte group
    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [rbx + r9 + 1]
    movzx   edx, byte [rbx + r9 + 2]

    ; byte 0: bits [7:2]
    mov     r8d, eax
    shr     r8d, 2
    movzx   r8d, byte [r15 + r8]
    mov     [r13 + r10], r8b
    inc     r10

    ; byte 1: bits [1:0] of b0 + bits [7:4] of b1
    mov     r8d, eax
    and     r8d, 0x03
    shl     r8d, 4
    mov     r11d, ecx
    shr     r11d, 4
    or      r8d, r11d
    movzx   r8d, byte [r15 + r8]
    mov     [r13 + r10], r8b
    inc     r10

    ; byte 2: bits [3:0] of b1 + bits [7:6] of b2
    mov     r8d, ecx
    and     r8d, 0x0F
    shl     r8d, 2
    mov     r11d, edx
    shr     r11d, 6
    or      r8d, r11d
    movzx   r8d, byte [r15 + r8]
    mov     [r13 + r10], r8b
    inc     r10

    ; byte 3: bits [5:0] of b2
    mov     r8d, edx
    and     r8d, 0x3F
    movzx   r8d, byte [r15 + r8]
    mov     [r13 + r10], r8b
    inc     r10

    add     r9, 3
    jmp     .b64e_loop

.b64e_partial:
    ; 0, 1, or 2 remaining bytes
    mov     rax, r12
    sub     rax, r9
    test    rax, rax
    jz      .b64e_done

    ; load available bytes (with zero padding)
    xor     ecx, ecx
    xor     edx, edx
    movzx   eax, byte [rbx + r9]

    cmp     r12, r9 + 2
    jbe     .b64e_one_byte
    movzx   ecx, byte [rbx + r9 + 1]

.b64e_one_byte:
    ; encode 4 chars (with '=' padding)
    mov     r8d, eax
    shr     r8d, 2
    movzx   r8d, byte [r15 + r8]
    mov     [r13 + r10], r8b
    inc     r10

    mov     r8d, eax
    and     r8d, 0x03
    shl     r8d, 4
    mov     r11d, ecx
    shr     r11d, 4
    or      r8d, r11d
    movzx   r8d, byte [r15 + r8]
    mov     [r13 + r10], r8b
    inc     r10

    ; if only 1 byte: next 2 chars are '=='
    mov     rax, r12
    sub     rax, r9
    cmp     rax, 1
    je      .b64e_pad2

    ; 2 bytes: encode 3rd char, then '='
    mov     r8d, ecx
    and     r8d, 0x0F
    shl     r8d, 2
    movzx   r8d, byte [r15 + r8]
    mov     [r13 + r10], r8b
    inc     r10
    mov     byte [r13 + r10], '='
    inc     r10
    jmp     .b64e_done

.b64e_pad2:
    mov     byte [r13 + r10], '='
    inc     r10
    mov     byte [r13 + r10], '='
    inc     r10

.b64e_done:
    test    r14, r14
    jz      .b64e_ok
    mov     [r14], r10

.b64e_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.b64e_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_base64_encode

; -----------------------------------------------------------------------------
; str_base64_decode
;
; Decode standard Base64 (padded) into bytes.
;
; Signature:
;   int64_t str_base64_decode(const StrSlice *src, uint8_t *dst,
;                              uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_base64_decode

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    ; length must be multiple of 4
    test    r12b, 0x03
    jnz     .b64d_invalid

    ; max decoded = (src_len / 4) * 3
    mov     r9, r12
    shr     r9, 2
    imul    r9, r9, 3
    cmp     r9, r14
    ja      .b64d_too_small

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index

.b64d_loop:
    cmp     r9, r12
    jae     .b64d_done

    ; decode 4 chars → 3 bytes
    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [rbx + r9 + 1]
    movzx   edx, byte [rbx + r9 + 2]
    movzx   r8d, byte [rbx + r9 + 3]

    ; decode each char
    push    r9
    push    r10

    ; char 0
    mov     edi, eax
    call    _b64_decode_char
    test    rax, rax
    js      .b64d_invalid_char
    mov     r11, rax            ; v0

    ; char 1
    mov     edi, ecx
    call    _b64_decode_char
    test    rax, rax
    js      .b64d_invalid_char
    mov     r9, rax             ; v1 (reuse r9 temporarily)

    ; byte 0: v0 << 2 | v1 >> 4
    mov     rax, r11
    shl     eax, 2
    mov     rcx, r9
    shr     ecx, 4
    or      al, cl
    pop     r10
    pop     r9
    mov     [r13 + r10], al
    inc     r10
    push    r9
    push    r10
    push    r11
    push    r9                  ; v1

    ; char 2
    movzx   edi, byte [rbx + r9 + 2]
    call    _b64_decode_char
    ; rax = v2 or -1 (padding)

    pop     rcx                 ; v1
    pop     r11                 ; v0
    pop     r10
    pop     r9

    test    rax, rax
    js      .b64d_skip_b1       ; padding

    ; byte 1: (v1 & 0x0F) << 4 | v2 >> 2
    mov     r8, rcx
    and     r8d, 0x0F
    shl     r8d, 4
    mov     r11, rax
    shr     r11d, 2
    or      r8b, r11b
    mov     [r13 + r10], r8b
    inc     r10

    ; char 3
    movzx   edi, byte [rbx + r9 + 3]
    push    rax                 ; v2
    push    r10
    call    _b64_decode_char
    pop     r10
    pop     rcx                 ; v2

    test    rax, rax
    js      .b64d_skip_b2       ; padding

    ; byte 2: (v2 & 0x03) << 6 | v3
    mov     r8d, ecx
    and     r8d, 0x03
    shl     r8d, 6
    or      r8b, al
    mov     [r13 + r10], r8b
    inc     r10

.b64d_skip_b2:
.b64d_skip_b1:
    add     r9, 4
    jmp     .b64d_loop

.b64d_invalid_char:
    pop     r10
    pop     r9
.b64d_invalid:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.b64d_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.b64d_done:
    test    r15, r15
    jz      .b64d_ok
    mov     [r15], r10

.b64d_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_base64_decode

; -----------------------------------------------------------------------------
; _b64_decode_char  (internal)
;
; Decode a single Base64 character to 0..63, or -1 for padding.
;
; Arguments: DIL = char
; Returns:   RAX = 0..63, or -1 for '=', or STR_ERR_PARSE for invalid
; -----------------------------------------------------------------------------

_b64_decode_char:
    movzx   eax, dil

    ; A-Z → 0-25
    cmp     al, 'A'
    jb      .dc_lower
    cmp     al, 'Z'
    ja      .dc_lower
    sub     al, 'A'
    ret

.dc_lower:
    ; a-z → 26-51
    cmp     al, 'a'
    jb      .dc_digit
    cmp     al, 'z'
    ja      .dc_digit
    sub     al, 'a'
    add     al, 26
    ret

.dc_digit:
    ; 0-9 → 52-61
    cmp     al, '0'
    jb      .dc_plus
    cmp     al, '9'
    ja      .dc_plus
    sub     al, '0'
    add     al, 52
    ret

.dc_plus:
    ; + → 62
    cmp     al, '+'
    jne     .dc_slash
    mov     eax, 62
    ret

.dc_slash:
    ; / → 63
    cmp     al, '/'
    jne     .dc_pad
    mov     eax, 63
    ret

.dc_pad:
    ; = → padding (-1)
    cmp     al, '='
    jne     .dc_invalid
    mov     rax, -1
    ret

.dc_invalid:
    mov     rax, STR_ERR_PARSE
    ret

; -----------------------------------------------------------------------------
; str_base64_encode_url — URL-safe Base64 (no padding)
; str_base64_decode_url — URL-safe Base64 decode
; -----------------------------------------------------------------------------

STR_FUNC str_base64_encode_url

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, r8

    lea     r9, [rel _b64_url_enc]  ; use URL alphabet

    xor     r10, r10            ; src index
    xor     r11, r11            ; dst index

.b64u_loop:
    mov     rax, r12
    sub     rax, r10
    cmp     rax, 3
    jb      .b64u_partial

    movzx   eax, byte [rbx + r10]
    movzx   ecx, byte [rbx + r10 + 1]
    movzx   edx, byte [rbx + r10 + 2]

    mov     r8d, eax
    shr     r8d, 2
    movzx   r8d, byte [r9 + r8]
    mov     [r13 + r11], r8b
    inc     r11

    mov     r8d, eax
    and     r8d, 0x03
    shl     r8d, 4
    push    rdx
    mov     edx, ecx
    shr     edx, 4
    or      r8d, edx
    pop     rdx
    movzx   r8d, byte [r9 + r8]
    mov     [r13 + r11], r8b
    inc     r11

    mov     r8d, ecx
    and     r8d, 0x0F
    shl     r8d, 2
    push    rcx
    mov     ecx, edx
    shr     ecx, 6
    or      r8d, ecx
    pop     rcx
    movzx   r8d, byte [r9 + r8]
    mov     [r13 + r11], r8b
    inc     r11

    mov     r8d, edx
    and     r8d, 0x3F
    movzx   r8d, byte [r9 + r8]
    mov     [r13 + r11], r8b
    inc     r11

    add     r10, 3
    jmp     .b64u_loop

.b64u_partial:
    mov     rax, r12
    sub     rax, r10
    test    rax, rax
    jz      .b64u_done

    xor     ecx, ecx
    movzx   eax, byte [rbx + r10]
    cmp     rax, 2
    jb      .b64u_one

    movzx   ecx, byte [rbx + r10 + 1]

.b64u_one:
    ; encode 2 or 3 output chars (NO padding)
    mov     r8d, eax
    shr     r8d, 2
    movzx   r8d, byte [r9 + r8]
    mov     [r13 + r11], r8b
    inc     r11

    mov     r8d, eax
    and     r8d, 0x03
    shl     r8d, 4
    mov     edx, ecx
    shr     edx, 4
    or      r8d, edx
    movzx   r8d, byte [r9 + r8]
    mov     [r13 + r11], r8b
    inc     r11

    mov     rax, r12
    sub     rax, r10
    cmp     rax, 1
    je      .b64u_done          ; only 1 byte, stop here (no 3rd char)

    ; 2 bytes: emit 3rd char
    mov     r8d, ecx
    and     r8d, 0x0F
    shl     r8d, 2
    movzx   r8d, byte [r9 + r8]
    mov     [r13 + r11], r8b
    inc     r11

.b64u_done:
    test    r15, r15
    jz      .b64u_ok
    mov     [r15], r11

.b64u_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_base64_encode_url
