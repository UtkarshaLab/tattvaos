; =============================================================================
; str/hash/murmur3.asm
; MurmurHash3 by Austin Appleby — 32-bit and 128-bit x64 variants.
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
; MurmurHash3 algorithm (128-bit x64 variant):
;
;   Process 16-byte blocks:
;     k1 = block[0..7]
;     k2 = block[8..15]
;     k1 *= C1; k1 = rotl(k1, 31); k1 *= C2; h1 ^= k1
;     h1 = rotl(h1, 27); h1 += h2; h1 = h1*5 + 0x52DCE729
;     k2 *= C2; k2 = rotl(k2, 33); k2 *= C1; h2 ^= k2
;     h2 = rotl(h2, 31); h2 += h1; h2 = h2*5 + 0x38495AB5
;
;   Tail: handle remaining 1..15 bytes
;   Finalization: fmix64 on h1, h2
;
; Constants:
;   C1 = 0x87C37B91114253D5
;   C2 = 0x4CF5AD432745937F
;
; Properties:
;   - Excellent avalanche (all output bits depend on all input bits)
;   - NOT cryptographic — seed-dependent, but seed is not a secret
;   - Fast on 64-bit hardware: processes 16 bytes per 2 multiplies
;   - Good for bloom filters, consistent hashing, hash tables
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; MurmurHash3 x64 128 constants
MM3_C1  equ 0x87C37B91114253D5
MM3_C2  equ 0x4CF5AD432745937F

; fmix64 macro — finalizer for 64-bit word
; Input/output in register reg, uses rax as temp
%macro FMIX64 1
    xor     %1, %1              ; wrong — fmix64 doesn't XOR with itself
    ; correct fmix64:
    mov     rax, %1
    shr     rax, 33
    xor     %1, rax
    mov     rax, 0xFF51AFD7ED558CCD
    imul    %1, rax
    mov     rax, %1
    shr     rax, 33
    xor     %1, rax
    mov     rax, 0xC4CEB9FE1A85EC53
    imul    %1, rax
    mov     rax, %1
    shr     rax, 33
    xor     %1, rax
%endmacro

section .text

; -----------------------------------------------------------------------------
; str_murmur3_32
;
; MurmurHash3 32-bit variant.
;
; Signature:
;   int64_t str_murmur3_32(const uint8_t *data, uint64_t len,
;                           uint32_t seed, uint32_t *out)
;
; Arguments:
;   RDI  — data
;   RSI  — len
;   EDX  — seed
;   RCX  — out
; -----------------------------------------------------------------------------

; MurmurHash3_x86_32 constants
MM3_32_C1   equ 0xCC9E2D51
MM3_32_C2   equ 0x1B873593

STR_FUNC str_murmur3_32

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; data
    mov     r12, rsi            ; len
    mov     r13d, edx           ; seed → h
    mov     r14, rcx            ; out

    mov     eax, r13d           ; h = seed

    ; number of 4-byte blocks
    mov     r9, r12
    shr     r9, 2
    xor     rcx, rcx

.mm32_block_loop:
    cmp     rcx, r9
    jae     .mm32_tail

    ; load 4 bytes
    mov     r10d, dword [rbx + rcx * 4]

    ; k *= C1
    imul    r10d, r10d, MM3_32_C1

    ; k = rotl32(k, 15)
    rol     r10d, 15

    ; k *= C2
    imul    r10d, r10d, MM3_32_C2

    ; h ^= k
    xor     eax, r10d

    ; h = rotl32(h, 13)
    rol     eax, 13

    ; h = h*5 + 0xE6546B64
    lea     eax, [eax + eax * 4]    ; h * 5
    add     eax, 0xE6546B64

    inc     rcx
    jmp     .mm32_block_loop

.mm32_tail:
    ; tail bytes: len & 3 remaining
    mov     r9, r12
    and     r9, 3
    test    r9, r9
    jz      .mm32_finalize

    xor     r10d, r10d
    ; byte offset to tail = len - (len & 3) = len & ~3
    mov     r11, r12
    and     r11, ~3

    ; load remaining bytes in little-endian
    cmp     r9, 3
    jb      .mm32_tail_2
    movzx   ecx, byte [rbx + r11 + 2]
    shl     ecx, 16
    or      r10d, ecx

.mm32_tail_2:
    cmp     r9, 2
    jb      .mm32_tail_1
    movzx   ecx, byte [rbx + r11 + 1]
    shl     ecx, 8
    or      r10d, ecx

