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
extern early_bump_init
extern early_bump_alloc
extern early_bump_free
extern early_bump_realloc
extern free_list_init
extern free_list_alloc
extern free_list_free
extern free_list_realloc
extern leak_tracker_init
extern leak_track_alloc
extern leak_track_free
extern leak_track_update_size

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
    call leak_tracker_init
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
    push rdi                        ; preserve size
    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_alloc
    jmp .post_alloc
.free_list:
    call free_list_alloc

.post_alloc:
    pop rdi                         ; restore size
    test rax, rax
    jz .done

    ; Track allocation: RDI = pointer, RSI = size, RDX = caller IP
    push rax
    mov rdx, [rsp + 8]              ; RDX = return address of caller (since we pushed rax, RSP is offset by 8)
    mov rsi, rdi                    ; RSI = size
    mov rdi, rax                    ; RDI = pointer
    call leak_track_alloc
    pop rax
.done:
    ret

; -----------------------------------------------------------------------------
; heap_free — frees memory from the active allocator
; Input:
;   RDI = pointer to free
; Output: none
; -----------------------------------------------------------------------------
global heap_free
heap_free:
    test rdi, rdi
    jz .done

    push rdi                        ; preserve pointer
    call leak_track_free
    pop rdi                         ; restore pointer

    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_free
    ret
.free_list:
    call free_list_free
.done:
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
    push rbx
    push r12
    push r13

    mov r12, rdi                    ; R12 = old pointer
    mov r13, rsi                    ; R13 = new size

    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_realloc
    jmp .post_realloc
.free_list:
    call free_list_realloc

.post_realloc:
    test rax, rax
    jz .exit                        ; if realloc failed, exit

    cmp rax, r12
    je .in_place

    ; Pointer shifted!
    ; 1. Untrack the old pointer (if it was non-zero)
    test r12, r12
    jz .track_new
    
    push rax
    mov rdi, r12
    call leak_track_free
    pop rax

.track_new:
    ; 2. Track the new pointer
    push rax
    mov rdi, rax                    ; RDI = pointer
    mov rsi, r13                    ; RSI = size
    mov rdx, [rsp + 32]             ; RDX = return address of caller (pushed rbx, r12, r13, rax = 32 bytes)
    call leak_track_alloc
    pop rax
    jmp .exit

.in_place:
    ; Size updated in-place
    push rax
    mov rdi, r12
    mov rsi, r13
    call leak_track_update_size
    pop rax

.exit:
    pop r13
    pop r12
    pop rbx
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
