; =============================================================================
; str/utf8/iter.asm
; UTF-8 codepoint iterator — walk a string one codepoint at a time.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; StrIter layout (from types.inc):
;
;   .ptr   dq  — current position pointer
;   .end   dq  — one past last byte
;   .cp    dd  — last decoded codepoint
;   ._pad  dd  — padding
;
; Usage pattern:
;
;   ; init
;   lea  rdi, [my_iter]
;   mov  rsi, str_ptr
;   mov  rdx, str_byte_len
;   call str_utf8_iter_init
;
;   ; loop
;   .loop:
;       lea  rdi, [my_iter]
;       call str_utf8_iter_next
;       cmp  rax, STR_ERR_ITER_END
;       je   .done
;       test rax, rax
;       jnz  .error
;       ; codepoint is in [my_iter + StrIter.cp]
;       jmp  .loop
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_utf8_iter_init
;
; Initialize a StrIter over a UTF-8 byte buffer.
;
; Signature:
;   int64_t str_utf8_iter_init(StrIter *iter,
;                               const uint8_t *ptr,
;                               uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to StrIter (caller-allocated, 24 bytes)
;   RSI  — pointer to UTF-8 byte buffer
;   RDX  — byte length
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  if iter or ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_iter_init

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     qword [rdi + StrIter.ptr], rsi      ; .ptr = buf start
    mov     rax, rsi
    add     rax, rdx
    mov     qword [rdi + StrIter.end], rax      ; .end = buf start + len
    mov     dword [rdi + StrIter.cp],  0        ; .cp  = 0 (not yet decoded)

    xor     eax, eax                            ; STR_OK
    pop     rbp
    ret

STR_ENDFUNC str_utf8_iter_init

; -----------------------------------------------------------------------------
; str_utf8_iter_init_slice
;
; Initialize a StrIter from a StrSlice.
;
; Signature:
;   int64_t str_utf8_iter_init_slice(StrIter *iter, const StrSlice *slice)
;
; Arguments:
;   RDI  — pointer to StrIter
;   RSI  — pointer to StrSlice
;
; Returns:
;   RAX  = STR_OK or STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_iter_init_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx
    mov     rbx, rdi                            ; save iter ptr

    mov     rdx, [rsi + StrSlice.len]           ; byte_len
    mov     rsi, [rsi + StrSlice.ptr]           ; ptr
    mov     rdi, rbx

    pop_regs rbx
    pop     rbp
    jmp     str_utf8_iter_init                  ; tail call

STR_ENDFUNC str_utf8_iter_init_slice

; -----------------------------------------------------------------------------
; str_utf8_iter_next
;
; Advance the iterator by one codepoint. Decoded codepoint is stored
; in iter->cp and also returned context via the iterator state.
;
; Signature:
;   int64_t str_utf8_iter_next(StrIter *iter)
;
; Arguments:
;   RDI  — pointer to StrIter
;
; Returns:
;   RAX  = STR_OK           codepoint decoded, iter->cp updated, ptr advanced
;   RAX  = STR_ERR_ITER_END iterator exhausted (ptr == end)
;   RAX  = STR_ERR_NULL     iter is null
;
; After return:
;   iter->cp holds the decoded codepoint (only valid when RAX == STR_OK)
;   iter->ptr has advanced past the consumed bytes
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_iter_next

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi                            ; rbx = iter ptr
    mov     rax, [rbx + StrIter.ptr]            ; rax = current ptr
    mov     r12, [rbx + StrIter.end]            ; r12 = end ptr

    ; check exhausted
    cmp     rax, r12
    jae     .exhausted

    ; decode one codepoint — unchecked (assume pre-validated input)
    ; str_utf8_decode_unchecked(ptr, out_advance*)
    ; we need a stack slot for out_advance
    sub     rsp, 16                             ; allocate: [rsp] = advance
    and     rsp, -16                            ; align

    mov     rdi, rax                            ; ptr = iter->ptr
    lea     rsi, [rsp]                          ; out_advance on stack
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     dword [rbx + StrIter.cp], eax       ; iter->cp = codepoint

    ; advance iter->ptr by bytes consumed
    mov     rcx, [rsp]                          ; rcx = advance count
    mov     rdx, [rbx + StrIter.ptr]
    add     rdx, rcx
    mov     [rbx + StrIter.ptr], rdx

    ; restore stack
    mov     rsp, rbp
    sub     rsp, 0                              ; rbp still valid

    pop_regs r12, rbx
    xor     eax, eax                            ; STR_OK
    pop     rbp
    ret

.exhausted:
    pop_regs r12, rbx
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_utf8_iter_next

; -----------------------------------------------------------------------------
; str_utf8_iter_next_cp
;
; Like str_utf8_iter_next but returns the codepoint directly in EAX
; instead of writing to iter->cp. Slightly more convenient for tight loops.
;
; Signature:
;   int64_t str_utf8_iter_next_cp(StrIter *iter, uint32_t *out_cp)
;
; Arguments:
;   RDI  — pointer to StrIter
;   RSI  — pointer to uint32_t to receive codepoint
;
; Returns:
;   RAX  = STR_OK           codepoint written to *out_cp
;   RAX  = STR_ERR_ITER_END exhausted
;   RAX  = STR_ERR_NULL     iter or out_cp is null
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_iter_next_cp

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi                            ; r12 = out_cp

    ; reuse iter_next logic inline
    mov     rax, [rbx + StrIter.ptr]
    mov     rcx, [rbx + StrIter.end]
    cmp     rax, rcx
    jae     .end

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rax
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     dword [r12], eax                    ; *out_cp = codepoint
    mov     dword [rbx + StrIter.cp], eax       ; also update iter->cp

    mov     rcx, [rsp]
    mov     rdx, [rbx + StrIter.ptr]
    add     rdx, rcx
    mov     [rbx + StrIter.ptr], rdx

    mov     rsp, rbp

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.end:
    pop_regs r12, rbx
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_utf8_iter_next_cp

; -----------------------------------------------------------------------------
; str_utf8_iter_peek
;
; Decode the next codepoint WITHOUT advancing the iterator.
;
; Signature:
;   int64_t str_utf8_iter_peek(const StrIter *iter, uint32_t *out_cp)
;
; Arguments:
;   RDI  — pointer to StrIter (not modified)
;   RSI  — pointer to uint32_t to receive codepoint
;
; Returns:
;   RAX  = STR_OK           codepoint written, iterator unchanged
;   RAX  = STR_ERR_ITER_END exhausted
;   RAX  = STR_ERR_NULL     iter or out_cp is null
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_iter_peek

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi

    mov     rax, [rbx + StrIter.ptr]
    mov     rcx, [rbx + StrIter.end]
    cmp     rax, rcx
    jae     .end

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rax
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    ; eax = codepoint, ptr NOT advanced

    mov     dword [r12], eax

    mov     rsp, rbp

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.end:
    pop_regs r12, rbx
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_utf8_iter_peek

; -----------------------------------------------------------------------------
; str_utf8_iter_rewind
;
; Reset iterator back to the start of the buffer.
;
; Signature:
;   int64_t str_utf8_iter_rewind(StrIter *iter, const uint8_t *start)
;
; Arguments:
;   RDI  — pointer to StrIter
;   RSI  — original start pointer (same as passed to iter_init)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  iter or start is null
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_iter_rewind

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     qword [rdi + StrIter.ptr], rsi
    mov     dword [rdi + StrIter.cp],  0

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_utf8_iter_rewind

; -----------------------------------------------------------------------------
; str_utf8_iter_is_done
;
; Predicate: is the iterator exhausted?
;
; Signature:
;   int64_t str_utf8_iter_is_done(const StrIter *iter)
;
; Arguments:
;   RDI  — pointer to StrIter
;
; Returns:
;   RAX  = 1  exhausted
;   RAX  = 0  more codepoints remain
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_iter_is_done

    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrIter.ptr]
    mov     rcx, [rdi + StrIter.end]
    cmp     rax, rcx
    setae   al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_utf8_iter_is_done