; =============================================================================
; Tattva OS — lib/mem/virt/tlb_shootdown.asm
; =============================================================================
; Multi-Core TLB Shootdown — sends Inter-Processor Interrupts (IPIs) to
; all other active cores, forcing them to invalidate stale TLB entries
; when page mappings or permissions change.
;
; Design:
;   1. BSP writes shootdown request (address + count) to shared struct.
;   2. BSP sends fixed-vector IPI (vector 0xFB) to all-excluding-self.
;   3. Each AP's ISR performs invlpg or CR3 reload, then atomically
;      increments the ACK counter.
;   4. BSP spins until ACK count == (active_cores - 1).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_TLB_SHOOTDOWN_ASM
%define LIB_MEM_VIRT_TLB_SHOOTDOWN_ASM

[BITS 64]

; LAPIC MMIO base and register offsets
TLB_LAPIC_BASE      equ 0xFEE00000
TLB_LAPIC_ICR_LOW   equ 0x300
TLB_LAPIC_ICR_HIGH  equ 0x310
TLB_LAPIC_EOI       equ 0x0B0

; IPI vector used for TLB shootdowns
TLB_SHOOTDOWN_VEC   equ 0xFB

; Shootdown mode constants
TLB_SHOOTDOWN_PAGE  equ 0           ; invalidate specific page(s)
TLB_SHOOTDOWN_FULL  equ 1           ; full CR3 reload

section .text

; -----------------------------------------------------------------------------
; tlb_shootdown — request all other cores to invalidate TLB entries
; Input:
;   RDI = virtual address to invalidate (page-aligned)
;   RSI = number of pages to invalidate (0 = full flush)
; Output: none
; Clobbers: RAX, RCX, RDX, RDI, RSI
; NOTE: This function blocks until all remote cores have acknowledged
;       the shootdown. Must not be called from interrupt context.
; -----------------------------------------------------------------------------
global tlb_shootdown
tlb_shootdown:
    push rbx
    push r12

    ; 1. Set up the shootdown request
    mov [tlb_sd_vaddr], rdi
    mov [tlb_sd_count], rsi

    ; Determine mode: if count == 0, do full flush
    test rsi, rsi
    jz .set_full
    mov byte [tlb_sd_mode], TLB_SHOOTDOWN_PAGE
    jmp .send_ipi
.set_full:
    mov byte [tlb_sd_mode], TLB_SHOOTDOWN_FULL

.send_ipi:
    ; 2. Reset ACK counter to 0
    mov qword [tlb_sd_ack], 0

    ; Memory fence — ensure request is visible before IPI
    mfence

    ; 3. Calculate expected ACKs = active_cores - 1 (BSP doesn't ACK itself)
    mov r12d, [smp_active_cores]
    dec r12d                        ; R12 = expected ACK count
    test r12d, r12d
    jz .local_only                  ; single core, just do local flush

    ; 4. Send fixed-vector IPI to all-excluding-self
    ;    ICR format:
    ;      [31:20] = 0 (destination, ignored for shorthand)
    ;      [19:18] = 11b (all excluding self)
    ;      [15]    = 0 (edge triggered)
    ;      [14]    = 1 (assert)
    ;      [10:8]  = 000 (fixed delivery)
    ;      [7:0]   = vector (0xFB)
    mov eax, 0x000C4000 | TLB_SHOOTDOWN_VEC
    mov dword [TLB_LAPIC_BASE + TLB_LAPIC_ICR_LOW], eax

    ; 5. Perform local invalidation on BSP as well
    call .do_local_flush

    ; 6. Spin-wait for all APs to acknowledge
.wait_loop:
    pause
    mov eax, [tlb_sd_ack]
    cmp eax, r12d
    jb .wait_loop                   ; keep spinning until all ACKed

    jmp .done

.local_only:
    ; Single core system — just do the local flush
    call .do_local_flush

.done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; .do_local_flush — perform TLB invalidation on the current core
; Uses the shared shootdown request fields to decide what to flush.
; -----------------------------------------------------------------------------
.do_local_flush:
    cmp byte [tlb_sd_mode], TLB_SHOOTDOWN_FULL
    je .flush_full

    ; Page-level invalidation
    mov rax, [tlb_sd_vaddr]
    mov rcx, [tlb_sd_count]

.flush_page_loop:
    test rcx, rcx
    jz .flush_done
    invlpg [rax]
    add rax, 4096
    dec rcx
    jmp .flush_page_loop

.flush_full:
    mov rax, cr3
    mov cr3, rax                    ; reload CR3 → flush all non-global entries

.flush_done:
    ret

; -----------------------------------------------------------------------------
; tlb_shootdown_isr — ISR handler for vector 0xFB (called on each AP)
; Must be installed in the IDT at vector TLB_SHOOTDOWN_VEC.
; Performs the requested TLB invalidation and ACKs the shootdown.
; -----------------------------------------------------------------------------
global tlb_shootdown_isr
tlb_shootdown_isr:
    push rax
    push rcx
    push rdx

    ; Perform the requested invalidation
    cmp byte [tlb_sd_mode], TLB_SHOOTDOWN_FULL
    je .isr_full

    ; Page-level invalidation
    mov rax, [tlb_sd_vaddr]
    mov rcx, [tlb_sd_count]

.isr_page_loop:
    test rcx, rcx
    jz .isr_ack
    invlpg [rax]
    add rax, 4096
    dec rcx
    jmp .isr_page_loop

.isr_full:
    mov rax, cr3
    mov cr3, rax

.isr_ack:
    ; Atomically increment ACK counter
    lock inc dword [tlb_sd_ack]

    ; Send End-Of-Interrupt to Local APIC
    mov dword [TLB_LAPIC_BASE + TLB_LAPIC_EOI], 0

    pop rdx
    pop rcx
    pop rax
    iretq

; -----------------------------------------------------------------------------
; Data — Shootdown request structure
; -----------------------------------------------------------------------------
section .data

align 8
tlb_sd_vaddr:   dq 0               ; virtual address to invalidate
tlb_sd_count:   dq 0               ; number of pages (0 = full flush)
tlb_sd_mode:    db 0                ; 0 = page, 1 = full
align 4
tlb_sd_ack:     dd 0                ; atomic ACK counter from remote cores

align 4
global smp_active_cores
smp_active_cores: dd 1              ; default to 1 core (BSP)

%endif ; LIB_MEM_VIRT_TLB_SHOOTDOWN_ASM
