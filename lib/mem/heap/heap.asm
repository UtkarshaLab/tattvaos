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
; _aslr_random_gap — generates a random gap size between 16 and 256 (step of 16)
; Output:
;   RAX = gap size (16-byte aligned)
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
_aslr_random_gap:
    push rbx
    ; Check if RDRAND is supported (CPUID.01H:ECX.30)
    mov eax, 1
    cpuid
    bt ecx, 30
    jnc .use_rdtsc

    ; RDRAND is supported, try to generate a hardware random number
    rdrand eax
    jc .have_rand

.use_rdtsc:
    ; Fallback to RDTSC for pseudo-randomness
    rdtsc                           ; EDX:EAX = TSC
    xor eax, edx

.have_rand:
    ; Constrain to 0-15
    xor edx, edx
    mov ecx, 16
    div ecx                         ; EDX = random % 16

    ; Calculate gap_size: 16 + 16 * EDX
    mov eax, edx
    shl eax, 4                      ; EAX = EDX * 16
    add eax, 16                     ; EAX = EAX + 16
    
    pop rbx
    ret

; -----------------------------------------------------------------------------
; heap_alloc — allocates memory from the active allocator with a random gap
; Input:
;   RDI = size of allocation in bytes
; Output:
;   RAX = allocated pointer, or 0 if OOM
; -----------------------------------------------------------------------------
global heap_alloc
heap_alloc:
    push rbx
    push rdi                        ; preserve original size

    ; 1. Get random gap size
    call _aslr_random_gap           ; RAX = gap_size
    mov rbx, rax                    ; RBX = gap_size

    ; 2. Add gap_size to requested size
    pop rdi                         ; RDI = original size
    push rdi                        ; push again for tracking
    add rdi, rbx                    ; RDI = size + gap_size

    ; 3. Call active allocator
    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_alloc
    jmp .post_alloc
.free_list:
    call free_list_alloc

.post_alloc:
    test rax, rax
    jz .done                        ; OOM, return 0

    ; RAX = original_ptr
    ; Offsetted pointer = original_ptr + gap_size
    ; Store gap_size at offsetted_ptr - 8
    mov rdx, rax
    add rdx, rbx                    ; RDX = offsetted_ptr
    mov [rdx - 8], rbx              ; store gap_size

    ; Prepare RAX as returned pointer (offsetted_ptr)
    mov rax, rdx

    ; 4. Track allocation: RDI = offsetted_ptr, RSI = original requested size
    push rax                        ; push offsetted_ptr
    mov rsi, [rsp + 8]              ; RSI = original size (rsp points to rax, next is rdi)
    mov rdx, [rsp + 24]             ; RDX = return address of caller (saved rax + rdi + rbx + call = 24 bytes)
    mov rdi, rax                    ; RDI = offsetted_ptr
    call leak_track_alloc
    pop rax

.done:
    pop rdi
    pop rbx
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

    push rbx
    push rdi                        ; preserve offsetted_ptr for leak_track_free

    ; 1. Untrack the offsetted pointer
    call leak_track_free
    pop rdi                         ; RDI = offsetted_ptr

    ; 2. Decode the original pointer and gap size
    ; original_ptr = offsetted_ptr - [offsetted_ptr - 8]
    mov rbx, [rdi - 8]              ; RBX = gap_size
    sub rdi, rbx                    ; RDI = original_ptr

    ; 3. Call active allocator
    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_free
    pop rbx
    ret
.free_list:
    call free_list_free
    pop rbx
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
    push r14

    mov r12, rdi                    ; R12 = old offsetted pointer
    mov r13, rsi                    ; R13 = new requested size

    ; Decode old pointer if it is non-zero
    test r12, r12
    jz .alloc_new

    ; original_ptr = old_offsetted_ptr - [old_offsetted_ptr - 8]
    mov rbx, [r12 - 8]               ; RBX = old gap size
    mov rdi, r12
    sub rdi, rbx                     ; RDI = old original pointer
    jmp .do_realloc

.alloc_new:
    xor rdi, rdi                    ; RDI = 0

.do_realloc:
    ; Get new random gap size
    call _aslr_random_gap
    mov r14, rax                    ; R14 = new gap size

    ; Add new gap size to new requested size
    mov rsi, r13
    add rsi, r14                    ; RSI = new total size

    ; Call active allocator realloc
    cmp byte [heap_active_allocator], 0
    jne .free_list
    call early_bump_realloc
    jmp .post_realloc
.free_list:
    call free_list_realloc

.post_realloc:
    test rax, rax
    jz .exit                        ; OOM, return 0

    ; RAX = new original pointer
    ; Calculate new offsetted pointer
    mov rdx, rax
    add rdx, r14                    ; RDX = new offsetted pointer
    mov [rdx - 8], r14              ; store new gap size

    ; Prepare RAX as returned pointer (new offsetted pointer)
    mov rax, rdx

    ; If pointer changed, we need to update leak tracker
    cmp rax, r12
    je .in_place

    ; Pointer shifted!
    ; 1. Untrack the old pointer (if non-zero)
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
    mov rsi, r13                    ; RSI = user requested size
    mov rdx, [rsp + 40]             ; RDX = caller RIP (pushed rbx, r12, r13, r14, rax = 40 bytes)
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
    pop r14
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
