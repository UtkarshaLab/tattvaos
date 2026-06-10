; =============================================================================
; str/format/fmt.asm
; Main printf-style format engine.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   format/itoa.asm    (str_itoa_i64, str_itoa_u64, str_itoa_hex,
;                        str_itoa_hex_up, str_itoa_oct, str_itoa_bin)
;   format/dtoa.asm    (str_dtoa)
;   format/padding.asm (str_pad_to_width, FMT_FLAG_*)
;   core/copy.asm      (str_copy_bytes)
;   utf8/encode.asm    (str_utf8_encode_unchecked)
;
; -----------------------------------------------------------------------------
; Format specifiers supported:
;
;   %d, %i   — signed decimal integer (int64)
;   %u       — unsigned decimal integer (uint64)
;   %x       — unsigned hex lowercase
;   %X       — unsigned hex uppercase
;   %o       — unsigned octal
;   %b       — unsigned binary (extension)
;   %f       — floating point fixed notation
;   %e, %E   — floating point scientific
;   %g, %G   — floating point shortest
;   %s       — UTF-8 string (StrSlice* or char*)
;   %c       — Unicode codepoint (uint32)
;   %p       — pointer (hex with 0x prefix)
;   %%       — literal percent
;
; Flags:
;   -        — left-align
;   +        — always show sign
;   (space)  — space before positive
;   0        — zero-pad
;   #        — alternate form (0x prefix for hex, 0 for oct)
;
; Width and precision:
;   %10d     — minimum width 10
;   %-10d    — left-aligned, width 10
;   %010d    — zero-padded, width 10
;   %.5f     — 5 decimal places
;   %10.5f   — width 10, 5 decimal places
;   %*d      — width from argument
;   %.*f     — precision from argument
;
; Calling convention for fmt:
;   Arguments passed on the stack in order after format string.
;   Use the str_fmt_arg_* macros to push arguments.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_itoa_i64
extern str_itoa_u64
extern str_itoa_hex
extern str_itoa_hex_up
extern str_itoa_oct
extern str_itoa_bin
extern str_dtoa
extern str_copy_bytes
extern str_utf8_encode_unchecked
extern str_pad_to_width

; Internal buffer for formatting a single value
FMT_VAL_BUF  equ 128

section .text

