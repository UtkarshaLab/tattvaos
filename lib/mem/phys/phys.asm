; =============================================================================
; Tattva OS — lib/mem/phys/phys.asm
; =============================================================================
; Physical memory manager. Coordinates E820 parsing, bitmap allocation,
; page booking, and runtime PMM APIs.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_PHYS_PHYS_ASM
%define LIB_MEM_PHYS_PHYS_ASM

[BITS 64]

extern kswapd_check_and_reclaim
extern numa_local_bitmaps_active
extern numa_nodes
extern numa_node_count
extern numa_get_distance
extern numa_get_node_by_phys
extern bitmap_set_bit_local
extern bitmap_clear_bit_local
extern bitmap_find_free_local
extern uart_print_dec
extern msg_numa_fallback_prefix
extern msg_numa_fallback_middle
extern msg_numa_fallback_dist
extern msg_numa_fallback_suffix

section .text

; -----------------------------------------------------------------------------
; phys_init — discovers system RAM, calculates bitmap requirements, locates
;             a safe memory slot for the page bitmap, and initializes it.
; Input:  none (reads from global boot_info_ptr)
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
phys_init:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10

    ; 1. Load BootInfo pointer
    mov rdi, [boot_info_ptr]
    test rdi, rdi
    jz .error_halt                  ; crash early if BootInfo is null

    ; 2. Extract E820 map address and entry count
    mov rsi, [rdi + 0]              ; rsi = physical pointer to e820 entries (offset 0)
    mov rdx, [rdi + 8]              ; rdx = e820 entry count (offset 8)
    test rsi, rsi
    jz .error_halt
    test rdx, rdx
    jz .error_halt

    ; 3. Parse E820 map to get max RAM address and total usable page count
    mov rdi, rsi                    ; RDI = e820 map pointer
    mov rsi, rdx                    ; RSI = entry count
    call phys_parse_e820            ; RAX = max_phys_addr, RCX = total_pages
    test rax, rax
    jz .error_halt

    ; Store results in state
    mov [phys_state + phys_state_t.max_phys_addr], rax
    mov [phys_state + phys_state_t.total_pages], rcx
    mov [phys_state + phys_state_t.free_pages], rcx

    ; 4. Calculate bitmap size in bytes: (max_phys_addr / 4096) / 8
    ; which is max_phys_addr / 32768 (shr 15)
    mov rbx, rax
    shr rbx, 15                     ; rbx = bitmap_size in bytes
    test rbx, rbx
    jnz .store_bitmap_size
    mov rbx, 1                      ; ensure size is at least 1 byte
.store_bitmap_size:
    mov [phys_state + phys_state_t.bitmap_size], rbx

    ; 5. Scan the E820 map to find a free RAM region above 1MB to place the bitmap
    mov rdi, [boot_info_ptr]
    mov rsi, [rdi + 0]              ; rsi = E820 map pointer
    mov rdx, [rdi + 8]              ; rdx = entry count
    xor r8, r8                      ; r8 = index loop

.scan_loop:
    cmp r8, rdx
    jge .no_bitmap_mem

    ; Calculate pointer to current entry: RSI + R8 * 24
    mov r9, r8
    imul r9, 24
    add r9, rsi

    ; Check type == 1 (usable RAM)
    mov r10d, [r9 + e820_entry.type]
    cmp r10d, 1
    jne .next_entry

    mov r10, [r9 + e820_entry.base]
    mov r11, [r9 + e820_entry.length]

    ; Check if base is below 1MB (0x100000). If so, shrink or skip.
    cmp r10, 0x100000
    jae .check_size

    ; Base is below 1MB. Adjust base and length.
    mov rcx, 0x100000
    sub rcx, r10                    ; rcx = offset from base to 1MB
    cmp r11, rcx
    jbe .next_entry                 ; not enough memory left in this region
    add r10, rcx                    ; shift base to 1MB
    sub r11, rcx                    ; shrink length

