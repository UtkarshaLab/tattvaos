; =============================================================================
; str/core/copy.asm
; Copy bytes into buffers and StrSlice duplication.
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
; Copy functions operate on raw bytes — no UTF-8 awareness needed.
; StrSlice is always valid UTF-8 by invariant, so copying bytes
; preserves validity automatically.
;
; Functions:
;   str_copy_bytes    — memcpy equivalent
;   str_copy_to_buf   — copy StrSlice into a raw byte buffer
;   str_copy_slice    — copy one StrSlice into another (same backing)
;   str_copy_overlap  — safe copy for overlapping regions (memmove)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_copy_bytes
;
; Copy byte_len bytes from src to dst. Regions must NOT overlap.
; For overlapping regions use str_copy_overlap.
;
; Signature:
;   int64_t str_copy_bytes(uint8_t *dst, const uint8_t *src,
;                           uint64_t byte_len)
;
; Arguments:
;   RDI  — destination pointer
;   RSI  — source pointer
;   RDX  — byte count
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  dst or src is null
; -----------------------------------------------------------------------------

STR_FUNC str_copy_bytes

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    ; zero length → no-op
    test    rdx, rdx
    jz      .ok

    push_regs rbx, r12, r13

    mov     rbx, rdi            ; dst
    mov     r12, rsi            ; src
    mov     r13, rdx            ; len

    ; copy 8 bytes at a time
.qloop:
    cmp     r13, 8
    jb      .bloop

    mov     rax, [r12]
    mov     [rbx], rax
    add     rbx, 8
    add     r12, 8
    sub     r13, 8
    jmp     .qloop

    ; copy remaining bytes
.bloop:
    test    r13, r13
    jz      .copy_done

    movzx   eax, byte [r12]
    mov     [rbx], al
    inc     rbx
    inc     r12
    dec     r13
    jmp     .bloop

.copy_done:
    pop_regs r13, r12, rbx

.ok:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_copy_bytes

; -----------------------------------------------------------------------------
; str_copy_overlap
;
; Copy byte_len bytes from src to dst, safe for overlapping regions.
; Equivalent to memmove.
;
; Signature:
;   int64_t str_copy_overlap(uint8_t *dst, const uint8_t *src,
;                              uint64_t byte_len)
; -----------------------------------------------------------------------------

STR_FUNC str_copy_overlap

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    test    rdx, rdx
    jz      .ok_ov

    ; if dst < src or no overlap → forward copy
    cmp     rdi, rsi
    jbe     .forward

    ; check if regions actually overlap
    mov     rax, rsi
    add     rax, rdx            ; src + len
    cmp     rdi, rax
    jae     .forward            ; dst >= src+len → no overlap

    ; backward copy: start from end
    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    ; point to last byte
    add     rbx, r13
    add     r12, r13
    dec     rbx
    dec     r12

.bkwd_loop:
    test    r13, r13
    jz      .bkwd_done

    movzx   eax, byte [r12]
    mov     [rbx], al
    dec     rbx
    dec     r12
    dec     r13
    jmp     .bkwd_loop

.bkwd_done:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.forward:
    ; safe to do forward copy
    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

.fwd_qloop:
    cmp     r13, 8
    jb      .fwd_bloop

    mov     rax, [r12]
    mov     [rbx], rax
    add     rbx, 8
    add     r12, 8
    sub     r13, 8
    jmp     .fwd_qloop

.fwd_bloop:
    test    r13, r13
    jz      .fwd_done

    movzx   eax, byte [r12]
    mov     [rbx], al
    inc     rbx
    inc     r12
    dec     r13
    jmp     .fwd_bloop

.fwd_done:
    pop_regs r13, r12, rbx

.ok_ov:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_copy_overlap

; -----------------------------------------------------------------------------
; str_copy_to_buf
;
; Copy the bytes of a StrSlice into a raw buffer.
; Buffer must have capacity >= slice.len.
; Does NOT null-terminate (use str_to_cstr for that).
;
; Signature:
;   int64_t str_copy_to_buf(const StrSlice *src, uint8_t *buf,
;                            uint64_t buf_cap, uint64_t *out_written)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — destination buffer
;   RDX  — buffer capacity in bytes
;   RCX  — pointer to uint64_t to receive bytes written (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          src or buf is null
;   RAX  = STR_ERR_BUF_TOO_SMALL buf_cap < slice.len
; -----------------------------------------------------------------------------

STR_FUNC str_copy_to_buf

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; src slice
    mov     r12, rsi            ; dst buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_written (may be null)

    mov     r8,  [rbx + StrSlice.len]
    mov     r9,  [rbx + StrSlice.ptr]

    ; check capacity
    cmp     r8, r13
    ja      .buf_too_small

    ; copy
    mov     rdi, r12
    mov     rsi, r9
    mov     rdx, r8

    ; inline fast copy
    mov     rcx, r8

.ctb_qloop:
    cmp     rcx, 8
    jb      .ctb_bloop

    mov     rax, [rsi]
    mov     [rdi], rax
    add     rdi, 8
    add     rsi, 8
    sub     rcx, 8
    jmp     .ctb_qloop

.ctb_bloop:
    test    rcx, rcx
    jz      .ctb_done

    movzx   eax, byte [rsi]
    mov     [rdi], al
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .ctb_bloop

.ctb_done:
    ; write out_written if provided
    test    r14, r14
    jz      .ctb_ok
    mov     [r14], r8

.ctb_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.buf_too_small:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_copy_to_buf

; -----------------------------------------------------------------------------
; str_copy_slice
;
; Shallow copy: make dst point to the same buffer as src.
; No allocation — dst becomes another view of the same memory.
;
; Signature:
;   int64_t str_copy_slice(StrSlice *dst, const StrSlice *src)
; -----------------------------------------------------------------------------

STR_FUNC str_copy_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rsi + StrSlice.ptr]
    mov     rcx, [rsi + StrSlice.len]
    mov     [rdi + StrSlice.ptr], rax
    mov     [rdi + StrSlice.len], rcx

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_copy_slice

; -----------------------------------------------------------------------------
; str_fill
;
; Fill a byte buffer with a repeated byte value.
; Equivalent to memset.
;
; Signature:
;   int64_t str_fill(uint8_t *buf, uint8_t value, uint64_t len)
;
; Arguments:
;   RDI  — buffer pointer
;   SIL  — byte value to fill with
;   RDX  — byte count
; -----------------------------------------------------------------------------

STR_FUNC str_fill

    guard_null rdi, STR_ERR_NULL

    test    rdx, rdx
    jz      .ok_fill

    push_regs rbx, r12

    mov     rbx, rdi
    movzx   eax, sil            ; fill byte

    ; broadcast to 8 bytes: fill all 8 bytes of rax with the same value
    mov     ah, al
    mov     cx, ax
    shl     eax, 16
    or      ax, cx
    mov     ecx, eax
    shl     rax, 32
    or      rax, rcx

    mov     r12, rdx

.fill_qloop:
    cmp     r12, 8
    jb      .fill_bloop

    mov     [rbx], rax
    add     rbx, 8
    sub     r12, 8
    jmp     .fill_qloop

.fill_bloop:
    test    r12, r12
    jz      .fill_done

    mov     [rbx], al
    inc     rbx
    dec     r12
    jmp     .fill_bloop

.fill_done:
    pop_regs r12, rbx

.ok_fill:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_fill
