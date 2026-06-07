; =============================================================================
; str/utf8/nth.asm
; Get the Nth Unicode codepoint from a UTF-8 string (0-indexed).
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
; Note on complexity:
;   UTF-8 is not random-access. To get codepoint N you must walk
;   from the start of the string — O(N) in the worst case.
;   If you need many random accesses, build an offset index instead.
;
;   For sequential access, use iter.asm — far more efficient.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_utf8_nth
;
; Return the Nth codepoint (0-indexed) from a UTF-8 byte buffer.
;
; Signature:
;   int64_t str_utf8_nth(const uint8_t *ptr, uint64_t byte_len,
;                         uint64_t n, uint32_t *out_cp)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length
;   RDX  — codepoint index N (0-based)
;   RCX  — pointer to uint32_t to receive the codepoint
;
; Returns:
;   RAX  = STR_OK               codepoint written to *out_cp
;   RAX  = STR_ERR_NULL         ptr or out_cp is null
;   RAX  = STR_ERR_OUT_OF_BOUNDS N >= codepoint count of string
;   RAX  = STR_ERR_INVALID_UTF8  malformed sequence encountered
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_nth

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi                ; rbx = current ptr
    mov     r12, rsi                ; r12 = byte_len
    add     r12, rbx                ; r12 = end ptr
    mov     r13, rdx                ; r13 = target index N
    mov     r14, rcx                ; r14 = out_cp
    xor     r15, r15                ; r15 = current codepoint index

.walk:
    ; past end?
    cmp     rbx, r12
    jae     .out_of_bounds

    ; at target index?
    cmp     r15, r13
    je      .found

    ; skip this codepoint — determine its byte length
    movzx   eax, byte [rbx]

    ; inline charlen (no call overhead)
    test    al, 0x80
    jz      .skip1

    cmp     al, 0xC2
    jb      .bad_utf8
    cmp     al, 0xDF
    jbe     .skip2

    cmp     al, 0xEF
    jbe     .skip3

    cmp     al, 0xF4
    jbe     .skip4

    jmp     .bad_utf8

.skip1: add rbx, 1 ; jmp .next
        jmp .next
.skip2: add rbx, 2
        jmp .next
.skip3: add rbx, 3
        jmp .next
.skip4: add rbx, 4

.next:
    inc     r15
    jmp     .walk

.found:
    ; decode codepoint at rbx
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]              ; advance slot (discarded)
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     dword [r14], eax        ; *out_cp = codepoint

    mov     rsp, rbp

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax                ; STR_OK
    pop     rbp
    ret

.out_of_bounds:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

.bad_utf8:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

STR_ENDFUNC str_utf8_nth

; -----------------------------------------------------------------------------
; str_utf8_nth_slice
;
; Like str_utf8_nth but takes a StrSlice.
;
; Signature:
;   int64_t str_utf8_nth_slice(const StrSlice *slice, uint64_t n,
;                               uint32_t *out_cp)
;
; Arguments:
;   RDI  — pointer to StrSlice
;   RSI  — codepoint index N (0-based)
;   RDX  — pointer to uint32_t to receive codepoint
;
; Returns:
;   RAX  = STR_OK or error
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_nth_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx
    mov     rbx, rdi

    mov     rcx, rdx                        ; out_cp
    mov     rdx, rsi                        ; n
    mov     rsi, [rbx + StrSlice.len]       ; byte_len
    mov     rdi, [rbx + StrSlice.ptr]       ; ptr

    pop_regs rbx
    pop     rbp
    jmp     str_utf8_nth                    ; tail call

STR_ENDFUNC str_utf8_nth_slice

; -----------------------------------------------------------------------------
; str_utf8_first
;
; Return the first codepoint of a UTF-8 string. Shorthand for nth(0).
;
; Signature:
;   int64_t str_utf8_first(const uint8_t *ptr, uint64_t byte_len,
;                           uint32_t *out_cp)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length
;   RDX  — pointer to uint32_t to receive codepoint
;
; Returns:
;   RAX  = STR_OK or error
;   RAX  = STR_ERR_OUT_OF_BOUNDS  if string is empty
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_first

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    test    rsi, rsi
    jz      .empty

    ; n=0: just decode at ptr directly
    push_regs rbx
    mov     rbx, rdx                ; save out_cp

    sub     rsp, 16
    and     rsp, -16

    lea     rsi, [rsp]              ; advance slot
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     dword [rbx], eax

    mov     rsp, rbp

    pop_regs rbx
    xor     eax, eax
    pop     rbp
    ret

.empty:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

STR_ENDFUNC str_utf8_first

; -----------------------------------------------------------------------------
; str_utf8_last
;
; Return the last codepoint of a UTF-8 string.
; Walks backward from end to find the last leading byte.
;
; Signature:
;   int64_t str_utf8_last(const uint8_t *ptr, uint64_t byte_len,
;                          uint32_t *out_cp)
;
; Arguments:
;   RDI  — pointer to UTF-8 byte buffer
;   RSI  — byte length
;   RDX  — pointer to uint32_t to receive codepoint
;
; Returns:
;   RAX  = STR_OK or error
;   RAX  = STR_ERR_OUT_OF_BOUNDS  if string is empty
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_last

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    test    rsi, rsi
    jz      .empty

    push_regs rbx, r12, r13

    mov     rbx, rdi                ; rbx = base ptr
    mov     r12, rsi                ; r12 = byte_len
    mov     r13, rdx                ; r13 = out_cp

    ; start from last byte, walk backward past continuation bytes
    lea     rax, [rbx + r12 - 1]   ; rax = last byte ptr

.back:
    cmp     rax, rbx
    jb      .bad_utf8               ; ran off the start — malformed

    movzx   ecx, byte [rax]

    ; continuation byte: (byte & 0xC0) == 0x80 → keep going back
    mov     edx, ecx
    and     edx, 0xC0
    cmp     edx, 0x80
    je      .prev

    ; found leading byte — decode from here
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rax
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     dword [r13], eax

    mov     rsp, rbp

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.prev:
    dec     rax
    jmp     .back

.empty:
    mov     rax, STR_ERR_OUT_OF_BOUNDS
    pop     rbp
    ret

.bad_utf8:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

STR_ENDFUNC str_utf8_last