.check_size:
    ; Check if this adjusted region has enough bytes to hold the bitmap
    cmp r11, rbx
    jb .next_entry

    ; Found a suitable block! Place bitmap at the base address of this region (R10)
    mov [phys_state + phys_state_t.bitmap_addr], r10
    jmp .init_bitmap

.next_entry:
    inc r8
    jmp .scan_loop

.no_bitmap_mem:
    ; Panics if we cannot find memory for the allocator bitmap
    mov rsi, msg_err_bitmap_oom
    call uart_print_str
    cli
.halt_loop:
    hlt
    jmp .halt_loop

.init_bitmap:
    ; 6. Fill the entire bitmap memory with 0xFF (all pages reserved by default)
    ; Target address: bitmap_addr, Fill value: 0xFF, Count: bitmap_size bytes
    mov rdi, [phys_state + phys_state_t.bitmap_addr]
    mov rcx, rbx                    ; RCX = bitmap_size in bytes
    mov al, 0xFF
    cld
    rep stosb                       ; fill the bitmap

    ; 7. Re-scan E820 map and clear bits for usable RAM regions (Subfeature 1.3)
    mov rdi, [boot_info_ptr]
    mov rsi, [rdi + 0]              ; rsi = E820 map pointer
    mov rdx, [rdi + 8]              ; rdx = entry count
    xor r8, r8                      ; r8 = index loop

.clear_loop:
    cmp r8, rdx
    jge .clear_done

    mov r9, r8
    imul r9, 24
    add r9, rsi                     ; r9 = e820_entry pointer

    mov r10d, [r9 + e820_entry.type]
    cmp r10d, 1                      ; type == 1 (usable)?
    jne .next_clear

    mov r10, [r9 + e820_entry.base]
    mov r11, [r9 + e820_entry.length]

    ; Calculate start page index = base / 4096 (shr 12)
    mov rbx, r10
    shr rbx, 12                     ; rbx = start page index

    ; Calculate page count = length / 4096 (shr 12)
    mov rcx, r11
    shr rcx, 12                     ; rcx = page count

.clear_page_loop:
    test rcx, rcx
    jz .next_clear

    ; Clear bit for page index rbx
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r9
    
    mov rdi, rbx
    call bitmap_clear_bit
    
    pop r9
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi

    inc rbx                         ; next page
    dec rcx
    jmp .clear_page_loop

.next_clear:
    inc r8
    jmp .clear_loop

.clear_done:
    ; 8. Protect low 1MB memory region (0x0 to 0x100000) (Subfeature 1.4)
    ; 1MB / 4096 = 256 pages. Set the first 256 bits in the bitmap to 1.
    xor rbx, rbx                    ; rbx = start page index = 0
    mov rcx, 256                    ; rcx = 256 pages (1MB)

.reserve_low_loop:
    test rcx, rcx
    jz .reserve_low_done

    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    
    mov rdi, rbx
    call bitmap_set_bit
    
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi

    inc rbx
    dec rcx
    jmp .reserve_low_loop

.reserve_low_done:
    ; -----------------------------------------------------------------------------
    ; 9. Protect Kernel Code & Data (Subfeature 1.5)
    ; Mark all pages from 1MB (0x100000) to kernel_end as reserved.
    ; -----------------------------------------------------------------------------
    mov rax, kernel_end
    add rax, 4095
    shr rax, 12                     ; RAX = kernel_end page index (exclusive)
    mov rbx, 256                    ; start page index = 256 (1MB)

.reserve_kernel_loop:
    cmp rbx, rax
    jae .reserve_kernel_done

    push rax
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    
    mov rdi, rbx
    call bitmap_set_bit
    
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rax

    inc rbx
    jmp .reserve_kernel_loop

