; =============================================================================
; Tattva OS — unet/core/link/sbuf.asm
; =============================================================================
; Zero-copy network socket buffer descriptors (sbuf).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_SBUF_ASM
%define UNET_CORE_LINK_SBUF_ASM

[BITS 64]

%include "unet/core/link/net_ring.inc"

section .text

extern is_valid_phys_packet_buffer
extern msg_security_err
extern net_recycle_push

; -----------------------------------------------------------------------------
; net_sbuf_create — Creates a zero-copy socket buffer descriptor
; Input:
;   RDI = physical address of page frame
;   RSI = virtual address of page frame
;   RDX = packet size in bytes
;   RCX = offset within page
; Output:
;   RAX = pointer to net_sbuf_t, or 0 on failure
; -----------------------------------------------------------------------------
global net_sbuf_create
net_sbuf_create:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = phys
    mov r12, rsi                    ; R12 = virt
    mov r13, rdx                    ; R13 = length
    mov r14, rcx                    ; R14 = offset

    ; TOCTOU Defense: Validate physical address range immediately
    mov rdi, rbx
    call is_valid_phys_packet_buffer
    test rax, rax
    jz .security_panic              ; trigger kernel panic on breach!

    ; Allocate memory for net_sbuf_t
    mov rdi, 40                     ; sizeof(net_sbuf_t)
    call heap_alloc
    test rax, rax
    jz .fail

    ; Populate descriptor fields
    mov [rax + net_sbuf_t.phys_addr], rbx
    mov [rax + net_sbuf_t.virt_addr], r12
    mov [rax + net_sbuf_t.length], r13d
    mov [rax + net_sbuf_t.offset], r14d
    mov dword [rax + net_sbuf_t.ref_count], 1 ; initial reference
    mov dword [rax + net_sbuf_t.flow_hash], 0
    mov qword [rax + net_sbuf_t.next], 0

    jmp .exit

.security_panic:
    mov rdi, msg_security_err
    mov rsi, rbx                    ; physical address offending
    call kernel_panic
    cli
.halt:
    hlt
    jmp .halt

.fail:
    xor rax, rax
.exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; net_sbuf_ref — Atomically increments reference counter
; Input:
;   RDI = pointer to net_sbuf_t
; -----------------------------------------------------------------------------
global net_sbuf_ref
net_sbuf_ref:
    test rdi, rdi
    jz .done
    lock inc dword [rdi + net_sbuf_t.ref_count]
.done:
    ret

; -----------------------------------------------------------------------------
; net_sbuf_free — Decrements reference count and reclaims physical page if 0
; Input:
;   RDI = pointer to net_sbuf_t
; -----------------------------------------------------------------------------
global net_sbuf_free
net_sbuf_free:
    test rdi, rdi
    jz .exit
    
    push rbx
    mov rbx, rdi                    ; RBX = sbuf pointer
    
    ; Decrement atomically and check if it has reached 0
    lock dec dword [rbx + net_sbuf_t.ref_count]
    jnz .done                       ; reference still exists

    ; Reference count reached 0, recycle physical frame
    mov rdi, [rbx + net_sbuf_t.phys_addr]
    call net_recycle_push           ; push physical page back to fast pool

    ; Unmap virtual pointer associated with page (if non-zero)
    mov rdi, [rbx + net_sbuf_t.virt_addr]
    test rdi, rdi
    jz .free_desc
    call virt_unmap

.free_desc:
    ; Free the socket buffer structure descriptor itself
    mov rdi, rbx
    call heap_free

.done:
    pop rbx
.exit:
    ret

%endif ; UNET_CORE_LINK_SBUF_ASM
