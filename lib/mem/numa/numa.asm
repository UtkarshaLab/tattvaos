; =============================================================================
; Tattva OS — lib/mem/numa/numa.asm
; =============================================================================
; NUMA Range structures and Node ID lookup functions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_NUMA_NUMA_ASM
%define LIB_MEM_NUMA_NUMA_ASM

[BITS 64]



; Maximum memory ranges we support parsing from SRAT
NUMA_MAX_RANGES equ 32

; NUMA node distance matrix constants
NUMA_MAX_NODES equ 8
NUMA_DEFAULT_LOCAL_DISTANCE equ 10
NUMA_DEFAULT_REMOTE_DISTANCE equ 20

section .text

; -----------------------------------------------------------------------------
; numa_get_node_by_phys — finds the NUMA Node ID for a physical address
; Input:
;   RDI = physical address
; Output:
;   RAX = Node ID (32-bit), or 0 if not found / UMA fallback
; -----------------------------------------------------------------------------
global numa_get_node_by_phys
numa_get_node_by_phys:
    push rbx
    push rcx
    push rdx

    mov rcx, [numa_range_count]
    test rcx, rcx
    jz .fallback

    lea rbx, [numa_ranges]
    xor rdx, rdx                    ; index i = 0

.loop:
    cmp rdx, rcx
    jge .fallback

    ; Calculate offset of range entry
    mov rax, rdx
    imul rax, numa_range_t_size
    lea r8, [rbx + rax]

    ; Check if entry is enabled (flags bit 0)
    mov eax, [r8 + numa_range_t.flags]
    test al, 1
    jz .next

    ; Check if RDI >= base
    mov rax, [r8 + numa_range_t.base]
    cmp rdi, rax
    jb .next

    ; Check if RDI < base + length
    add rax, [r8 + numa_range_t.length]
    cmp rdi, rax
    jb .found

.next:
    inc rdx
    jmp .loop

.found:
    movzx rax, dword [r8 + numa_range_t.node_id]
    jmp .exit

.fallback:
    xor rax, rax                    ; default to Node 0

.exit:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_get_distance — gets relative memory distance between two nodes
; Input:
;   RDI = node_from (Node ID)
;   RSI = node_to (Node ID)
; Output:
;   RAX = relative distance (e.g. 10 = local, 20 = default remote, 255 = unreachable)
; -----------------------------------------------------------------------------
global numa_get_distance
numa_get_distance:
    push rbx
    push rcx
    push rdx

    ; 1. Check bounds against numa_node_count
    mov rcx, [numa_node_count]
    test rcx, rcx
    jz .local_check                 ; if count is 0 (uninitialized), do UMA check

    cmp rdi, rcx
    jae .out_of_bounds
    cmp rsi, rcx
    jae .out_of_bounds

    ; Calculate index: node_from * numa_node_count + node_to
    mov rax, rdi
    imul rax, rcx
    add rax, rsi                    ; RAX = index
    
    ; Load distance byte from matrix
    lea rbx, [numa_distance_matrix]
    movzx rax, byte [rbx + rax]
    jmp .exit

.local_check:
    ; Fallback UMA check: if node_from == node_to, distance is 10, else 255
    cmp rdi, rsi
    je .local
    mov rax, 255
    jmp .exit
.local:
    mov rax, NUMA_DEFAULT_LOCAL_DISTANCE
    jmp .exit

.out_of_bounds:
    mov rax, 255                    ; unreachable/invalid

.exit:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; alloc_local_pages_for_bitmap — allocate contiguous pages within a node's physical ranges
; Input:
;   RDI = pointer to numa_node_t
;   RSI = page_count
; Output:
;   RAX = physical address, or 0 if failed
; Clobbers: RAX, RCX, RDX, R8, R9, R10, R11
; -----------------------------------------------------------------------------
alloc_local_pages_for_bitmap:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov r12, rdi                    ; r12 = node_ptr
    mov r13, rsi                    ; r13 = page_count
    mov r14d, [r12 + numa_node_t.node_id]

    ; Walk all numa_ranges to find one that belongs to node_id R14D
    xor rbx, rbx                    ; rbx = range index i = 0