.reserve_kernel_done:

    ; -----------------------------------------------------------------------------
    ; 10. Protect Page Bitmap Self-Memory (Subfeature 1.6)
    ; Mark all pages from bitmap_addr to bitmap_addr + bitmap_size as reserved.
    ; -----------------------------------------------------------------------------
    mov rbx, [phys_state + phys_state_t.bitmap_addr]
    mov rcx, [phys_state + phys_state_t.bitmap_size]
    
    ; Convert base to page index
    shr rbx, 12                     ; rbx = start page index
    
    ; Calculate end page index
    mov rax, [phys_state + phys_state_t.bitmap_addr]
    add rax, rcx                    ; rax = end address of bitmap
    add rax, 4095
    shr rax, 12                     ; rax = end page index (exclusive)

.reserve_bitmap_loop:
    cmp rbx, rax
    jae .reserve_bitmap_done

    push rax
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    
    mov rdi, rbx
    call bitmap_set_bit
    
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rax

    inc rbx
    jmp .reserve_bitmap_loop

.reserve_bitmap_done:
    ; 11. Recount free pages by scanning the bitmap for zero bits
    ;     This is the authoritative count after all protections are applied.
    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    mov rcx, [phys_state + phys_state_t.total_pages]
    xor r8, r8                      ; R8 = free page counter
    xor r9, r9                      ; R9 = current page index

.recount_loop:
    cmp r9, rcx
    jge .recount_done

    ; Test bit R9 in bitmap
    mov rax, r9
    shr rax, 3                      ; byte offset
    mov rbx, r9
    and rbx, 7                      ; bit offset
    bt [rsi + rax], rbx
    jc .recount_next                ; bit set = reserved, skip

    inc r8                          ; bit clear = free page

.recount_next:
    inc r9
    jmp .recount_loop

.recount_done:
    ; Store accurate counters
    mov [phys_state + phys_state_t.free_pages], r8
    mov rax, [phys_state + phys_state_t.total_pages]
    sub rax, r8
    mov [phys_state + phys_state_t.reserved_pages], rax

    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

.error_halt:
    cli
    hlt
    jmp .error_halt

; -----------------------------------------------------------------------------
; phys_alloc_page — allocates a single 4KB physical page
; Input:  none
; Output: RAX = physical address of the allocated page, or 0 if OOM
; Clobbers: none (preserves all registers except RAX)
; -----------------------------------------------------------------------------
global phys_alloc_page
phys_alloc_page:
    ; Check if NUMA active
    mov rax, [numa_local_bitmaps_active]
    test rax, rax
    jz .use_uma

    ; NUMA active: allocate from Node 0
    xor rdi, rdi                    ; RDI = node_id = 0
    mov rsi, 1                      ; page_count = 1
    call phys_alloc_pages_node      ; RAX = physical address
    ret

.use_uma:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    ; Check watermarks and trigger page reclamation if needed
    call kswapd_check_and_reclaim

    ; Find 1 free page
    mov rdi, 1
    call bitmap_find_free
    cmp rax, -1
    je .oom

    ; Save the page index in RDI
    mov rdi, rax

    ; Set the bit to 1
    call bitmap_set_bit

    ; Decrement free_pages count
    dec qword [phys_state + phys_state_t.free_pages]
    ; Increment reserved_pages count
    inc qword [phys_state + phys_state_t.reserved_pages]

    ; Calculate physical address: page_index * 4096 (shl 12)
    mov rax, rdi
    shl rax, 12
    jmp .done

.oom:
    xor rax, rax                    ; return 0 on OOM

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; phys_free_page — frees a single 4KB physical page
; Input:  RDI = physical address of the page to free
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
global phys_free_page
phys_free_page:
    mov rsi, 1                      ; count = 1
    jmp phys_free_pages             ; tail call

; -----------------------------------------------------------------------------
; phys_alloc_pages — allocates N contiguous 4KB physical pages
; Input:  RDI = page count (N)
; Output: RAX = physical address of the start of the allocated region, or 0 if OOM
; Clobbers: none (preserves all registers except RAX)
; -----------------------------------------------------------------------------
global phys_alloc_pages
phys_alloc_pages:
    ; Check if NUMA active
    mov rax, [numa_local_bitmaps_active]
    test rax, rax
    jz .use_uma

    ; NUMA active: allocate from Node 0
    mov rsi, rdi                    ; RSI = page count
    xor rdi, rdi                    ; RDI = node_id = 0
    call phys_alloc_pages_node      ; RAX = physical address
    ret

