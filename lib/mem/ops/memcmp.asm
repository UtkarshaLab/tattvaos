; =============================================================================
; Tattva OS — lib/mem/ops/memcmp.asm
; =============================================================================
; AVX2-optimized memcmp implementation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_OPS_MEMCMP_ASM
%define LIB_MEM_OPS_MEMCMP_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; memcmp — compares RDX bytes of memory at RDI and RSI
; Input:
;   RDI = pointer to first memory block
;   RSI = pointer to second memory block
;   RDX = byte count
; Output:
;   RAX = 0 if identical,
;         positive value if first mismatching byte in RDI is greater,
;         negative value if first mismatching byte in RDI is less
; Clobbers: RAX, RCX, RDX, RSI, RDI, YMM0, YMM1, YMM2
; -----------------------------------------------------------------------------
global memcmp
memcmp:
    cmp rdx, 0
    je .equal

    ; Check if we have at least 32 bytes to compare
    cmp rdx, 32
    jb .comp_sub32

    mov rcx, rdx
    shr rcx, 5                      ; RCX = number of 32-byte blocks
    and rdx, 31                     ; RDX = remaining bytes (stored in RDX)

.loop32:
    vmovdqu ymm0, [rdi]             ; load 32 bytes from block 1
    vmovdqu ymm1, [rsi]             ; load 32 bytes from block 2
    vpcmpeqb ymm2, ymm0, ymm1       ; compare bytes: 0xFF on match, 0x00 on mismatch
    vpmovmskb eax, ymm2             ; extract match mask to EAX
    cmp eax, 0xFFFFFFFF             ; check if all 32 bytes matched
    jne .mismatch_32

    add rdi, 32
    add rsi, 32
    dec rcx
    jnz .loop32

.comp_sub32:
    ; Compare remaining bytes (< 32) byte-by-byte
    test rdx, rdx
    jz .equal

.sub32_loop:
    movzx eax, byte [rdi]
    movzx ecx, byte [rsi]
    cmp al, cl
    jne .mismatch_sub32

    inc rdi
    inc rsi
    dec rdx
    jnz .sub32_loop

.equal:
    xor rax, rax                    ; return 0
    ret

.mismatch_32:
    not eax                         ; EAX: bits set to 1 represent mismatches
    bsf ecx, eax                    ; Find first mismatch index (0 to 31)
    movzx eax, byte [rdi + rcx]
    movzx ecx, byte [rsi + rcx]
    sub eax, ecx                    ; RAX = p1[index] - p2[index]
    ret

.mismatch_sub32:
    sub eax, ecx                    ; RAX = al - cl
    ret

%endif ; LIB_MEM_OPS_MEMCMP_ASM
