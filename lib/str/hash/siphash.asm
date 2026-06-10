; =============================================================================
; str/hash/siphash.asm
; SipHash-2-4 — cryptographically strong PRF, DoS-resistant hash.
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
; SipHash-2-4 algorithm (Aumasson & Bernstein, 2012):
;
;   State: four 64-bit words v0, v1, v2, v3
;   Key:   128-bit (two 64-bit words k0, k1)
;
;   Initialization:
;     v0 = k0 ^ 0x736f6d6570736575
;     v1 = k1 ^ 0x646f72616e646f6d
;     v2 = k0 ^ 0x6c7967656e657261
;     v3 = k1 ^ 0x7465646279746573
;
;   For each 8-byte block m:
;     v3 ^= m
;     repeat 2 times: SipRound
;     v0 ^= m
;
;   Finalization:
;     v2 ^= 0xFF
;     repeat 4 times: SipRound
;     return v0 ^ v1 ^ v2 ^ v3
;
;   SipRound:
;     v0 += v1; v1 = rotl(v1, 13); v1 ^= v0; v0 = rotl(v0, 32)
;     v2 += v3; v3 = rotl(v3, 16); v3 ^= v2
;     v0 += v3; v3 = rotl(v3, 21); v3 ^= v0
;     v2 += v1; v1 = rotl(v1, 17); v1 ^= v2; v2 = rotl(v2, 32)
;
; Properties:
;   - Keyed PRF — requires 128-bit secret key
;   - DoS-resistant: attacker without key can't find collisions
;   - Used as default HashMap hasher in Rust, Python 3.4+
;   - NOT for password hashing or MACs over untrusted data
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; SipHash IV constants
SIP_C0  equ 0x736f6d6570736575
SIP_C1  equ 0x646f72616e646f6d
SIP_C2  equ 0x6c7967656e657261
SIP_C3  equ 0x7465646279746573

; SipRound macro — operates on v0..v3 in registers
; v0=r8, v1=r9, v2=r10, v3=r11
%macro SIPROUND 0
    add     r8,  r9             ; v0 += v1
    rol     r9,  13             ; v1 = rotl(v1, 13)
    xor     r9,  r8             ; v1 ^= v0
    rol     r8,  32             ; v0 = rotl(v0, 32)
    add     r10, r11            ; v2 += v3
    rol     r11, 16             ; v3 = rotl(v3, 16)
    xor     r11, r10            ; v3 ^= v2
    add     r8,  r11            ; v0 += v3
    rol     r11, 21             ; v3 = rotl(v3, 21)
    xor     r11, r8             ; v3 ^= v0
    add     r10, r9             ; v2 += v1
    rol     r9,  17             ; v1 = rotl(v1, 17)
    xor     r9,  r10            ; v1 ^= v2
    rol     r10, 32             ; v2 = rotl(v2, 32)
%endmacro

section .text

; -----------------------------------------------------------------------------
; str_siphash_24
;
; Compute SipHash-2-4 of a byte buffer with a 128-bit key.
;
; Signature:
;   int64_t str_siphash_24(const uint8_t *data, uint64_t len,
;                           const uint8_t *key,   ; 16 bytes
;                           uint64_t *out)
;
; Arguments:
;   RDI  — data pointer
;   RSI  — byte length
;   RDX  — key pointer (16 bytes: k0 at [rdx], k1 at [rdx+8])
;   RCX  — pointer to uint64_t to receive hash
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_siphash_24

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; data
    mov     r12, rsi            ; len
    mov     r13, rdx            ; key
    mov     r14, rcx            ; out

    ; load key
    mov     r15, [r13]          ; k0
    mov     rax, [r13 + 8]      ; k1

    ; initialize state
    ; v0 = k0 ^ C0
    mov     r8, r15
    mov     r9, SIP_C0
    xor     r8, r9              ; v0

    ; v1 = k1 ^ C1
    mov     r9, rax
    mov     rcx, SIP_C1
    xor     r9, rcx             ; v1

    ; v2 = k0 ^ C2
    mov     r10, r15
    mov     rcx, SIP_C2
    xor     r10, rcx            ; v2

    ; v3 = k1 ^ C3
    mov     r11, rax
    mov     rcx, SIP_C3
    xor     r11, rcx            ; v3

    ; Process 8-byte blocks
    ; number of full 8-byte blocks
    mov     r13, r12
    shr     r13, 3              ; r13 = block count
    xor     r15, r15            ; block index
    xor     rcx, rcx            ; byte offset

.sip_block_loop:
    cmp     r15, r13
    jae     .sip_tail

    ; load 8 bytes little-endian
    mov     rax, [rbx + rcx]    ; m = 8 bytes from data

    ; v3 ^= m
    xor     r11, rax

    ; 2 SipRounds
    SIPROUND
    SIPROUND

    ; v0 ^= m
    xor     r8, rax

    add     rcx, 8
    inc     r15
    jmp     .sip_block_loop

