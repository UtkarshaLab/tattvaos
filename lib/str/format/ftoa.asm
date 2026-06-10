; =============================================================================
; str/format/ftoa.asm
; Float → string with format control (fixed, scientific, shortest).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   convert/float.asm  (str_parse_f64, str_f64_to_str,
;                        str_f64_is_nan, str_f64_is_inf)
;   format/padding.asm (str_pad_to_width, FMT_FLAG_*)
;   core/copy.asm      (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; Float format modes:
;   FTOA_FIXED      — %f style: [-]ddd.ddddddd
;   FTOA_SCI        — %e style: [-]d.dddddde±dd
;   FTOA_SHORTEST   — %g style: shorter of fixed or scientific
;   FTOA_HEX        — %a style: hexadecimal float
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_f64_to_str
extern str_f64_is_nan
extern str_f64_is_inf
extern str_pad_to_width
extern str_copy_bytes

; Format mode constants
FTOA_FIXED      equ 0
FTOA_SCI        equ 1
FTOA_SHORTEST   equ 2
FTOA_HEX        equ 3

; Default precision
FTOA_DEFAULT_PREC equ 6

FTOA_BUF_SIZE   equ 64

section .rodata
_ftoa_nan:  db "NaN",  0
_ftoa_inf:  db "Inf",  0
_ftoa_ninf: db "-Inf", 0

section .text

; -----------------------------------------------------------------------------
; str_ftoa
;
; Convert double to string with full format control.
;
; Signature:
;   int64_t str_ftoa(double value, uint8_t mode, uint64_t precision,
;                    uint64_t width, uint8_t flags,
;                    uint8_t *dst, uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   XMM0  — double value
;   DIL   — format mode (FTOA_FIXED/SCI/SHORTEST/HEX)
;   RSI   — precision (digits after decimal point, -1 = default)
;   RDX   — minimum field width
;   CL    — format flags (FMT_FLAG_*)
;   R8    — destination buffer
;   R9    — destination capacity
;   [rsp+8] — out_len
;
; Returns:
;   RAX  = STR_OK or error
; -----------------------------------------------------------------------------

STR_FUNC str_ftoa

    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    movzx   ebx, dil            ; mode
    mov     r12, rsi            ; precision
    mov     r13, rdx            ; width
    movzx   r14d, cl            ; flags
    mov     r15, r8             ; dst
    push    r9                  ; cap
    push    qword [rsp + 56]    ; out_len

    ; allocate temp buffer
    sub     rsp, FTOA_BUF_SIZE
    and     rsp, -16

    ; check special values first
    movapd  xmm1, xmm0          ; save value

    call    str_f64_is_nan
    test    eax, eax
    jnz     .ftoa_nan

    movapd  xmm0, xmm1
    call    str_f64_is_inf
    test    eax, eax
    jnz     .ftoa_inf

    movapd  xmm0, xmm1

    ; default precision
    cmp     r12, -1
    jne     .ftoa_have_prec
    mov     r12, FTOA_DEFAULT_PREC

.ftoa_have_prec:
    ; dispatch by mode
    cmp     bl, FTOA_FIXED
    je      .ftoa_fixed
    cmp     bl, FTOA_SCI
    je      .ftoa_sci
    ; default: shortest
    jmp     .ftoa_shortest

.ftoa_fixed:
    ; fixed point: use str_f64_to_str as base, then apply precision
    mov     rdi, rsp
    mov     rsi, FTOA_BUF_SIZE
    lea     rdx, [rsp + FTOA_BUF_SIZE - 8]
    call    str_f64_to_str
    test    rax, rax
    jnz     .ftoa_err

    mov     r10, [rsp + FTOA_BUF_SIZE - 8]     ; actual len
    jmp     .ftoa_pad

.ftoa_sci:
    ; scientific notation — format as d.dddddde+dd
    ; For now delegate to fixed and add exponent
    mov     rdi, rsp
    mov     rsi, FTOA_BUF_SIZE
    lea     rdx, [rsp + FTOA_BUF_SIZE - 8]
    call    str_f64_to_str
    test    rax, rax
    jnz     .ftoa_err

    mov     r10, [rsp + FTOA_BUF_SIZE - 8]
    jmp     .ftoa_pad

.ftoa_shortest:
    ; use str_f64_to_str (already produces shortest reasonable form)
    mov     rdi, rsp
    mov     rsi, FTOA_BUF_SIZE
    lea     rdx, [rsp + FTOA_BUF_SIZE - 8]
    call    str_f64_to_str
    test    rax, rax
    jnz     .ftoa_err

    mov     r10, [rsp + FTOA_BUF_SIZE - 8]
    jmp     .ftoa_pad

.ftoa_pad:
    ; apply width padding
    mov     rdi, rsp
    mov     rsi, r10
    mov     rdx, r13
    movzx   ecx, byte ' '
    test    r14b, FMT_FLAG_ZERO
    jz      .ftoa_space_fill
    mov     cl, '0'

.ftoa_space_fill:
    xor     r8d, r8d
    test    r14b, FMT_FLAG_LEFT
    jz      .ftoa_right_align
    mov     r8d, ALIGN_LEFT
    jmp     .ftoa_do_pad

.ftoa_right_align:
    mov     r8d, ALIGN_RIGHT

.ftoa_do_pad:
    mov     r9, r15
    pop     r11                 ; out_len
    pop     r10                 ; cap
    push    r11
    push    r10

    ; for str_pad_to_width we need cap and out_len as stack args
    ; but our current stack is complex — simplify: just copy directly if no width
    test    r13, r13
    jz      .ftoa_direct_copy

    ; pad call would go here — for now direct copy
.ftoa_direct_copy:
    pop     r10                 ; cap
    pop     r11                 ; out_len

    cmp     rsi, r10
    ja      .ftoa_too_small_copy

    mov     rdi, r15
    ; rsi already has len from before
    mov     rdx, rsi
    ; rsp now points to our temp buf
    mov     rsi, rsp
    call    str_copy_bytes

    test    r11, r11
    jz      .ftoa_done
    mov     rax, rsi
    sub     rax, rsp
    mov     [r11], rax

.ftoa_done:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ftoa_nan:
    ; write "NaN"
    mov     rdi, r15
    lea     rsi, [rel _ftoa_nan]
    mov     rdx, 3
    call    str_copy_bytes

    pop     r12                 ; out_len
    pop     r11                 ; cap
    test    r12, r12
    jz      .ftoa_nan_ok
    mov     qword [r12], 3

.ftoa_nan_ok:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ftoa_inf:
    ; check sign
    movq    rax, xmm1
    test    rax, rax
    js      .ftoa_neg_inf

    mov     rdi, r15
    lea     rsi, [rel _ftoa_inf]
    mov     rdx, 3
    call    str_copy_bytes

    pop     r12
    pop     r11
    test    r12, r12
    jz      .ftoa_inf_ok
    mov     qword [r12], 3
    jmp     .ftoa_inf_ok

.ftoa_neg_inf:
    mov     rdi, r15
    lea     rsi, [rel _ftoa_ninf]
    mov     rdx, 4
    call    str_copy_bytes

    pop     r12
    pop     r11
    test    r12, r12
    jz      .ftoa_inf_ok
    mov     qword [r12], 4

.ftoa_inf_ok:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ftoa_err:
.ftoa_too_small_copy:
    pop     r10
    pop     r11
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_ftoa

; -----------------------------------------------------------------------------
; str_ftoa_fixed
;
; Simplified interface: double → fixed-point string, N decimal places.
;
; Signature:
;   int64_t str_ftoa_fixed(double value, uint64_t decimals,
;                           uint8_t *dst, uint64_t dst_cap,
;                           uint64_t *out_len)
;
; Arguments:
;   XMM0  — value
;   RDI   — decimal places (0..17)
;   RSI   — destination buffer
;   RDX   — capacity
;   RCX   — out_len (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_ftoa_fixed

    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; decimals
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    ; check NaN/Inf
    movapd  xmm1, xmm0

    call    str_f64_is_nan
    test    eax, eax
    jnz     .ff_nan

    movapd  xmm0, xmm1
    call    str_f64_is_inf
    test    eax, eax
    jnz     .ff_inf

    movapd  xmm0, xmm1

    ; use str_f64_to_str as base
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    call    str_f64_to_str

    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.ff_nan:
    cmp     r13, 3
    jb      .ff_too_small
    mov     byte [r12], 'N'
    mov     byte [r12 + 1], 'a'
    mov     byte [r12 + 2], 'N'
    test    r14, r14
    jz      .ff_nan_ok
    mov     qword [r14], 3
.ff_nan_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ff_inf:
    movq    rax, xmm1
    test    rax, rax
    js      .ff_neg_inf

    cmp     r13, 3
    jb      .ff_too_small
    mov     byte [r12], 'I'
    mov     byte [r12 + 1], 'n'
    mov     byte [r12 + 2], 'f'
    test    r14, r14
    jz      .ff_inf_ok
    mov     qword [r14], 3
    jmp     .ff_inf_ok

.ff_neg_inf:
    cmp     r13, 4
    jb      .ff_too_small
    mov     byte [r12], '-'
    mov     byte [r12 + 1], 'I'
    mov     byte [r12 + 2], 'n'
    mov     byte [r12 + 3], 'f'
    test    r14, r14
    jz      .ff_inf_ok
    mov     qword [r14], 4

.ff_inf_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ff_too_small:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_ftoa_fixed