.use_uma:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    ; Check watermarks and trigger page reclamation if needed (preserve RDI)
    push rdi
    call kswapd_check_and_reclaim
    pop rdi

    ; Save count in R8
    mov r8, rdi

    ; Find R8 contiguous free pages
    call bitmap_find_free
    cmp rax, -1
    je .oom

    ; Save start page index in R9
    mov r9, rax

    ; Loop to set bits from R9 to R9 + R8 - 1
    mov rsi, r9                     ; current page index
    mov rcx, r8                     ; loop counter
.set_loop:
    test rcx, rcx
    jz .set_done
    
    mov rdi, rsi
    call bitmap_set_bit
    
    inc rsi
    dec rcx
    jmp .set_loop

.set_done:
    ; Update free_pages count
    sub [phys_state + phys_state_t.free_pages], r8
    ; Update reserved_pages count
    add [phys_state + phys_state_t.reserved_pages], r8

    ; Calculate physical address: start_page_index * 4096
    mov rax, r9
    shl rax, 12
    jmp .done

.oom:
    xor rax, rax                    ; return 0 on OOM

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; phys_alloc_page_node — allocates a single 4KB page from a specific node
; Input:  RDI = node_id
; Output: RAX = physical address, or 0 if OOM
; -----------------------------------------------------------------------------
global phys_alloc_page_node
phys_alloc_page_node:
    mov rsi, 1                      ; page_count = 1
    jmp phys_alloc_pages_node       ; tail call

; -----------------------------------------------------------------------------
; phys_alloc_pages_node — allocates contiguous pages from a specific node
; Input:
;   RDI = node_id
;   RSI = page_count (N)
; Output:
;   RAX = physical address of allocated region, or 0 if OOM
; -----------------------------------------------------------------------------
global phys_alloc_pages_node
phys_alloc_pages_node:
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

    mov r12, rdi                    ; R12 = requested node_id
    mov r13, rsi                    ; R13 = page_count

    ; Verify node_id is within count
    mov rax, [numa_node_count]
    cmp r12, rax
    jae .fallback_init

    ; Check if node is active
    mov rax, r12
    imul rax, numa_node_t_size
    lea rbx, [numa_nodes + rax]     ; RBX = node_ptr
    mov eax, [rbx + numa_node_t.flags]
    test al, 1                      ; active?
    jz .fallback_init

    ; Try allocating from the requested node
    mov rdi, rbx
    mov rsi, r13
    call bitmap_find_free_local
    cmp rax, -1
    je .fallback_init

    ; Allocation succeeded on requested node!
    mov rdx, rax                    ; RDX = relative start page index
    jmp .perform_alloc

.fallback_init:
    ; Fallback initialization: set tried mask (bitmask)
    xor r15, r15
    cmp r12, 64
    jae .fallback_loop              ; safe guard
    mov rax, 1
    mov rcx, r12
    shl rax, cl
    mov r15, rax                    ; R15 = tried mask (bit for requested node set)

.fallback_loop:
    ; Find untried active node with minimum distance
    mov rbp, -1                     ; RBP = best node index
    mov r8, 255                     ; R8 = minimum distance

    xor r9, r9                      ; R9 = loop index J = 0