.mm32_tail_1:
    movzx   ecx, byte [rbx + r11]
    or      r10d, ecx

    imul    r10d, r10d, MM3_32_C1
    rol     r10d, 15
    imul    r10d, r10d, MM3_32_C2
    xor     eax, r10d

.mm32_finalize:
    ; h ^= len
    xor     eax, r12d

    ; fmix32
    mov     r9d, eax
    shr     r9d, 16
    xor     eax, r9d
    imul    eax, eax, 0x85EBCA6B
    mov     r9d, eax
    shr     r9d, 13
    xor     eax, r9d
    imul    eax, eax, 0xC2B2AE35
    mov     r9d, eax
    shr     r9d, 16
    xor     eax, r9d

    mov     [r14], eax

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_murmur3_32

; -----------------------------------------------------------------------------
; str_murmur3_128
;
; MurmurHash3 128-bit x64 variant. Returns 16 bytes.
;
; Signature:
;   int64_t str_murmur3_128(const uint8_t *data, uint64_t len,
;                            uint32_t seed, uint8_t *out)
;
; Arguments:
;   RDI  — data
;   RSI  — len
;   EDX  — seed
;   RCX  — out (16 bytes: h1 at [rcx], h2 at [rcx+8])
; -----------------------------------------------------------------------------

STR_FUNC str_murmur3_128

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx           ; seed
    mov     r14, rcx            ; out

    ; h1 = h2 = seed
    mov     r8d, r13d           ; h1
    mov     r9d, r13d           ; h2
    movsxd  r8, r8d             ; zero extend to 64-bit
    movsxd  r9, r9d

    ; number of 16-byte blocks
    mov     r15, r12
    shr     r15, 4
    xor     rcx, rcx            ; block index

.mm128_block:
    cmp     rcx, r15
    jae     .mm128_tail

    ; k1 = bytes 0..7 of block
    mov     rax, [rbx + rcx * 16]       ; k1
    ; k2 = bytes 8..15 of block
    mov     rdx, [rbx + rcx * 16 + 8]  ; k2

    ; k1 mix
    mov     r10, MM3_C1
    imul    rax, r10
    rol     rax, 31
    mov     r10, MM3_C2
    imul    rax, r10
    xor     r8, rax

    ; h1 update
    rol     r8, 27
    add     r8, r9
    lea     r8, [r8 + r8 * 4]      ; h1 * 5
    add     r8, 0x52DCE729

    ; k2 mix
    mov     r10, MM3_C2
    imul    rdx, r10
    rol     rdx, 33
    mov     r10, MM3_C1
    imul    rdx, r10
    xor     r9, rdx

    ; h2 update
    rol     r9, 31
    add     r9, r8
    lea     r9, [r9 + r9 * 4]      ; h2 * 5
    add     r9, 0x38495AB5

    inc     rcx
    jmp     .mm128_block

.mm128_tail:
    ; tail: up to 15 bytes
    mov     r15, r12
    and     r15, 15             ; remaining bytes
    test    r15, r15
    jz      .mm128_finalize

    ; byte offset to tail
    mov     r13, r12
    and     r13, ~15

    xor     rax, rax            ; k1
    xor     rdx, rdx            ; k2

    ; load tail bytes into k1 (bytes 0..7) and k2 (bytes 8..14)
    ; complex byte loading — handle each case
    cmp     r15, 15
    jb      .mm128_t14
    movzx   r10, byte [rbx + r13 + 14]
    shl     r10, 48
    or      rdx, r10

.mm128_t14:
    cmp     r15, 14
    jb      .mm128_t13
    movzx   r10, byte [rbx + r13 + 13]
    shl     r10, 40
    or      rdx, r10

.mm128_t13:
    cmp     r15, 13
    jb      .mm128_t12
    movzx   r10, byte [rbx + r13 + 12]
    shl     r10, 32
    or      rdx, r10

.mm128_t12:
    cmp     r15, 12
    jb      .mm128_t11
    movzx   r10, byte [rbx + r13 + 11]
    shl     r10, 24
    or      rdx, r10

.mm128_t11:
    cmp     r15, 11
    jb      .mm128_t10
    movzx   r10, byte [rbx + r13 + 10]
    shl     r10, 16
    or      rdx, r10

