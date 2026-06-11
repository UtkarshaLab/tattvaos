; =============================================================================
; Tattva OS — unet/core/link/recycle.asm
; =============================================================================
; Fast-path page recycle pool to bypass slow global PMM allocation locks.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_RECYCLE_ASM
%define UNET_CORE_LINK_RECYCLE_ASM

[BITS 64]

%include "unet/core/link/net_ring.inc"

section .text

extern is_valid_phys_packet_buffer

; -----------------------------------------------------------------------------
; net_recycle_push — Push physical page to recycle pool to bypass PMM lock
; Input:
;   RDI = physical address of page frame
; Output:
;   RAX = 1 on successful recycle (fast-path), or calls phys_free_page (slow-path)
; -----------------------------------------------------------------------------
global net_recycle_push
net_recycle_push:
    push rbx
    mov rbx, rdi                    ; RBX = physical page

    ; Security verification: protect PMM pool from corruption/illegal values
    call is_valid_phys_packet_buffer
    test rax, rax
    jz .bad_frame

    ; Acquire recycle pool spinlock
    lea r8, [net_rx_recycle_pool + net_recycle_pool_t.lock]
.spin_acquire:
    mov al, 1
    xchg [r8], al                   ; atomic swap
    test al, al                     ; check if old value was 0
    jz .acquired
.wait:
    pause
    cmp byte [r8], 0
    jne .wait
    jmp .spin_acquire

.acquired:
    ; Check if pool is full
    mov edx, [net_rx_recycle_pool + net_recycle_pool_t.count]
    cmp edx, 512
    jae .pool_full

    ; Push to stack
    lea rax, [net_rx_recycle_pool + net_recycle_pool_t.frames]
    mov [rax + rdx * 8], rbx
    inc edx
    mov [net_rx_recycle_pool + net_recycle_pool_t.count], edx

    ; Release spinlock
    mov byte [r8], 0
    mov rax, 1
    jmp .exit

.pool_full:
    ; Release spinlock
    mov byte [r8], 0
    
    ; Fallback to standard PMM page free (slow-path)
    mov rdi, rbx
    call phys_free_page
    mov rax, 1
    jmp .exit

.bad_frame:
    xor rax, rax
.exit:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; net_recycle_pop — Retrieve physical page from pool, or fallback to PMM alloc
; Output:
;   RAX = physical page address, or 0 on failure
; -----------------------------------------------------------------------------
global net_recycle_pop
net_recycle_pop:
    push rbx

    ; Acquire recycle pool spinlock
    lea r8, [net_rx_recycle_pool + net_recycle_pool_t.lock]
.spin_acquire:
    mov al, 1
    xchg [r8], al
    test al, al
    jz .acquired
.wait:
    pause
    cmp byte [r8], 0
    jne .wait
    jmp .spin_acquire

.acquired:
    ; Check if pool is empty
    mov edx, [net_rx_recycle_pool + net_recycle_pool_t.count]
    test edx, edx
    jz .pool_empty

    ; Pop from stack
    dec edx
    lea rax, [net_rx_recycle_pool + net_recycle_pool_t.frames]
    mov rbx, [rax + rdx * 8]
    mov [net_rx_recycle_pool + net_recycle_pool_t.count], edx

    ; Release spinlock
    mov byte [r8], 0
    mov rax, rbx
    jmp .exit

.pool_empty:
    ; Release spinlock
    mov byte [r8], 0
    
    ; Fallback to standard PMM allocation (slow-path)
    call phys_alloc_page
    jmp .exit

.exit:
    pop rbx
    ret

section .bss
align 16
global net_rx_recycle_pool
net_rx_recycle_pool:
    resq 512                        ; frames array (4096 bytes)
    resd 1                          ; count (4 bytes)
    alignb 8
    .lock: resq 1                   ; lock (8 bytes)

%endif ; UNET_CORE_LINK_RECYCLE_ASM
