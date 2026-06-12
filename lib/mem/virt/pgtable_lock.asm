; =============================================================================
; Tattva OS — lib/mem/virt/pgtable_lock.asm
; =============================================================================
; Per-PML4-entry spinlocks for concurrent page table protection (3.4).
; Guards directory updates using fine-grained locks indexed by PML4 slot,
; preventing race conditions during concurrent virt_map/virt_unmap calls
; on multi-core systems.
;
; Lock granularity: 1 spinlock per PML4 entry (512 locks total).
; All virtual addresses sharing the same PML4 index (512GB region) share
; a lock. This provides good parallelism while keeping the lock array small.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_LOCK_ASM
%define LIB_MEM_VIRT_PGTABLE_LOCK_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; pgtable_lock_acquire — acquire spinlock for a PML4 index (with TSX lock elision)
; Input:
;   RDI = virtual address (used to derive PML4 index)
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global pgtable_lock_acquire
pgtable_lock_acquire:
    push rbx
    push rdi
    push r8

    ; Derive PML4 index from virtual address: bits 39-47
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = PML4 index (0-511)

    ; Check if there is an active thread
    extern sched_get_current_thread
    call sched_get_current_thread   ; RAX = current thread pointer
    test rax, rax
    jz .traditional_lock_no_index   ; if no current thread, bypass TSX

    ; Check if abort count for this lock has exceeded limit (e.g. 3)
    lea r8, [pgtable_lock_abort_counts]
    mov al, [r8 + rcx]
    cmp al, 3
    jae .traditional_lock_no_index   ; if abort count >= 3, bypass TSX completely

    ; Calculate lock byte address: &pgtable_locks[index]
    lea r8, [pgtable_locks]
    add r8, rcx                     ; R8 = &lock_byte

    ; Try entering Speculative block
    ; Fallback path is .tsx_fallback
    extern tsx_begin
    push rax
    push rcx
    push r8
    lea rdi, [.tsx_fallback]
    lea rsi, [.tsx_fallback]
    call tsx_begin
    pop r8
    pop rcx
    pop rax

    ; We are in transactional state!
    ; Check if lock is already held
    cmp byte [r8], 0
    jne .tsx_abort_explicit

    ; Lock is free. Return success without setting lock byte!
    pop r8
    pop rdi
    pop rbx
    ret

.tsx_abort_explicit:
    ; Lock busy, explicitly abort and fall back
    extern tsx_end
    call tsx_end                    ; reset tsx active status

.tsx_fallback:
    ; Recalculate PML4 index in case registers were clobbered
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF

    ; Increment the abort count for this lock
    lea r9, [pgtable_lock_abort_counts]
    inc byte [r9 + rcx]

.traditional_lock_no_index:
    ; Recalculate lock address: R8 = &pgtable_locks[PML4 index]
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF
    lea r8, [pgtable_locks]
    add r8, rcx

.traditional_lock:
    mov rax, r8                     ; RAX = &lock_byte
.spin:
    mov al, 1
    xchg [rax], al                  ; swap AL and lock byte (implicit LOCK)
    test al, al                     ; check if it was 0 (unlocked)
    jz .acquired                    ; old value was 0 -> acquired!
 
    ; Lock is held by another core — spin with PAUSE
.wait:
    pause                           ; hint to CPU: spin-wait loop
    cmp byte [rax], 0               ; re-read lock without bus lock
    jne .wait                       ; still held, keep spinning
 
    jmp .spin                       ; lock released, try again
 
.acquired:
    pop r8
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; pgtable_lock_release — release spinlock for a PML4 index (with TSX lock elision)
; Input:
;   RDI = virtual address (used to derive PML4 index)
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global pgtable_lock_release
pgtable_lock_release:
    push rbx
    push rdi

    ; Check if thread has TSX active
    call sched_get_current_thread
    test rax, rax
    jz .traditional_release

    mov rbx, [rax + thread_t.tsx_active]
    test rbx, rbx
    jz .traditional_release

    ; TSX is active, commit it and bypass lock clear
    ; Reset abort count to 0 since transaction succeeded!
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF
    lea rbx, [pgtable_lock_abort_counts]
    mov byte [rbx + rcx], 0

    extern tsx_end
    call tsx_end
    jmp .done

.traditional_release:
    ; Derive PML4 index from virtual address: bits 39-47
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = PML4 index (0-511)

    ; Calculate lock byte address and clear it
    lea rax, [pgtable_locks]
    mov byte [rax + rcx], 0         ; release: simple store

    ; Decay the abort count on traditional release (adaptive back-off)
    lea rax, [pgtable_lock_abort_counts]
    mov dl, [rax + rcx]
    test dl, dl
    jz .done
    dec dl
    mov [rax + rcx], dl
.done:
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Data — Lock array (512 bytes, one per PML4 entry)
; -----------------------------------------------------------------------------
section .bss

align 64                            ; cache-line aligned to reduce false sharing
pgtable_locks: resb 512             ; 0 = unlocked, 1 = locked

align 64
global pgtable_lock_abort_counts
pgtable_lock_abort_counts: resb 512 ; tracks consecutive aborts per PML4 lock

%endif ; LIB_MEM_VIRT_PGTABLE_LOCK_ASM
