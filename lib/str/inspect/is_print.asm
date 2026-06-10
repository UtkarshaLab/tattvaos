; =============================================================================
; str/inspect/is_print.asm
; Check whether a codepoint or string contains only printable characters.
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
; Printable definition used here:
;
;   ASCII printable:  0x20..0x7E  (space through tilde — no DEL 0x7F)
;   Non-printable:    0x00..0x1F  (C0 controls)
;                     0x7F        (DEL)
;                     0x80..0x9F  (C1 controls — Latin-1)
;
;   Unicode printable: everything NOT in the following categories:
;     Cc — control characters   (includes C0, DEL, C1)
;     Cs — surrogates
;     Cn — unassigned
;
;   In practice: valid codepoint AND not a control character.
;   We check:
;     - 0x00..0x1F  → not printable (C0 controls)
;     - 0x7F        → not printable (DEL)
;     - 0x80..0x9F  → not printable (C1 controls)
;     - 0xD800..0xDFFF → not printable (surrogates)
;     - > 0x10FFFF  → not printable (out of Unicode range)
;     - Everything else → printable
;
; str_is_print_cp     — Unicode-aware
; str_is_ascii_print  — ASCII only (0x20..0x7E)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; str_is_print_cp
;
; Check if a codepoint is printable.
;
; Signature:
;   int64_t str_is_print_cp(uint32_t cp)
;
; Returns:
;   RAX  = 1  printable
;   RAX  = 0  not printable (control, surrogate, or out of range)
; -----------------------------------------------------------------------------

STR_FUNC str_is_print_cp

    ; out of Unicode range
    cmp     edi, CODEPOINT_MAX
    ja      .false

    ; C0 controls: 0x00..0x1F
    cmp     edi, 0x1F
    jbe     .false

    ; DEL: 0x7F
    cmp     edi, 0x7F
    je      .false

    ; C1 controls: 0x80..0x9F
    cmp     edi, 0x80
    jb      .true               ; 0x20..0x7E → printable ASCII
    cmp     edi, 0x9F
    jbe     .false

    ; surrogates: 0xD800..0xDFFF
    cmp     edi, SURROGATE_HIGH_MIN
    jb      .true
    cmp     edi, SURROGATE_LOW_MAX
    jbe     .false

.true:
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_is_print_cp

; -----------------------------------------------------------------------------
; str_is_ascii_print_byte
;
; Fast ASCII printable check: byte in 0x20..0x7E.
;
; Signature:
;   int64_t str_is_ascii_print_byte(uint8_t byte)
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_print_byte

    movzx   eax, dil
    sub     eax, 0x20           ; shift so 0x20 → 0
    cmp     eax, 0x5E           ; 0x7E - 0x20 = 0x5E
    setbe   al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_print_byte

; -----------------------------------------------------------------------------
; str_is_print
;
; Check if every codepoint in a UTF-8 string is printable.
;
; Signature:
;   int64_t str_is_print(const uint8_t *ptr, uint64_t byte_len)
;
; Returns:
;   RAX  = 1  all printable, non-empty
;   RAX  = 0  empty or any control/surrogate codepoint present
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_is_print

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.print_loop:
    cmp     rbx, r12
    jae     .all_print

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     r13, [rsp]
    mov     rsp, rbp
    add     rbx, r13

    mov     edi, eax
    push    rbx
    push    r12
    call    str_is_print_cp
    pop     r12
    pop     rbx

    test    eax, eax
    jz      .not_print

    jmp     .print_loop

.all_print:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_print:
    pop_regs r13, r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_print

; -----------------------------------------------------------------------------
; str_is_ascii_print
;
; ASCII-only printable check — no UTF-8 decoding. Rejects any byte >= 0x7F.
;
; Signature:
;   int64_t str_is_ascii_print(const uint8_t *ptr, uint64_t byte_len)
; -----------------------------------------------------------------------------

STR_FUNC str_is_ascii_print

    guard_null rdi, STR_ERR_NULL

    test    rsi, rsi
    jz      .false

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi
    add     r12, rbx

.ap_loop:
    cmp     rbx, r12
    jae     .ap_true

    movzx   eax, byte [rbx]
    inc     rbx

    sub     eax, 0x20
    cmp     eax, 0x5E
    ja      .ap_false

    jmp     .ap_loop

.ap_true:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.ap_false:
    pop_regs r12, rbx

.false:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_is_ascii_print

; -----------------------------------------------------------------------------
; str_is_print_slice — StrSlice wrapper
; -----------------------------------------------------------------------------

STR_FUNC str_is_print_slice

    guard_null rdi, STR_ERR_NULL
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]
    pop     rbp
    jmp     str_is_print

STR_ENDFUNC str_is_print_slice