; =============================================================================
; str/search/starts.asm
; Check if a StrSlice starts with a given prefix.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/cmp.asm  (str_eq_bytes)
;
; -----------------------------------------------------------------------------
; Functions:
;   str_starts_with         — exact prefix match
;   str_starts_with_nocase  — case-insensitive prefix match
;   str_starts_with_byte    — single byte prefix
;   str_strip_prefix        — if prefix matches, return slice without it
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_eq_bytes

section .text

; -----------------------------------------------------------------------------
; str_starts_with
;
; Check if haystack starts with prefix.
;
; Signature:
;   int64_t str_starts_with(const StrSlice *haystack,
;                            const StrSlice *prefix)
;
; Returns:
;   RAX  = 1  starts with prefix
;   RAX  = 0  does not start with prefix (or null)
; -----------------------------------------------------------------------------

STR_FUNC str_starts_with

    test    rdi, rdi
    jz      .false_sw
    test    rsi, rsi
    jz      .false_sw

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    mov     r8,  [r12 + StrSlice.len]   ; prefix.len

    ; empty prefix → always true
    test    r8, r8
    jz      .true_sw

    ; prefix longer than haystack → false
    mov     r9, [rbx + StrSlice.len]
    cmp     r8, r9
    ja      .false_sw_pop

    ; compare first prefix.len bytes
    mov     rdi, [rbx + StrSlice.ptr]   ; haystack.ptr
    mov     rsi, r8                     ; a_len = prefix.len
    mov     rdx, [r12 + StrSlice.ptr]   ; prefix.ptr
    mov     rcx, r8                     ; b_len = prefix.len
    call    str_eq_bytes

    pop_regs r12, rbx
    ; rax = 1 if equal, 0 if not
    pop     rbp
    ret

.true_sw:
    pop_regs r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false_sw_pop:
    pop_regs r12, rbx
.false_sw:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_starts_with

; -----------------------------------------------------------------------------
; str_starts_with_byte
;
; Check if haystack starts with a specific byte.
;
; Signature:
;   int64_t str_starts_with_byte(const StrSlice *haystack, uint8_t byte_val)
; -----------------------------------------------------------------------------

STR_FUNC str_starts_with_byte

    test    rdi, rdi
    jz      .false_swb

    mov     rax, [rdi + StrSlice.len]
    test    rax, rax
    jz      .false_swb

    mov     rax, [rdi + StrSlice.ptr]
    movzx   eax, byte [rax]
    cmp     al, sil
    sete    al
    movzx   eax, al

    pop     rbp
    ret

.false_swb:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_starts_with_byte

; -----------------------------------------------------------------------------
; str_starts_with_nocase
;
; Case-insensitive prefix check (ASCII fold).
;
; Signature:
;   int64_t str_starts_with_nocase(const StrSlice *haystack,
;                                   const StrSlice *prefix)
; -----------------------------------------------------------------------------

STR_FUNC str_starts_with_nocase

    test    rdi, rdi
    jz      .false_nc
    test    rsi, rsi
    jz      .false_nc

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi

    mov     r13, [r12 + StrSlice.len]

    test    r13, r13
    jz      .true_nc

    cmp     r13, [rbx + StrSlice.len]
    ja      .false_nc_pop

    mov     r8,  [rbx + StrSlice.ptr]
    mov     r9,  [r12 + StrSlice.ptr]
    xor     ecx, ecx

.nc_loop:
    cmp     rcx, r13
    jae     .true_nc

    movzx   eax, byte [r8 + rcx]
    movzx   edx, byte [r9 + rcx]

    cmp     al, 'A'
    jb      .nc_no_fold_a
    cmp     al, 'Z'
    ja      .nc_no_fold_a
    or      al, 0x20
.nc_no_fold_a:
    cmp     dl, 'A'
    jb      .nc_no_fold_b
    cmp     dl, 'Z'
    ja      .nc_no_fold_b
    or      dl, 0x20
.nc_no_fold_b:

    cmp     al, dl
    jne     .false_nc_pop

    inc     rcx
    jmp     .nc_loop

.true_nc:
    pop_regs r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.false_nc_pop:
    pop_regs r13, r12, rbx
.false_nc:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_starts_with_nocase

; -----------------------------------------------------------------------------
; str_strip_prefix
;
; If haystack starts with prefix, return the slice after it.
; If not, return STR_ERR_NOT_FOUND.
;
; Signature:
;   int64_t str_strip_prefix(const StrSlice *haystack,
;                             const StrSlice *prefix,
;                             StrSlice *out)
;
; Arguments:
;   RDI  — haystack
;   RSI  — prefix
;   RDX  — output StrSlice (haystack without prefix)
;
; Returns:
;   RAX  = STR_OK           prefix stripped, result in *out
;   RAX  = STR_ERR_NOT_FOUND haystack does not start with prefix
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_strip_prefix

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    ; check starts_with
    call    str_starts_with
    test    eax, eax
    jz      .sp_not_found

    ; strip: out.ptr = haystack.ptr + prefix.len
    ;        out.len = haystack.len - prefix.len
    mov     rax, [r12 + StrSlice.len]   ; prefix.len
    mov     rcx, [rbx + StrSlice.ptr]
    add     rcx, rax
    mov     [r13 + StrSlice.ptr], rcx

    mov     rcx, [rbx + StrSlice.len]
    sub     rcx, rax
    mov     [r13 + StrSlice.len], rcx

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sp_not_found:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_strip_prefix