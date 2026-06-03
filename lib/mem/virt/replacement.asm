; =============================================================================
; Tattva OS — lib/mem/virt/replacement.asm
; =============================================================================
; Active/Inactive Page List Manager for Page Replacement (Subfeature 7.1).
; Maintains doubly-linked lists of user-space allocated physical page frames,
; synchronized by a spinlock to allow concurrent multi-core operations.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_REPLACEMENT_ASM
%define LIB_MEM_VIRT_REPLACEMENT_ASM

[BITS 64]

; Node structure for tracked page frames
struc page_node_t
    .phys_addr  resq 1          ; Physical address of the 4KB page frame
    .virt_addr  resq 1          ; Virtual address where it is mapped
    .flags      resq 1          ; Flags (1 = Active, 0 = Inactive)
    .prev       resq 1          ; Previous node pointer
    .next       resq 1          ; Next node pointer
endstruc

section .text

; External Heap Allocator APIs
extern heap_alloc
extern heap_free

; -----------------------------------------------------------------------------
; page_list_init — resets the active and inactive page lists
; -----------------------------------------------------------------------------
global page_list_init
page_list_init:
    mov qword [active_list_head], 0
    mov qword [active_list_tail], 0
    mov qword [active_count], 0
    mov qword [inactive_list_head], 0
    mov qword [inactive_list_tail], 0
    mov qword [inactive_count], 0
    mov byte [replacement_lock], 0
    ret

; -----------------------------------------------------------------------------
; page_list_add_active — tracks a new physical page in the active list
; Input:
;   RDI = physical address
;   RSI = virtual address
; Output: none
; Clobbers: RAX, RCX, RDX, R8
; -----------------------------------------------------------------------------
global page_list_add_active
page_list_add_active:
    push rbx
    push r12
    push r13
    mov r12, rdi                    ; R12 = phys_addr
    mov r13, rsi                    ; R13 = virt_addr

    ; 1. Allocate block for list node
    mov rdi, page_node_t_size
    call heap_alloc
    test rax, rax
    jz .exit                        ; fail silently on OOM

    mov rbx, rax                    ; RBX = node pointer

    ; 2. Populate structure fields
    mov [rbx + page_node_t.phys_addr], r12
    mov [rbx + page_node_t.virt_addr], r13
    mov qword [rbx + page_node_t.flags], 1 ; flag = 1 (Active)
    mov qword [rbx + page_node_t.prev], 0
    mov qword [rbx + page_node_t.next], 0

    ; 3. Acquire spinlock
    call replacement_lock_acquire

    ; 4. Prepend to active list
    mov rcx, [active_list_head]
    test rcx, rcx
    jz .first_node

    mov [rbx + page_node_t.next], rcx
    mov [rcx + page_node_t.prev], rbx
    mov [active_list_head], rbx
    jmp .inserted

.first_node:
    mov [active_list_head], rbx
    mov [active_list_tail], rbx

.inserted:
    inc qword [active_count]
    call replacement_lock_release

.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; page_list_add_inactive — tracks a new physical page in the inactive list
; Input:
;   RDI = physical address
;   RSI = virtual address
; Output: none
; Clobbers: RAX, RCX, RDX, R8
; -----------------------------------------------------------------------------
global page_list_add_inactive
page_list_add_inactive:
    push rbx
    push r12
    push r13
    mov r12, rdi                    ; R12 = phys_addr
    mov r13, rsi                    ; R13 = virt_addr

    ; 1. Allocate block for list node
    mov rdi, page_node_t_size
    call heap_alloc
    test rax, rax
    jz .exit

    mov rbx, rax                    ; RBX = node pointer

    ; 2. Populate structure fields
    mov [rbx + page_node_t.phys_addr], r12
    mov [rbx + page_node_t.virt_addr], r13
    mov qword [rbx + page_node_t.flags], 0 ; flag = 0 (Inactive)
    mov qword [rbx + page_node_t.prev], 0
    mov qword [rbx + page_node_t.next], 0

    ; 3. Acquire spinlock
    call replacement_lock_acquire

    ; 4. Prepend to inactive list
    mov rcx, [inactive_list_head]
    test rcx, rcx
    jz .first_node

    mov [rbx + page_node_t.next], rcx
    mov [rcx + page_node_t.prev], rbx
    mov [inactive_list_head], rbx
    jmp .inserted