.sip_tail:
    ; Handle remaining bytes (0..7)
    ; b = (len % 256) << 56
    ; b |= remaining bytes in little-endian order
    mov     rax, r12
    and     rax, 0xFF
    shl     rax, 56             ; last byte of m = length low 8 bits

    ; remaining = len & 7
    mov     r13, r12
    and     r13, 7

    ; load remaining bytes
    test    r13, r13
    jz      .sip_tail_done

    ; we need to load r13 bytes from rbx+rcx into rax (low bits)
    xor     r15, r15            ; byte index in tail

.sip_tail_load:
    cmp     r15, r13
    jae     .sip_tail_done

    movzx   rdx, byte [rbx + rcx + r15]
    mov     r9, r15
    shl     r9, 3               ; bit offset = byte_index * 8
    shl     rdx, cl             ; shift byte into position
    ; Note: cl = r9b here — x86 shift uses cl for variable shifts
    ; Need to use r9 as shift amount
    push    rcx
    mov     cl, r9b
    shl     rdx, cl
    pop     rcx
    or      rax, rdx

    inc     r15
    jmp     .sip_tail_load

.sip_tail_done:
    ; v3 ^= last block
    xor     r11, rax
    SIPROUND
    SIPROUND
    xor     r8, rax

    ; Finalization
    xor     r10, 0xFF           ; v2 ^= 0xFF

    SIPROUND
    SIPROUND
    SIPROUND
    SIPROUND

    ; result = v0 ^ v1 ^ v2 ^ v3
    xor     r8, r9
    xor     r8, r10
    xor     r8, r11

    mov     [r14], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_siphash_24

; -----------------------------------------------------------------------------
; str_siphash_24_slice
;
; SipHash-2-4 of a StrSlice with a 128-bit key.
;
; Signature:
;   int64_t str_siphash_24_slice(const StrSlice *slice, const uint8_t *key,
;                                 uint64_t *out)
; -----------------------------------------------------------------------------

STR_FUNC str_siphash_24_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi            ; key
    ; rdx = out

    mov     rcx, rdx            ; out
    mov     rdx, r12            ; key
    mov     rsi, [rbx + StrSlice.len]
    mov     rdi, [rbx + StrSlice.ptr]

    pop_regs r12, rbx
    pop     rbp
    jmp     str_siphash_24

STR_ENDFUNC str_siphash_24_slice

; -----------------------------------------------------------------------------
; str_siphash_24_with_seed
;
; SipHash-2-4 using two 64-bit seeds instead of a 16-byte key array.
; Convenience wrapper for when seeds are in registers.
;
; Signature:
;   int64_t str_siphash_24_with_seed(const uint8_t *data, uint64_t len,
;                                     uint64_t seed0, uint64_t seed1,
;                                     uint64_t *out)
;
; Arguments:
;   RDI  — data
;   RSI  — len
;   RDX  — seed0 (k0)
;   RCX  — seed1 (k1)
;   R8   — out
; -----------------------------------------------------------------------------

STR_FUNC str_siphash_24_with_seed

    guard_null rdi, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx            ; seed0 = k0
    mov     r14, rcx            ; seed1 = k1
    mov     r15, r8             ; out

    ; initialize state directly from seeds
    mov     r8, r13
    xor     r8, SIP_C0          ; v0

    mov     r9, r14
    xor     r9, SIP_C1          ; v1

    mov     r10, r13
    xor     r10, SIP_C2         ; v2

    mov     r11, r14
    xor     r11, SIP_C3         ; v3

    ; process blocks
    mov     r13, r12
    shr     r13, 3
    xor     rcx, rcx
    xor     rax, rax

.sip_ws_block:
    cmp     rax, r13
    jae     .sip_ws_tail

    mov     rdx, [rbx + rcx]
    xor     r11, rdx
    SIPROUND
    SIPROUND
    xor     r8, rdx

    add     rcx, 8
    inc     rax
    jmp     .sip_ws_block

.sip_ws_tail:
    ; tail processing
    mov     rdx, r12
    and     rdx, 0xFF
    shl     rdx, 56

    mov     r13, r12
    and     r13, 7
    xor     rax, rax

.sip_ws_tail_loop:
    cmp     rax, r13
    jae     .sip_ws_tail_done

    movzx   r14, byte [rbx + rcx + rax]
    push    rcx
    mov     cl, al
    shl     cl, 3
    shl     r14, cl
    pop     rcx
    or      rdx, r14

    inc     rax
    jmp     .sip_ws_tail_loop

.sip_ws_tail_done:
    xor     r11, rdx
    SIPROUND
    SIPROUND
    xor     r8, rdx

    xor     r10, 0xFF
    SIPROUND
    SIPROUND
    SIPROUND
    SIPROUND

    xor     r8, r9
    xor     r8, r10
    xor     r8, r11

    mov     [r15], r8

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_siphash_24_with_seed