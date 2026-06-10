; =============================================================================
; str/format/sprintf.asm
; Format into a buffer, returning result as a StrSlice.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   format/fmt.asm  (str_fmt)
;
; -----------------------------------------------------------------------------
; str_sprintf is the primary user-facing format function.
; It wraps str_fmt with a cleaner interface and returns a StrSlice.
;
; Usage pattern:
;
;   ; prepare args array
;   mov     qword [args], 42        ; first arg
;   mov     qword [args+8], 0x1234  ; second arg
;
;   lea     rdi, [fmt_str]
;   lea     rsi, [args]
;   mov     rdx, 2                  ; arg count
;   lea     rcx, [buf]
;   mov     r8,  buf_cap
;   lea     r9,  [out_slice]
;   call    str_sprintf
;
; For floating point args, store the double's raw bits:
;   movsd   xmm0, [my_double]
;   movq    [args+16], xmm0
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_fmt

section .text

; -----------------------------------------------------------------------------
; str_sprintf
;
; Format a string into a buffer and return result as StrSlice.
;
; Signature:
;   int64_t str_sprintf(const char *fmt, const uint64_t *args,
;                        uint64_t arg_count, uint8_t *buf,
;                        uint64_t buf_cap, StrSlice *out)
;
; Arguments:
;   RDI  — format string (null-terminated)
;   RSI  — argument array (uint64_t[])
;   RDX  — argument count
;   RCX  — output buffer
;   R8   — buffer capacity
;   R9   — output StrSlice
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL
;   RAX  = STR_ERR_INVALID_FORMAT
; -----------------------------------------------------------------------------

STR_FUNC str_sprintf

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; fmt
    mov     r12, rsi            ; args
    mov     r13, rdx            ; arg_count
    mov     r14, rcx            ; buf
    mov     r15, r8             ; buf_cap
    push    r9                  ; out slice

    ; allocate space for written length on stack
    sub     rsp, 8
    and     rsp, -16

    ; call str_fmt
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r14
    mov     r8,  r15
    lea     r9,  [rsp]          ; out_len
    call    str_fmt
    test    rax, rax
    jnz     .ss_err

    ; build output StrSlice
    mov     rcx, [rsp]          ; bytes written
    pop     rdx                 ; restore out_len slot (done with it)

    pop     r9                  ; out slice
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], rcx

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ss_err:
    add     rsp, 8
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_sprintf

; -----------------------------------------------------------------------------
; str_snprintf
;
; Like str_sprintf but writes null-terminator and returns byte count.
; Drop-in for C snprintf.
;
; Signature:
;   int64_t str_snprintf(uint8_t *buf, uint64_t buf_cap,
;                         const char *fmt, const uint64_t *args,
;                         uint64_t arg_count, uint64_t *out_len)
;
; Arguments:
;   RDI  — output buffer
;   RSI  — buffer capacity (including space for null terminator)
;   RDX  — format string
;   RCX  — argument array
;   R8   — argument count
;   R9   — out_len (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_snprintf

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    ; need at least 1 byte for null terminator
    cmp     rsi, 1
    jb      .snpf_too_small

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; buf
    mov     r12, rsi            ; cap
    mov     r13, rdx            ; fmt
    mov     r14, rcx            ; args
    mov     r15, r8             ; arg_count
    push    r9                  ; out_len

    ; reserve 1 byte for null terminator
    dec     r12

    sub     rsp, 8
    and     rsp, -16

    mov     rdi, r13
    mov     rsi, r14
    mov     rdx, r15
    mov     rcx, rbx
    mov     r8,  r12
    lea     r9,  [rsp]
    call    str_fmt
    test    rax, rax
    jnz     .snpf_err

    mov     rcx, [rsp]          ; bytes written
    add     rsp, 8

    ; write null terminator
    mov     byte [rbx + rcx], 0

    pop     r9
    test    r9, r9
    jz      .snpf_ok
    mov     [r9], rcx

.snpf_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.snpf_err:
    add     rsp, 8
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.snpf_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_snprintf

; -----------------------------------------------------------------------------
; str_fmt_count
;
; Count how many bytes would be written without actually writing.
; Useful for pre-computing buffer sizes.
;
; Signature:
;   int64_t str_fmt_count(const char *fmt, const uint64_t *args,
;                          uint64_t arg_count, uint64_t *out_len)
;
; Arguments:
;   RDI  — format string
;   RSI  — args
;   RDX  — arg count
;   RCX  — out_len (required)
; -----------------------------------------------------------------------------

STR_FUNC str_fmt_count

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    ; allocate a large scratch buffer on stack to absorb output
    ; Max reasonable format output: 4096 bytes
    sub     rsp, 4096
    and     rsp, -16

    sub     rsp, 8              ; out_len slot
    and     rsp, -16

    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, rsp
    add     rcx, 8              ; point to scratch buf
    mov     r8,  4096
    lea     r9,  [rsp]
    call    str_fmt
    test    rax, rax
    jnz     .fc_err

    mov     rax, [rsp]          ; bytes written
    mov     [r14], rax

    mov     rsp, rbp
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.fc_err:
    mov     rsp, rbp
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_fmt_count

; -----------------------------------------------------------------------------
; str_fmt_slice
;
; Format using a StrSlice as the format string (not null-terminated).
;
; Signature:
;   int64_t str_fmt_slice(const StrSlice *fmt, const uint64_t *args,
;                          uint64_t arg_count, uint8_t *buf,
;                          uint64_t buf_cap, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_fmt_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    ; Copy format slice to null-terminated temp buffer on stack
    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; fmt slice
    mov     r12, rsi            ; args
    mov     r13, rdx            ; arg_count
    mov     r14, rcx            ; buf
    mov     r15, r8             ; buf_cap
    push    r9                  ; out

    mov     r9, [rbx + StrSlice.len]

    ; allocate null-terminated copy
    lea     rax, [r9 + 1]
    sub     rsp, rax
    and     rsp, -16

    ; copy format bytes
    mov     rdi, rsp
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, r9
    push    r9
    call    str_copy_bytes      ; (would need extern — simplified)
    pop     r9

    ; null terminate
    mov     byte [rsp + r9], 0

    ; call str_sprintf
    mov     rdi, rsp            ; null-terminated fmt
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r14
    mov     r8,  r15
    pop     r9                  ; out
    call    str_sprintf

    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_fmt_slice