.first_node:
    mov [inactive_list_head], rbx
    mov [inactive_list_tail], rbx

.inserted:
    inc qword [inactive_count]
    call replacement_lock_release

.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; page_list_remove — unlinks and frees the node tracking a physical page
; Input:
;   RDI = physical address
; Output: none
; Clobbers: RAX, RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
global page_list_remove
page_list_remove:
    push rbx
    push r12
    mov r12, rdi

    call replacement_lock_acquire

    ; Search lists
    mov rdi, r12
    call page_list_find             ; RAX = node, RDX = list (1=Active, 0=Inactive)
    test rax, rax
    jz .unlock_done

    mov rbx, rax                    ; RBX = node

    ; Unlink from list
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]

    test r8, r8
    jz .is_head
    mov [r8 + page_node_t.next], r9
    jmp .check_tail

.is_head:
    test rdx, rdx
    jz .inactive_head
    mov [active_list_head], r9
    jmp .check_tail
.inactive_head:
    mov [inactive_list_head], r9

.check_tail:
    test r9, r9
    jz .is_tail
    mov [r9 + page_node_t.prev], r8
    jmp .count_dec

.is_tail:
    test rdx, rdx
    jz .inactive_tail
    mov [active_list_tail], r8
    jmp .count_dec
.inactive_tail:
    mov [inactive_list_tail], r8

.count_dec:
    test rdx, rdx
    jz .dec_inactive
    dec qword [active_count]
    jmp .free_block
.dec_inactive:
    dec qword [inactive_count]

.free_block:
    call replacement_lock_release

    ; Free the allocated list node back to heap
    mov rdi, rbx
    call heap_free
    jmp .exit

.unlock_done:
    call replacement_lock_release
.exit:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; page_list_move_to_active — moves a page from inactive to active list
; Input:
;   RDI = physical address
; Output: none
; Clobbers: RAX, RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
global page_list_move_to_active
page_list_move_to_active:
    push rbx
    push r12
    mov r12, rdi

    call replacement_lock_acquire

    mov rdi, r12
    call page_list_find
    test rax, rax
    jz .unlock_done
    test rdx, rdx
    jnz .unlock_done                ; already active

    mov rbx, rax                    ; RBX = node to move

    ; 1. Unlink from inactive list
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]

    test r8, r8
    jz .inactive_head
    mov [r8 + page_node_t.next], r9
    jmp .inactive_check_tail
.inactive_head:
    mov [inactive_list_head], r9

.inactive_check_tail:
    test r9, r9
    jz .inactive_tail
    mov [r9 + page_node_t.prev], r8
    jmp .inactive_unlinked
.inactive_tail:
    mov [inactive_list_tail], r8

.inactive_unlinked:
    dec qword [inactive_count]

    ; 2. Prepend to active list (head)
    mov qword [rbx + page_node_t.flags], 1 ; Active
    mov qword [rbx + page_node_t.prev], 0
    mov rcx, [active_list_head]
    mov [rbx + page_node_t.next], rcx

    test rcx, rcx
    jz .active_first
    mov [rcx + page_node_t.prev], rbx
    mov [active_list_head], rbx
    jmp .active_linked

.active_first:
    mov [active_list_head], rbx
    mov [active_list_tail], rbx

.active_linked:
    inc qword [active_count]

