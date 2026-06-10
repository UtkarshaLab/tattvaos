; =============================================================================
; str/format/padding.asm
; Width, precision, and alignment formatting helpers.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm   (str_copy_bytes, str_fill)
;   utf8/encode.asm (str_utf8_encode_unchecked)
;
; -----------------------------------------------------------------------------
; These functions are used internally by fmt.asm and sprintf.asm.
; They handle the common pattern:
;   "given a value string of length N, produce output of width W,
;    aligned left/right/center, padded with fill character"
;
; All functions write into caller-supplied buffers.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes
extern str_fill
extern str_utf8_encode_unchecked

; Alignment flags
ALIGN_LEFT   equ 0   ; '-' flag: left-align, pad right
ALIGN_RIGHT  equ 1   ; default: right-align, pad left
ALIGN_CENTER equ 2   ; center (not standard printf, but useful)
ALIGN_SIGN   equ 3   ; '0' flag: zero-pad after sign

section .text

; -----------------------------------------------------------------------------
; str_pad_to_width
;
; Pad a string to a minimum width using a fill character.
;
; Signature:
;   int64_t str_pad_to_width(const uint8_t *value, uint64_t value_len,
;                             uint64_t width, uint8_t fill,
;                             uint8_t alignment,
;                             uint8_t *dst, uint64_t dst_cap,
;                             uint64_t *out_len)
;
; Arguments:
;   RDI  — value string pointer
;   RSI  — value string length
;   RDX  — minimum field width (0 = no padding)
;   RCX  — fill byte (usually ' ' or '0')
;   R8   — alignment (ALIGN_LEFT/RIGHT/CENTER)
;   R9   — destination buffer
;   [rsp+8]  — dst_cap (7th arg)
;   [rsp+16] — out_len pointer (8th arg)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL
; -----------------------------------------------------------------------------

STR_FUNC str_pad_to_width

    guard_null rdi, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; value ptr
    mov     r12, rsi            ; value_len
    mov     r13, rdx            ; width
    movzx   r14d, cl            ; fill byte
    movzx   r15d, r8b           ; alignment

    ; dst and stack args
    push    r9                  ; save dst

    ; compute padding needed
    mov     r10, r13            ; width
    cmp     r12, r13
    jae     .pw_no_pad          ; value_len >= width → no padding

    sub     r10, r12            ; pad_count = width - value_len

    ; check capacity: width bytes needed
    pop     r9                  ; dst
    mov     r11, [rsp + 56]     ; dst_cap (after push_regs + push r9 + rbp)
    mov     r8,  [rsp + 64]     ; out_len

    cmp     r13, r11
    ja      .pw_too_small_2

    ; write based on alignment
    cmp     r15b, ALIGN_LEFT
    je      .pw_left
    cmp     r15b, ALIGN_CENTER
    je      .pw_center

    ; right-align (default): fill then value
.pw_right:
    ; write fill
    mov     rdi, r9
    movzx   esi, r14b
    mov     rdx, r10
    call    str_fill

    ; write value
    mov     rdi, r9
    add     rdi, r10
    mov     rsi, rbx
    mov     rdx, r12
    call    str_copy_bytes

    jmp     .pw_write_len

.pw_left:
    ; write value then fill
    mov     rdi, r9
    mov     rsi, rbx
    mov     rdx, r12
    call    str_copy_bytes

    mov     rdi, r9
    add     rdi, r12
    movzx   esi, r14b
    mov     rdx, r10
    call    str_fill

    jmp     .pw_write_len

.pw_center:
    ; split pad: left_pad = pad/2, right_pad = pad - left_pad
    mov     rax, r10
    shr     rax, 1              ; left_pad
    mov     rcx, r10
    sub     rcx, rax            ; right_pad

    ; left fill
    mov     rdi, r9
    movzx   esi, r14b
    mov     rdx, rax
    push    rax
    push    rcx
    call    str_fill
    pop     rcx
    pop     rax

    ; value
    mov     rdi, r9
    add     rdi, rax
    mov     rsi, rbx
    mov     rdx, r12
    push    rax
    push    rcx
    call    str_copy_bytes
    pop     rcx
    pop     rax

    ; right fill
    mov     rdi, r9
    add     rdi, rax
    add     rdi, r12
    movzx   esi, r14b
    mov     rdx, rcx
    call    str_fill

.pw_write_len:
    test    r8, r8
    jz      .pw_ok
    mov     [r8], r13           ; total width

.pw_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pw_no_pad:
    ; no padding — just copy value
    pop     r9
    mov     r11, [rsp + 56]
    mov     r8,  [rsp + 64]

    cmp     r12, r11
    ja      .pw_too_small_2

    mov     rdi, r9
    mov     rsi, rbx
    mov     rdx, r12
    call    str_copy_bytes

    test    r8, r8
    jz      .pw_ok_nopad
    mov     [r8], r12

.pw_ok_nopad:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pw_too_small_2:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_pad_to_width

