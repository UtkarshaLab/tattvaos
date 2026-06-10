; =============================================================================
; str/search/contains.asm
; Check if a StrSlice contains a substring or byte.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   search/find.asm  (str_find, str_find_byte, str_find_nocase)
;
; -----------------------------------------------------------------------------
; All contains functions return 1/0 (predicate form).
; They are thin wrappers over find — the heavy lifting is in find.asm.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_find
extern str_find_byte
extern str_find_nocase

section .text

; -----------------------------------------------------------------------------
; str_contains
;
; Check if haystack contains needle.
;
; Signature:
;   int64_t str_contains(const StrSlice *haystack, const StrSlice *needle)
;
; Returns:
;   RAX  = 1   needle found in haystack
;   RAX  = 0   not found (or null pointer)
; -----------------------------------------------------------------------------

STR_FUNC str_contains

    test    rdi, rdi
    jz      .false
    test    rsi, rsi
    jz      .false

    call    str_find

    ; rax >= 0 → found, rax < 0 → STR_ERR_NOT_FOUND
    test    rax, rax
    js      .false

    mov     eax, STR_TRUE
    pop     rbp
    ret

.false:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_contains

; -----------------------------------------------------------------------------
; str_contains_byte
;
; Check if haystack contains a specific byte value.
;
; Signature:
;   int64_t str_contains_byte(const StrSlice *haystack, uint8_t byte_val)
;
; Returns:
;   RAX  = 1  found
;   RAX  = 0  not found
; -----------------------------------------------------------------------------

STR_FUNC str_contains_byte

    test    rdi, rdi
    jz      .false_cb

    call    str_find_byte

    test    rax, rax
    js      .false_cb

    mov     eax, STR_TRUE
    pop     rbp
    ret

.false_cb:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_contains_byte

; -----------------------------------------------------------------------------
; str_contains_nocase
;
; Case-insensitive contains (ASCII fold).
;
; Signature:
;   int64_t str_contains_nocase(const StrSlice *haystack,
;                                const StrSlice *needle)
; -----------------------------------------------------------------------------

STR_FUNC str_contains_nocase

    test    rdi, rdi
    jz      .false_nc
    test    rsi, rsi
    jz      .false_nc

    call    str_find_nocase

    test    rax, rax
    js      .false_nc

    mov     eax, STR_TRUE
    pop     rbp
    ret

.false_nc:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_contains_nocase

; -----------------------------------------------------------------------------
; str_contains_any_byte
;
; Check if haystack contains ANY byte from a set of bytes.
;
; Signature:
;   int64_t str_contains_any_byte(const StrSlice *haystack,
;                                  const uint8_t *byte_set,
;                                  uint64_t set_len)
;
; Arguments:
;   RDI  — haystack StrSlice
;   RSI  — pointer to byte set
;   RDX  — number of bytes in set
;
; Returns:
;   RAX  = 1  at least one byte from set found
;   RAX  = 0  none found
; -----------------------------------------------------------------------------

STR_FUNC str_contains_any_byte

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    test    rdx, rdx
    jz      .false_any

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; byte set
    mov     r14, rdx            ; set len

    ; build a 256-bit lookup bitset on stack (32 bytes)
    sub     rsp, 32
    and     rsp, -16

    ; zero the bitset
    mov     qword [rsp],      0
    mov     qword [rsp + 8],  0
    mov     qword [rsp + 16], 0
    mov     qword [rsp + 24], 0

    ; set bits for each byte in set
    xor     r15, r15
.build_set:
    cmp     r15, r14
    jae     .set_built

    movzx   eax, byte [r13 + r15]
    ; bit index = byte_val, word = byte_val / 64, bit = byte_val % 64
    mov     ecx, eax
    and     ecx, 63             ; bit position
    shr     eax, 6              ; word index (0..3)
    mov     rdx, 1
    shl     rdx, cl
    or      [rsp + rax * 8], rdx

    inc     r15
    jmp     .build_set

.set_built:
    ; scan haystack
    xor     r15, r15

.scan_any:
    cmp     r15, r12
    jae     .not_found_any

    movzx   eax, byte [rbx + r15]
    mov     ecx, eax
    and     ecx, 63
    shr     eax, 6
    mov     rdx, [rsp + rax * 8]
    bt      rdx, rcx
    jc      .found_any

    inc     r15
    jmp     .scan_any

.found_any:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_found_any:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx

.false_any:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_contains_any_byte

; -----------------------------------------------------------------------------
; str_contains_only_bytes
;
; Check if every byte in haystack belongs to a given byte set.
; Useful for: is this string hex? is this string Base64? etc.
;
; Signature:
;   int64_t str_contains_only_bytes(const StrSlice *haystack,
;                                    const uint8_t *byte_set,
;                                    uint64_t set_len)
; Returns:
;   RAX  = 1  all bytes in haystack are in the set
;   RAX  = 0  at least one byte not in set (or haystack empty)
; -----------------------------------------------------------------------------

STR_FUNC str_contains_only_bytes

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    ; empty haystack → false (no bytes to check)
    mov     rax, [rdi + StrSlice.len]
    test    rax, rax
    jz      .false_only

    test    rdx, rdx
    jz      .false_only

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx

    ; build bitset
    sub     rsp, 32
    and     rsp, -16

    mov     qword [rsp],      0
    mov     qword [rsp + 8],  0
    mov     qword [rsp + 16], 0
    mov     qword [rsp + 24], 0

    xor     r15, r15
.ob_build:
    cmp     r15, r14
    jae     .ob_built

    movzx   eax, byte [r13 + r15]
    mov     ecx, eax
    and     ecx, 63
    shr     eax, 6
    mov     rdx, 1
    shl     rdx, cl
    or      [rsp + rax * 8], rdx

    inc     r15
    jmp     .ob_build

.ob_built:
    xor     r15, r15

.ob_scan:
    cmp     r15, r12
    jae     .ob_all_in_set

    movzx   eax, byte [rbx + r15]
    mov     ecx, eax
    and     ecx, 63
    shr     eax, 6
    mov     rdx, [rsp + rax * 8]
    bt      rdx, rcx
    jnc     .ob_not_in_set

    inc     r15
    jmp     .ob_scan

.ob_all_in_set:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.ob_not_in_set:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx

.false_only:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_contains_only_bytes