.range_loop:
    cmp rbx, [numa_range_count]
    jae .failed

    mov rax, rbx
    imul rax, numa_range_t_size
    lea rdx, [numa_ranges + rax]

    ; Check if range is enabled and belongs to our node
    mov eax, [rdx + numa_range_t.flags]
    test al, 1                      ; enabled?
    jz .next_range
    mov eax, [rdx + numa_range_t.node_id]
    cmp eax, r14d
    jne .next_range

    ; USABLE RANGE found! Search for consecutive free pages inside [base .. base+length]
    mov r8, [rdx + numa_range_t.base]
    mov r9, [rdx + numa_range_t.length]
    
    ; Convert base and end to page indices
    shr r8, 12                      ; r8 = start page
    mov r10, r8
    shr r9, 12
    add r10, r9                     ; r10 = end page (exclusive)

    ; Search from r8 to r10 - r13
    mov rdi, r8                     ; rdi = current search index
.search_loop:
    mov rcx, rdi
    add rcx, r13
    cmp rcx, r10
    ja .next_range                  ; exceeds this range

    ; Verify if r13 pages starting at rdi are all free in the global bitmap
    xor rcx, rcx                    ; rcx = offset 0 .. r13-1
.check_free:
    cmp rcx, r13
    jae .found_block

    mov rax, rdi
    add rax, rcx                    ; page index to test

    ; Test page index in the global bitmap
    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    mov rdx, rax
    shr rdx, 3                      ; byte offset
    and rax, 7                      ; bit offset
    bt [rsi + rdx], rax
    jc .blocked                     ; bit set = occupied

    inc rcx
    jmp .check_free

.blocked:
    add rdi, rcx                    ; skip checked pages
    inc rdi
    jmp .search_loop

.found_block:
    ; Reserve these pages in the global bitmap
    xor rcx, rcx
.reserve_loop:
    cmp rcx, r13
    jae .reserve_done

    mov rax, rdi
    add rax, rcx

    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    mov rdx, rax
    shr rdx, 3                      ; byte offset
    and rax, 7                      ; bit offset
    bts [rsi + rdx], rax            ; set bit to 1

    inc rcx
    jmp .reserve_loop

.reserve_done:
    ; Return physical address
    mov rax, rdi
    shl rax, 12                     ; convert to phys address
    jmp .exit

.next_range:
    inc rbx
    jmp .range_loop

.failed:
    xor rax, rax                    ; return 0

.exit:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_init_local_bitmaps — allocates and transitions to node-local bitmaps
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global numa_init_local_bitmaps
numa_init_local_bitmaps:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r14, [numa_node_count]
    test r14, r14
    jz .exit                        ; if 0 nodes, exit

    ; 1. Calculate boundaries for each node
    xor r15, r15                    ; r15 = node index k = 0
.node_setup_loop:
    cmp r15, r14
    jae .init_bitmaps_start

    mov rax, r15
    imul rax, numa_node_t_size
    lea r12, [numa_nodes + rax]     ; r12 = current node descriptor

    ; Initialize default values
    mov dword [r12 + numa_node_t.node_id], r15d
    mov dword [r12 + numa_node_t.flags], 0
    mov qword [r12 + numa_node_t.start_page], -1 ; 0xFFFFFFFFFFFFFFFF
    mov qword [r12 + numa_node_t.end_page], 0
    mov qword [r12 + numa_node_t.total_pages], 0
    mov qword [r12 + numa_node_t.free_pages], 0
    mov qword [r12 + numa_node_t.reserved_pages], 0

    ; Scan numa_ranges to find boundaries
    xor rbx, rbx                    ; rbx = range index = 0