.fallback_search_loop:
    cmp r9, [numa_node_count]
    jae .fallback_search_done

    ; Check if active
    mov rax, r9
    imul rax, numa_node_t_size
    lea rcx, [numa_nodes + rax]
    mov eax, [rcx + numa_node_t.flags]
    test al, 1
    jz .next_fallback_search

    ; Check if already tried
    mov rax, 1
    mov rcx, r9
    shl rax, cl
    test r15, rax
    jnz .next_fallback_search       ; already tried

    ; Get distance from r12 (requested node) to r9 (node J)
    mov rdi, r12
    mov rsi, r9
    call numa_get_distance          ; RAX = distance
    cmp rax, 255
    je .next_fallback_search        ; unreachable node

    cmp rax, r8
    jae .next_fallback_search       ; not closer

    mov r8, rax                     ; new minimum distance
    mov rbp, r9                     ; new best node index

.next_fallback_search:
    inc r9
    jmp .fallback_search_loop

.fallback_search_done:
    cmp rbp, -1
    je .oom                         ; no more candidate nodes found

    ; Mark rbp as tried
    mov rax, 1
    mov rcx, rbp
    shl rax, cl
    or r15, rax

    ; Try allocating from node rbp
    mov rax, rbp
    imul rax, numa_node_t_size
    lea rbx, [numa_nodes + rax]     ; RBX = candidate node_ptr

    mov rdi, rbx
    mov rsi, r13
    call bitmap_find_free_local
    cmp rax, -1
    je .fallback_loop               ; failed, try next closest node

    ; Allocation succeeded on candidate node rbp!
    mov rdx, rax                    ; RDX = relative start page index

    ; Print fallback log
    push rdx
    mov rsi, msg_numa_fallback_prefix
    call uart_print_str
    mov rax, r12
    call uart_print_dec
    mov rsi, msg_numa_fallback_middle
    call uart_print_str
    mov rax, rbp
    call uart_print_dec
    mov rsi, msg_numa_fallback_dist
    call uart_print_str
    mov rax, r8
    call uart_print_dec
    mov rsi, msg_numa_fallback_suffix
    call uart_print_str
    pop rdx
    jmp .perform_alloc

.perform_alloc:
    ; RBX = node_ptr
    ; RDX = relative start page index
    ; R13 = page_count
    
    ; Mark bits in the node's local bitmap
    xor rcx, rcx                    ; RCX = index offset = 0
.set_bits_loop:
    cmp rcx, r13
    jae .update_counters

    mov rsi, rdx
    add rsi, rcx                    ; relative page to set

    mov rdi, rbx
    call bitmap_set_bit_local

    inc rcx
    jmp .set_bits_loop

.update_counters:
    ; Update node-local counters
    sub [rbx + numa_node_t.free_pages], r13
    add [rbx + numa_node_t.reserved_pages], r13

    ; Update global counters
    sub [phys_state + phys_state_t.free_pages], r13
    add [phys_state + phys_state_t.reserved_pages], r13

    ; Calculate physical address: (node.start_page + relative_page) * 4096
    mov rax, [rbx + numa_node_t.start_page]
    add rax, rdx
    shl rax, 12                     ; physical address
    jmp .exit

.oom:
    xor rax, rax                    ; return 0

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

; -----------------------------------------------------------------------------
; phys_free_pages — frees N contiguous 4KB physical pages
; Input:  RDI = starting physical address
;         RSI = page count (N)
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
global phys_free_pages
phys_free_pages:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    ; Check if NUMA active
    mov rax, [numa_local_bitmaps_active]
    test rax, rax
    jz .use_uma

    ; NUMA active: free from node-local bitmaps
    mov r8, rsi                     ; R8 = count N
    mov r9, rdi                     ; R9 = physical address
    
    ; Determine node ID for the physical address
    mov rdi, r9
    call numa_get_node_by_phys      ; RAX = Node ID
    
    ; Get node descriptor
    imul rax, numa_node_t_size
    lea rbx, [numa_nodes + rax]     ; RBX = node descriptor

    ; Calculate relative start page index: (phys_addr >> 12) - node.start_page
    mov rcx, r9
    shr rcx, 12                     ; RCX = absolute page index
    sub rcx, [rbx + numa_node_t.start_page] ; RCX = relative start page index

    ; Loop to clear bits
    xor rdx, rdx                    ; RDX = loop counter i = 0
