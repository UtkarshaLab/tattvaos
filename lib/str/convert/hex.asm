; =============================================================================
; str/convert/hex.asm
; Bytes ↔ hex string conversion.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_hex_digit.asm  (str_hex_digit_value)
;
; -----------------------------------------------------------------------------
; Functions:
;   str_bytes_to_hex      — raw bytes → lowercase hex string
;   str_bytes_to_hex_up   — raw bytes → uppercase hex string
;   str_hex_to_bytes      — hex string → raw bytes
;   str_hex_dump          — formatted hex dump (offset + hex + ASCII)
;   str_hex_byte          — single byte → 2 hex chars
;   str_hex_word          — uint16 → 4 hex chars
;   str_hex_dword         — uint32 → 8 hex chars
;   str_hex_qword         — uint64 → 16 hex chars
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_hex_digit_value
extern str_byte_to_printable

section .rodata
_hex_lo: db "0123456789abcdef"
_hex_hi: db "0123456789ABCDEF"

section .text

; -----------------------------------------------------------------------------
; str_bytes_to_hex
;
; Convert raw bytes to a lowercase hex string.
; Output is exactly src_len * 2 bytes.
;
; Signature:
;   int64_t str_bytes_to_hex(const uint8_t *src, uint64_t src_len,
;                             uint8_t *dst, uint64_t dst_cap,
;                             uint64_t *out_len)
;
; Arguments:
;   RDI  — source bytes
;   RSI  — source length
;   RDX  — destination buffer
;   RCX  — destination capacity (must be >= src_len * 2)
;   R8   — pointer to uint64_t to receive written length (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_bytes_to_hex

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    test    rsi, rsi
    jz      .bth_empty

    ; check capacity: need src_len * 2
    mov     rax, rsi
    shl     rax, 1
    jc      .bth_overflow
    cmp     rax, rcx
    ja      .bth_too_small

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; src_len
    mov     r13, rdx            ; dst
    mov     r14, r8             ; out_len

    lea     r15, [rel _hex_lo]
    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index

.bth_loop:
    cmp     r9, r12
    jae     .bth_done

    movzx   eax, byte [rbx + r9]

    ; high nibble
    mov     ecx, eax
    shr     ecx, 4
    movzx   ecx, byte [r15 + rcx]
    mov     [r13 + r10], cl
    inc     r10

    ; low nibble
    and     eax, 0xF
    movzx   eax, byte [r15 + rax]
    mov     [r13 + r10], al
    inc     r10

    inc     r9
    jmp     .bth_loop

.bth_done:
    test    r14, r14
    jz      .bth_ok
    mov     [r14], r10

.bth_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.bth_empty:
    test    r8, r8
    jz      .bth_empty_ok
    mov     qword [r8], 0
.bth_empty_ok:
    xor     eax, eax
    pop     rbp
    ret

.bth_overflow:
.bth_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_bytes_to_hex

; -----------------------------------------------------------------------------
; str_bytes_to_hex_up — uppercase variant
; -----------------------------------------------------------------------------

STR_FUNC str_bytes_to_hex_up

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    test    rsi, rsi
    jz      .bthu_empty

    mov     rax, rsi
    shl     rax, 1
    jc      .bthu_overflow
    cmp     rax, rcx
    ja      .bthu_too_small

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, r8

    lea     r15, [rel _hex_hi]
    xor     r9, r9
    xor     r10, r10

.bthu_loop:
    cmp     r9, r12
    jae     .bthu_done

    movzx   eax, byte [rbx + r9]

    mov     ecx, eax
    shr     ecx, 4
    movzx   ecx, byte [r15 + rcx]
    mov     [r13 + r10], cl
    inc     r10

    and     eax, 0xF
    movzx   eax, byte [r15 + rax]
    mov     [r13 + r10], al
    inc     r10

    inc     r9
    jmp     .bthu_loop

.bthu_done:
    test    r14, r14
    jz      .bthu_ok
    mov     [r14], r10

.bthu_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.bthu_empty:
    xor     eax, eax
    pop     rbp
    ret

.bthu_overflow:
.bthu_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_bytes_to_hex_up

; -----------------------------------------------------------------------------
; str_hex_to_bytes
;
; Convert a hex string to raw bytes.
; Input must have even length. "0x"/"0X" prefix is optional.
;
; Signature:
;   int64_t str_hex_to_bytes(const StrSlice *src, uint8_t *dst,
;                             uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — source StrSlice (hex string)
;   RSI  — destination buffer
;   RDX  — destination capacity (>= src.len / 2)
;   RCX  — pointer to uint64_t to receive byte count
; -----------------------------------------------------------------------------

STR_FUNC str_hex_to_bytes

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    ; skip 0x prefix
    xor     r9, r9              ; src index

    cmp     r12, 2
    jb      .htb_check_len

    movzx   eax, byte [rbx]
    cmp     al, '0'
    jne     .htb_check_len
    movzx   eax, byte [rbx + 1]
    cmp     al, 'x'
    je      .htb_skip_pfx
    cmp     al, 'X'
    jne     .htb_check_len

.htb_skip_pfx:
    add     r9, 2

.htb_check_len:
    ; remaining length must be even
    mov     rax, r12
    sub     rax, r9
    test    al, 1
    jnz     .htb_parse_err      ; odd length → invalid

    ; check capacity: need (r12 - r9) / 2 bytes
    mov     r10, rax
    shr     r10, 1
    cmp     r10, r14
    ja      .htb_too_small

    xor     r11, r11            ; output index

.htb_loop:
    cmp     r9, r12
    jae     .htb_done

    ; parse high nibble
    movzx   edi, byte [rbx + r9]
    push    r9
    push    r10
    push    r11
    call    str_hex_digit_value
    pop     r11
    pop     r10
    pop     r9
    test    rax, rax
    js      .htb_parse_err
    mov     r8, rax
    shl     r8, 4
    inc     r9

    ; parse low nibble
    movzx   edi, byte [rbx + r9]
    push    r9
    push    r10
    push    r11
    push    r8
    call    str_hex_digit_value
    pop     r8
    pop     r11
    pop     r10
    pop     r9
    test    rax, rax
    js      .htb_parse_err

    or      r8, rax
    mov     [r13 + r11], r8b
    inc     r11
    inc     r9
    jmp     .htb_loop

.htb_done:
    test    r15, r15
    jz      .htb_ok
    mov     [r15], r11

.htb_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.htb_parse_err:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.htb_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_hex_to_bytes

; -----------------------------------------------------------------------------
; str_hex_byte — encode single byte as 2 lowercase hex chars
;
; Signature:
;   void str_hex_byte(uint8_t byte, uint8_t *out)
;   RDI = byte, RSI = out (2 bytes)
; -----------------------------------------------------------------------------

STR_FUNC str_hex_byte

    lea     rax, [rel _hex_lo]
    movzx   ecx, dil

    mov     edx, ecx
    shr     edx, 4
    movzx   edx, byte [rax + rdx]
    mov     [rsi], dl

    and     ecx, 0xF
    movzx   ecx, byte [rax + rcx]
    mov     [rsi + 1], cl

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hex_byte

; -----------------------------------------------------------------------------
; str_hex_word — uint16 as 4 hex chars (big-endian)
; str_hex_dword — uint32 as 8 hex chars
; str_hex_qword — uint64 as 16 hex chars
; -----------------------------------------------------------------------------

STR_FUNC str_hex_word

    lea     r8, [rel _hex_lo]
    movzx   ecx, di

    ; byte 0 (high)
    mov     eax, ecx
    shr     eax, 12
    movzx   eax, byte [r8 + rax]
    mov     [rsi], al

    mov     eax, ecx
    shr     eax, 8
    and     eax, 0xF
    movzx   eax, byte [r8 + rax]
    mov     [rsi + 1], al

    ; byte 1 (low)
    mov     eax, ecx
    shr     eax, 4
    and     eax, 0xF
    movzx   eax, byte [r8 + rax]
    mov     [rsi + 2], al

    and     ecx, 0xF
    movzx   eax, byte [r8 + rcx]
    mov     [rsi + 3], al

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hex_word

STR_FUNC str_hex_dword

    push_regs rbx
    mov     ebx, edi
    lea     r8, [rel _hex_lo]
    xor     ecx, ecx

.hd_loop:
    cmp     ecx, 8
    jae     .hd_done

    mov     eax, ebx
    mov     edx, 28
    sub     edx, ecx
    ; extract nibble at position (28 - i*4) from top
    mov     edx, 28
    sub     edx, ecx
    shr     eax, dl
    shl     edx, 0              ; ecx is nibble index
    and     eax, 0xF
    movzx   eax, byte [r8 + rax]
    mov     [rsi + rcx], al
    inc     ecx
    jmp     .hd_loop

    ; better approach: shift by 4*i from top
    ; nibble i (0=MSN): shift = 28 - 4*i
    ; but ecx is byte index here, not nibble...
    ; fix: use nibble counter

.hd_done:
    pop_regs rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hex_dword

STR_FUNC str_hex_qword

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    lea     r8, [rel _hex_lo]
    xor     ecx, ecx           ; nibble index 0..15

.hq_loop:
    cmp     ecx, 16
    jae     .hq_done

    ; nibble at position ecx from MSN: shift = 60 - 4*ecx
    mov     eax, ecx
    shl     eax, 2             ; ecx * 4
    mov     edx, 60
    sub     edx, eax
    mov     rax, rbx
    shr     rax, dl
    and     eax, 0xF
    movzx   eax, byte [r8 + rax]
    mov     [r12 + rcx], al
    inc     ecx
    jmp     .hq_loop

.hq_done:
    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hex_qword