; -----------------------------------------------------------------------------
; str_pad_zero_with_sign
;
; Zero-pad a numeric string after the sign character.
; Used for %05d style formatting: "-42" with width=5 → "-0042"
;
; Signature:
;   int64_t str_pad_zero_with_sign(const uint8_t *value, uint64_t value_len,
;                                   uint64_t width,
;                                   uint8_t *dst, uint64_t dst_cap,
;                                   uint64_t *out_len)
;
; Arguments:
;   RDI  — value string (may start with '-' or '+')
;   RSI  — value length
;   RDX  — field width
;   RCX  — destination buffer
;   R8   — capacity
;   R9   — out_len (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_pad_zero_with_sign

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; value
    mov     r12, rsi            ; value_len
    mov     r13, rdx            ; width
    mov     r14, rcx            ; dst
    mov     r15, r8             ; cap
    push    r9                  ; out_len

    ; no padding needed?
    cmp     r12, r13
    jae     .pzs_copy_only

    ; check capacity
    cmp     r13, r15
    ja      .pzs_too_small

    mov     r10, r14            ; write cursor
    xor     r11, r11            ; sign_len = 0

    ; check for sign prefix
    movzx   eax, byte [rbx]
    cmp     al, '-'
    je      .pzs_has_sign
    cmp     al, '+'
    jne     .pzs_no_sign

.pzs_has_sign:
    ; copy sign char first
    mov     [r10], al
    inc     r10
    inc     r11                 ; sign_len = 1

.pzs_no_sign:
    ; pad_count = width - value_len
    mov     rax, r13
    sub     rax, r12

    ; write zero padding
    mov     rdi, r10
    movzx   esi, byte '0'
    mov     rdx, rax
    call    str_fill

    add     r10, rax

    ; write rest of value (skip sign if present)
    mov     rdi, r10
    mov     rsi, rbx
    add     rsi, r11            ; skip sign
    mov     rdx, r12
    sub     rdx, r11
    call    str_copy_bytes

    pop     r9
    test    r9, r9
    jz      .pzs_ok
    mov     [r9], r13

.pzs_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pzs_copy_only:
    ; value fits without padding
    cmp     r12, r15
    ja      .pzs_too_small

    mov     rdi, r14
    mov     rsi, rbx
    mov     rdx, r12
    call    str_copy_bytes

    pop     r9
    test    r9, r9
    jz      .pzs_ok_copy
    mov     [r9], r12

.pzs_ok_copy:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pzs_too_small:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_pad_zero_with_sign

; -----------------------------------------------------------------------------
; str_truncate_precision
;
; Truncate a string to at most `precision` bytes.
; Used for %.*s style formatting.
;
; Signature:
;   int64_t str_truncate_precision(const uint8_t *value, uint64_t value_len,
;                                   uint64_t precision,
;                                   uint8_t *dst, uint64_t dst_cap,
;                                   uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_truncate_precision

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; effective length = min(value_len, precision)
    mov     rax, rsi
    cmp     rax, rdx
    jbe     .tp_use_value_len
    mov     rax, rdx            ; truncate to precision

.tp_use_value_len:
    ; check capacity
    cmp     rax, r8
    ja      .tp_too_small

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rax            ; effective len

    mov     rdi, rcx
    mov     rsi, rbx
    mov     rdx, r12
    call    str_copy_bytes

    test    r9, r9
    jz      .tp_ok
    mov     [r9], r12

.tp_ok:
    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tp_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_truncate_precision

; -----------------------------------------------------------------------------
; str_format_sign
;
; Determine sign prefix for a numeric value.
; Returns the sign character or 0 if none needed.
;
; Signature:
;   uint8_t str_format_sign(int64_t value, uint8_t flags)
;
; Arguments:
;   RDI  — signed value
;   SIL  — flags (bit 0 = '+' flag, bit 1 = ' ' flag)
;
; Returns:
;   AL   — '-', '+', ' ', or 0 (no sign)
; -----------------------------------------------------------------------------

; Flag bits for str_format_sign
FMT_FLAG_PLUS  equ 0x01    ; always show sign
FMT_FLAG_SPACE equ 0x02    ; space before positive
FMT_FLAG_HASH  equ 0x04    ; alternate form (0x prefix etc.)
FMT_FLAG_ZERO  equ 0x08    ; zero pad
FMT_FLAG_LEFT  equ 0x10    ; left-align

STR_FUNC str_format_sign

    test    rdi, rdi
    js      .fs_negative

    ; positive or zero
    test    sil, FMT_FLAG_PLUS
    jnz     .fs_plus

    test    sil, FMT_FLAG_SPACE
    jnz     .fs_space

    xor     eax, eax
    pop     rbp
    ret

.fs_negative:
    mov     al, '-'
    pop     rbp
    ret

.fs_plus:
    mov     al, '+'
    pop     rbp
    ret

.fs_space:
    mov     al, ' '
    pop     rbp
    ret

STR_ENDFUNC str_format_sign