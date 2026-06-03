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
; pgtable_lock_acquire — acquire spinlock for a PML4 index
; Input:
;   RDI = virtual address (used to derive PML4 index)
; Output: none
; Clobbers: RAX, RCX
; NOTE: Uses PAUSE-based spin wait to reduce bus contention.
; -----------------------------------------------------------------------------
global pgtable_lock_acquire
pgtable_lock_acquire:
    ; Derive PML4 index from virtual address: bits 39-47
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = PML4 index (0-511)

    ; Calculate lock byte address: &pgtable_locks[index]
    lea rax, [pgtable_locks]
    add rax, rcx                    ; RAX = &lock_byte

.spin:
    ; Try to atomically set the lock byte to 1 by swapping
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
    ret

; -----------------------------------------------------------------------------
; pgtable_lock_release — release spinlock for a PML4 index
; Input:
;   RDI = virtual address (used to derive PML4 index)
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global pgtable_lock_release
pgtable_lock_release:
    ; Derive PML4 index from virtual address: bits 39-47
    mov rcx, rdi
    shr rcx, 39
    and rcx, 0x1FF                  ; RCX = PML4 index (0-511)

    ; Calculate lock byte address and clear it
    lea rax, [pgtable_locks]
    mov byte [rax + rcx], 0         ; release: simple store (x86 guarantees ordering)
    ret

; -----------------------------------------------------------------------------
; Data — Lock array (512 bytes, one per PML4 entry)
; -----------------------------------------------------------------------------
section .bss

align 64                            ; cache-line aligned to reduce false sharing
pgtable_locks: resb 512             ; 0 = unlocked, 1 = locked

%endif ; LIB_MEM_VIRT_PGTABLE_LOCK_ASM
