; =============================================================================
; Tattva OS — lib/mem/heap/heap.asm
; =============================================================================
; Unified Heap Allocator selector wrapper (Subfeature 9.1).
; Directs requests to either the early bump allocator or the free-list allocator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_HEAP_HEAP_ASM
%define LIB_MEM_HEAP_HEAP_ASM

[BITS 64]

section .text

; External symbols (from other included parts or libraries)
extern uart_print_str

; -----------------------------------------------------------------------------
; heap_init — initializes the early heap using the bump allocator
; Input:
;   RDI = start address of heap region
;   RSI = size of heap region in bytes
; Output: none
; -----------------------------------------------------------------------------
global heap_init
heap_init:
    mov byte [heap_active_allocator], 0 ; set to early bump allocator
    call early_bump_init
    ret

; -----------------------------------------------------------------------------
; heap_alloc — allocates memory from the active allocator
; Input:
;   RDI = size of allocation in bytes
; Output:
;   RAX = allocated pointer, or 0 if OOM
; -----------------------------------------------------------------------------
global heap_alloc
heap_alloc:
    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_alloc
    ret
.free_list:
    call free_list_alloc
    ret

; -----------------------------------------------------------------------------
; heap_free — frees memory from the active allocator
; Input:
;   RDI = pointer to free
; Output: none
; -----------------------------------------------------------------------------
global heap_free
heap_free:
    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_free
    ret
.free_list:
    call free_list_free
    ret

; -----------------------------------------------------------------------------
; heap_realloc — resizes allocation from the active allocator
; Input:
;   RDI = pointer
;   RSI = new size
; Output:
;   RAX = new pointer, or 0
; -----------------------------------------------------------------------------
global heap_realloc
heap_realloc:
    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_realloc
    ret
.free_list:
    call free_list_realloc
    ret

; -----------------------------------------------------------------------------
; heap_transition — transitions remaining bump allocator space to free-list
; Output: none
; -----------------------------------------------------------------------------
global heap_transition
heap_transition:
    push rbx
    push rdi
    push rsi

    ; Check if already transitioned
    cmp byte [heap_active_allocator], 1
    je .done

    ; Get current bump pointer
    mov rdi, [early_bump_state + early_bump_state_t.current]
    
    ; Align current pointer to 16-byte boundary
    add rdi, 15
    and rdi, -16                    ; RDI = aligned start address for free list
    
    ; Get end of heap
    mov rsi, [early_bump_state + early_bump_state_t.end]
    
    ; Calculate remaining size: end - start
    sub rsi, rdi
    
    ; If remaining size is too small for free-list block header, do not transition
    cmp rsi, heap_block_t_size + 16
    jbe .done_set

    ; Initialize the free-list allocator with the remaining region
    call free_list_init

.done_set:
    mov byte [heap_active_allocator], 1 ; set to free-list allocator
    
    ; Print transition notification to UART
    mov rsi, msg_heap_transitioned
    call uart_print_str

.done:
    pop rsi
    pop rdi
    pop rbx
    ret

section .data

align 8
global heap_active_allocator
heap_active_allocator: db 0        ; 0 = early bump, 1 = free-list

msg_heap_transitioned:  db "Heap transitioned from Early Bump to Free List allocator.", 0x0D, 0x0A, 0

%endif ; LIB_MEM_HEAP_HEAP_ASM
