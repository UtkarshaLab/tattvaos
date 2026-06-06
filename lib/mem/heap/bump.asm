; =============================================================================
; Tattva OS — lib/mem/heap/bump.asm
; =============================================================================
; Early bump allocator. Fast, non-reclaimable memory allocator for early boot.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_HEAP_BUMP_ASM
%define LIB_MEM_HEAP_BUMP_ASM

[BITS 64]

struc early_bump_state_t
    .start          resq 1      ; Start address of heap region
    .current        resq 1      ; Current bump allocation pointer
    .end            resq 1      ; End address of heap region
endstruc

section .text

; -----------------------------------------------------------------------------
; early_bump_init — initializes the bump allocator in a given memory region
; Input:
;   RDI = start address of heap region
;   RSI = size of heap region in bytes
; Output: none
; Clobbers: RAX
; -----------------------------------------------------------------------------
global early_bump_init
early_bump_init:
    mov [early_bump_state + early_bump_state_t.start], rdi
    mov [early_bump_state + early_bump_state_t.current], rdi
    
    mov rax, rdi
    add rax, rsi                    ; RAX = end address
    mov [early_bump_state + early_bump_state_t.end], rax
    ret

; -----------------------------------------------------------------------------
; early_bump_alloc — allocates size bytes from the heap, 16-byte aligned
; Input:
;   RDI = size of allocation in bytes
; Output:
;   RAX = pointer to allocated memory, or 0 if OOM
; Clobbers: RCX, RDX
; -----------------------------------------------------------------------------
global early_bump_alloc
early_bump_alloc:
    ; Load current pointer
    mov rax, [early_bump_state + early_bump_state_t.current]
    
    ; Align current pointer to 16-byte boundary
    add rax, 15
    and rax, -16                    ; RAX = 16-byte aligned address
    
    ; Calculate new current pointer: RAX + RDI
    mov rcx, rax
    add rcx, rdi                    ; RCX = new current pointer
    
    ; Verify we don't exceed the end of the heap
    mov rdx, [early_bump_state + early_bump_state_t.end]
    cmp rcx, rdx
    ja .oom                         ; if new_current > end, OOM
    
    ; Update current pointer
    mov [early_bump_state + early_bump_state_t.current], rcx
    ret                             ; RAX contains the aligned address
    
.oom:
    xor rax, rax                    ; return 0 on OOM
    ret

; -----------------------------------------------------------------------------
; early_bump_free — free previously allocated pointer (no-op in bump allocator)
; Input:
;   RDI = pointer to free
; Output: none
; -----------------------------------------------------------------------------
global early_bump_free
early_bump_free:
    ret

; -----------------------------------------------------------------------------
; early_bump_realloc — resize allocation (fallback for bump allocator)
; Input:
;   RDI = pointer
;   RSI = new size
; Output:
;   RAX = new pointer or 0
; -----------------------------------------------------------------------------
global early_bump_realloc
early_bump_realloc:
    test rdi, rdi
    jz .do_alloc
    
    ; cannot safely shrink/grow in bump allocator without size info, return 0
    xor rax, rax
    ret

.do_alloc:
    mov rdi, rsi
    jmp early_bump_alloc

section .data

align 8
global early_bump_state
early_bump_state:
    istruc early_bump_state_t
        at early_bump_state_t.start,      dq 0
        at early_bump_state_t.current,    dq 0
        at early_bump_state_t.end,        dq 0
    iend

%endif ; LIB_MEM_HEAP_BUMP_ASM
