; =============================================================================
; Tattva OS — lib/mem/virt/swap.asm
; =============================================================================
; Polymorphic swap subsystem and concrete RAM-backed swap helpers.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_SWAP_ASM
%define LIB_MEM_VIRT_SWAP_ASM

[BITS 64]

; Maximum swap slots
SWAP_MAX_SLOTS equ 512

; Page Table Entry Flags (re-defined locally for assembly safety)
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_ACCESSED   equ (1 << 5)
PAGE_SWAPPED    equ (1 << 10)       ; Bit 10 represents a swapped out page
PAGE_ZSWAPPED   equ (1 << 11)       ; Bit 11 represents a compressed zswap page

; Node structure for tracked page frames (matches replacement.asm)
struc page_node_t
    .phys_addr  resq 1          ; Physical address of the 4KB page frame
    .virt_addr  resq 1          ; Virtual address where it is mapped
    .flags      resq 1          ; Flags (1 = Active, 0 = Inactive)
    .prev       resq 1          ; Previous node pointer
    .next       resq 1          ; Next node pointer
endstruc

; swap_device_t structure definition
struc swap_device_t
    .name           resq 1
    .read_page      resq 1
    .write_page     resq 1
    .alloc_slot     resq 1
    .free_slot      resq 1
    .max_slots      resq 1
endstruc

section .text

; External symbols
extern phys_alloc_page
extern phys_free_page
extern virt_walk_table
extern heap_free
extern memcpy
extern phys_state
extern active_list_head
extern active_list_tail
extern inactive_list_head
extern inactive_list_tail
extern active_count
extern inactive_count
extern replacement_lock_acquire
extern replacement_lock_release

extern current_swap_device
extern mock_swap_dev
extern swap_register_device

extern zswap_init
extern zswap_compress_and_store
extern zswap_free_slot

; -----------------------------------------------------------------------------
; swap_init — registers the default Mock RAM device and clears memory slots
; -----------------------------------------------------------------------------
global swap_init
swap_init:
    push rdi
    push rcx
    push rax

    ; Register mock_swap_dev as the default active swap device
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Zero-out the mock RAM swap slots table
    lea rdi, [swap_slots]
    mov rcx, SWAP_MAX_SLOTS
    xor rax, rax
    cld
    rep stosq

    call zswap_init

    pop rax
    pop rcx
    pop rdi
    ret

; =============================================================================
; Polymorphic Redirections (resolve operations on current_swap_device)
; =============================================================================

; -----------------------------------------------------------------------------
; swap_alloc_slot — redirects allocation to active swap device
; -----------------------------------------------------------------------------
global swap_alloc_slot
swap_alloc_slot:
    mov rax, [current_swap_device]
    test rax, rax
    jz .err
    jmp [rax + swap_device_t.alloc_slot]
.err:
    mov rax, -1
    ret

; -----------------------------------------------------------------------------
; swap_free_slot — redirects release to active swap device
; -----------------------------------------------------------------------------
global swap_free_slot
swap_free_slot:
    ; Input: RDI = slot
    mov rax, [current_swap_device]
    test rax, rax
    jz .exit
    jmp [rax + swap_device_t.free_slot]
.exit:
    ret

; -----------------------------------------------------------------------------
; swap_write_page — redirects write to active swap device
; Input: RDI = source physical address, RSI = swap slot index
; -----------------------------------------------------------------------------
global swap_write_page
swap_write_page:
    push rbx
    push rdi
    push rsi

    mov rbx, [current_swap_device]
    test rbx, rbx
    jz .err

    ; Swap parameters: write_page expects RDI=slot, RSI=src_phys
    push rdi                        ; push src_phys
    push rsi                        ; push slot
    pop rdi                         ; RDI = slot
    pop rsi                         ; RSI = src_phys

    call [rbx + swap_device_t.write_page]
    jmp .done
.err:
    xor rax, rax
