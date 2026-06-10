; =============================================================================
; str/hash/fnv1a.asm
; FNV-1a (Fowler-Noll-Vo) hash — 32-bit and 64-bit variants.
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
; FNV-1a algorithm:
;
;   hash = offset_basis
;   for each byte b:
;       hash = hash XOR b
;       hash = hash * prime
;
; Constants:
;   32-bit: offset = 0x811C9DC5, prime = 0x01000193
;   64-bit: offset = 0xCBF29CE484222325, prime = 0x00000100000001B3
;
; Properties:
;   - Simple and fast (XOR + multiply per byte)
;   - Good avalanche for small keys
;   - NOT cryptographic — do not use for security
;   - Excellent for hash tables, symbol lookup
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; FNV constants
FNV32_OFFSET    equ 0x811C9DC5
FNV32_PRIME     equ 0x01000193
FNV64_OFFSET    equ 0xCBF29CE484222325
FNV64_PRIME     equ 0x00000100000001B3

section .text

; -----------------------------------------------------------------------------
; str_fnv1a_32
;
; Compute FNV-1a 32-bit hash of a byte buffer.
;
; Signature:
;   int64_t str_fnv1a_32(const uint8_t *data, uint64_t len, uint32_t *out)
;
; Arguments:
;   RDI  — data pointer
;   RSI  — byte length
;   RDX  — pointer to uint32_t to receive hash
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_fnv1a_32

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi            ; data
    mov     r12, rsi            ; len

    ; init hash = offset_basis
    mov     eax, FNV32_OFFSET
    xor     ecx, ecx            ; index

.fnv32_loop:
    cmp     rcx, r12
    jae     .fnv32_done

    ; hash ^= data[i]
    movzx   r8d, byte [rbx + rcx]
    xor     eax, r8d

    ; hash *= prime
    imul    eax, eax, FNV32_PRIME

    inc     rcx
    jmp     .fnv32_loop

.fnv32_done:
    mov     [rdx], eax

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_fnv1a_32

; -----------------------------------------------------------------------------
; str_fnv1a_32_slice
;
; FNV-1a 32-bit hash of a StrSlice.
;
; Signature:
;   int64_t str_fnv1a_32_slice(const StrSlice *slice, uint32_t *out)
; -----------------------------------------------------------------------------

STR_FUNC str_fnv1a_32_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rdx, rsi
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]

    pop     rbp
    jmp     str_fnv1a_32

STR_ENDFUNC str_fnv1a_32_slice

; -----------------------------------------------------------------------------
; str_fnv1a_64
;
; Compute FNV-1a 64-bit hash of a byte buffer.
;
; Signature:
;   int64_t str_fnv1a_64(const uint8_t *data, uint64_t len, uint64_t *out)
;
; Arguments:
;   RDI  — data pointer
;   RSI  — byte length
;   RDX  — pointer to uint64_t to receive hash
; -----------------------------------------------------------------------------

STR_FUNC str_fnv1a_64

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    ; init hash = offset_basis (64-bit)
    mov     rax, FNV64_OFFSET
    xor     ecx, ecx

.fnv64_loop:
    cmp     rcx, r12
    jae     .fnv64_done

    movzx   r8d, byte [rbx + rcx]
    xor     rax, r8

    ; hash *= prime (64-bit)
    mov     r9, FNV64_PRIME
    imul    rax, r9

    inc     rcx
    jmp     .fnv64_loop

.fnv64_done:
    mov     [r13], rax

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_fnv1a_64

; -----------------------------------------------------------------------------
; str_fnv1a_64_slice — StrSlice wrapper
; -----------------------------------------------------------------------------

STR_FUNC str_fnv1a_64_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rdx, rsi
    mov     rsi, [rdi + StrSlice.len]
    mov     rdi, [rdi + StrSlice.ptr]

    pop     rbp
    jmp     str_fnv1a_64

STR_ENDFUNC str_fnv1a_64_slice

; -----------------------------------------------------------------------------
; str_fnv1a_32_incremental
;
; Incrementally update a running FNV-1a 32-bit hash.
; Allows hashing data in chunks without storing the full buffer.
;
; Signature:
;   uint32_t str_fnv1a_32_incremental(uint32_t running_hash,
;                                      const uint8_t *data, uint64_t len)
;
; Arguments:
;   EDI  — current hash value (or FNV32_OFFSET for first call)
;   RSI  — data pointer
;   RDX  — byte length
;
; Returns:
;   EAX  — updated hash value
; -----------------------------------------------------------------------------

STR_FUNC str_fnv1a_32_incremental

    push_regs rbx, r12

    mov     eax, edi            ; running hash
    mov     rbx, rsi            ; data
    mov     r12, rdx            ; len
    xor     ecx, ecx

.fnv32i_loop:
    cmp     rcx, r12
    jae     .fnv32i_done

    movzx   r8d, byte [rbx + rcx]
    xor     eax, r8d
    imul    eax, eax, FNV32_PRIME

    inc     rcx
    jmp     .fnv32i_loop

.fnv32i_done:
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_fnv1a_32_incremental

; -----------------------------------------------------------------------------
; str_fnv1a_64_incremental — 64-bit incremental variant
; -----------------------------------------------------------------------------

STR_FUNC str_fnv1a_64_incremental

    push_regs rbx, r12

    mov     rax, rdi            ; running hash
    mov     rbx, rsi
    mov     r12, rdx
    xor     ecx, ecx

.fnv64i_loop:
    cmp     rcx, r12
    jae     .fnv64i_done

    movzx   r8d, byte [rbx + rcx]
    xor     rax, r8

    mov     r9, FNV64_PRIME
    imul    rax, r9

    inc     rcx
    jmp     .fnv64i_loop

.fnv64i_done:
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_fnv1a_64_incremental