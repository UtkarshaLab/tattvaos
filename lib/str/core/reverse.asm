; =============================================================================
; str/core/reverse.asm
; Reverse a UTF-8 string codepoint by codepoint into a buffer.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm   (str_copy_bytes)
;   utf8/charlen.asm (str_utf8_charlen)
;
; -----------------------------------------------------------------------------
; Reversing UTF-8 is NOT the same as reversing bytes.
; We must reverse at the CODEPOINT boundary level.
;
; Algorithm:
;   1. Walk forward collecting (ptr, seq_len) pairs for each codepoint
;   2. Write codepoints in reverse order into output buffer
;
; For in-place reverse we use a temp buffer on the stack or caller-supplied.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes
extern str_utf8_charlen

section .text

; -----------------------------------------------------------------------------
; str_reverse
;
; Reverse a UTF-8 StrSlice codepoint-by-codepoint into a buffer.
;
; Signature:
;   int64_t str_reverse(const StrSlice *src, uint8_t *buf,
;                        uint64_t buf_cap, StrSlice *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — output buffer
;   RDX  — buffer capacity
;   RCX  — output StrSlice
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          src, buf, or out is null
;   RAX  = STR_ERR_BUF_TOO_SMALL buf_cap < src.len
;   RAX  = STR_ERR_INVALID_UTF8  malformed input
; -----------------------------------------------------------------------------

STR_FUNC str_reverse

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out

    mov     r9,  [rbx + StrSlice.len]

    ; empty → empty output
    test    r9, r9
    jz      .rev_empty

    ; capacity check: output is same byte length as input
    cmp     r9, r13
    ja      .rev_too_small

    ; ASCII fast path: if all bytes < 0x80, byte-reverse is fine
    ; (check first byte — if 0x7F or less, do full ASCII check)
    mov     r10, [rbx + StrSlice.ptr]
    movzx   eax, byte [r10]
    test    al, 0x80
    jnz     .utf8_reverse       ; non-ASCII → full UTF-8 reverse

    ; check entire buffer for ASCII
    mov     r15, r9
    mov     r11, r10

.ascii_check:
    test    r15, r15
    jz      .do_byte_reverse    ; all ASCII → byte reverse

    movzx   eax, byte [r11]
    test    al, 0x80
    jnz     .utf8_reverse

    inc     r11
    dec     r15
    jmp     .ascii_check

.do_byte_reverse:
    ; simple byte reverse for ASCII
    mov     r11, r10            ; src start
    mov     r15, r9             ; len
    mov     r13, r12            ; dst write ptr (from end)
    add     r13, r15
    dec     r13                 ; point to last dst byte

    xor     r15, r15            ; i = 0

.byte_rev_loop:
    cmp     r15, r9
    jae     .byte_rev_done

    movzx   eax, byte [r11 + r9 - r15 - 1]
    mov     [r12 + r15], al
    inc     r15
    jmp     .byte_rev_loop

.byte_rev_done:
    jmp     .rev_write_out

.utf8_reverse:
    ; Full UTF-8 codepoint reverse
    ; Pass 1: collect codepoint offsets and lengths into a temp stack array
    ; We store (offset, seqlen) pairs. Max codepoints = src.len (all ASCII)
    ; Use heap-style alloc via rsp for the index array

    mov     r10, [rbx + StrSlice.ptr]
    mov     r11, r9             ; remaining

    ; allocate stack space for offset array: src.len * 2 * 8 bytes worst case
    ; but that's too much for large strings — use inline scan instead

    ; Pass 1: write codepoints in reverse using backward scan
    ; For each codepoint from the end, find its leading byte and copy it

    mov     r15, r9             ; r15 = total remaining (shrinks from end)
    xor     r13, r13            ; output write offset (from r12)

.rev_pass:
    test    r15, r15
    jz      .rev_write_out

    ; walk backward from r10 + r15 - 1 to find leading byte
    mov     r11, r15
    dec     r11                 ; last byte index

.find_lead:
    movzx   eax, byte [r10 + r11]
    mov     ecx, eax
    and     ecx, 0xC0
    cmp     ecx, 0x80
    jne     .got_lead_byte      ; not continuation → leading byte

    test    r11, r11
    jz      .rev_bad_utf8
    dec     r11
    jmp     .find_lead

.got_lead_byte:
    ; seq_len = r15 - r11
    mov     rdx, r15
    sub     rdx, r11            ; seq_len

    ; copy sequence [r10 + r11, r10 + r11 + seq_len) → [r12 + r13]
    mov     rdi, r12
    add     rdi, r13
    lea     rsi, [r10 + r11]
    push    r15
    push    r13
    push    rdx
    call    str_copy_bytes
    pop     rdx
    pop     r13
    pop     r15

    add     r13, rdx            ; advance output offset
    mov     r15, r11            ; shrink remaining to before this codepoint
    jmp     .rev_pass

.rev_write_out:
    mov     [r14 + StrSlice.ptr], r12
    mov     [r14 + StrSlice.len], r9

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rev_empty:
    mov     qword [rcx + StrSlice.ptr], 0
    mov     qword [rcx + StrSlice.len], 0

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rev_too_small:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.rev_bad_utf8:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID_UTF8
    pop     rbp
    ret

STR_ENDFUNC str_reverse

; -----------------------------------------------------------------------------
; str_reverse_ascii
;
; Reverse a guaranteed-ASCII string in-place within a buffer.
; Faster than str_reverse — no UTF-8 decoding needed.
;
; Signature:
;   int64_t str_reverse_ascii(uint8_t *buf, uint64_t len)
;
; Arguments:
;   RDI  — buffer (modified in place)
;   RSI  — byte length
; -----------------------------------------------------------------------------

STR_FUNC str_reverse_ascii

    guard_null rdi, STR_ERR_NULL

    ; 0 or 1 bytes → already reversed
    cmp     rsi, 1
    jbe     .ra_done

    push_regs rbx, r12

    mov     rbx, rdi            ; lo ptr
    mov     r12, rdi
    add     r12, rsi
    dec     r12                 ; hi ptr

.ra_loop:
    cmp     rbx, r12
    jae     .ra_done_loop

    movzx   eax, byte [rbx]
    movzx   ecx, byte [r12]
    mov     [rbx], cl
    mov     [r12], al

    inc     rbx
    dec     r12
    jmp     .ra_loop

.ra_done_loop:
    pop_regs r12, rbx

.ra_done:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_reverse_ascii