.done:
    pop rsi
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; swap_read_page — redirects read to active swap device
; Input: RDI = destination physical address, RSI = swap slot index
; -----------------------------------------------------------------------------
global swap_read_page
swap_read_page:
    push rbx
    push rdi
    push rsi

    mov rbx, [current_swap_device]
    test rbx, rbx
    jz .err

    ; Swap parameters: read_page expects RDI=slot, RSI=dest_phys
    push rdi                        ; push dest_phys
    push rsi                        ; push slot
    pop rdi                         ; RDI = slot
    pop rsi                         ; RSI = dest_phys

    call [rbx + swap_device_t.read_page]
    jmp .done
.err:
    xor rax, rax
.done:
    pop rsi
    pop rdi
    pop rbx
    ret

; =============================================================================
; Concrete RAM-Backed Swap Helper Functions (used by mock_swap_dev)
; =============================================================================

; -----------------------------------------------------------------------------
; ram_swap_alloc_slot — allocates physical backing frame for slot
; -----------------------------------------------------------------------------
global ram_swap_alloc_slot
ram_swap_alloc_slot:
    push rcx
    push rsi

    lea rsi, [swap_slots]
    xor rcx, rcx
.loop:
    cmp rcx, SWAP_MAX_SLOTS
    jge .full

    mov rax, [rsi + rcx * 8]
    test rax, rax
    jz .found

    inc rcx
    jmp .loop
.found:
    push rcx
    call phys_alloc_page
    pop rcx
    test rax, rax
    jz .full

    mov [rsi + rcx * 8], rax
    mov rax, rcx
    jmp .done
.full:
    mov rax, -1
.done:
    pop rsi
    pop rcx
    ret

; -----------------------------------------------------------------------------
; ram_swap_free_slot — frees physical backing frame of slot
; -----------------------------------------------------------------------------
global ram_swap_free_slot
ram_swap_free_slot:
    ; Input: RDI = slot index
    push rax
    push rbx
    push rdi

    cmp rdi, SWAP_MAX_SLOTS
    jae .done

    lea rbx, [swap_slots]
    mov rax, [rbx + rdi * 8]
    test rax, rax
    jz .done

    push rdi
    mov rdi, rax
    call phys_free_page
    pop rdi

    mov qword [rbx + rdi * 8], 0
.done:
    pop rdi
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; ram_swap_write_page — copies data from physical source to mock RAM slot
; -----------------------------------------------------------------------------
global ram_swap_write_page
ram_swap_write_page:
    ; Input: RDI = src_phys, RSI = slot
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    lea rax, [swap_slots]
    mov rdi, [rax + r13 * 8]
    test rdi, rdi
    jz .exit

    mov rsi, r12
    mov rdx, 4096
    call memcpy
.exit:
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; ram_swap_read_page — copies data from mock RAM slot to physical destination
; -----------------------------------------------------------------------------
global ram_swap_read_page
ram_swap_read_page:
    ; Input: RDI = dest_phys, RSI = slot
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    lea rax, [swap_slots]
    mov rsi, [rax + r13 * 8]
    test rsi, rsi
    jz .exit

    mov rdi, r12
    mov rdx, 4096
    call memcpy
.exit:
    pop r13
    pop r12
    ret

; =============================================================================
; Clock/Second-Chance Page Eviction Routine
; =============================================================================

; -----------------------------------------------------------------------------
; page_replace_clock_evict — Second-Chance / Clock Eviction algorithm
; Finds an untouched page mapping (Accessed = 0), evicts it to active swap,
; and frees its physical frame.
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global page_replace_clock_evict
page_replace_clock_evict:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Acquire replacement list spinlock
    call replacement_lock_acquire

    ; Check if inactive list is empty. If so, populate it from active list.
    mov rbx, [inactive_list_head]
    test rbx, rbx
    jnz .scan_inactive

    ; Populate inactive list by scanning active list from tail to head
    mov rbx, [active_list_tail]
    test rbx, rbx
    jz .fail_unlock                 ; no tracked pages at all!

.populate_loop:
    test rbx, rbx
    jz .scan_inactive

    mov r12, [rbx + page_node_t.prev] ; save prev pointer for tail->head traversal

    ; Check if this user page's Accessed bit is 0
    mov rdi, [rbx + page_node_t.virt_addr]
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address, RDX = level
    test rax, rax
    jz .pop_unmapped

    mov rcx, [rax]
    test rcx, PAGE_ACCESSED
    jnz .pop_has_accessed

    ; Accessed is 0! Move this page to the inactive list
    ; Unlink from active list
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

    ; Prepend to inactive list
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
    jmp .pop_next