.clear_bits_loop:
    cmp rdx, r8
    jae .update_free_counters

    mov rsi, rcx
    add rsi, rdx                    ; relative page index to clear

    mov rdi, rbx
    call bitmap_clear_bit_local

    inc rdx
    jmp .clear_bits_loop

.update_free_counters:
    ; Update node-local counters
    add [rbx + numa_node_t.free_pages], r8
    sub [rbx + numa_node_t.reserved_pages], r8

    ; Update global counters
    add [phys_state + phys_state_t.free_pages], r8
    sub [phys_state + phys_state_t.reserved_pages], r8
    jmp .done

.use_uma:
    ; Save count in R8 and start address in R9
    mov r8, rsi
    mov r9, rdi

    ; Calculate start page index: address / 4096
    shr r9, 12                      ; R9 = start page index

    ; Loop to clear bits from R9 to R9 + R8 - 1
    mov rsi, r9                     ; current page index
    mov rcx, r8                     ; loop counter
.clear_loop:
    test rcx, rcx
    jz .clear_done
    
    mov rdi, rsi
    call bitmap_clear_bit
    
    inc rsi
    dec rcx
    jmp .clear_loop

.clear_done:
    ; Update free_pages count
    add [phys_state + phys_state_t.free_pages], r8
    ; Update reserved_pages count
    sub [phys_state + phys_state_t.reserved_pages], r8

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; phys_add_region — dynamically adds a new physical RAM region (RAM Hotplug) (1.11)
; Input:
;   RDI = physical base address of the region
;   RSI = length of the region in bytes
; Output: none
; Clobbers: RAX, RCX, RDX, RDI, RSI
; -----------------------------------------------------------------------------
global phys_add_region
phys_add_region:
    push rbx
    push rbp
    
    ; Convert base and length to page index and count
    mov rax, rdi
    shr rax, 12                     ; RAX = start page index
    mov rcx, rsi
    shr rcx, 12                     ; RCX = page count
    
    test rcx, rcx
    jz .done

    ; Update total_pages and free_pages counters
    add [phys_state + phys_state_t.total_pages], rcx
    add [phys_state + phys_state_t.free_pages], rcx
    
    ; Calculate new max physical address if needed
    mov rdx, rdi
    add rdx, rsi                    ; RDX = end address of new region
    cmp rdx, [phys_state + phys_state_t.max_phys_addr]
    jbe .clear_loop
    mov [phys_state + phys_state_t.max_phys_addr], rdx

.clear_loop:
    test rcx, rcx
    jz .done
    
    push rax
    push rcx
    mov rdi, rax
    call bitmap_clear_bit           ; clear bit (make free)
    pop rcx
    pop rax
    
    inc rax                         ; next page index
    dec rcx
    jmp .clear_loop

.done:
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; phys_get_stats — returns the pointer to the physical memory state structure (1.12)
; Input:  none
; Output: RAX = pointer to phys_state
; -----------------------------------------------------------------------------
global phys_get_stats
phys_get_stats:
    mov rax, phys_state
    ret

; -----------------------------------------------------------------------------
; Physical State and Error Messages
; -----------------------------------------------------------------------------
section .data

align 8
global phys_state
phys_state:
    istruc phys_state_t
        at phys_state_t.bitmap_addr,    dq 0
        at phys_state_t.bitmap_size,    dq 0
        at phys_state_t.total_pages,    dq 0
        at phys_state_t.free_pages,     dq 0
        at phys_state_t.max_phys_addr,  dq 0
        at phys_state_t.reserved_pages, dq 0
        at phys_state_t.swap_pages,     dq 0
        at phys_state_t.dirty_pages,    dq 0
    iend

msg_err_bitmap_oom: db "!!! KERNEL PANIC: Failed to locate free RAM above 1MB for Page Bitmap !!!", 0x0D, 0x0A, 0

%endif ; LIB_MEM_PHYS_PHYS_ASM