.node_ranges_loop:
    cmp rbx, [numa_range_count]
    jae .node_setup_next

    mov rax, rbx
    imul rax, numa_range_t_size
    lea rdx, [numa_ranges + rax]

    ; Check enabled
    mov eax, [rdx + numa_range_t.flags]
    test al, 1
    jz .next_range_setup
    ; Check matching node_id
    mov eax, [rdx + numa_range_t.node_id]
    cmp eax, r15d
    jne .next_range_setup

    ; Mark node active (bit 0 = 1)
    or dword [r12 + numa_node_t.flags], 1

    ; Get page bounds
    mov r8, [rdx + numa_range_t.base]
    mov r9, [rdx + numa_range_t.length]
    
    shr r8, 12                      ; range start page
    mov r10, r8
    shr r9, 12
    add r10, r9                     ; range end page (exclusive)

    ; Update node start_page
    mov rcx, [r12 + numa_node_t.start_page]
    cmp rcx, -1
    je .set_start_page
    cmp r8, rcx
    jae .check_end_page
.set_start_page:
    mov [r12 + numa_node_t.start_page], r8

.check_end_page:
    mov rcx, [r12 + numa_node_t.end_page]
    cmp r10, rcx
    jbe .add_total_pages
    mov [r12 + numa_node_t.end_page], r10

.add_total_pages:
    mov rcx, r10
    sub rcx, r8                     ; range page count
    add [r12 + numa_node_t.total_pages], rcx

.next_range_setup:
    inc rbx
    jmp .node_ranges_loop

.node_setup_next:
    inc r15
    jmp .node_setup_loop

.init_bitmaps_start:
    ; 2. Allocate and initialize bitmap for each active node
    xor r15, r15                    ; r15 = node index k = 0
.node_bitmap_loop:
    cmp r15, r14
    jae .complete_transition

    mov rax, r15
    imul rax, numa_node_t_size
    lea r12, [numa_nodes + rax]     ; r12 = current node descriptor

    ; Check if node is active
    mov eax, [r12 + numa_node_t.flags]
    test al, 1
    jz .node_bitmap_next

    ; Calculate bitmap size in bytes
    mov rax, [r12 + numa_node_t.end_page]
    sub rax, [r12 + numa_node_t.start_page] ; page count
    add rax, 7
    shr rax, 3                      ; bitmap size in bytes
    mov [r12 + numa_node_t.bitmap_size], rax

    ; Calculate bitmap page count
    add rax, 4095
    shr rax, 12                      ; bitmap pages needed
    mov r13, rax                    ; r13 = bitmap page count

    ; Allocate local memory from this node for the bitmap
    mov rdi, r12
    mov rsi, r13
    call alloc_local_pages_for_bitmap
    test rax, rax
    jnz .local_alloc_ok

    ; Fallback to global allocator if local allocation failed
    mov rdi, r13
    call phys_alloc_pages
    test rax, rax
    jz .panic_oom

.local_alloc_ok:
    mov [r12 + numa_node_t.bitmap_addr], rax

    ; Clear the allocated bitmap memory to 0 (all pages free by default)
    mov rdi, rax
    mov rcx, [r12 + numa_node_t.bitmap_size]
    xor al, al
    cld
    rep stosb

    ; Reserve the bitmap's own pages in its local bitmap
    mov rbx, [r12 + numa_node_t.bitmap_addr]
    shr rbx, 12                     ; start page index of bitmap
    sub rbx, [r12 + numa_node_t.start_page] ; relative start page

    xor rcx, rcx                    ; index 0 .. r13-1
.reserve_local_bitmap_pages:
    cmp rcx, r13
    jae .populate_from_global

    mov rsi, rbx
    add rsi, rcx                    ; relative page index parameter

    mov rdi, r12
    call bitmap_set_bit_local

    inc rcx
    jmp .reserve_local_bitmap_pages

