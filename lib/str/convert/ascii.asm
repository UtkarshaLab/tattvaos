; =============================================================================
; str/convert/ascii.asm
; ASCII-only byte-level conversions — no UTF-8 decoding needed.
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
; All functions operate on raw bytes. They are safe to call on ASCII input
; only. For Unicode-aware transforms use convert/case.asm.
;
; Functions:
;   str_ascii_to_upper      — uppercase ASCII bytes in buffer
;   str_ascii_to_lower      — lowercase ASCII bytes in buffer
;   str_ascii_to_upper_buf  — write uppercased copy into new buffer
;   str_ascii_to_lower_buf  — write lowercased copy into new buffer
;   str_ascii_to_upper_slice — uppercase a StrSlice into buffer
;   str_ascii_to_lower_slice — lowercase a StrSlice into buffer
;   str_byte_to_printable   — convert non-printable to '.' (for hex dumps)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes

section .text

; -----------------------------------------------------------------------------
; str_ascii_to_upper
;
; Uppercase ASCII letters in-place. Non-ASCII bytes unchanged.
;
; Signature:
;   int64_t str_ascii_to_upper(uint8_t *buf, uint64_t len)
;
; Arguments:
;   RDI  — buffer pointer (modified in place)
;   RSI  — byte length
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_to_upper

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .ok_up

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi
    xor     ecx, ecx

.up_loop:
    cmp     rcx, r12
    jae     .up_done

    movzx   eax, byte [rbx + rcx]

    ; if a-z: clear bit 5 (subtract 0x20)
    cmp     al, 'a'
    jb      .up_next
    cmp     al, 'z'
    ja      .up_next
    and     al, 0xDF            ; clear bit 5 → uppercase

    mov     [rbx + rcx], al

.up_next:
    inc     rcx
    jmp     .up_loop

.up_done:
    pop_regs r12, rbx

.ok_up:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ascii_to_upper

; -----------------------------------------------------------------------------
; str_ascii_to_lower
;
; Lowercase ASCII letters in-place.
;
; Signature:
;   int64_t str_ascii_to_lower(uint8_t *buf, uint64_t len)
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_to_lower

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .ok_lo

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi
    xor     ecx, ecx

.lo_loop:
    cmp     rcx, r12
    jae     .lo_done

    movzx   eax, byte [rbx + rcx]

    cmp     al, 'A'
    jb      .lo_next
    cmp     al, 'Z'
    ja      .lo_next
    or      al, 0x20            ; set bit 5 → lowercase

    mov     [rbx + rcx], al

.lo_next:
    inc     rcx
    jmp     .lo_loop

.lo_done:
    pop_regs r12, rbx

.ok_lo:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ascii_to_lower

; -----------------------------------------------------------------------------
; str_ascii_to_upper_buf
;
; Write uppercased copy of src into dst buffer. src unchanged.
;
; Signature:
;   int64_t str_ascii_to_upper_buf(const uint8_t *src, uint64_t len,
;                                   uint8_t *dst, uint64_t dst_cap)
;
; Arguments:
;   RDI  — source
;   RSI  — length
;   RDX  — destination buffer
;   RCX  — destination capacity
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_to_upper_buf

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    cmp     rsi, rcx
    ja      .too_small_up

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    xor     ecx, ecx

.upb_loop:
    cmp     rcx, r12
    jae     .upb_done

    movzx   eax, byte [rbx + rcx]

    cmp     al, 'a'
    jb      .upb_copy
    cmp     al, 'z'
    ja      .upb_copy
    and     al, 0xDF

.upb_copy:
    mov     [r13 + rcx], al
    inc     rcx
    jmp     .upb_loop

.upb_done:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.too_small_up:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_ascii_to_upper_buf

; -----------------------------------------------------------------------------
; str_ascii_to_lower_buf
;
; Write lowercased copy of src into dst buffer.
;
; Signature:
;   int64_t str_ascii_to_lower_buf(const uint8_t *src, uint64_t len,
;                                   uint8_t *dst, uint64_t dst_cap)
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_to_lower_buf

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    cmp     rsi, rcx
    ja      .too_small_lo

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    xor     ecx, ecx

.lob_loop:
    cmp     rcx, r12
    jae     .lob_done

    movzx   eax, byte [rbx + rcx]

    cmp     al, 'A'
    jb      .lob_copy
    cmp     al, 'Z'
    ja      .lob_copy
    or      al, 0x20

.lob_copy:
    mov     [r13 + rcx], al
    inc     rcx
    jmp     .lob_loop

.lob_done:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.too_small_lo:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_ascii_to_lower_buf

; -----------------------------------------------------------------------------
; str_ascii_to_upper_slice
;
; Uppercase a StrSlice into a buffer, return result as StrSlice.
;
; Signature:
;   int64_t str_ascii_to_upper_slice(const StrSlice *src,
;                                     uint8_t *buf, uint64_t buf_cap,
;                                     StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_to_upper_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out

    mov     r9,  [rbx + StrSlice.len]

    cmp     r9, r13
    ja      .ups_too_small

    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r9
    mov     rdx, r12
    mov     rcx, r13
    call    str_ascii_to_upper_buf
    test    rax, rax
    jnz     .ups_err

    mov     [r14 + StrSlice.ptr], r12
    mov     [r14 + StrSlice.len], r9

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ups_too_small:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.ups_err:
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_ascii_to_upper_slice

; -----------------------------------------------------------------------------
; str_ascii_to_lower_slice
;
; Lowercase a StrSlice into a buffer, return result as StrSlice.
;
; Signature:
;   int64_t str_ascii_to_lower_slice(const StrSlice *src,
;                                     uint8_t *buf, uint64_t buf_cap,
;                                     StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_to_lower_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    mov     r9, [rbx + StrSlice.len]

    cmp     r9, r13
    ja      .los_too_small

    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, r9
    mov     rdx, r12
    mov     rcx, r13
    call    str_ascii_to_lower_buf
    test    rax, rax
    jnz     .los_err

    mov     [r14 + StrSlice.ptr], r12
    mov     [r14 + StrSlice.len], r9

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.los_too_small:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.los_err:
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_ascii_to_lower_slice

; -----------------------------------------------------------------------------
; str_byte_to_printable
;
; Convert a byte to printable form for hex dump display.
; Returns byte if 0x20..0x7E, else '.'.
;
; Signature:
;   uint8_t str_byte_to_printable(uint8_t byte)
;
; Arguments:
;   DIL  — byte
;
; Returns:
;   AL   — printable byte or '.'
; -----------------------------------------------------------------------------

STR_FUNC str_byte_to_printable

    movzx   eax, dil

    cmp     al, 0x20
    jb      .not_printable
    cmp     al, 0x7E
    ja      .not_printable

    pop     rbp
    ret

.not_printable:
    mov     al, '.'
    pop     rbp
    ret

STR_ENDFUNC str_byte_to_printable
