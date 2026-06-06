; =============================================================================
; Tattva OS — lib/mem/heap/defrag.asm
; =============================================================================
; Heap Defragmenter (Subfeature 9.5).
; Compacts heap memory dynamically by sliding active blocks to lower addresses
; and updates reference pointers using a relocation registry.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_HEAP_DEFRAG_ASM
%define LIB_MEM_HEAP_DEFRAG_ASM

[BITS 64]

; Table size for pointer registration
RELOC_TABLE_SIZE equ 64

section .text

; External symbols (from other modules in the same unit)
extern early_bump_state
extern heap_active_allocator
extern free_list_head
extern uart_print_str

; -----------------------------------------------------------------------------
; heap_register_relocatable — registers the address of a pointer variable
; Input:
;   RDI = address of the pointer variable (to be updated during compaction)
; Output:
;   RAX = 1 on success, 0 if table is full
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global heap_register_relocatable
heap_register_relocatable:
    xor rcx, rcx                    ; loop index
.find_slot:
    cmp rcx, RELOC_TABLE_SIZE
    jae .fail
    
    mov rax, [heap_reloc_table + rcx * 8]
    test rax, rax                   ; check if slot is free (0)
    jz .store
    
    inc rcx
    jmp .find_slot

.store:
    mov [heap_reloc_table + rcx * 8], rdi
    mov rax, 1
    ret

.fail:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; heap_unregister_relocatable — unregisters the address of a pointer variable
; Input:
;   RDI = address of the pointer variable
; Output:
;   RAX = 1 on success, 0 if not found
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global heap_unregister_relocatable
heap_unregister_relocatable:
    xor rcx, rcx
.find_slot:
    cmp rcx, RELOC_TABLE_SIZE
    jae .fail
    
    mov rax, [heap_reloc_table + rcx * 8]
    cmp rax, rdi
    je .clear
    
    inc rcx
    jmp .find_slot

.clear:
    mov qword [heap_reloc_table + rcx * 8], 0
    mov rax, 1
    ret

.fail:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; heap_compact — compacts active heap allocations and updates registered pointers
; Output:
;   RAX = 1 on success
; -----------------------------------------------------------------------------
global heap_compact
heap_compact:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    ; 1. Verify that the free-list allocator is active
    mov al, [heap_active_allocator]
    cmp al, 1
    jne .done_ok                    ; if not active, compaction is a no-op

    ; 2. Determine start and end of free-list heap region
    ; heap_start = early_bump_state.current aligned to 16 bytes
    mov r12, [early_bump_state + early_bump_state_t.current]
    add r12, 15
    and r12, -16                    ; R12 = heap start address (current block pointer)
    
    mov r13, r12                    ; R13 = write pointer (where next used block will slide)
    
    mov r14, [early_bump_state + early_bump_state_t.end] ; R14 = heap end address

    ; 3. Sliding Compaction Pass
.compact_loop:
    cmp r12, r14
    jae .loop_done                  ; traversed whole heap

    mov rbx, [r12 + heap_block_t.flags]
    test rbx, 1                     ; is this block currently used?
    jz .skip_free

    ; --- Used Block Relocation ---
    ; Get size of current block payload
    mov rcx, [r12 + heap_block_t.size]
    
    cmp r12, r13                    ; check if block is already at the write pointer
    je .no_move

    ; Move block to R13
    mov rdx, rcx
    add rdx, heap_block_t_size      ; RDX = total bytes to copy (header + payload)
    
    ; Save registers for copy loop
    push rsi
    push rdi
    push rcx
    
    mov rsi, r12                    ; source = old block start
    mov rdi, r13                    ; dest = new block start
    mov rcx, rdx                    ; count = total size in bytes
    cld
    rep movsb                       ; copy block
    
    pop rcx
    pop rdi
    pop rsi

    ; Update pointer references in the relocation table
    mov rax, r12
    add rax, heap_block_t_size      ; RAX = old payload address
    mov rdx, r13
    add rdx, heap_block_t_size      ; RDX = new payload address
    call .update_relocations

.no_move:
    ; Advance write pointer by this block's total space (payload size + header)
    mov rcx, [r13 + heap_block_t.size]
    add r13, heap_block_t_size
    add r13, rcx                    ; R13 = next write position
    jmp .next_block

.skip_free:
    ; If block is free, we skip advancing R13 (so subsequent used blocks slide into it)
    jmp .next_block

.next_block:
    ; Advance R12 to the next block in physical memory order
    mov rcx, [r12 + heap_block_t.size]
    add r12, heap_block_t_size
    add r12, rcx                    ; R12 = next physical block
    jmp .compact_loop

.loop_done:
    ; 4. Rebuild Consolidated Free list
    ; All free space has been pushed to the end, starting at R13, ending at R14
    cmp r13, r14
    jae .heap_full                  ; no free space left

    ; Calculate remaining free size (excluding header overhead)
    mov rax, r14
    sub rax, r13
    sub rax, heap_block_t_size      ; RAX = remaining payload size

    ; Check if remaining space is too small for a valid block
    cmp rax, 16
    jl .heap_full

    ; Create a single large free block at R13
    mov [r13 + heap_block_t.size], rax
    mov qword [r13 + heap_block_t.flags], 0 ; free
    mov qword [r13 + heap_block_t.next], 0
    mov qword [r13 + heap_block_t.prev], 0
    
    mov [free_list_head], r13
    jmp .done_ok

.heap_full:
    mov qword [free_list_head], 0   ; list is empty, heap is 100% full

.done_ok:
    mov rax, 1

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Helper: updates registered pointers referencing old address to new address
; Input:
;   RAX = old payload address
;   RDX = new payload address
; -----------------------------------------------------------------------------
.update_relocations:
    push rcx
    push rsi
    push rdi
    push r8

    xor rcx, rcx                    ; loop index
.reloc_loop:
    cmp rcx, RELOC_TABLE_SIZE
    jae .reloc_done
    
    mov rsi, [heap_reloc_table + rcx * 8]
    test rsi, rsi                   ; check if registered slot is active
    jz .next
    
    mov r8, [rsi]                   ; R8 = current value of variable
    cmp r8, rax                     ; does it match the relocated old payload address?
    jne .next
    
    mov [rsi], rdx                  ; update variable content to new payload address!

.next:
    inc rcx
    jmp .reloc_loop

.reloc_done:
    pop r8
    pop rdi
    pop rsi
    pop rcx
    ret

section .bss

align 8
global heap_reloc_table
heap_reloc_table: resq RELOC_TABLE_SIZE

%endif ; LIB_MEM_HEAP_DEFRAG_ASM
