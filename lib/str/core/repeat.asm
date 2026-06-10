; =============================================================================
; str/core/repeat.asm
; Repeat a StrSlice N times into a caller-supplied buffer.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm  (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; repeat never allocates — caller supplies the buffer.
; Result is always valid UTF-8 if input is valid UTF-8.
;
; Functions:
;   str_repeat        — repeat a StrSlice N times
;   str_repeat_byte   — repeat a single byte N times (memset variant)
;   str_repeat_cp     — repeat a Unicode codepoint N times
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes
extern str_utf8_encode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_repeat
;
; Write src repeated N times into buf, return as StrSlice.
;
; Signature:
;   int64_t str_repeat(const StrSlice *src, uint64_t n,
;                       uint8_t *buf, uint64_t buf_cap,
;                       StrSlice *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — repeat count N
;   RDX  — output buffer
;   RCX  — buffer capacity
;   R8   — output StrSlice
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          src, buf, or out is null
;   RAX  = STR_ERR_BUF_TOO_SMALL buf_cap < src.len * N
;   RAX  = STR_ERR_OVERFLOW      src.len * N overflows uint64
; -----------------------------------------------------------------------------

STR_FUNC str_repeat

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; n
    mov     r13, rdx            ; buf
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out

    ; n == 0 → empty output
    test    r12, r12
    jz      .repeat_empty

    mov     r9, [rbx + StrSlice.len]    ; src.len

    ; overflow check: src.len * n
    mov     rax, r9
    mul     r12                         ; rdx:rax = src.len * n
    test    rdx, rdx
    jnz     .overflow_rep               ; high bits set → overflow

    ; capacity check
    cmp     rax, r14
    ja      .too_small_rep

    mov     r11, rax            ; total output len
    mov     r10, r13            ; write cursor

.rep_loop:
    test    r12, r12
    jz      .rep_done

    mov     rdi, r10
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, r9
    push    r12
    call    str_copy_bytes
    pop     r12
    test    rax, rax
    jnz     .err_rep

    add     r10, r9
    dec     r12
    jmp     .rep_loop

.rep_done:
    mov     [r15 + StrSlice.ptr], r13
    mov     [r15 + StrSlice.len], r11

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.repeat_empty:
    mov     qword [r8 + StrSlice.ptr], 0
    mov     qword [r8 + StrSlice.len], 0

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.overflow_rep:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.too_small_rep:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.err_rep:
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_repeat

; -----------------------------------------------------------------------------
; str_repeat_byte
;
; Fill buf with byte_val repeated N times.
; Faster than str_repeat for single-byte fill — uses 8-byte broadcast.
;
; Signature:
;   int64_t str_repeat_byte(uint8_t byte_val, uint64_t n,
;                            uint8_t *buf, uint64_t buf_cap,
;                            StrSlice *out)
;
; Arguments:
;   DIL  — byte value
;   RSI  — count N
;   RDX  — output buffer
;   RCX  — buffer capacity
;   R8   — output StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_repeat_byte

    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    ; n == 0 → empty
    test    rsi, rsi
    jz      .rb_empty

    ; capacity check
    cmp     rsi, rcx
    ja      .rb_too_small

    push_regs rbx, r12, r13, r14

    movzx   ebx, dil            ; byte val
    mov     r12, rsi            ; n
    mov     r13, rdx            ; buf
    mov     r14, r8             ; out

    ; broadcast byte to 64-bit
    mov     rax, rbx
    mov     ah, bl
    mov     cx, ax
    shl     eax, 16
    or      ax, cx
    mov     ecx, eax
    shl     rax, 32
    or      rax, rcx

    mov     r9, r13             ; write ptr
    mov     r10, r12            ; remaining

.rb_qloop:
    cmp     r10, 8
    jb      .rb_bloop

    mov     [r9], rax
    add     r9, 8
    sub     r10, 8
    jmp     .rb_qloop

.rb_bloop:
    test    r10, r10
    jz      .rb_done

    mov     [r9], bl
    inc     r9
    dec     r10
    jmp     .rb_bloop

.rb_done:
    mov     [r14 + StrSlice.ptr], r13
    mov     [r14 + StrSlice.len], r12

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rb_empty:
    mov     qword [r8 + StrSlice.ptr], 0
    mov     qword [r8 + StrSlice.len], 0
    xor     eax, eax
    pop     rbp
    ret

.rb_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_repeat_byte

; -----------------------------------------------------------------------------
; str_repeat_cp
;
; Encode a Unicode codepoint and repeat it N times into buf.
;
; Signature:
;   int64_t str_repeat_cp(uint32_t cp, uint64_t n,
;                          uint8_t *buf, uint64_t buf_cap,
;                          StrSlice *out)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — count N
;   RDX  — buffer
;   RCX  — capacity
;   R8   — out StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_repeat_cp

    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    test    rsi, rsi
    jz      .rcp_empty

    push_regs rbx, r12, r13, r14, r15

    mov     ebx, edi            ; cp
    mov     r12, rsi            ; n
    mov     r13, rdx            ; buf
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out

    ; encode fill codepoint
    sub     rsp, 16
    and     rsp, -16

    mov     edi, ebx
    mov     rsi, rsp
    call    str_utf8_encode_unchecked
    ; eax = fill_byte_len

    mov     r11, rax            ; fill_byte_len

    ; check: n * fill_byte_len <= cap
    mov     rax, r12
    mul     r11
    test    rdx, rdx
    jnz     .rcp_overflow

    cmp     rax, r14
    ja      .rcp_too_small

    mov     r10, rax            ; total bytes
    mov     r9, r13             ; write cursor

.rcp_loop:
    test    r12, r12
    jz      .rcp_done

    mov     rdi, r9
    mov     rsi, rsp
    mov     rdx, r11
    push    r12
    call    str_copy_bytes
    pop     r12

    add     r9, r11
    dec     r12
    jmp     .rcp_loop

.rcp_done:
    mov     rsp, rbp

    mov     [r15 + StrSlice.ptr], r13
    mov     [r15 + StrSlice.len], r10

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rcp_empty:
    mov     qword [r8 + StrSlice.ptr], 0
    mov     qword [r8 + StrSlice.len], 0
    xor     eax, eax
    pop     rbp
    ret

.rcp_overflow:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.rcp_too_small:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_repeat_cp
