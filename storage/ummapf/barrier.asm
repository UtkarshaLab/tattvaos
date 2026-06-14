; =============================================================================
; Tattva OS — storage/ummapf/barrier.asm
; =============================================================================
; Hardware metadata barrier flushing (Subfeature 27.5).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef STORAGE_UMMAPF_BARRIER_ASM
%define STORAGE_UMMAPF_BARRIER_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; pmem_flush_range — flushes a memory range to persistent storage
; Input:
;   RDI = start address
;   RSI = size in bytes
; Output: none
; -----------------------------------------------------------------------------
global pmem_flush_range
pmem_flush_range:
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx

    test rsi, rsi
    jz .done

    ; Align RDI to cache line boundary (64 bytes)
    mov rcx, rdi
    and rcx, 63                     ; RAX = offset from 64-byte alignment
    sub rdi, rcx                    ; Align start pointer to 64 bytes
    add rsi, rcx                    ; Increase size to cover the offset

    ; Compute end boundary address (RDX = RDI + RSI)
    mov rdx, rdi
    add rdx, rsi

    ; Check CPUID for cache flushing capabilities
    ; Leaf 7, Subleaf 0: EBX bit 24 = CLWB, bit 23 = CLFLUSHOPT
    mov eax, 7
    xor ecx, ecx
    cpuid

    test ebx, (1 << 24)             ; CLWB support check
    jnz .clwb_loop

    test ebx, (1 << 23)             ; CLFLUSHOPT support check
    jnz .clflushopt_loop

.clflush_loop:
    clflush [rdi]
    add rdi, 64
    cmp rdi, rdx
    jb .clflush_loop
    jmp .fence

.clwb_loop:
    clwb [rdi]
    add rdi, 64
    cmp rdi, rdx
    jb .clwb_loop
    jmp .fence

.clflushopt_loop:
    clflushopt [rdi]
    add rdi, 64
    cmp rdi, rdx
    jb .clflushopt_loop

.fence:
    sfence                          ; Order and serialize write-combining/flushes

.done:
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    ret

%endif ; STORAGE_UMMAPF_BARRIER_ASM
