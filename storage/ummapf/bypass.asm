; =============================================================================
; Tattva OS — storage/ummapf/bypass.asm
; =============================================================================
; Direct write cache bypass using non-temporal writes (Subfeature 27.4).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef STORAGE_UMMAPF_BYPASS_ASM
%define STORAGE_UMMAPF_BYPASS_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; pmem_memcpy_nt — copies memory using non-temporal instructions to bypass CPU cache
; Input:
;   RDI = destination address
;   RSI = source address
;   RDX = size in bytes
; Output: none
; -----------------------------------------------------------------------------
global pmem_memcpy_nt
pmem_memcpy_nt:
    push rdi
    push rsi
    push rdx
    push rcx
    push rax

    test rdx, rdx
    jz .done

    ; 1. Align destination to 16 bytes (if size is small, we can just do byte copy)
    cmp rdx, 32
    jb .byte_copy

.align_dest:
    mov rax, rdi
    and rax, 15                     ; RAX = dest offset from 16-byte alignment
    jz .aligned_loop                ; already aligned!

    ; Dest is not aligned. Copy 1 byte to align.
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jmp .align_dest

.aligned_loop:
    ; Destination is now 16-byte aligned.
    ; Copy in chunks of 16 bytes using movdqu and movntdq.
    mov rcx, rdx
    shr rcx, 4                      ; RCX = number of 16-byte chunks
    jz .trailing_bytes

.chunk_loop:
    movdqu xmm0, [rsi]              ; Load 16 bytes (unaligned from source is fine)
    movntdq [rdi], xmm0             ; Write 16 bytes bypassing cache (destination is aligned!)
    add rsi, 16
    add rdi, 16
    dec rcx
    jnz .chunk_loop

    ; Calculate remaining bytes
    and rdx, 15

.trailing_bytes:
    test rdx, rdx
    jz .sfence_done

.byte_copy:
    ; Copy remaining/trailing bytes
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jnz .byte_copy

.sfence_done:
    sfence                          ; Flush write buffers to memory controller

.done:
    pop rax
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    ret

%endif ; STORAGE_UMMAPF_BYPASS_ASM