.pop_has_accessed:
    ; Accessed is 1: clear Accessed bit in PTE
    and qword [rax], ~PAGE_ACCESSED
    invlpg [rdi]                    ; flush TLB
    jmp .pop_next

.pop_unmapped:
    ; Node is no longer mapped, let's unlink and free it
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]
    test r8, r8
    jz .pop_unmap_head
    mov [r8 + page_node_t.next], r9
    jmp .pop_unmap_tail
.pop_unmap_head:
    mov [active_list_head], r9
.pop_unmap_tail:
    test r9, r9
    jz .pop_unmap_tail_done
    mov [r9 + page_node_t.prev], r8
    jmp .pop_unmap_done
.pop_unmap_tail_done:
    mov [active_list_tail], r8
.pop_unmap_done:
    dec qword [active_count]
    
    ; Free the node structure
    call replacement_lock_release
    mov rdi, rbx
    call heap_free
    call replacement_lock_acquire

.pop_next:
    mov rbx, r12
    jmp .populate_loop

.scan_inactive:
    ; Scan inactive list from tail to head (oldest first)
    mov rbx, [inactive_list_tail]

.scan_loop:
    test rbx, rbx
    jz .fail_unlock                 ; traversed the entire inactive list and found nothing

    mov r12, [rbx + page_node_t.prev] ; save prev pointer for tail-to-head traversal

    mov rdi, [rbx + page_node_t.virt_addr]
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE, RDX = level
    test rax, rax
    jz .scan_unmapped

    mov rcx, [rax]
    test rcx, PAGE_ACCESSED
    jnz .scan_second_chance

    ; Found untouched page! Let's evict it.
    mov r13, rax                    ; R13 = PTE address
    mov r14, rcx                    ; R14 = PTE value
    mov r15, [rbx + page_node_t.phys_addr] ; R15 = physical page address

    ; Release lock for memory allocation and copying
    call replacement_lock_release

    ; 1. Try Zswap compression first
    mov rdi, r15                    ; source physical address
    call zswap_compress_and_store   ; RAX = slot index / -1
    cmp rax, -1
    je .fallback_disk_swap          ; compression failed, fallback to disk swap

    mov r10, rax                    ; R10 = Zswap slot index
    mov r8, 1                       ; R8 = 1 indicates Zswap page
    jmp .lock_and_commit

.fallback_disk_swap:
    ; 1. Allocate a disk swap slot
    call swap_alloc_slot            ; RAX = slot index, or -1
    cmp rax, -1
    je .fail_swap_full

    mov r10, rax                    ; R10 = swap slot index

    ; 2. Copy page contents to the active swap device
    mov rdi, r15                    ; source physical address
    mov rsi, r10                    ; slot index
    call swap_write_page
    mov r8, 0                       ; R8 = 0 indicates regular disk swap

.lock_and_commit:
    ; Re-acquire lock to commit the changes to PTE and list
    call replacement_lock_acquire

    ; Verify PTE is still present and matches
    mov rdi, [rbx + page_node_t.virt_addr]
    xor rsi, rsi
    push r8                         ; preserve Zswap indicator flag
    call virt_walk_table
    pop r8                          ; restore Zswap indicator flag
    cmp rax, r13
    jne .abort_evict                ; PTE changed, abort!

    ; 3. Update the page table entry
    ; Clear PRESENT, clear ACCESSED, set PAGE_SWAPPED, store swap slot index in bits 12-51
    mov rcx, r14
    and rcx, 0xFFF                  ; preserve lower 12 flags
    mov r11, (1 << 63)
    and r11, r14
    or rcx, r11                     ; preserve NX flag
    
    and rcx, ~PAGE_PRESENT          ; clear Present
    and rcx, ~PAGE_ACCESSED         ; clear Accessed
    or rcx, PAGE_SWAPPED            ; set Swapped
    
    test r8, r8
    jz .pte_flags_done
    or rcx, PAGE_ZSWAPPED           ; set Zswapped flag
