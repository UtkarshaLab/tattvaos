; =============================================================================
; str/core/trim.asm
; Strip leading and/or trailing whitespace (or custom bytes) from a StrSlice.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_space.asm  (str_is_space_cp)
;   utf8/decode.asm       (str_utf8_decode_unchecked)
;   utf8/charlen.asm      (str_utf8_charlen)
;
; -----------------------------------------------------------------------------
; All trim operations return a StrSlice that is a sub-view of the input.
; No allocation, no copy — just pointer + length adjustment.
;
; Functions:
;   str_trim        — strip both ends (Unicode whitespace)
;   str_trim_start  — strip leading whitespace
;   str_trim_end    — strip trailing whitespace
;   str_trim_ascii  — ASCII-only whitespace trim (faster)
;   str_trim_byte   — strip a specific byte from both ends
;   str_trim_slice  — strip a specific string prefix/suffix
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_is_space_cp
extern str_utf8_decode_unchecked
extern str_utf8_charlen

section .text

; -----------------------------------------------------------------------------
; str_trim_start
;
; Remove leading Unicode whitespace from a StrSlice.
; Returns a sub-slice (no copy).
;
; Signature:
;   int64_t str_trim_start(const StrSlice *src, StrSlice *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — output StrSlice
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  src or out is null
; -----------------------------------------------------------------------------

STR_FUNC str_trim_start

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; out
    mov     r13, [rbx + StrSlice.ptr]   ; current ptr
    mov     r14, [rbx + StrSlice.len]   ; remaining len
    mov     r9,  r13
    add     r9,  r14            ; end ptr

.ts_loop:
    test    r14, r14
    jz      .ts_done            ; all whitespace → empty result

    ; decode codepoint
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, r13
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r8, [rsp]           ; advance
    mov     rsp, rbp

    ; check if whitespace
    mov     edi, eax
    push    r13
    push    r14
    push    r8
    call    str_is_space_cp
    pop     r8
    pop     r14
    pop     r13

    test    eax, eax
    jz      .ts_done            ; not whitespace → stop

    add     r13, r8
    sub     r14, r8
    jmp     .ts_loop

.ts_done:
    mov     [r12 + StrSlice.ptr], r13
    mov     [r12 + StrSlice.len], r14

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_trim_start

; -----------------------------------------------------------------------------
; str_trim_end
;
; Remove trailing Unicode whitespace from a StrSlice.
; Walks backward — finds last non-whitespace codepoint boundary.
;
; Signature:
;   int64_t str_trim_end(const StrSlice *src, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_trim_end

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, [rbx + StrSlice.ptr]   ; base ptr
    mov     r14, [rbx + StrSlice.len]   ; byte len

    ; start from last byte
    mov     r9, r14             ; new length (shrinks from end)

.te_loop:
    test    r9, r9
    jz      .te_done

    ; walk backward past continuation bytes to find leading byte
    mov     r8, r9
    dec     r8                  ; last byte index

.te_find_lead:
    movzx   eax, byte [r13 + r8]
    mov     ecx, eax
    and     ecx, 0xC0
    cmp     ecx, 0x80
    jne     .te_got_lead        ; found leading byte
    test    r8, r8
    jz      .te_done            ; malformed — stop
    dec     r8
    jmp     .te_find_lead

.te_got_lead:
    ; decode codepoint at r13 + r8
    sub     rsp, 16
    and     rsp, -16

    lea     rdi, [r13 + r8]
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     rsp, rbp

    ; check whitespace
    mov     edi, eax
    push    r8
    push    r9
    call    str_is_space_cp
    pop     r9
    pop     r8

    test    eax, eax
    jz      .te_done            ; not whitespace → stop

    ; trim: new length = r8 (index of leading byte)
    mov     r9, r8
    jmp     .te_loop

.te_done:
    mov     [r12 + StrSlice.ptr], r13
    mov     [r12 + StrSlice.len], r9

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_trim_end

; -----------------------------------------------------------------------------
; str_trim
;
; Remove both leading and trailing Unicode whitespace.
;
; Signature:
;   int64_t str_trim(const StrSlice *src, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_trim

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    ; trim start first (writes into out)
    mov     rsi, r12
    call    str_trim_start
    test    rax, rax
    jnz     .trim_err

    ; trim end on the result (out → out)
    mov     rdi, r12
    mov     rsi, r12
    call    str_trim_end

.trim_err:
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_trim

; -----------------------------------------------------------------------------
; str_trim_ascii
;
; ASCII-only whitespace trim — both ends. No UTF-8 decoding.
; Faster than str_trim for known-ASCII input.
;
; Signature:
;   int64_t str_trim_ascii(const StrSlice *src, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_trim_ascii

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, [rbx + StrSlice.ptr]
    mov     r14, [rbx + StrSlice.len]

    ; trim leading
.ta_start:
    test    r14, r14
    jz      .ta_done

    movzx   eax, byte [r13]

    ; SP = 0x20
    cmp     al, 0x20
    je      .ta_adv_start
    ; HT..CR = 0x09..0x0D
    cmp     al, 0x09
    jb      .ta_trim_end
    cmp     al, 0x0D
    ja      .ta_trim_end

.ta_adv_start:
    inc     r13
    dec     r14
    jmp     .ta_start

.ta_trim_end:
    ; trim trailing
.ta_end:
    test    r14, r14
    jz      .ta_done

    movzx   eax, byte [r13 + r14 - 1]

    cmp     al, 0x20
    je      .ta_adv_end
    cmp     al, 0x09
    jb      .ta_done
    cmp     al, 0x0D
    ja      .ta_done

.ta_adv_end:
    dec     r14
    jmp     .ta_end

.ta_done:
    mov     [r12 + StrSlice.ptr], r13
    mov     [r12 + StrSlice.len], r14

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_trim_ascii

; -----------------------------------------------------------------------------
; str_trim_byte
;
; Trim a specific byte value from both ends of a StrSlice.
;
; Signature:
;   int64_t str_trim_byte(const StrSlice *src, uint8_t byte_val,
;                          StrSlice *out)
;
; Arguments:
;   RDI  — source StrSlice
;   SIL  — byte value to trim
;   RDX  — output StrSlice
; -----------------------------------------------------------------------------

STR_FUNC str_trim_byte

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    movzx   r12d, sil           ; trim byte
    mov     r13, [rbx + StrSlice.ptr]
    mov     r14, [rbx + StrSlice.len]

.tb_start:
    test    r14, r14
    jz      .tb_done

    movzx   eax, byte [r13]
    cmp     al, r12b
    jne     .tb_trim_end

    inc     r13
    dec     r14
    jmp     .tb_start

.tb_trim_end:
.tb_end:
    test    r14, r14
    jz      .tb_done

    movzx   eax, byte [r13 + r14 - 1]
    cmp     al, r12b
    jne     .tb_done

    dec     r14
    jmp     .tb_end

.tb_done:
    mov     [rdx + StrSlice.ptr], r13
    mov     [rdx + StrSlice.len], r14

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_trim_byte
