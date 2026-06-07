; =============================================================================
; str/utf8/bom.asm
; UTF-8 BOM (Byte Order Mark) detection, stripping, and writing.
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
; The UTF-8 BOM is the three-byte sequence: EF BB BF
; It encodes U+FEFF (ZERO WIDTH NO-BREAK SPACE) in UTF-8.
;
; It is OPTIONAL in UTF-8. Many Unix tools reject it. Windows tools
; often emit it. The str library treats it as:
;   - Valid UTF-8 (it is, technically)
;   - A nuisance at string boundaries to be stripped on ingestion
;
; Functions:
;   str_utf8_has_bom         — does buffer start with EF BB BF?
;   str_utf8_strip_bom       — return StrSlice with BOM removed if present
;   str_utf8_write_bom       — write EF BB BF into a buffer
;   str_utf8_strip_bom_slice — strip BOM from a StrSlice in place
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata

; UTF-8 BOM bytes
UTF8_BOM_B0     equ 0xEF
UTF8_BOM_B1     equ 0xBB
UTF8_BOM_B2     equ 0xBF
UTF8_BOM_LEN    equ 3

section .text

; -----------------------------------------------------------------------------
; str_utf8_has_bom
;
; Check whether a byte buffer starts with the UTF-8 BOM (EF BB BF).
;
; Signature:
;   int64_t str_utf8_has_bom(const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to byte buffer
;   RSI  — byte length
;
; Returns:
;   RAX  = 1   BOM present (first 3 bytes are EF BB BF)
;   RAX  = 0   no BOM (or buffer shorter than 3 bytes)
;   RAX  = STR_ERR_NULL  ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_has_bom

    guard_null rdi, STR_ERR_NULL

    ; need at least 3 bytes
    cmp     rsi, UTF8_BOM_LEN
    jb      .no_bom

    movzx   eax, byte [rdi]
    cmp     al, UTF8_BOM_B0
    jne     .no_bom

    movzx   eax, byte [rdi + 1]
    cmp     al, UTF8_BOM_B1
    jne     .no_bom

    movzx   eax, byte [rdi + 2]
    cmp     al, UTF8_BOM_B2
    jne     .no_bom

    mov     eax, STR_TRUE
    pop     rbp
    ret

.no_bom:
    mov     eax, STR_FALSE
    pop     rbp
    ret

STR_ENDFUNC str_utf8_has_bom

; -----------------------------------------------------------------------------
; str_utf8_strip_bom
;
; Return a StrSlice that skips the BOM if present, otherwise returns
; a slice over the full buffer. Does NOT modify the original buffer.
;
; Signature:
;   int64_t str_utf8_strip_bom(const uint8_t *ptr, uint64_t byte_len,
;                               StrSlice *out_slice)
;
; Arguments:
;   RDI  — pointer to byte buffer
;   RSI  — byte length
;   RDX  — pointer to StrSlice to receive result
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  ptr or out_slice is null
;
; The output slice always points into the same buffer — no copy made.
; If BOM present: out_slice.ptr = ptr+3, out_slice.len = byte_len-3
; If no BOM:      out_slice.ptr = ptr,   out_slice.len = byte_len
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_strip_bom

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    ; check BOM
    cmp     rsi, UTF8_BOM_LEN
    jb      .no_bom_slice

    movzx   eax, byte [rdi]
    cmp     al, UTF8_BOM_B0
    jne     .no_bom_slice

    movzx   eax, byte [rdi + 1]
    cmp     al, UTF8_BOM_B1
    jne     .no_bom_slice

    movzx   eax, byte [rdi + 2]
    cmp     al, UTF8_BOM_B2
    jne     .no_bom_slice

    ; BOM found — skip 3 bytes
    lea     rax, [rdi + UTF8_BOM_LEN]
    mov     [rdx + StrSlice.ptr], rax
    mov     rax, rsi
    sub     rax, UTF8_BOM_LEN
    mov     [rdx + StrSlice.len], rax
    jmp     .ok

.no_bom_slice:
    mov     [rdx + StrSlice.ptr], rdi
    mov     [rdx + StrSlice.len], rsi

.ok:
    xor     eax, eax                ; STR_OK
    pop     rbp
    ret

STR_ENDFUNC str_utf8_strip_bom

; -----------------------------------------------------------------------------
; str_utf8_strip_bom_slice
;
; Strip BOM from a StrSlice in place — modifies slice.ptr and slice.len
; if a BOM is present. No-op if no BOM.
;
; Signature:
;   int64_t str_utf8_strip_bom_slice(StrSlice *slice)
;
; Arguments:
;   RDI  — pointer to StrSlice (modified in place)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL  slice is null
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_strip_bom_slice

    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.ptr]
    mov     rsi, [rdi + StrSlice.len]

    ; need at least 3 bytes
    cmp     rsi, UTF8_BOM_LEN
    jb      .no_bom_inplace

    movzx   ecx, byte [rax]
    cmp     cl, UTF8_BOM_B0
    jne     .no_bom_inplace

    movzx   ecx, byte [rax + 1]
    cmp     cl, UTF8_BOM_B1
    jne     .no_bom_inplace

    movzx   ecx, byte [rax + 2]
    cmp     cl, UTF8_BOM_B2
    jne     .no_bom_inplace

    ; advance ptr by 3, reduce len by 3
    add     rax, UTF8_BOM_LEN
    sub     rsi, UTF8_BOM_LEN
    mov     [rdi + StrSlice.ptr], rax
    mov     [rdi + StrSlice.len], rsi