.populate_from_global:
    ; 3. Populate allocation status of all pages from global bitmap
    mov r10, [r12 + numa_node_t.start_page]
    mov r11, [r12 + numa_node_t.end_page]
    xor rbx, rbx                    ; relative page index = 0

.populate_loop:
    mov rax, r10
    add rax, rbx                    ; rax = absolute page index
    cmp rax, r11
    jae .recount_node_free_pages

    ; Test absolute page in the global bitmap
    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    mov rdx, rax
    shr rdx, 3                      ; byte offset
    and rax, 7                      ; bit offset
    bt [rsi + rdx], rax
    jnc .populate_next              ; if clear (0/free), skip

    ; Set bit in the local bitmap
    mov rdi, r12
    mov rsi, rbx                    ; relative index
    call bitmap_set_bit_local

.populate_next:
    inc rbx
    jmp .populate_loop

.recount_node_free_pages:
    ; 4. Authoritative recount of free pages for this node
    mov rsi, [r12 + numa_node_t.bitmap_addr]
    mov rax, [r12 + numa_node_t.end_page]
    sub rax, [r12 + numa_node_t.start_page] ; page count
    mov rcx, rax

    xor r8, r8                      ; r8 = free page counter
    xor r9, r9                      ; r9 = relative page index
.node_recount_loop:
    cmp r9, rcx
    jae .node_recount_done

    mov rax, r9
    shr rax, 3                      ; byte offset
    mov rbx, r9
    and rbx, 7                      ; bit offset
    bt [rsi + rax], rbx
    jc .node_recount_next           ; if bit set, page is reserved

    inc r8                          ; page is free

.node_recount_next:
    inc r9
    jmp .node_recount_loop

.node_recount_done:
    mov [r12 + numa_node_t.free_pages], r8
    mov rax, [r12 + numa_node_t.total_pages]
    sub rax, r8
    mov [r12 + numa_node_t.reserved_pages], rax

    ; Mark bitmap initialized (bit 1 = 1)
    or dword [r12 + numa_node_t.flags], 2

.node_bitmap_next:
    inc r15
    jmp .node_bitmap_loop

.complete_transition:
    ; Set active flag to 1
    mov qword [numa_local_bitmaps_active], 1

    ; Print success message
    mov rsi, msg_numa_local_bitmaps_ok
    call uart_print_str

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

.panic_oom:
    ; Early boot crash if we cannot allocate local bitmap
    mov rsi, msg_err_numa_bitmap_oom
    call uart_print_str
    cli
.halt_loop:
    hlt
    jmp .halt_loop

; -----------------------------------------------------------------------------
; Data Section — NUMA ranges array and count
; -----------------------------------------------------------------------------
section .data

align 8
global numa_ranges
global numa_range_count
global numa_node_count
global numa_distance_matrix
global numa_nodes
global numa_local_bitmaps_active
global msg_numa_fallback_prefix
global msg_numa_fallback_middle
global msg_numa_fallback_dist
global msg_numa_fallback_suffix


numa_ranges:          times NUMA_MAX_RANGES * numa_range_t_size db 0
numa_range_count:     dq 0
numa_node_count:      dq 0
numa_distance_matrix: times NUMA_MAX_NODES * NUMA_MAX_NODES db 0
numa_nodes:          times NUMA_MAX_NODES * numa_node_t_size db 0
numa_local_bitmaps_active:   dq 0

msg_numa_local_bitmaps_ok:   db "NUMA: Node-Local Bitmaps successfully initialized.", 0x0D, 0x0A, 0
msg_err_numa_bitmap_oom:    db "Panic: Out of memory during NUMA local bitmap allocation.", 0x0D, 0x0A, 0

msg_numa_fallback_prefix: db "NUMA: Node ", 0
msg_numa_fallback_middle: db " OOM, falling back to Node ", 0
msg_numa_fallback_dist:   db " (distance ", 0
msg_numa_fallback_suffix: db ")", 0x0D, 0x0A, 0

%endif ; LIB_MEM_NUMA_NUMA_ASM
