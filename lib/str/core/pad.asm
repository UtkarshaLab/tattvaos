; =============================================================================
; str/core/pad.asm
; Pad a StrSlice to a target width with a fill byte or codepoint.
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
;   utf8/len.asm    (str_utf8_len)
;
; -----------------------------------------------------------------------------
; Padding writes into a caller-supplied buffer.
; Width is in CODEPOINTS (not bytes) for Unicode correctness.
; Fill character defaults to space (U+0020) if not specified.
;
; Functions:
;   str_pad_left    — right-align: fill on left
;   str_pad_right   — left-align:  fill on right
;   str_pad_center  — center: fill split between left and right
;   str_pad_byte    — pad with a raw byte (ASCII only, faster)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes
extern str_fill
extern str_utf8_encode_unchecked
extern str_utf8_len

section .text

; -----------------------------------------------------------------------------
; _pad_encode_fill  (internal)
;
; Encode fill_cp into fill_buf, return byte length of encoded fill char.
; Uses stack: caller sets up sub rsp, 16 before calling.
;
; In:  EDI = fill codepoint, RSI = fill_buf ptr
; Out: EAX = fill byte length (1..4)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; str_pad_right
;
; Left-align: write src bytes, then fill on the right.
; If src.codepoint_len >= width, output is a copy of src (no truncation).
;
; Signature:
;   int64_t str_pad_right(const StrSlice *src, uint64_t width,
;                          uint32_t fill_cp, uint8_t *buf,
;                          uint64_t buf_cap, StrSlice *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — target width in codepoints
;   EDX  — fill codepoint (e.g. ' ' = 0x20)
;   RCX  — output buffer
;   R8   — buffer capacity
;   R9   — output StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_pad_right

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    push    r9                  ; save out

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; width
    mov     r13d, edx           ; fill_cp
    mov     r14, rcx            ; buf
    mov     r15, r8             ; cap

    ; get codepoint length of src
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, [rbx + StrSlice.len]
    call    str_utf8_len
    ; rax = src codepoint len

    ; if src_cp_len >= width → just copy src
    cmp     rax, r12
    jae     .pr_no_pad

    mov     r10, r12
    sub     r10, rax            ; pad_count = width - src_cp_len

    ; encode fill char to get fill_bytes
    sub     rsp, 16
    and     rsp, -16

    mov     edi, r13d
    mov     rsi, rsp
    call    str_utf8_encode_unchecked
    ; eax = fill byte length
    mov     r11, rax            ; fill_byte_len

    mov     rsp, rbp

    ; total = src.byte_len + pad_count * fill_byte_len
    mov     rax, r10
    mul     r11                 ; rax = pad total bytes
    jc      .pr_overflow

    mov     rsi, [rbx + StrSlice.len]
    add     rax, rsi
    jc      .pr_overflow

    cmp     rax, r15
    ja      .pr_too_small

    mov     r8, rax             ; total output len

    ; copy src
    mov     rdi, r14
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, [rbx + StrSlice.len]
    call    str_copy_bytes

    ; write fill chars
    mov     r9, r14
    add     r9, [rbx + StrSlice.len]   ; write ptr after src

    ; encode fill byte(s) into temp, then repeat
    sub     rsp, 16
    and     rsp, -16

    mov     edi, r13d
    mov     rsi, rsp
    call    str_utf8_encode_unchecked
    ; eax = fill_byte_len, [rsp..rsp+eax-1] = encoded fill

    mov     r11, rax
    mov     rsp, rbp

    ; repeat r10 times
    push    r10
    push    r11
    push    r9

    ; re-encode to stack for the loop
    sub     rsp, 16
    and     rsp, -16

    mov     edi, r13d
    mov     rsi, rsp
    call    str_utf8_encode_unchecked

    pop     r9
    pop     r11
    pop     r10

.pr_fill_loop:
    test    r10, r10
    jz      .pr_fill_done

    mov     rdi, r9
    mov     rsi, rsp
    mov     rdx, r11
    call    str_copy_bytes

    add     r9, r11
    dec     r10
    jmp     .pr_fill_loop

.pr_fill_done:
    mov     rsp, rbp

    pop     r9
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pr_no_pad:
    ; no padding needed — copy src into buf
    mov     r8, [rbx + StrSlice.len]
    cmp     r8, r15
    ja      .pr_too_small

    mov     rdi, r14
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, r8
    call    str_copy_bytes

    pop     r9
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pr_overflow:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.pr_too_small:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_pad_right

; -----------------------------------------------------------------------------
; str_pad_left
;
; Right-align: fill on the left, then src bytes.
;
; Signature:
;   int64_t str_pad_left(const StrSlice *src, uint64_t width,
;                         uint32_t fill_cp, uint8_t *buf,
;                         uint64_t buf_cap, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_pad_left

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    push    r9

    mov     rbx, rdi
    mov     r12, rsi            ; width
    mov     r13d, edx           ; fill_cp
    mov     r14, rcx            ; buf
    mov     r15, r8             ; cap

    ; get src codepoint length
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, [rbx + StrSlice.len]
    call    str_utf8_len

    cmp     rax, r12
    jae     .pl_no_pad

    mov     r10, r12
    sub     r10, rax            ; pad_count

    ; encode fill char
    sub     rsp, 16
    and     rsp, -16

    mov     edi, r13d
    mov     rsi, rsp
    call    str_utf8_encode_unchecked
    mov     r11, rax            ; fill_byte_len
    ; encoded fill at [rsp..rsp+r11-1]

    ; total = pad_count * fill_byte_len + src.byte_len
    mov     rax, r10
    mul     r11
    jc      .pl_overflow

    mov     rsi, [rbx + StrSlice.len]
    add     rax, rsi
    jc      .pl_overflow

    cmp     rax, r15
    ja      .pl_too_small

    mov     r8, rax             ; total

    ; write fill chars first
    mov     r9, r14             ; write cursor

.pl_fill_loop:
    test    r10, r10
    jz      .pl_fill_done

    mov     rdi, r9
    mov     rsi, rsp
    mov     rdx, r11
    call    str_copy_bytes

    add     r9, r11
    dec     r10
    jmp     .pl_fill_loop

.pl_fill_done:
    mov     rsp, rbp

    ; copy src
    mov     rdi, r9
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, [rbx + StrSlice.len]
    call    str_copy_bytes

    pop     r9
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pl_no_pad:
    mov     r8, [rbx + StrSlice.len]
    cmp     r8, r15
    ja      .pl_too_small

    mov     rdi, r14
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, r8
    call    str_copy_bytes

    pop     r9
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pl_overflow:
    mov     rsp, rbp
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.pl_too_small:
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_pad_left

; -----------------------------------------------------------------------------
; str_pad_center
;
; Center: split padding evenly. Extra pad goes on the right.
;
; Signature:
;   int64_t str_pad_center(const StrSlice *src, uint64_t width,
;                           uint32_t fill_cp, uint8_t *buf,
;                           uint64_t buf_cap, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_pad_center

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    push    r9

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     r14, rcx
    mov     r15, r8

    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, [rbx + StrSlice.len]
    call    str_utf8_len

    cmp     rax, r12
    jae     .pc_no_pad

    mov     r10, r12
    sub     r10, rax            ; total_pad

    mov     r11, r10
    shr     r11, 1              ; left_pad = total_pad / 2
    mov     r10, r10
    sub     r10, r11            ; right_pad = total_pad - left_pad

    ; encode fill
    sub     rsp, 16
    and     rsp, -16

    mov     edi, r13d
    mov     rsi, rsp
    call    str_utf8_encode_unchecked
    mov     r8, rax             ; fill_byte_len

    ; check total capacity
    mov     rax, r11
    add     rax, r10            ; total_pad_cp
    mul     r8
    jc      .pc_overflow

    add     rax, [rbx + StrSlice.len]
    jc      .pc_overflow
    cmp     rax, r15
    ja      .pc_too_small

    mov     r9, r14             ; write cursor

    ; write left pad
    push    r10
    push    r11

.pc_left_loop:
    test    r11, r11
    jz      .pc_left_done

    mov     rdi, r9
    mov     rsi, rsp
    mov     rdx, r8
    call    str_copy_bytes
    add     r9, r8
    dec     r11
    jmp     .pc_left_loop

.pc_left_done:
    pop     r11

    ; copy src
    mov     rdi, r9
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, [rbx + StrSlice.len]
    call    str_copy_bytes
    add     r9, [rbx + StrSlice.len]

    pop     r10

    ; write right pad
.pc_right_loop:
    test    r10, r10
    jz      .pc_right_done

    mov     rdi, r9
    mov     rsi, rsp
    mov     rdx, r8
    call    str_copy_bytes
    add     r9, r8
    dec     r10
    jmp     .pc_right_loop

.pc_right_done:
    ; total len = r9 - r14
    mov     rax, r9
    sub     rax, r14

    mov     rsp, rbp
    pop     r9
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pc_no_pad:
    mov     r8, [rbx + StrSlice.len]
    cmp     r8, r15
    ja      .pc_too_small

    mov     rdi, r14
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, r8
    call    str_copy_bytes

    mov     rsp, rbp
    pop     r9
    mov     [r9 + StrSlice.ptr], r14
    mov     [r9 + StrSlice.len], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pc_overflow:
    mov     rsp, rbp
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.pc_too_small:
    mov     rsp, rbp
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_pad_center