; -----------------------------------------------------------------------------
; str_fmt_write_str  (internal helper)
;
; Write a C string (null-terminated) or StrSlice* to output buffer.
; Handles width and left-align flags.
;
; RDI = str ptr (char* or StrSlice*)
; RSI = is_slice (1 = StrSlice*, 0 = char*)
; RDX = width, RCX = flags, R8 = dst, R9 = dst remaining, R10 = dst written
; Returns: bytes written in RAX, or negative error
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; str_fmt
;
; Format a string according to a format specification.
; NOTE: This is a simplified variadic implementation using a va_list style
; array of uint64_t arguments passed as a pointer.
;
; Signature:
;   int64_t str_fmt(const char *fmt, const uint64_t *args, uint64_t arg_count,
;                   uint8_t *dst, uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — format string (null-terminated)
;   RSI  — pointer to argument array (uint64_t[])
;   RDX  — number of arguments
;   RCX  — destination buffer
;   R8   — destination capacity
;   R9   — pointer to uint64_t for bytes written (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          fmt or dst is null
;   RAX  = STR_ERR_BUF_TOO_SMALL output buffer too small
;   RAX  = STR_ERR_INVALID_FORMAT malformed format string
; -----------------------------------------------------------------------------

STR_FUNC str_fmt

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; fmt string
    mov     r12, rsi            ; args array
    mov     r13, rdx            ; arg count
    mov     r14, rcx            ; dst
    mov     r15, r8             ; dst_cap
    push    r9                  ; out_len

    xor     r9, r9              ; arg index
    xor     r10, r10            ; dst write offset

.fmt_loop:
    movzx   eax, byte [rbx]
    test    al, al
    jz      .fmt_done           ; end of format string

    cmp     al, '%'
    jne     .fmt_literal

    ; format specifier
    inc     rbx

    ; --- parse flags ---
    xor     r11d, r11d          ; flags = 0

.fmt_flags:
    movzx   eax, byte [rbx]

    cmp     al, '-'
    jne     .fmt_flag_plus
    or      r11d, FMT_FLAG_LEFT
    inc     rbx
    jmp     .fmt_flags

.fmt_flag_plus:
    cmp     al, '+'
    jne     .fmt_flag_space
    or      r11d, FMT_FLAG_PLUS
    inc     rbx
    jmp     .fmt_flags

.fmt_flag_space:
    cmp     al, ' '
    jne     .fmt_flag_zero
    or      r11d, FMT_FLAG_SPACE
    inc     rbx
    jmp     .fmt_flags

.fmt_flag_zero:
    cmp     al, '0'
    jne     .fmt_flag_hash
    or      r11d, FMT_FLAG_ZERO
    inc     rbx
    jmp     .fmt_flags

.fmt_flag_hash:
    cmp     al, '#'
    jne     .fmt_done_flags
    or      r11d, FMT_FLAG_HASH
    inc     rbx
    jmp     .fmt_flags

.fmt_done_flags:
    ; --- parse width ---
    xor     ecx, ecx            ; width = 0

    movzx   eax, byte [rbx]
    cmp     al, '*'
    jne     .fmt_width_digits

    ; width from args
    cmp     r9, r13
    jae     .fmt_bad
    mov     rcx, [r12 + r9 * 8]
    inc     r9
    inc     rbx
    jmp     .fmt_done_width

.fmt_width_digits:
.fmt_width_loop:
    movzx   eax, byte [rbx]
    sub     eax, '0'
    cmp     eax, 9
    ja      .fmt_done_width

    imul    ecx, ecx, 10
    add     ecx, eax
    inc     rbx
    jmp     .fmt_width_loop

.fmt_done_width:
    mov     rcx, rcx            ; width in rcx

    ; --- parse precision ---
    xor     r8d, r8d            ; precision = -1 (default)
    dec     r8                  ; r8 = -1

    movzx   eax, byte [rbx]
    cmp     al, '.'
    jne     .fmt_done_prec

    inc     rbx
    xor     r8d, r8d            ; precision starts at 0

    movzx   eax, byte [rbx]
    cmp     al, '*'
    jne     .fmt_prec_digits

    cmp     r9, r13
    jae     .fmt_bad
    mov     r8, [r12 + r9 * 8]
    inc     r9
    inc     rbx
    jmp     .fmt_done_prec

.fmt_prec_digits:
.fmt_prec_loop:
    movzx   eax, byte [rbx]
    sub     eax, '0'
    cmp     eax, 9
    ja      .fmt_done_prec

    imul    r8d, r8d, 10
    add     r8d, eax
    inc     rbx
    jmp     .fmt_prec_loop

.fmt_done_prec:
    ; --- length modifiers (skip: we always use 64-bit) ---
    movzx   eax, byte [rbx]
    cmp     al, 'l'
    je      .fmt_skip_mod
    cmp     al, 'h'
    je      .fmt_skip_mod
    cmp     al, 'z'
    jne     .fmt_specifier
.fmt_skip_mod:
    inc     rbx
    movzx   eax, byte [rbx]
    cmp     al, 'l'
    jne     .fmt_specifier
    inc     rbx
    jmp     .fmt_specifier

.fmt_specifier:
    movzx   eax, byte [rbx]
    inc     rbx

    ; allocate temp value buffer
    sub     rsp, FMT_VAL_BUF
    and     rsp, -16

    cmp     al, '%'
    je      .fmt_percent

    cmp     al, 'd'
    je      .fmt_signed
    cmp     al, 'i'
    je      .fmt_signed

    cmp     al, 'u'
    je      .fmt_unsigned

    cmp     al, 'x'
    je      .fmt_hex_lo
    cmp     al, 'X'
    je      .fmt_hex_hi

    cmp     al, 'o'
    je      .fmt_octal

    cmp     al, 'b'
    je      .fmt_binary

    cmp     al, 'f'
    je      .fmt_float_fixed
    cmp     al, 'e'
    je      .fmt_float_sci
    cmp     al, 'E'
    je      .fmt_float_sci
    cmp     al, 'g'
    je      .fmt_float_short
    cmp     al, 'G'
    je      .fmt_float_short

    cmp     al, 's'
    je      .fmt_string

    cmp     al, 'c'
    je      .fmt_char

    cmp     al, 'p'
    je      .fmt_pointer

    jmp     .fmt_bad_spec

; --- %% ---
.fmt_percent:
    mov     rsp, rbp
    sub     rsp, 0
    ; just write one '%'
    cmp     r10, r15
    jae     .fmt_out_overflow
    mov     byte [r14 + r10], '%'
    inc     r10
    jmp     .fmt_next_spec

; --- %d / %i ---
.fmt_signed:
    cmp     r9, r13
    jae     .fmt_bad

    mov     rdi, [r12 + r9 * 8]    ; signed value
    inc     r9
    mov     rsi, rcx               ; width
    movzx   edx, r11b              ; flags
    mov     cl, ' '
    test    r11d, FMT_FLAG_ZERO
    jz      .fmt_si_fill
    mov     cl, '0'
.fmt_si_fill:
    mov     r8, rsp                ; temp buf
    mov     r9d, FMT_VAL_BUF
    push    r9
    push    qword 0               ; out_len (discard)
    call    str_itoa_i64
    add     rsp, 16
    mov     r9, [rsp + FMT_VAL_BUF - 8]    ; bytes written
    jmp     .fmt_write_val

; --- %u ---
.fmt_unsigned:
    cmp     r9, r13
    jae     .fmt_bad

    mov     rdi, [r12 + r9 * 8]
    inc     r9
    mov     rsi, rcx
    movzx   edx, r11b
    mov     cl, ' '
    test    r11d, FMT_FLAG_ZERO
    jz      .fmt_ui_fill
    mov     cl, '0'
.fmt_ui_fill:
    mov     r8, rsp
    mov     r9d, FMT_VAL_BUF
    push    r9
    push    qword 0
    call    str_itoa_u64
    add     rsp, 16
    mov     r9, [rsp + FMT_VAL_BUF - 8]
    jmp     .fmt_write_val

; --- %x ---
.fmt_hex_lo:
    cmp     r9, r13
    jae     .fmt_bad

    mov     rdi, [r12 + r9 * 8]
    inc     r9
    mov     rsi, rcx
    movzx   edx, r11b
    mov     cl, ' '
    test    r11d, FMT_FLAG_ZERO
    jz      .fmt_xl_fill
    mov     cl, '0'
.fmt_xl_fill:
    mov     r8, rsp
    mov     r9d, FMT_VAL_BUF
    push    r9
    push    qword 0
    call    str_itoa_hex
    add     rsp, 16
    mov     r9, [rsp + FMT_VAL_BUF - 8]
    jmp     .fmt_write_val

; --- %X ---
.fmt_hex_hi:
    cmp     r9, r13
    jae     .fmt_bad

    mov     rdi, [r12 + r9 * 8]
    inc     r9
    mov     rsi, rcx
    movzx   edx, r11b
    mov     cl, ' '
    mov     r8, rsp
    mov     r9d, FMT_VAL_BUF
    push    r9
    push    qword 0
    call    str_itoa_hex_up
    add     rsp, 16
    mov     r9, [rsp + FMT_VAL_BUF - 8]
    jmp     .fmt_write_val

; --- %o ---
.fmt_octal:
    cmp     r9, r13
    jae     .fmt_bad

    mov     rdi, [r12 + r9 * 8]
    inc     r9
    mov     rsi, rcx
    movzx   edx, r11b
    mov     cl, ' '
    mov     r8, rsp
    mov     r9d, FMT_VAL_BUF
    push    r9
    push    qword 0
    call    str_itoa_oct
    add     rsp, 16
    mov     r9, [rsp + FMT_VAL_BUF - 8]
    jmp     .fmt_write_val

; --- %b ---
.fmt_binary:
    cmp     r9, r13
    jae     .fmt_bad

    mov     rdi, [r12 + r9 * 8]
    inc     r9
    mov     rsi, rcx
    movzx   edx, r11b
    mov     cl, ' '
    mov     r8, rsp
    mov     r9d, FMT_VAL_BUF
    push    r9
    push    qword 0
    call    str_itoa_bin
    add     rsp, 16
    mov     r9, [rsp + FMT_VAL_BUF - 8]
    jmp     .fmt_write_val

; --- %f / %e / %g ---
.fmt_float_fixed:
.fmt_float_sci:
.fmt_float_short:
    cmp     r9, r13
    jae     .fmt_bad

    ; load double from args (passed as raw bits)
    mov     rax, [r12 + r9 * 8]
    movq    xmm0, rax
    inc     r9

    mov     rdi, rsp
    mov     rsi, FMT_VAL_BUF
    lea     rdx, [rsp + FMT_VAL_BUF - 8]
    call    str_dtoa
    mov     r9, [rsp + FMT_VAL_BUF - 8]
    jmp     .fmt_write_val

; --- %s ---
.fmt_string:
    cmp     r9, r13
    jae     .fmt_bad

    mov     rdi, [r12 + r9 * 8]    ; char* or StrSlice*
    inc     r9

    test    rdi, rdi
    jz      .fmt_null_str

    ; check if it looks like a StrSlice (treat as char* for simplicity)
    ; For proper StrSlice support, caller should use %S extension
    ; Here we treat as null-terminated char*

    ; compute length
    mov     rsi, rdi
    xor     ecx, ecx
.fmt_str_len:
    cmp     byte [rsi], 0
    je      .fmt_str_len_done
    inc     rsi
    inc     ecx
    jmp     .fmt_str_len

.fmt_str_len_done:
    ; apply precision (max chars to print)
    cmp     r8, -1
    je      .fmt_str_no_prec
    cmp     rcx, r8
    jbe     .fmt_str_no_prec
    mov     ecx, r8d

.fmt_str_no_prec:
    ; copy to temp buf
    push    rcx
    mov     rsi, rdi
    mov     rdi, rsp
    add     rdi, 8
    mov     rdx, rcx
    call    str_copy_bytes
    pop     r9                  ; r9 = len

    ; temp buf is at rsp+8
    lea     rdi, [rsp + 8]
    jmp     .fmt_write_from_rdi

.fmt_null_str:
    ; write "(null)"
    lea     rdi, [rel .null_str]
    mov     r9, 6
    jmp     .fmt_write_from_rdi

; --- %c ---
.fmt_char:
    cmp     r9, r13
    jae     .fmt_bad

    mov     edi, dword [r12 + r9 * 8]   ; codepoint (low 32 bits)
    inc     r9

    ; encode codepoint to temp buf
    mov     rsi, rsp
    call    str_utf8_encode_unchecked
    ; rax = bytes written
    mov     r9, rax
    mov     rdi, rsp
    jmp     .fmt_write_from_rdi

; --- %p ---
.fmt_pointer:
    cmp     r9, r13
    jae     .fmt_bad

    mov     rdi, [r12 + r9 * 8]
    inc     r9
    ; format as hex with 0x prefix, width=16 zero-padded
    mov     rsi, 16
    movzx   edx, r11b
    or      edx, FMT_FLAG_HASH | FMT_FLAG_ZERO
    mov     cl, '0'
    mov     r8, rsp
    mov     r9d, FMT_VAL_BUF
    push    r9
    push    qword 0
    call    str_itoa_hex
    add     rsp, 16
    mov     r9, [rsp + FMT_VAL_BUF - 8]
    jmp     .fmt_write_val

.fmt_write_val:
    ; value is at rsp, length in r9 — apply width padding and write to dst
    mov     rdi, rsp

.fmt_write_from_rdi:
    ; rdi = value ptr, r9 = value len, rcx = width, r11d = flags
    ; copy to dst directly (simplified — no padding for now)
    ; TODO: apply width/padding via str_pad_to_width

    ; check space
    mov     rax, r10
    add     rax, r9
    cmp     rax, r15
    ja      .fmt_out_overflow

    ; copy
    push    r9
    mov     rsi, rdi
    mov     rdi, r14
    add     rdi, r10
    mov     rdx, r9
    call    str_copy_bytes
    pop     r9

    add     r10, r9

.fmt_next_spec:
    mov     rsp, rbp
    sub     rsp, 0
    jmp     .fmt_loop

; --- literal character ---
.fmt_literal:
    cmp     r10, r15
    jae     .fmt_out_overflow

    mov     [r14 + r10], al
    inc     r10
    inc     rbx
    jmp     .fmt_loop

.fmt_done:
    pop     r9                  ; out_len
    test    r9, r9
    jz      .fmt_ok
    mov     [r9], r10

.fmt_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.fmt_bad:
.fmt_bad_spec:
    mov     rsp, rbp
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_FORMAT
    pop     rbp
    ret

.fmt_out_overflow:
    mov     rsp, rbp
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

section .rodata
.null_str: db "(null)"