.no_bom_inplace:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_utf8_strip_bom_slice

; -----------------------------------------------------------------------------
; str_utf8_write_bom
;
; Write the UTF-8 BOM (EF BB BF) into a buffer.
; Used when producing output that Windows consumers expect to have a BOM.
;
; Signature:
;   int64_t str_utf8_write_bom(uint8_t *buf, uint64_t buf_cap)
;
; Arguments:
;   RDI  — pointer to output buffer
;   RSI  — buffer capacity (must be >= 3)
;
; Returns:
;   RAX  = STR_OK               BOM written (3 bytes)
;   RAX  = STR_ERR_NULL         buf is null
;   RAX  = STR_ERR_BUF_TOO_SMALL buf_cap < 3
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_write_bom

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, UTF8_BOM_LEN
    jb      .too_small

    mov     byte [rdi],     UTF8_BOM_B0
    mov     byte [rdi + 1], UTF8_BOM_B1
    mov     byte [rdi + 2], UTF8_BOM_B2

    xor     eax, eax
    pop     rbp
    ret

.too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf8_write_bom

; -----------------------------------------------------------------------------
; str_utf8_bom_len
;
; Return the byte length of the BOM if present, 0 otherwise.
; Convenience for "how many bytes to skip?"
;
; Signature:
;   int64_t str_utf8_bom_len(const uint8_t *ptr, uint64_t byte_len)
;
; Arguments:
;   RDI  — pointer to byte buffer
;   RSI  — byte length
;
; Returns:
;   RAX  = 3  BOM present
;   RAX  = 0  no BOM
;   RAX  = STR_ERR_NULL  ptr is null
; -----------------------------------------------------------------------------

STR_FUNC str_utf8_bom_len

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, UTF8_BOM_LEN
    jb      .zero

    movzx   eax, byte [rdi]
    cmp     al, UTF8_BOM_B0
    jne     .zero

    movzx   eax, byte [rdi + 1]
    cmp     al, UTF8_BOM_B1
    jne     .zero

    movzx   eax, byte [rdi + 2]
    cmp     al, UTF8_BOM_B2
    jne     .zero

    mov     eax, UTF8_BOM_LEN
    pop     rbp
    ret

.zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_utf8_bom_len