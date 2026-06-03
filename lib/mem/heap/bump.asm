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

struc heap_state_t
    .start          resq 1      ; Start address of heap region
    .current        resq 1      ; Current bump allocation pointer
    .end            resq 1      ; End address of heap region
endstruc

section .text

; -----------------------------------------------------------------------------
; heap_init — initializes the bump allocator in a given memory region
; Input:
;   RDI = start address of heap region
;   RSI = size of heap region in bytes
; Output: none
; Clobbers: RAX
; -----------------------------------------------------------------------------
global heap_init
heap_init:
    mov [heap_state + heap_state_t.start], rdi
    mov [heap_state + heap_state_t.current], rdi
    
    mov rax, rdi
    add rax, rsi                    ; RAX = end address
    mov [heap_state + heap_state_t.end], rax
    ret

; -----------------------------------------------------------------------------
; heap_alloc — allocates size bytes from the heap, 16-byte aligned
; Input:
;   RDI = size of allocation in bytes
; Output:
;   RAX = pointer to allocated memory, or 0 if OOM
; Clobbers: RCX, RDX
; -----------------------------------------------------------------------------
global heap_alloc
heap_alloc:
    ; Load current pointer
    mov rax, [heap_state + heap_state_t.current]
    
    ; Align current pointer to 16-byte boundary
    add rax, 15
    and rax, -16                    ; RAX = 16-byte aligned address
    
    ; Calculate new current pointer: RAX + RDI
    mov rcx, rax
    add rcx, rdi                    ; RCX = new current pointer
    
    ; Verify we don't exceed the end of the heap
    mov rdx, [heap_state + heap_state_t.end]
    cmp rcx, rdx
    ja .oom                         ; if new_current > end, OOM
    
    ; Update current pointer
    mov [heap_state + heap_state_t.current], rcx
    ret                             ; RAX contains the aligned address

.oom:
    xor rax, rax                    ; return 0 on OOM
    ret

; -----------------------------------------------------------------------------
; heap_free — free previously allocated pointer (no-op in bump allocator)
; Input:
;   RDI = pointer to free
; Output: none
; -----------------------------------------------------------------------------
global heap_free
heap_free:
    ret

; -----------------------------------------------------------------------------
; heap_realloc — resize allocation (fallback for bump allocator)
; Input:
;   RDI = pointer
;   RSI = new size
; Output:
;   RAX = new pointer or 0
; -----------------------------------------------------------------------------
global heap_realloc
heap_realloc:
    test rdi, rdi
    jz .do_alloc
    
    ; cannot safely shrink/grow in bump allocator without size info, return 0
    xor rax, rax
    ret

.do_alloc:
    mov rdi, rsi
    jmp heap_alloc

section .data

align 8
global heap_state
heap_state:
    istruc heap_state_t
        at heap_state_t.start,      dq 0
        at heap_state_t.current,    dq 0
        at heap_state_t.end,        dq 0
    iend

%endif ; LIB_MEM_HEAP_BUMP_ASM