.mm128_t10:
    cmp     r15, 10
    jb      .mm128_t9
    movzx   r10, byte [rbx + r13 + 9]
    shl     r10, 8
    or      rdx, r10

.mm128_t9:
    cmp     r15, 9
    jb      .mm128_t8
    movzx   r10, byte [rbx + r13 + 8]
    or      rdx, r10

    ; k2 mix (if we had any k2 bytes)
    mov     r11, MM3_C2
    imul    rdx, r11
    rol     rdx, 33
    mov     r11, MM3_C1
    imul    rdx, r11
    xor     r9, rdx

.mm128_t8:
    cmp     r15, 8
    jb      .mm128_t7
    movzx   r10, byte [rbx + r13 + 7]
    shl     r10, 56
    or      rax, r10

.mm128_t7:
    cmp     r15, 7
    jb      .mm128_t6
    movzx   r10, byte [rbx + r13 + 6]
    shl     r10, 48
    or      rax, r10

.mm128_t6:
    cmp     r15, 6
    jb      .mm128_t5
    movzx   r10, byte [rbx + r13 + 5]
    shl     r10, 40
    or      rax, r10

.mm128_t5:
    cmp     r15, 5
    jb      .mm128_t4
    movzx   r10, byte [rbx + r13 + 4]
    shl     r10, 32
    or      rax, r10

.mm128_t4:
    cmp     r15, 4
    jb      .mm128_t3
    movzx   r10, byte [rbx + r13 + 3]
    shl     r10, 24
    or      rax, r10

.mm128_t3:
    cmp     r15, 3
    jb      .mm128_t2
    movzx   r10, byte [rbx + r13 + 2]
    shl     r10, 16
    or      rax, r10

.mm128_t2:
    cmp     r15, 2
    jb      .mm128_t1
    movzx   r10, byte [rbx + r13 + 1]
    shl     r10, 8
    or      rax, r10

.mm128_t1:
    movzx   r10, byte [rbx + r13]
    or      rax, r10

    ; k1 mix
    mov     r11, MM3_C1
    imul    rax, r11
    rol     rax, 31
    mov     r11, MM3_C2
    imul    rax, r11
    xor     r8, rax

.mm128_finalize:
    ; h1 ^= len, h2 ^= len
    xor     r8, r12
    xor     r9, r12

    ; h1 += h2, h2 += h1
    add     r8, r9
    add     r9, r8

    ; fmix64 on h1 and h2
    ; fmix64(h1):
    mov     rax, r8
    shr     rax, 33
    xor     r8, rax
    mov     rax, 0xFF51AFD7ED558CCD
    imul    r8, rax
    mov     rax, r8
    shr     rax, 33
    xor     r8, rax
    mov     rax, 0xC4CEB9FE1A85EC53
    imul    r8, rax
    mov     rax, r8
    shr     rax, 33
    xor     r8, rax

    ; fmix64(h2):
    mov     rax, r9
    shr     rax, 33
    xor     r9, rax
    mov     rax, 0xFF51AFD7ED558CCD
    imul    r9, rax
    mov     rax, r9
    shr     rax, 33
    xor     r9, rax
    mov     rax, 0xC4CEB9FE1A85EC53
    imul    r9, rax
    mov     rax, r9
    shr     rax, 33
    xor     r9, rax

    ; final mix
    add     r8, r9
    add     r9, r8

    ; write output
    mov     [r14],     r8
    mov     [r14 + 8], r9

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_murmur3_128

; -----------------------------------------------------------------------------
; str_murmur3_32_slice / str_murmur3_128_slice — StrSlice wrappers
; -----------------------------------------------------------------------------

STR_FUNC str_murmur3_32_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12d, esi           ; seed
    ; rdx = out

    mov     rcx, rdx
    movzx   edx, r12w
    mov     rsi, [rbx + StrSlice.len]
    mov     rdi, [rbx + StrSlice.ptr]

    pop_regs r12, rbx
    pop     rbp
    jmp     str_murmur3_32

STR_ENDFUNC str_murmur3_32_slice

STR_FUNC str_murmur3_128_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12d, esi
    mov     rcx, rdx

    movzx   edx, r12w
    mov     rsi, [rbx + StrSlice.len]
    mov     rdi, [rbx + StrSlice.ptr]

    pop_regs r12, rbx
    pop     rbp
    jmp     str_murmur3_128

STR_ENDFUNC str_murmur3_128_slice