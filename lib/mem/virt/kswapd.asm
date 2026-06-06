; =============================================================================
; Tattva OS — lib/mem/virt/kswapd.asm
; =============================================================================
; Page-out Daemon (kswapd) implementation for watermark memory reclamation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_KSWAPD_ASM
%define LIB_MEM_VIRT_KSWAPD_ASM

[BITS 64]

; Offsets for phys_state_t (locally defined for assembly visibility)
phys_state_t_free_pages_offset     equ 24
phys_state_t_reserved_pages_offset equ 40

section .text

; External symbols
extern phys_state
extern page_replace_clock_evict
extern uart_print_str
extern kmem_cache_reap
extern kmem_cache_file
extern kmem_cache_task
extern kmem_cache_vma

; Watermarks
global kswapd_low_watermark
global kswapd_high_watermark

; -----------------------------------------------------------------------------
; kswapd_init — initializes kswapd watermarks
; -----------------------------------------------------------------------------
global kswapd_init
kswapd_init:
    ; Default watermarks:
    ; Low: 256 pages (1MB)
    ; High: 512 pages (2MB)
    mov qword [kswapd_low_watermark], 256
    mov qword [kswapd_high_watermark], 512
    mov byte [kswapd_running], 0
    ret

; -----------------------------------------------------------------------------
; kswapd_check_and_reclaim — checks watermarks and evicts pages if necessary
; Input:  none
; Output: RAX = number of pages reclaimed
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global kswapd_check_and_reclaim
kswapd_check_and_reclaim:
    push rbx
    push r12
    push r13

    ; Avoid recursive calls if kswapd allocation itself triggers check
    mov al, [kswapd_running]
    test al, al
    jnz .no_run

    ; Acquire running guard lock
    mov byte [kswapd_running], 1

    ; Get current free page count
    mov rax, phys_state
    mov r12, [rax + phys_state_t_free_pages_offset] ; R12 = free_pages
    
    ; Compare with low watermark
    cmp r12, [kswapd_low_watermark]
    jae .done_reclaim                ; free_pages >= low_watermark, exit

    ; RAM has dropped below low watermark! Run sweeps.
    mov rsi, msg_kswapd_wake
    call uart_print_str

    xor r13, r13                    ; R13 = count of pages reclaimed

    ; --- Slab Reaping Pass ---
    xor r14, r14                    ; R14 = count of slabs/pages reaped

    mov rdi, kmem_cache_file
    call kmem_cache_reap
    add r14, rax

    mov rdi, kmem_cache_task
    call kmem_cache_reap
    add r14, rax

    mov rdi, kmem_cache_vma
    call kmem_cache_reap
    add r14, rax

    test r14, r14
    jz .skip_slab_reclaim_update

    ; Update physical telemetry stats
    mov rax, phys_state
    add [rax + phys_state_t_free_pages_offset], r14
    sub [rax + phys_state_t_reserved_pages_offset], r14

    add r13, r14                    ; add to total pages reclaimed count

.skip_slab_reclaim_update:

.sweep_loop:
    ; Check if we hit the high watermark
    mov rax, phys_state
    mov rcx, [rax + phys_state_t_free_pages_offset]
    cmp rcx, [kswapd_high_watermark]
    jae .sweep_done

    ; Evict one page
    call page_replace_clock_evict
    test rax, rax
    jz .sweep_stuck                 ; no more eviction candidates or swap is full

    inc r13
    jmp .sweep_loop

.sweep_stuck:
    mov rsi, msg_kswapd_stuck
    call uart_print_str
    jmp .sweep_done

.sweep_done:
    test r13, r13
    jz .done_reclaim

    mov rsi, msg_kswapd_done
    call uart_print_str
    
.done_reclaim:
    mov byte [kswapd_running], 0
    mov rax, r13                    ; return pages reclaimed
    jmp .exit

.no_run:
    xor rax, rax

.exit:
    pop r13
    pop r12
    pop rbx
    ret

section .data

align 8
kswapd_low_watermark:  dq 0
kswapd_high_watermark: dq 0
kswapd_running:        db 0

msg_kswapd_wake:    db "[kswapd] Free RAM below low watermark. Running page-out sweeps...", 0x0D, 0x0A, 0
msg_kswapd_stuck:   db "[kswapd] Sweeps halted: no more eviction candidates or swap is full.", 0x0D, 0x0A, 0
msg_kswapd_done:    db "[kswapd] Sweeps complete. Free RAM restored above high watermark.", 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_KSWAPD_ASM