.pte_flags_done:

    ; Shift swap slot index (R10) to bits 12-51
    mov r9, r10
    shl r9, 12
    or rcx, r9                      ; merge swap slot index into PTE

    mov [r13], rcx                  ; write new PTE value

    ; 4. Flush TLB
    invlpg [rdi]

    ; 5. Unlink from inactive list
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]
    test r8, r8
    jz .inactive_head_evict
    mov [r8 + page_node_t.next], r9
    jmp .inactive_check_tail_evict
.inactive_head_evict:
    mov [inactive_list_head], r9
.inactive_check_tail_evict:
    test r9, r9
    jz .inactive_tail_evict
    mov [r9 + page_node_t.prev], r8
    jmp .inactive_unlinked_evict
.inactive_tail_evict:
    mov [inactive_list_tail], r8
.inactive_unlinked_evict:
    dec qword [inactive_count]

    call replacement_lock_release

    ; 6. Free the physical page frame
    mov rdi, r15
    call phys_free_page

    ; 7. Free the node structure
    mov rdi, rbx
    call heap_free

    ; 8. Update telemetry
    inc qword [phys_state + phys_state_t.swap_pages]

    mov rax, 1                      ; return 1 (success)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.scan_second_chance:
    ; Give second chance: clear Accessed, move back to active list
    and qword [rax], ~PAGE_ACCESSED
    invlpg [rdi]

    ; Unlink from inactive list
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]
    test r8, r8
    jz .second_head
    mov [r8 + page_node_t.next], r9
    jmp .second_check_tail
.second_head:
    mov [inactive_list_head], r9
.second_check_tail:
    test r9, r9
    jz .second_tail
    mov [r9 + page_node_t.prev], r8
    jmp .second_unlinked
.second_tail:
    mov [inactive_list_tail], r8
.second_unlinked:
    dec qword [inactive_count]

    ; Prepend to active list (head)
    mov qword [rbx + page_node_t.flags], 1 ; Active
    mov qword [rbx + page_node_t.prev], 0
    mov rcx, [active_list_head]
    mov [rbx + page_node_t.next], rcx
    test rcx, rcx
    jz .second_active_first
    mov [rcx + page_node_t.prev], rbx
    mov [active_list_head], rbx
    jmp .second_active_linked
.second_active_first:
    mov [active_list_head], rbx
    mov [active_list_tail], rbx
.second_active_linked:
    inc qword [active_count]

    jmp .scan_next

.scan_unmapped:
    ; Unlink and free unmapped page node
    mov r8, [rbx + page_node_t.prev]
    mov r9, [rbx + page_node_t.next]
    test r8, r8
    jz .scan_unmap_head
    mov [r8 + page_node_t.next], r9
    jmp .scan_unmap_tail
.scan_unmap_head:
    mov [inactive_list_head], r9
.scan_unmap_tail:
    test r9, r9
    jz .scan_unmap_tail_done
    mov [r9 + page_node_t.prev], r8
    jmp .scan_unmap_done
.scan_unmap_tail_done:
    mov [inactive_list_tail], r8
.scan_unmap_done:
    dec qword [inactive_count]

    call replacement_lock_release
    mov rdi, rbx
    call heap_free
    call replacement_lock_acquire

.scan_next:
    mov rbx, r12
    jmp .scan_loop

.abort_evict:
    ; Free the swap slot we allocated since we aborted eviction
    call replacement_lock_release
    mov rdi, r10
    test r8, r8
    jz .abort_disk_swap
    call zswap_free_slot
    jmp .abort_done
.abort_disk_swap:
    call swap_free_slot
.abort_done:
    call replacement_lock_acquire
    jmp .scan_next

.fail_swap_full:
    call replacement_lock_acquire
    jmp .fail_unlock

.fail_unlock:
    call replacement_lock_release
    xor rax, rax                    ; return 0 (failure)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data

align 8
global swap_slots
swap_slots: times SWAP_MAX_SLOTS dq 0

%endif ; LIB_MEM_VIRT_SWAP_ASM