.unlock_done:
    call replacement_lock_release
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; page_list_move_to_inactive — moves a page from active to inactive list
; Input:
;   RDI = physical address
; Output: none
; Clobbers: RAX, RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
global page_list_move_to_inactive
page_list_move_to_inactive:
    push rbx
    push r12
    mov r12, rdi

    call replacement_lock_acquire

    mov rdi, r12
    call page_list_find
    test rax, rax
    jz .unlock_done
    test rdx, rdx
    jz .unlock_done                 ; already inactive

    mov rbx, rax                    ; RBX = node to move

    ; 1. Unlink from active list
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]

    test r8, r8
    jz .active_head
    mov [r8 + page_node_t.next], r9
    jmp .active_check_tail
.active_head:
    mov [active_list_head], r9

.active_check_tail:
    test r9, r9
    jz .active_tail
    mov [r9 + page_node_t.prev], r8
    jmp .active_unlinked
.active_tail:
    mov [active_list_tail], r8

.active_unlinked:
    dec qword [active_count]

    ; 2. Prepend to inactive list (head)
    mov qword [rbx + page_node_t.flags], 0 ; Inactive
    mov qword [rbx + page_node_t.prev], 0
    mov rcx, [inactive_list_head]
    mov [rbx + page_node_t.next], rcx

    test rcx, rcx
    jz .inactive_first
    mov [rcx + page_node_t.prev], rbx
    mov [inactive_list_head], rbx
    jmp .inactive_linked

.inactive_first:
    mov [inactive_list_head], rbx
    mov [inactive_list_tail], rbx

.inactive_linked:
    inc qword [inactive_count]

.unlock_done:
    call replacement_lock_release
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; page_list_get_active_count — returns count of active pages
; Output: RAX = active count
; -----------------------------------------------------------------------------
global page_list_get_active_count
page_list_get_active_count:
    mov rax, [active_count]
    ret

; -----------------------------------------------------------------------------
; page_list_get_inactive_count — returns count of inactive pages
; Output: RAX = inactive count
; -----------------------------------------------------------------------------
global page_list_get_inactive_count
page_list_get_inactive_count:
    mov rax, [inactive_count]
    ret

; -----------------------------------------------------------------------------
; page_list_find — internal helper to find a page node (expects lock held)
; Input:
;   RDI = physical address
; Output:
;   RAX = node pointer (0 if not found)
;   RDX = list flag (1 = Active, 0 = Inactive)
; -----------------------------------------------------------------------------
page_list_find:
    ; Search active list
    mov rax, [active_list_head]
.active_loop:
    test rax, rax
    jz .search_inactive
    cmp [rax + page_node_t.phys_addr], rdi
    je .found_active
    mov rax, [rax + page_node_t.next]
    jmp .active_loop

.found_active:
    mov rdx, 1
    ret

.search_inactive:
    ; Search inactive list
    mov rax, [inactive_list_head]
.inactive_loop:
    test rax, rax
    jz .not_found
    cmp [rax + page_node_t.phys_addr], rdi
    je .found_inactive
    mov rax, [rax + page_node_t.next]
    jmp .inactive_loop

.found_inactive:
    mov rdx, 0
    ret

.not_found:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; Spinlock helpers
; -----------------------------------------------------------------------------
replacement_lock_acquire:
    lea rcx, [replacement_lock]
.spin:
    mov al, 1
    xchg [rcx], al                  ; swap AL and lock byte (implicit LOCK)
    test al, al                     ; check if it was 0
    jz .acquired                    ; yes, acquired!
.wait:
    pause
    cmp byte [rcx], 0
    jne .wait
    jmp .spin
.acquired:
    ret

replacement_lock_release:
    mov byte [replacement_lock], 0
    ret

; -----------------------------------------------------------------------------
; Data Section — List Heads, Tails, Counts, and Spinlock
; -----------------------------------------------------------------------------
section .data

align 8
active_list_head:   dq 0
active_list_tail:   dq 0
active_count:       dq 0

inactive_list_head: dq 0
inactive_list_tail: dq 0
inactive_count:     dq 0

replacement_lock:   db 0

%endif ; LIB_MEM_VIRT_REPLACEMENT_ASM
