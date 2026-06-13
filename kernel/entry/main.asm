; =============================================================================
; Tattva OS — kernel/entry/main.asm
; =============================================================================
; Kernel main entry point. Invoked after subsystem initialization completes.
; Prints the final kernel ready message and transitions to the CPU idle loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

PAGE_PRESENT    equ (1 << 0)
PAGE_XO         equ (1 << 9)
PAGE_KEY_1      equ (1 << 59)
PAGE_NX         equ (1 << 63)

section .text

; External VMM functions
extern vma_create
extern uart_print_str
extern uart_print_hex64
extern phys_alloc_page
extern virt_map
extern virt_translate
extern memcpy
extern zero_page_addr
extern vma_destroy
extern page_list_get_active_count
extern page_list_get_inactive_count
extern page_list_move_to_inactive
extern page_list_move_to_active
extern virt_unmap
extern phys_free_page
extern page_replace_clock_evict
extern phys_state
extern swap_register_device
extern ata_swap_dev
extern nvme_swap_dev
extern kswapd_low_watermark
extern kswapd_high_watermark
extern kswapd_check_and_reclaim
extern zswap_compressed_pages
extern numa_ranges
extern numa_range_count
extern numa_node_count
extern numa_get_node_by_phys
extern numa_detect_init
extern numa_get_distance
extern uart_print_dec
extern numa_local_bitmaps_active
extern numa_nodes
extern phys_alloc_page_node
extern phys_alloc_pages_node

extern mtrr_supported
extern mtrr_get_vcnt
extern mtrr_set_variable
extern mtrr_get_variable
extern mtrr_disable_variable
extern fb_init
extern fb_benchmark
extern heap_active_allocator
extern heap_register_relocatable
extern heap_unregister_relocatable
extern heap_compact
extern kmem_cache_file
extern kmem_cache_task
extern kmem_cache_vma
extern kmem_slab_grow
extern kmem_slab_link
extern kmem_slab_unlink
extern kmem_cache_create
extern kmem_cache_free
extern kmem_cache_reap
extern buddy_init
extern buddy_alloc
extern buddy_free
extern buddy_free_heads
extern buddy_start_addr
extern buddy_end_addr
extern buddy_metadata
extern arena_create
extern arena_alloc
extern arena_reset
extern arena_destroy
extern arena_checkpoint_save
extern arena_checkpoint_restore
extern arena_init_local
extern arena_alloc_local
extern arena_reset_local
extern arena_destroy_local
extern pool_create
extern pool_alloc
extern pool_free
extern pool_grow
extern pool_destroy
extern mock_file_create
extern mock_file_destroy
extern vma_map_file
extern mmap_msync
extern mmap_munmap
extern virt_create_user_pml4
extern ipc_share_frame
extern ipc_create_ring_buffer
extern ipc_destroy_ring_buffer
extern leak_tracker_init
extern heap_leak_report
extern leak_table
extern uaf_init
extern current_thread_idx
extern tsx_begin
extern tsx_end
extern tsx_log_init
extern tsx_log_address
extern tsx_spec_walk_engine
extern trans_cache_lookup
extern trans_cache_invalidate
extern trans_cache_flush
extern pgtable_locks
extern pgtable_lock_acquire
extern pgtable_lock_release
extern hle_protect_range
extern hle_is_cache_aligned
extern pgtable_lock_abort_counts








kernel_main:
    ; 1. Print kernel execution ready state
    mov rsi, msg_kernel_ready
    call uart_print_str

    ; 2. Run VMM Page Fault On-Demand Paging Test
    mov rsi, msg_test_start
    call uart_print_str

    ; Create a VMA: start=0x70000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_ONDEMAND (0x83)
    mov rdi, 0x70000000
    mov rsi, 4096
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .test_fail_vma

    mov rsi, msg_vma_ok
    call uart_print_str

    ; Access address to trigger page fault (read/write check)
    mov rdi, 0x70000000
    mov byte [rdi], 0x42            ; should trigger #PF and resume!

    ; Verification 1: Check if the written byte is present and correct
    mov al, [rdi]
    cmp al, 0x42
    jne .test_fail_val

    ; Verification 2: Print the mock loaded page content
    mov rsi, rdi
    call uart_print_str             ; should print "TATTVA_OS_ONDEMAND_PAGE_LOADED"
    mov rsi, msg_crlf
    call uart_print_str

    ; Verification 3: Check unique address written at offset 32
    mov rax, [rdi + 32]
    cmp rax, 0x70000000
    jne .test_fail_addr

    ; Test PASSED!
    mov rsi, msg_test_passed
    call uart_print_str

    ; 3. Run VMM Page Fault Copy-on-Write (COW) Test
    mov rsi, msg_cow_test_start
    call uart_print_str

    ; Step A: Allocate a physical page for parent content
    call phys_alloc_page
    test rax, rax
    jz .cow_fail_alloc
    mov r14, rax                    ; R14 = parent physical address

    ; Step B: Initialize the parent page content
    mov rdi, r14
    mov rsi, msg_cow_parent_data
    mov rdx, 25                     ; length of "COW_PARENT_ORIGINAL_DATA" (24 chars + null)
    call memcpy

    ; Step C: Create a VMA for the COW virtual address
    ; start=0x60000000, size=4096, flags=VMA_READ|VMA_WRITE (0x03)
    mov rdi, 0x60000000
    mov rsi, 4096
    mov rdx, 0x03                   ; VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .cow_fail_vma

    ; Step D: Map 0x60000000 to the parent physical page as read-only with PAGE_COW
    mov rdi, 0x60000000
    mov rsi, r14                    ; physical page
    mov rdx, 0x200                  ; PAGE_COW flag (1 << 9)
    call virt_map
    test rax, rax
    jz .cow_fail_map

    ; Verify initial mapping: virtual address should read the parent data
    mov rsi, msg_cow_before_write
    call uart_print_str
    mov rsi, 0x60000000
    call uart_print_str
    mov rsi, msg_crlf
    call uart_print_str

    ; Step E: Write to the virtual address to trigger COW page fault
    mov rdi, 0x60000000
    ; Write "CHILD_DATA" to virtual page (triggering COW)
    mov rsi, msg_cow_child_data
    mov rdx, 11                     ; length of msg_cow_child_data (10 chars + null)
    call memcpy

    ; Step F: Verify the write succeeded on the virtual page
    mov rsi, msg_cow_after_write
    call uart_print_str
    mov rsi, 0x60000000
    call uart_print_str
    mov rsi, msg_crlf
    call uart_print_str

    ; Step G: Verify page isolation (parent page must remain unmodified)
    mov rsi, msg_cow_parent_check
    call uart_print_str
    mov rsi, r14
    call uart_print_str
    mov rsi, msg_crlf
    call uart_print_str

    ; Programmatic verification:
    ; 1. Check if virtual page content has modified data "CHILD_DATA"
    mov rax, [0x60000000]
    mov rbx, 0x41445F444C494843     ; 'CHILD_DA' in little-endian
    cmp rax, rbx
    jne .cow_fail_isolation

    ; 2. Check if parent page content is still "COW_PARENT_ORIGINAL_DATA"
    mov rax, [r14]
    mov rbx, 0x455241505F574F43     ; 'COW_PARE' in little-endian
    cmp rax, rbx
    jne .cow_fail_isolation

    ; 3. Verify that virtual address is now mapped to a different physical address
    mov rdi, 0x60000000
    call virt_translate
    cmp rax, r14
    je .cow_fail_same_page

    ; COW Test PASSED!
    mov rsi, msg_cow_test_passed
    call uart_print_str

    ; 4. Run VMM Page Fault Zero-Fill-on-Demand (ZFOD) Test
    mov rsi, msg_zfod_test_start
    call uart_print_str

    ; Step A: Create a VMA for the ZFOD virtual address space
    ; start=0x50000000, size=8192 (2 pages), flags=VMA_READ|VMA_WRITE|VMA_ZFOD (0x23)
    mov rdi, 0x50000000
    mov rsi, 8192
    mov rdx, 0x23                   ; VMA_READ | VMA_WRITE | VMA_ZFOD
    call vma_create
    test rax, rax
    jz .zfod_fail_vma

    ; Step B: Test the read path on page 1 (0x50000000)
    ; Reading from it should return 0 since it is mapped to the shared zero page
    mov rax, [0x50000000]
    test rax, rax
    jnz .zfod_fail_read_val

    ; Let's verify that zero_page_addr has been initialized
    mov rax, [zero_page_addr]
    test rax, rax
    jz .zfod_fail_zero_ptr

    mov rsi, msg_zfod_read_ok
    call uart_print_str

    ; Step C: Write to page 1 to trigger COW on the shared zero page
    mov rax, 0x123456789ABCDEF0
    mov [0x50000000], rax

    ; Step D: Verify the write succeeded on page 1
    mov rax, [0x50000000]
    mov rbx, 0x123456789ABCDEF0
    cmp rax, rbx
    jne .zfod_fail_write_val

    ; Step E: Verify page isolation (shared zero page must still be all zeroes)
    mov rcx, [zero_page_addr]
    mov rax, [rcx]                  ; read from physical address (identity mapped)
    test rax, rax
    jnz .zfod_fail_isolation

    ; Step F: Verify mapping isolation (0x50000000 maps to a private page, not the zero page)
    mov rdi, 0x50000000
    call virt_translate
    mov rcx, [zero_page_addr]
    cmp rax, rcx
    je .zfod_fail_same_page

    mov rsi, msg_zfod_page1_ok
    call uart_print_str

    ; Step G: Test direct write path on page 2 (0x50001000)
    ; Accessing it directly via write should allocate a private zeroed page immediately
    mov rax, 0xABCDEF0123456789
    mov [0x50001000], rax

    ; Step H: Verify the write succeeded on page 2
    mov rax, [0x50001000]
    mov rbx, 0xABCDEF0123456789
    cmp rax, rbx
    jne .zfod_fail_page2_val

    ; Step I: Verify page 2 is not mapped to the shared zero page
    mov rdi, 0x50001000
    call virt_translate
    mov rcx, [zero_page_addr]
    cmp rax, rcx
    je .zfod_fail_page2_same

    ; ZFOD Test PASSED!
    mov rsi, msg_zfod_test_passed
    call uart_print_str

    ; 5. Run VMM Page Fault Stack Auto-Grow Test
    mov rsi, msg_stack_test_start
    call uart_print_str

    ; Step A: Determine page boundary immediately below current RSP
    mov rdi, rsp
    and rdi, -4096                  ; align down to 4KB boundary
    sub rdi, 4096                   ; page address immediately below RSP
    mov r14, rdi                    ; R14 = stack grow test virtual address

    ; Step B: Create a VMA for this stack grow region
    ; start=R14, size=4096, flags=VMA_READ|VMA_WRITE|VMA_STACK (0x43)
    mov rsi, 4096
    mov rdx, 0x43                   ; VMA_READ | VMA_WRITE | VMA_STACK
    call vma_create
    test rax, rax
    jz .stack_fail_vma
    mov r13, rax                    ; R13 = VMA pointer

    ; Step C: Trigger a write to the stack page
    ; We write at R14 + 4088 (8 bytes below the top of the new page, i.e. 8 bytes below original page boundary)
    mov r15, r14
    add r15, 4088
    mov qword [r15], 0x9876543210FEDCBA

    ; Step D: Verify the write succeeded
    mov rax, [r15]
    mov rbx, 0x9876543210FEDCBA
    cmp rax, rbx
    jne .stack_fail_val

    ; Step E: Verify the page is now mapped in the page table
    mov rdi, r15
    call virt_translate
    test rax, rax
    jz .stack_fail_map

    ; Step F: Clean up the stack VMA
    mov rdi, r13
    call vma_destroy

    ; Stack Auto-Grow Test PASSED!
    mov rsi, msg_stack_test_passed
    call uart_print_str

    ; 6. Run VMM Page Replacement Active/Inactive Page Lists Test
    mov rsi, msg_rep_test_start
    call uart_print_str

    ; Step A: Verify initial active and inactive page counts are 0
    call page_list_get_active_count
    test rax, rax
    jnz .rep_fail_init_count
    call page_list_get_inactive_count
    test rax, rax
    jnz .rep_fail_init_count

    ; Step B: Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .rep_fail_alloc
    mov r14, rax                    ; R14 = physical page address

    ; Step C: Create a VMA for the tracked virtual address space
    ; start=0x30000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_USER (0x0B)
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .rep_fail_vma
    mov r15, rax                    ; R15 = VMA pointer

    ; Step D: Map 0x30000000 to the physical page (triggers active list hook)
    mov rdi, 0x30000000
    mov rsi, r14
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .rep_fail_map

    ; Step E: Verify page added to Active list
    call page_list_get_active_count
    cmp rax, 1
    jne .rep_fail_active_count
    call page_list_get_inactive_count
    test rax, rax
    jnz .rep_fail_inactive_count

    ; Step F: Move page to Inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Step G: Verify page is now in Inactive list
    call page_list_get_active_count
    test rax, rax
    jnz .rep_fail_active_count_inactive
    call page_list_get_inactive_count
    cmp rax, 1
    jne .rep_fail_inactive_count_inactive

    ; Step H: Move page back to Active list
    mov rdi, r14
    call page_list_move_to_active

    ; Step I: Verify page is back in Active list
    call page_list_get_active_count
    cmp rax, 1
    jne .rep_fail_active_count_back
    call page_list_get_inactive_count
    test rax, rax
    jnz .rep_fail_inactive_count_back

    ; Step J: Unmap page (triggers removal hook)
    mov rdi, 0x30000000
    call virt_unmap

    ; Step K: Verify page is untracked (counts return to 0)
    call page_list_get_active_count
    test rax, rax
    jnz .rep_fail_final_count
    call page_list_get_inactive_count
    test rax, rax
    jnz .rep_fail_final_count

    ; Step L: Clean up physical frame and VMA
    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    ; Active/Inactive Lists Test PASSED!
    mov rsi, msg_rep_test_passed
    call uart_print_str

    ; 7. Run VMM Clock/Second-Chance Eviction Test
    mov rsi, msg_clock_test_start
    call uart_print_str

    ; Step A: Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .clock_fail_alloc
    mov r14, rax                    ; R14 = physical page address

    ; Step B: Initialize page content
    mov rdi, r14
    mov rsi, msg_clock_test_data
    mov rdx, 25                     ; length of msg_clock_test_data
    call memcpy

    ; Step C: Create a VMA for the tracked virtual address space
    ; start=0x20000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_USER (0x0B)
    mov rdi, 0x20000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .clock_fail_vma
    mov r15, rax                    ; R15 = VMA pointer

    ; Step D: Map 0x20000000 to the physical page (triggers active list hook)
    mov rdi, 0x20000000
    mov rsi, r14
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .clock_fail_map

    ; Step E: Move page to inactive list (to make it a candidate for eviction)
    mov rdi, r14
    call page_list_move_to_inactive

    ; Verify it is in inactive list
    call page_list_get_inactive_count
    cmp rax, 1
    jne .clock_fail_inactive

    ; Step F: Clear Accessed bit in PTE to simulate no recent accesses
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .clock_fail_walk
    and qword [rax], ~0x20          ; clear PAGE_ACCESSED (bit 5)

    ; Step G: Trigger Clock Eviction!
    call page_replace_clock_evict
    test rax, rax
    jz .clock_fail_evict

    ; Step H: Verify page is evicted
    ; 1. PTE Present bit should be 0
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .clock_fail_walk_evicted
    mov rcx, [rax]
    test rcx, 1                     ; present bit set?
    jnz .clock_fail_still_present

    ; 2. PTE Swapped bit should be 1
    test rcx, 0x400                 ; PAGE_SWAPPED (bit 10) set?
    jz .clock_fail_not_swapped

    ; 3. Telemetry swap_pages count should be 1
    mov rax, [phys_state + phys_state_t.swap_pages]
    cmp rax, 1
    jne .clock_fail_stats

    ; 4. Active/Inactive list counts should return to 0
    call page_list_get_active_count
    test rax, rax
    jnz .clock_fail_list_counts
    call page_list_get_inactive_count
    test rax, rax
    jnz .clock_fail_list_counts

    mov rsi, msg_clock_evicted_ok
    call uart_print_str

    ; Step I: Access the evicted page to trigger swap-in page fault!
    ; We read from 0x20000000. It should transparently swap-in the page!
    mov rax, [0x20000000]

    ; Step J: Verify data is intact
    mov rax, [0x20000000]
    mov rbx, 0x434F4D5F50415753     ; 'SWAP_MOC' in little-endian
    cmp rax, rbx
    jne .clock_fail_data_corrupt

    ; Step K: Verify page statistics and lists are restored
    ; 1. Telemetry swap_pages count should return to 0
    mov rax, [phys_state + phys_state_t.swap_pages]
    test rax, rax
    jnz .clock_fail_stats_restore

    ; 2. Page should be back in the active list (count = 1)
    call page_list_get_active_count
    cmp rax, 1
    jne .clock_fail_active_restore
    call page_list_get_inactive_count
    test rax, rax
    jnz .clock_fail_inactive_restore

    ; Step L: Clean up
    ; Get new physical page mapping
    mov rdi, 0x20000000
    call virt_translate
    mov r14, rax                    ; save new physical address for freeing

    mov rdi, 0x20000000
    call virt_unmap
    
    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    ; Clock Eviction Test PASSED!
    mov rsi, msg_clock_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; ATA Swap Device Test
    ; -------------------------------------------------------------
    mov rsi, msg_ata_test_start
    call uart_print_str

    ; Register ATA device
    lea rdi, [ata_swap_dev]
    call swap_register_device

    ; Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .ata_fail_alloc
    mov r14, rax

    ; Initialize page content
    mov rdi, r14
    mov rsi, msg_ata_test_data
    mov rdx, 25
    call memcpy

    ; Create VMA
    mov rdi, 0x20000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .ata_fail_vma
    mov r15, rax

    ; Map the page
    mov rdi, 0x20000000
    mov rsi, r14
    mov rdx, 0x07                   ; PRESENT | WRITABLE | USER
    call virt_map
    test rax, rax
    jz .ata_fail_map

    ; Move to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Verify it is in inactive list
    call page_list_get_inactive_count
    cmp rax, 1
    jne .ata_fail_inactive

    ; Clear Accessed bit in PTE
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .ata_fail_walk
    and qword [rax], ~0x20          ; clear Accessed (bit 5)

    ; Trigger Clock Eviction (now writing to ATA)
    call page_replace_clock_evict
    test rax, rax
    jz .ata_fail_evict

    ; Verify page is evicted
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .ata_fail_walk_evicted
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .ata_fail_still_present
    test rcx, 0x400                 ; swapped?
    jz .ata_fail_not_swapped

    ; Access page to trigger swap-in page fault
    mov rax, [0x20000000]

    ; Verify data
    mov rax, [0x20000000]
    mov rbx, 0x4154415F4B434F4D     ; 'MOCK_ATA' in little-endian ("MOCK_ATA_SWAP_DATA")
    cmp rax, rbx
    jne .ata_fail_data_corrupt

    ; Cleanup
    mov rdi, 0x20000000
    call virt_translate
    mov r14, rax

    mov rdi, 0x20000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    mov rsi, msg_ata_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; NVMe Swap Device Test
    ; -------------------------------------------------------------
    mov rsi, msg_nvme_test_start
    call uart_print_str

    ; Register NVMe device
    lea rdi, [nvme_swap_dev]
    call swap_register_device

    ; Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .nvme_fail_alloc
    mov r14, rax

    ; Initialize page content
    mov rdi, r14
    mov rsi, msg_nvme_test_data
    mov rdx, 25
    call memcpy

    ; Create VMA
    mov rdi, 0x20000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .nvme_fail_vma
    mov r15, rax

    ; Map the page
    mov rdi, 0x20000000
    mov rsi, r14
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .nvme_fail_map

    ; Move to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Verify it is in inactive list
    call page_list_get_inactive_count
    cmp rax, 1
    jne .nvme_fail_inactive

    ; Clear Accessed bit
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .nvme_fail_walk
    and qword [rax], ~0x20

    ; Trigger Clock Eviction (now writing to NVMe)
    call page_replace_clock_evict
    test rax, rax
    jz .nvme_fail_evict

    ; Verify page is evicted
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .nvme_fail_walk_evicted
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .nvme_fail_still_present
    test rcx, 0x400                 ; swapped?
    jz .nvme_fail_not_swapped

    ; Access page to trigger swap-in page fault
    mov rax, [0x20000000]

    ; Verify data
    mov rax, [0x20000000]
    mov rbx, 0x4D564E5F4B434F4D     ; 'MOCK_NVM' in little-endian ("MOCK_NVME_SWAP_DATA")
    cmp rax, rbx
    jne .nvme_fail_data_corrupt

    ; Cleanup
    mov rdi, 0x20000000
    call virt_translate
    mov r14, rax

    mov rdi, 0x20000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    mov rsi, msg_nvme_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; 8. Run VMM Page-Out Daemon (kswapd) Watermark test
    ; -------------------------------------------------------------
    mov rsi, msg_kswapd_test_start
    call uart_print_str

    ; Step A: Register the default mock RAM swap device
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Step B: Map user page to put it in the active list, then move to inactive
    call phys_alloc_page
    test rax, rax
    jz .kswapd_fail_alloc_setup
    mov r14, rax

    mov rdi, r14
    mov rsi, msg_kswapd_test_data
    mov rdx, 25
    call memcpy

    ; Create VMA
    mov rdi, 0x20000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .kswapd_fail_vma_setup
    mov r15, rax

    ; Map
    mov rdi, 0x20000000
    mov rsi, r14
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .kswapd_fail_map_setup

    ; Move to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Clear Accessed bit in PTE
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .kswapd_fail_walk_setup
    and qword [rax], ~0x20          ; clear Accessed

    ; Step C: Artificially set low watermark to a high value to force trigger
    mov rax, [phys_state + phys_state_t.free_pages]
    mov rbx, rax
    add rbx, 10                     ; rbx = low watermark
    mov [kswapd_low_watermark], rbx
    add rbx, 10                     ; rbx = high watermark
    mov [kswapd_high_watermark], rbx

    ; Step D: Perform a physical page allocation.
    ; This should automatically trigger kswapd_check_and_reclaim!
    call phys_alloc_page
    test rax, rax
    jz .kswapd_fail_alloc_trigger
    mov r13, rax                    ; r13 = allocated physical page address

    ; Step E: Verify kswapd successfully evicted our page!
    mov rdi, 0x20000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .kswapd_fail_walk_evicted
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .kswapd_fail_still_present
    test rcx, 0x400                 ; swapped?
    jz .kswapd_fail_not_swapped

    ; Step F: Verify data swap-in still works
    mov rax, [0x20000000]           ; should transparently swap-in!
    
    ; Verify data
    mov rax, [0x20000000]
    mov rbx, 0x57534B4B5F434F4D     ; 'MOCK_KSW' in little-endian ("MOCK_KSWAPD_SWAP_DATA")
    cmp rax, rbx
    jne .kswapd_fail_data_corrupt

    ; Step G: Reset watermarks back to 0 to prevent further triggers
    mov qword [kswapd_low_watermark], 0
    mov qword [kswapd_high_watermark], 0

    ; Step H: Cleanup both mapped page and the allocated page
    mov rdi, 0x20000000
    call virt_translate
    mov r14, rax                    ; get new physical frame

    mov rdi, 0x20000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page
    mov rdi, r15
    call vma_destroy

    mov rdi, r13
    call phys_free_page             ; free page allocated during trigger

    ; kswapd Test PASSED!
    mov rsi, msg_kswapd_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; 9. Run VMM Zswap Compressed Cache Test
    ; -------------------------------------------------------------
    mov rsi, msg_zswap_test_start
    call uart_print_str

    ; Step A: Register the default mock RAM swap device (clean state)
    lea rdi, [mock_swap_dev]
    call swap_register_device

    ; Verify that initial zswap compressed pages telemetry is 0
    mov rax, [zswap_compressed_pages]
    test rax, rax
    jnz .zswap_fail_init_telemetry

    ; --- Part 1: Compressible Page Test ---
    ; Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .zswap_fail_alloc1
    mov r14, rax                    ; R14 = physical address

    ; Initialize the page content with a highly compressible pattern (repeated 0xAA)
    mov rdi, r14
    mov al, 0xAA
    mov rcx, 4096
    cld
    rep stosb

    ; Set a recognizable signature at the start to verify data integrity later
    mov rdi, r14
    mov rsi, msg_zswap_comp_sig
    mov rdx, 17                     ; length of "COMPRESSIBLE_SIG" (16 + null)
    call memcpy

    ; Create a VMA: start=0x30000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_USER
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .zswap_fail_vma1
    mov r15, rax                    ; R15 = VMA pointer

    ; Map 0x30000000 to the physical page
    mov rdi, 0x30000000
    mov rsi, r14
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .zswap_fail_map1

    ; Move page to inactive list to prepare for eviction
    mov rdi, r14
    call page_list_move_to_inactive

    ; Clear Accessed bit in PTE to ensure eviction choice
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .zswap_fail_walk1
    and qword [rax], ~0x20          ; clear PAGE_ACCESSED

    ; Trigger Clock Eviction (which will try Zswap first)
    call page_replace_clock_evict
    test rax, rax
    jz .zswap_fail_evict1

    ; Verify Page is Evicted and Swapped to Zswap Cache
    ; 1. PTE Present bit should be 0
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .zswap_fail_walk_ev1
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .zswap_fail_still_present1

    ; 2. PTE PAGE_SWAPPED (bit 10) should be 1
    test rcx, 0x400                 ; PAGE_SWAPPED
    jz .zswap_fail_not_swapped1

    ; 3. PTE PAGE_ZSWAPPED (bit 11) should be 1
    test rcx, 0x800                 ; PAGE_ZSWAPPED
    jz .zswap_fail_not_zswapped1

    ; 4. Zswap telemetry should show 1 compressed page
    mov rax, [zswap_compressed_pages]
    cmp rax, 1
    jne .zswap_fail_telemetry1

    mov rsi, msg_zswap_evicted_ok
    call uart_print_str

    ; Access page to trigger transparent swap-in page fault (decompression)
    mov rax, [0x30000000]

    ; Verify data integrity after decompression
    mov rsi, 0x30000000             ; RSI = virtual address
    mov rbx, 0x53534552504D4F43     ; 'COMPRESS' in little-endian ("COMPRESSIBLE_SIG")
    cmp [rsi], rbx
    jne .zswap_fail_data_corrupt1

    ; Verify zswap telemetry returns to 0
    mov rax, [zswap_compressed_pages]
    test rax, rax
    jnz .zswap_fail_telemetry_res1

    ; Clean up Part 1
    mov rdi, 0x30000000
    call virt_translate
    mov r14, rax                    ; get new physical frame address

    mov rdi, 0x30000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    mov rdi, r15
    call vma_destroy

    mov rsi, msg_zswap_comp_passed
    call uart_print_str


    ; --- Part 2: Uncompressible Page Test ---
    ; Allocate a physical page
    call phys_alloc_page
    test rax, rax
    jz .zswap_fail_alloc2
    mov r14, rax

    ; Initialize page with an uncompressible ascending byte sequence (0, 1, 2, ... 255 repeating)
    mov rdi, r14
    xor rcx, rcx
.fill_uncompressible:
    cmp rcx, 4096
    jge .fill_uncomp_done
    mov rdx, rcx
    and rdx, 0xFF                   ; byte value sequence 0-255
    mov [rdi + rcx], dl
    inc rcx
    jmp .fill_uncompressible
.fill_uncomp_done:

    ; Set signature at start to verify data integrity
    mov rdi, r14
    mov rsi, msg_zswap_uncomp_sig
    mov rdx, 19                     ; length of "UNCOMPRESSIBLE_SIG" (18 + null)
    call memcpy

    ; Create VMA
    mov rdi, 0x30000000
    mov rsi, 4096
    mov rdx, 0x0B
    call vma_create
    test rax, rax
    jz .zswap_fail_vma2
    mov r15, rax

    ; Map
    mov rdi, 0x30000000
    mov rsi, r14
    mov rdx, 0x07
    call virt_map
    test rax, rax
    jz .zswap_fail_map2

    ; Move to inactive list
    mov rdi, r14
    call page_list_move_to_inactive

    ; Clear Accessed bit in PTE
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .zswap_fail_walk2
    and qword [rax], ~0x20          ; clear Accessed

    ; Trigger clock eviction (which will attempt zswap, fail/bypass to disk swap)
    call page_replace_clock_evict
    test rax, rax
    jz .zswap_fail_evict2

    ; Verify Page is Evicted directly to Swap Disk (zswap bypass)
    ; 1. PTE Present bit should be 0
    mov rdi, 0x30000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .zswap_fail_walk_ev2
    mov rcx, [rax]
    test rcx, 1                     ; present?
    jnz .zswap_fail_still_present2

    ; 2. PTE PAGE_SWAPPED (bit 10) should be 1
    test rcx, 0x400
    jz .zswap_fail_not_swapped2

    ; 3. PTE PAGE_ZSWAPPED (bit 11) should be 0
    test rcx, 0x800
    jnz .zswap_fail_is_zswapped2

    ; 4. Zswap telemetry should be 0 (no pages compressed in zswap)
    mov rax, [zswap_compressed_pages]
    test rax, rax
    jnz .zswap_fail_telemetry2

    mov rsi, msg_zswap_disk_evicted_ok
    call uart_print_str

    ; Access page to trigger transparent swap-in page fault (from disk)
    mov rax, [0x30000000]

    ; Verify data integrity
    mov rsi, 0x30000000
    mov rbx, 0x4D4F434E55             ; 'UNCOM' in little-endian ("UNCOMPRESSIBLE_SIG")
    mov rax, [rsi]
    and rax, 0xFFFFFFFFFF             ; compare 5 bytes
    cmp rax, rbx
    jne .zswap_fail_data_corrupt2

    ; Clean up Part 2
    mov rdi, 0x30000000
    call virt_translate
    mov r14, rax

    mov rdi, 0x30000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    mov rdi, r15
    call vma_destroy

    ; Zswap Test Suite PASSED!
    mov rsi, msg_zswap_test_passed
    call uart_print_str

    ; -------------------------------------------------------------
    ; 10. Run VMM MTRR Cache Programming Test
    ; -------------------------------------------------------------
    mov rsi, msg_mtrr_test_start
    call uart_print_str

    ; Step A: Verify MTRRs are supported on this processor
    call mtrr_supported
    test rax, rax
    jz .mtrr_skip_test              ; if not supported, skip gracefully

    ; Step B: Print variable count
    call mtrr_get_vcnt
    mov rsi, msg_mtrr_vcnt_str
    call uart_print_str
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; Step C: Set Variable MTRR slot 0 to Write-Combining (1)
    ; Base: 0xE0000000, Size: 16MB (0x1000000)
    mov rdi, 0                      ; slot 0
    mov rsi, 0xE0000000             ; base physical address
    mov rdx, 0x1000000              ; size (16MB)
    mov rcx, 1                      ; type: Write-Combining (WC)
    call mtrr_set_variable
    test rax, rax
    jz .mtrr_fail_set

    ; Step D: Retrieve and verify variable range
    mov rdi, 0                      ; slot 0
    call mtrr_get_variable          ; RAX=1, RSI=base, RDX=size, RCX=type
    test rax, rax
    jz .mtrr_fail_get_active

    ; Verify base address
    cmp rsi, 0xE0000000
    jne .mtrr_fail_base

    ; Verify size
    cmp rdx, 0x1000000
    jne .mtrr_fail_size

    ; Verify memory type
    cmp rcx, 1
    jne .mtrr_fail_type

    ; Step E: Disable variable MTRR slot 0 to clean up
    mov rdi, 0
    call mtrr_disable_variable
    test rax, rax
    jz .mtrr_fail_disable

    ; Step F: Verify slot is indeed disabled now
    mov rdi, 0
    call mtrr_get_variable
    test rax, rax
    jnz .mtrr_fail_still_active

    ; MTRR Programming Test PASSED!
    mov rsi, msg_mtrr_test_passed
    call uart_print_str
    jmp .run_pat_test

.mtrr_skip_test:
    mov rsi, msg_mtrr_skipped_str
    call uart_print_str
    jmp .run_pat_test

.run_pat_test:
    ; -------------------------------------------------------------
    ; 11. Run VMM PAT Cache Configuration Test
    ; -------------------------------------------------------------
    mov rsi, msg_pat_test_start
    call uart_print_str

    ; Step A: Verify PAT is supported on this processor
    call pat_supported
    test rax, rax
    jz .pat_skip_test

    ; Step B: Read and verify default PAT MSR value
    call pat_get_msr                ; RAX = current PAT MSR value
    test rax, rax
    jz .pat_fail_get

    ; Save the default PAT value in R12
    mov r12, rax

    ; Step C: Assert default indices for key memory types
    ; Index for Write-Back (WB = 6) should be 0
    mov rdi, 6
    call pat_find_entry
    cmp rax, 0
    jne .pat_fail_wb_index

    ; Index for Write-Through (WT = 4) should be 1
    mov rdi, 4
    call pat_find_entry
    cmp rax, 1
    jne .pat_fail_wt_index

    ; Index for Write-Combining (WC = 1) should be 5
    mov rdi, 1
    call pat_find_entry
    cmp rax, 5
    jne .pat_fail_wc_index

    ; Index for Uncached (UC = 0) should be 3
    mov rdi, 0
    call pat_find_entry
    cmp rax, 3
    jne .pat_fail_uc_index

    ; Step D: Modify PAT to check writing capability
    ; We construct a custom PAT layout:
    ; Swap PAT4 (WP=5) and PAT5 (WC=1):
    ; Default EDX:EAX = 0x00070105_00070406
    ; Custom EDX:EAX  = 0x00070501_00070406
    mov rdi, 0x0007050100070406
    call pat_set_msr
    test rax, rax
    jz .pat_fail_set

    ; Step E: Verify swap succeeded
    ; Now, Write-Combining (WC = 1) should be found at index 4 (instead of 5)
    mov rdi, 1
    call pat_find_entry
    cmp rax, 4
    jne .pat_fail_wc_swap

    ; Write-Protect (WP = 5) should be found at index 5 (instead of 4)
    mov rdi, 5
    call pat_find_entry
    cmp rax, 5
    jne .pat_fail_wp_swap

    ; Step F: Restore original default PAT value
    mov rdi, r12
    call pat_set_msr
    test rax, rax
    jz .pat_fail_restore

    ; Verify that WC is restored back to index 5
    mov rdi, 1
    call pat_find_entry
    cmp rax, 5
    jne .pat_fail_restore_verify

    ; PAT Configuration Test PASSED!
    mov rsi, msg_pat_test_passed
    call uart_print_str
    jmp .run_fb_test

.run_fb_test:
    mov rsi, msg_fb_test_start_str
    call uart_print_str

    call fb_init
    cmp rax, 2                      ; skipped gracefully (no framebuffer)
    je .fb_skip_test
    test rax, rax
    jz .fb_fail_init

    call fb_benchmark
    test rax, rax
    jz .fb_fail_bench

    mov rsi, msg_fb_test_passed_str
    call uart_print_str
    jmp .run_heap_test

.fb_skip_test:
    mov rsi, msg_fb_skipped_str
    call uart_print_str
    jmp .run_heap_test


.fb_fail_init:
    mov rsi, msg_fb_fail_init_str
    call uart_print_str
    jmp .panic

.fb_fail_bench:
    mov rsi, msg_fb_fail_bench_str
    call uart_print_str
    jmp .panic

.run_heap_test:
    mov rsi, msg_heap_test_start
    call uart_print_str

    ; Step A: Verify that heap_active_allocator is 1 (free-list active)
    mov al, [heap_active_allocator]
    cmp al, 1
    jne .heap_fail_active

    ; Step B: Allocate three consecutive blocks of 64 bytes: A, B, C
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc
    mov r12, rax                    ; R12 = pointer A

    test rax, 15
    jnz .heap_fail_align

    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc2
    mov r13, rax                    ; R13 = pointer B

    test rax, 15
    jnz .heap_fail_align2

    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc3
    mov r14, rax                    ; R14 = pointer C

    test rax, 15
    jnz .heap_fail_align3

    ; Step C: Assert spacing between consecutive blocks
    ; Header size heap_block_t_size is 32 bytes. Payload is 64 bytes.
    ; Thus, B - A must be exactly 96 bytes (64 + 32).
    ; Likewise, C - B must be exactly 96 bytes.
    mov rax, r13
    sub rax, r12                    ; RAX = B - A
    cmp rax, 96
    jne .heap_fail_spacing

    mov rax, r14
    sub rax, r13                    ; RAX = C - B
    cmp rax, 96
    jne .heap_fail_spacing

    ; Step D: Free the middle block B to create a hole in the free list
    mov rdi, r13
    call heap_free

    ; Step E: Allocate a 16-byte block (below the splitting threshold of B)
    ; B size is 64 bytes. 16-byte aligned payload = 16.
    ; Splitting threshold minimum size = aligned_size (16) + header_size (32) + 16 = 64 bytes.
    ; Since B size (64) >= 64, it MUST split block B!
    ; Allocating 16 bytes from B (64 bytes) splits it into:
    ; - Allocated block: 16 bytes (pointer = B)
    ; - Remaining free block: 64 - 16 - 32 = 16 bytes (header at B + 16, pointer = B + 48)
    mov rdi, 16
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc_split
    mov r15, rax                    ; R15 = pointer to split block

    ; Verify that R15 (new allocation) returned exactly R13 (pointer B)
    cmp r15, r13
    jne .heap_fail_split_ptr

    ; Step F: Allocate another 16 bytes (should consume the split free block at B + 48)
    mov rdi, 16
    call heap_alloc
    test rax, rax
    jz .heap_fail_alloc_split2
    mov rbx, rax                    ; RBX = pointer to split remainder

    ; Verify the address of split remainder is B + 48 (R13 + 48)
    mov rax, r13
    add rax, 48
    cmp rbx, rax
    jne .heap_fail_split_rem

    ; Step G: Free all allocations to check coalescing
    mov rdi, r12                    ; free A
    call heap_free

    mov rdi, r15                    ; free split part 1 (B start)
    call heap_free

    mov rdi, rbx                    ; free split part 2 (B remainder)
    call heap_free

    mov rdi, r14                    ; free C
    call heap_free

    ; Step H: Allocate 256 bytes (requires merging A, B, and C)
    ; Contiguous free space from A start to C end:
    ; A payload (64) + B header (32) + B payload (64) + C header (32) + C payload (64) = 256 bytes.
    mov rdi, 256
    call heap_alloc
    test rax, rax
    jz .heap_fail_coalesce
    mov rbx, rax

    ; Verify it starts exactly at pointer A (R12)
    cmp rbx, r12
    jne .heap_fail_coalesce_ptr

    ; Free the coalesced block
    mov rdi, rbx
    call heap_free

    ; Heap Allocator Test PASSED!
    mov rsi, msg_heap_test_passed
    call uart_print_str
    jmp .run_defrag_test

.run_defrag_test:
    mov rsi, msg_defrag_test_start
    call uart_print_str

    ; Step A: Allocate three consecutive 64-byte blocks: A, B, C
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .defrag_fail_alloc_A
    mov [ptr_A], rax

    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .defrag_fail_alloc_B
    mov [ptr_B], rax

    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .defrag_fail_alloc_C
    mov [ptr_C], rax

    ; Step B: Register the pointer variables
    mov rdi, ptr_A
    call heap_register_relocatable
    test rax, rax
    jz .defrag_fail_reg

    mov rdi, ptr_B
    call heap_register_relocatable
    test rax, rax
    jz .defrag_fail_reg

    mov rdi, ptr_C
    call heap_register_relocatable
    test rax, rax
    jz .defrag_fail_reg

    ; Save block addresses for assertions
    mov r12, [ptr_A]                ; R12 = A's original payload address
    mov r13, [ptr_B]                ; R13 = B's original payload address
    mov r14, [ptr_C]                ; R14 = C's original payload address

    ; Step C: Free middle block B to create a hole
    mov rdi, [ptr_B]
    call heap_free

    ; Step D: Perform Compaction!
    call heap_compact
    test rax, rax
    jz .defrag_fail_compact

    ; Step E: Assertions
    ; 1. ptr_A must still point to A's original payload address
    mov rax, [ptr_A]
    cmp rax, r12
    jne .defrag_fail_assert_A

    ; 2. ptr_C must now point to B's original payload address (relocated payload)
    mov rax, [ptr_C]
    cmp rax, r13
    jne .defrag_fail_assert_C

    ; Step F: Clean up and unregister variables
    mov rdi, ptr_A
    call heap_unregister_relocatable
    mov rdi, ptr_B
    call heap_unregister_relocatable
    mov rdi, ptr_C
    call heap_unregister_relocatable

    ; Free compacted blocks A and C
    mov rdi, [ptr_A]
    call heap_free
    mov rdi, [ptr_C]
    call heap_free

    ; Heap Defragmenter Test PASSED!
    mov rsi, msg_defrag_test_passed
    call uart_print_str
    jmp .run_slab_test

.defrag_fail_alloc_A:
    mov rsi, msg_defrag_fail_alloc_A_str
    call uart_print_str
    jmp .panic

.defrag_fail_alloc_B:
    mov rsi, msg_defrag_fail_alloc_B_str
    call uart_print_str
    jmp .panic

.defrag_fail_alloc_C:
    mov rsi, msg_defrag_fail_alloc_C_str
    call uart_print_str
    jmp .panic

.defrag_fail_reg:
    mov rsi, msg_defrag_fail_reg_str
    call uart_print_str
    jmp .panic

.defrag_fail_compact:
    mov rsi, msg_defrag_fail_compact_str
    call uart_print_str
    jmp .panic

.defrag_fail_assert_A:
    mov rsi, msg_defrag_fail_assert_A_str
    call uart_print_str
    jmp .panic

.defrag_fail_assert_C:
    mov rsi, msg_defrag_fail_assert_C_str
    call uart_print_str
    jmp .panic

.run_slab_test:
    mov rsi, msg_slab_test_start
    call uart_print_str

    ; --- 1. Verify kmem_cache_file ---
    ; Check name is initialized to non-null and starts with 'kmem'
    mov rax, [kmem_cache_file + kmem_cache_t.name]
    test rax, rax
    jz .slab_fail_name
    mov ebx, [rax]
    cmp ebx, 0x6D656D6B             ; 'kmem' in little endian (0x6B, 0x6D, 0x65, 0x6D)
    jne .slab_fail_name

    ; Check object size is 256
    mov rax, [kmem_cache_file + kmem_cache_t.obj_size]
    cmp rax, 256
    jne .slab_fail_size

    ; Check alignment is 8
    mov rax, [kmem_cache_file + kmem_cache_t.align_size]
    cmp rax, 8
    jne .slab_fail_align

    ; Check list heads are 0
    mov rax, [kmem_cache_file + kmem_cache_t.slabs_full]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_file + kmem_cache_t.slabs_part]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_file + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_fail_lists

    ; --- 2. Verify kmem_cache_task ---
    ; Check name starts with 'kmem'
    mov rax, [kmem_cache_task + kmem_cache_t.name]
    test rax, rax
    jz .slab_fail_name
    mov ebx, [rax]
    cmp ebx, 0x6D656D6B
    jne .slab_fail_name

    ; Check object size is 512
    mov rax, [kmem_cache_task + kmem_cache_t.obj_size]
    cmp rax, 512
    jne .slab_fail_size

    ; Check alignment is 16
    mov rax, [kmem_cache_task + kmem_cache_t.align_size]
    cmp rax, 16
    jne .slab_fail_align

    ; Check list heads are 0
    mov rax, [kmem_cache_task + kmem_cache_t.slabs_full]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_task + kmem_cache_t.slabs_part]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_task + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_fail_lists

    ; --- 3. Verify kmem_cache_vma ---
    ; Check name starts with 'kmem'
    mov rax, [kmem_cache_vma + kmem_cache_t.name]
    test rax, rax
    jz .slab_fail_name
    mov ebx, [rax]
    cmp ebx, 0x6D656D6B
    jne .slab_fail_name

    ; Check object size is 64
    mov rax, [kmem_cache_vma + kmem_cache_t.obj_size]
    cmp rax, 64
    jne .slab_fail_size

    ; Check alignment is 8
    mov rax, [kmem_cache_vma + kmem_cache_t.align_size]
    cmp rax, 8
    jne .slab_fail_align

    ; Check list heads are 0
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_full]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_part]
    test rax, rax
    jnz .slab_fail_lists
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_fail_lists

    ; Slab Allocator Cache Definitions Test PASSED!
    mov rsi, msg_slab_test_passed
    call uart_print_str

    ; =========================================================================
    ; 10.2 Slab Lists Tracking & Grow Test
    ; =========================================================================
    mov rsi, msg_slab_grow_test_start
    call uart_print_str

    ; Grow kmem_cache_vma (size 64, align 8)
    mov rdi, kmem_cache_vma
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail

    ; R12 = pointer to grown slab
    mov r12, rax

    ; Check if the slab was linked into kmem_cache_vma.slabs_free
    mov r13, [kmem_cache_vma + kmem_cache_t.slabs_free]
    cmp r13, r12
    jne .slab_fail_free_list

    ; Verify slab magic, obj_count, and used_count
    mov rax, [r12 + slab_t.magic]
    cmp rax, 0x51AB51AB
    jne .slab_fail_magic

    mov rax, [r12 + slab_t.obj_count]
    cmp rax, 63
    jne .slab_fail_count

    mov rax, [r12 + slab_t.used_count]
    test rax, rax
    jnz .slab_fail_used

    ; Verify free_head is mem_start (slab + 56)
    mov rax, [r12 + slab_t.free_head]
    mov rbx, r12
    add rbx, 56
    cmp rax, rbx
    jne .slab_fail_free_head

    ; Verify first object points to next object (slab + 56 + 64)
    mov rcx, [rax]
    mov rdx, rbx
    add rdx, 64
    cmp rcx, rdx
    jne .slab_fail_free_chain

    ; Manually transition from slabs_free to slabs_part
    mov rdi, kmem_cache_vma
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r12
    call kmem_slab_unlink

    ; Check slabs_free is now empty (0)
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_fail_transition

    ; Link to slabs_part
    mov rdi, kmem_cache_vma
    mov rsi, kmem_cache_t.slabs_part
    mov rdx, r12
    call kmem_slab_link

    ; Check slabs_part has the slab
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_part]
    cmp rax, r12
    jne .slab_fail_transition

    ; Verify slab's links are updated (next/prev are 0 since list is single-item)
    mov rax, [r12 + slab_t.next]
    test rax, rax
    jnz .slab_fail_transition
    mov rax, [r12 + slab_t.prev]
    test rax, rax
    jnz .slab_fail_transition

    ; Clean up: unlink from slabs_part and free back to general heap
    mov rdi, kmem_cache_vma
    mov rsi, kmem_cache_t.slabs_part
    mov rdx, r12
    call kmem_slab_unlink

    mov rdi, r12
    call heap_free

    ; Reset lists
    mov qword [kmem_cache_vma + kmem_cache_t.slabs_free], 0
    mov qword [kmem_cache_vma + kmem_cache_t.slabs_part], 0
    mov qword [kmem_cache_vma + kmem_cache_t.slabs_full], 0

    ; Slab Lists Tracking Test PASSED!
    mov rsi, msg_slab_grow_test_passed
    call uart_print_str
    jmp .run_slab_ctor_test

.slab_grow_fail:
    mov rsi, msg_slab_fail_grow_str
    call uart_print_str
    jmp .panic

.slab_fail_free_list:
    mov rsi, msg_slab_fail_free_list_str
    call uart_print_str
    jmp .panic

.slab_fail_magic:
    mov rsi, msg_slab_fail_magic_str
    call uart_print_str
    jmp .panic

.slab_fail_count:
    mov rsi, msg_slab_fail_count_str
    call uart_print_str
    jmp .panic

.slab_fail_used:
    mov rsi, msg_slab_fail_used_str
    call uart_print_str
    jmp .panic

.slab_fail_free_head:
    mov rsi, msg_slab_fail_free_head_str
    call uart_print_str
    jmp .panic

.slab_fail_free_chain:
    mov rsi, msg_slab_fail_free_chain_str
    call uart_print_str
    jmp .panic

.slab_fail_transition:
    mov rsi, msg_slab_fail_transition_str
    call uart_print_str
    jmp .panic

.slab_fail_name:
    mov rsi, msg_slab_fail_name_str
    call uart_print_str
    jmp .panic

.slab_fail_size:
    mov rsi, msg_slab_fail_size_str
    call uart_print_str
    jmp .panic

.slab_fail_align:
    mov rsi, msg_slab_fail_align_str
    call uart_print_str
    jmp .panic

.slab_fail_lists:
    mov rsi, msg_slab_fail_lists_str
    call uart_print_str
    jmp .panic

.run_slab_ctor_test:
    mov rsi, msg_slab_ctor_test_start
    call uart_print_str

    ; Create a dynamic cache for verifying constructor execution
    mov rdi, msg_test_cache_name
    mov rsi, 64                     ; obj_size = 64
    mov rdx, 8                      ; align_size = 8
    mov rcx, test_ctor              ; ctor = test_ctor
    mov r8, 0                       ; dtor = NULL
    call kmem_cache_create
    test rax, rax
    jz .slab_grow_fail
    mov r12, rax                    ; R12 = kmem_cache_t pointer

    ; Grow the cache via kmem_slab_grow
    mov rdi, r12
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r13, rax                    ; R13 = slab pointer

    ; Assert grown slab's free_head is non-null
    mov r14, [r13 + slab_t.free_head]
    test r14, r14
    jz .slab_fail_ctor

    ; Assert first object retains the constructor-initialized state at offset 8
    mov rax, 0x123456789ABCDEF0
    cmp [r14 + 8], rax
    jne .slab_fail_ctor

    ; Assert second object is also initialized correctly
    mov r15, [r14]                  ; R15 = pointer to second object
    test r15, r15
    jz .slab_fail_ctor_chain

    cmp [r15 + 8], rax
    jne .slab_fail_ctor

    ; Clean up: unlink slab from slabs_free list and free resources
    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r13
    call kmem_slab_unlink

    mov rdi, r13
    call heap_free

    mov rdi, r12
    call heap_free

    mov rsi, msg_slab_ctor_test_passed
    call uart_print_str
    jmp .run_slab_reap_test

test_ctor:
    mov qword [rdi + 8], 0x123456789ABCDEF0
    ret

.slab_fail_ctor:
    mov rsi, msg_slab_fail_ctor_str
    call uart_print_str
    jmp .panic

.slab_fail_ctor_chain:
    mov rsi, msg_slab_fail_ctor_chain_str
    call uart_print_str
    jmp .panic

.run_slab_reap_test:
    mov rsi, msg_slab_reap_test_start
    call uart_print_str

    ; Step A: Grow an empty slab in kmem_cache_vma
    mov rdi, kmem_cache_vma
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r12, rax                    ; R12 = pointer to grown slab

    ; Verify it is in slabs_free list of kmem_cache_vma
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_free]
    cmp rax, r12
    jne .slab_reap_fail_setup

    ; Step B: Artificially configure watermarks to force kswapd trigger
    mov rax, [phys_state + phys_state_t.free_pages]
    mov r13, rax                    ; R13 = initial free pages count
    
    mov rbx, rax
    inc rbx                         ; RBX = current_free + 1
    mov [kswapd_low_watermark], rbx
    mov [kswapd_high_watermark], rbx

    ; Step C: Trigger kswapd
    call kswapd_check_and_reclaim

    ; Step D: Verify that the empty slab in kmem_cache_vma was reaped
    mov rax, [kmem_cache_vma + kmem_cache_t.slabs_free]
    test rax, rax
    jnz .slab_reap_fail_eviction

    ; Verify that physical free pages count increased by 1 (the reaped slab/page)
    mov rax, [phys_state + phys_state_t.free_pages]
    mov rbx, r13
    inc rbx
    cmp rax, rbx
    jne .slab_reap_fail_count

    ; Step E: Reset watermarks back to 0
    mov qword [kswapd_low_watermark], 0
    mov qword [kswapd_high_watermark], 0

    ; Slab Reaping Test PASSED!
    mov rsi, msg_slab_reap_test_passed
    call uart_print_str
    jmp .run_slab_color_test

.slab_reap_fail_setup:
    mov rsi, msg_slab_reap_fail_setup_str
    call uart_print_str
    jmp .panic

.slab_reap_fail_eviction:
    mov rsi, msg_slab_reap_fail_eviction_str
    call uart_print_str
    jmp .panic

.slab_reap_fail_count:
    mov rsi, msg_slab_reap_fail_count_str
    call uart_print_str
    jmp .panic

.run_slab_color_test:
    mov rsi, msg_slab_color_test_start
    call uart_print_str

    ; Create a cache with obj_size = 256, align_size = 8
    mov rdi, msg_test_color_cache_name
    mov rsi, 256
    mov rdx, 8
    mov rcx, 0                      ; ctor = NULL
    mov r8, 0                       ; dtor = NULL
    call kmem_cache_create
    test rax, rax
    jz .slab_grow_fail
    mov r12, rax                    ; R12 = cache pointer

    ; Verify that colour_max calculation was correct (expected 3)
    mov rax, [r12 + kmem_cache_t.colour_max]
    cmp rax, 3
    jne .slab_color_fail_max

    ; Grow first slab
    mov rdi, r12
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r13, rax                    ; R13 = slab 1

    ; Grow second slab
    mov rdi, r12
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r14, rax                    ; R14 = slab 2

    ; Grow third slab
    mov rdi, r12
    call kmem_slab_grow
    test rax, rax
    jz .slab_grow_fail
    mov r15, rax                    ; R15 = slab 3

    ; Calculate relative offsets of mem_start within slab pages
    mov rax, [r13 + slab_t.mem_start]
    sub rax, r13                    ; RAX = offset 1
    
    mov rbx, [r14 + slab_t.mem_start]
    sub rbx, r14                    ; RBX = offset 2
    
    mov rcx, [r15 + slab_t.mem_start]
    sub rcx, r15                    ; RCX = offset 3

    ; Assertions: offset2 should be offset1 + 64
    mov rdx, rax
    add rdx, 64
    cmp rbx, rdx
    jne .slab_color_fail_offset

    ; Assertions: offset3 should be offset1 + 128
    mov rdx, rax
    add rdx, 128
    cmp rcx, rdx
    jne .slab_color_fail_offset

    ; Clean up the dynamically grown slabs by unlinking and freeing
    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r13
    call kmem_slab_unlink
    mov rdi, r13
    call heap_free

    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r14
    call kmem_slab_unlink
    mov rdi, r14
    call heap_free

    mov rdi, r12
    mov rsi, kmem_cache_t.slabs_free
    mov rdx, r15
    call kmem_slab_unlink
    mov rdi, r15
    call heap_free

    ; Free the cache descriptor itself
    mov rdi, r12
    call heap_free

    ; Slab Cache Coloring Test PASSED!
    mov rsi, msg_slab_color_test_passed
    call uart_print_str
    jmp .run_buddy_init_test

.slab_color_fail_max:
    mov rsi, msg_slab_color_fail_max_str
    call uart_print_str
    jmp .panic

.slab_color_fail_offset:
    mov rsi, msg_slab_color_fail_offset_str
    call uart_print_str
    jmp .panic

.run_buddy_init_test:
    mov rsi, msg_buddy_test_start
    call uart_print_str

    ; Step A: Allocate memory for the test buddy allocator
    ; We allocate 10MB + 8MB = 18MB (18,874,368 bytes) to allow 8MB alignment
    mov rdi, 18874368
    call heap_alloc
    test rax, rax
    jz .buddy_fail_alloc
    mov r12, rax                    ; R12 = raw heap block pointer

    ; Align the start address to 8MB boundary
    mov r13, r12
    add r13, 8388607
    mov r14, 8388607
    not r14
    and r13, r14                    ; R13 = aligned start address (A)

    ; Initialize the buddy allocator: A (R13), size = 10MB (10,485,760 bytes)
    mov rdi, r13
    mov rsi, 10485760
    call buddy_init

    ; Verify buddy configuration variables
    mov rax, [buddy_start_addr]
    cmp rax, r13
    jne .buddy_fail_config

    mov rax, [buddy_end_addr]
    mov rbx, r13
    add rbx, 10485760
    cmp rax, rbx
    jne .buddy_fail_config

    ; Verify free list heads:
    ; Expected:
    ; buddy_free_heads[11] = A (R13)
    ; buddy_free_heads[9]  = A + 8MB (R13 + 8,388,608)
    ; All other free list heads must be NULL (0).
    xor rcx, rcx                    ; RCX = order (0 to 11)
.verify_list_loop:
    cmp rcx, 12
    jae .verify_list_done

    lea rax, [buddy_free_heads]
    mov rbx, [rax + rcx * 8]        ; RBX = buddy_free_heads[RCX]

    cmp rcx, 11
    je .check_order_11
    cmp rcx, 9
    je .check_order_9

    ; For other orders, head must be NULL
    test rbx, rbx
    jnz .buddy_fail_lists
    jmp .next_verify

.check_order_11:
    cmp rbx, r13
    jne .buddy_fail_lists
    jmp .next_verify

.check_order_9:
    mov rdx, r13
    add rdx, 8388608                ; 8MB
    cmp rbx, rdx
    jne .buddy_fail_lists

.next_verify:
    inc rcx
    jmp .verify_list_loop

.verify_list_done:
    ; Verify metadata array:
    ; page count = 10MB / 4KB = 2560 pages
    ; index 0 (A) must be 0x8B (free, order 11)
    ; index 2048 (A + 8MB) must be 0x89 (free, order 9)
    mov rdx, [buddy_metadata]
    test rdx, rdx
    jz .buddy_fail_metadata

    mov al, [rdx + 0]
    cmp al, 0x8B
    jne .buddy_fail_metadata

    mov al, [rdx + 2048]
    cmp al, 0x89
    jne .buddy_fail_metadata

    ; Clean up
    mov rdi, [buddy_metadata]
    call heap_free
    mov qword [buddy_metadata], 0

    mov rdi, r12
    call heap_free

    mov qword [buddy_start_addr], 0
    mov qword [buddy_end_addr], 0
    
    lea rdi, [buddy_free_heads]
    mov rcx, 12
    xor rax, rax
    cld
    rep stosq

    ; Buddy Allocator Initialization Test PASSED!
    mov rsi, msg_buddy_test_passed
    call uart_print_str
    jmp .run_buddy_split_test

.buddy_fail_alloc:
    mov rsi, msg_buddy_fail_alloc_str
    call uart_print_str
    jmp .panic

.buddy_fail_config:
    mov rsi, msg_buddy_fail_config_str
    call uart_print_str
    jmp .panic

.buddy_fail_lists:
    mov rsi, msg_buddy_fail_lists_str
    call uart_print_str
    jmp .panic

.buddy_fail_metadata:
    mov rsi, msg_buddy_fail_metadata_str
    call uart_print_str
    jmp .panic

.run_buddy_split_test:
    mov rsi, msg_buddy_split_test_start
    call uart_print_str

    ; Step A: Allocate memory for the test buddy allocator
    ; We allocate 10MB + 8MB = 18MB to allow 8MB alignment
    mov rdi, 18874368
    call heap_alloc
    test rax, rax
    jz .buddy_fail_alloc
    mov r12, rax                    ; R12 = raw heap block pointer

    ; Align the start address to 8MB boundary (A)
    mov r13, r12
    add r13, 8388607
    mov r14, 8388607
    not r14
    and r13, r14                    ; R13 = aligned start address (A)

    ; Initialize the buddy allocator: A (R13), size = 10MB (10,485,760 bytes)
    mov rdi, r13
    mov rsi, 10485760
    call buddy_init

    ; Step B: Allocate a block of Order 8 (1MB).
    mov rdi, 8                      ; requested order = 8
    call buddy_alloc
    test rax, rax
    jz .buddy_fail_split_alloc
    mov r15, rax                    ; R15 = allocated block pointer (expected A + 8MB)

    ; Verify that the allocated pointer is exactly A + 8MB (R13 + 8MB)
    mov rdx, r13
    add rdx, 8388608                ; RDX = A + 8MB
    cmp r15, rdx
    jne .buddy_fail_split_ptr

    ; Verify list heads after split:
    ; buddy_free_heads[11] must still be A (R13)
    ; buddy_free_heads[9]  must now be NULL (0)
    ; buddy_free_heads[8]  must now be A + 9MB (R13 + 9,437,184)
    ; All other free list heads must be NULL.
    xor rcx, rcx                    ; RCX = order
.verify_split_list_loop:
    cmp rcx, 12
    jae .verify_split_list_done

    lea rax, [buddy_free_heads]
    mov rbx, [rax + rcx * 8]        ; RBX = buddy_free_heads[RCX]

    cmp rcx, 11
    je .check_split_order_11
    cmp rcx, 8
    je .check_split_order_8

    ; For other orders, head must be NULL
    test rbx, rbx
    jnz .buddy_fail_split_lists
    jmp .next_split_verify

.check_split_order_11:
    cmp rbx, r13
    jne .buddy_fail_split_lists
    jmp .next_split_verify

.check_split_order_8:
    mov rdx, r13
    add rdx, 9437184                ; A + 9MB (8MB + 1MB)
    cmp rbx, rdx
    jne .buddy_fail_split_lists

.next_split_verify:
    inc rcx
    jmp .verify_split_list_loop

.verify_split_list_done:
    ; Verify metadata array:
    ; index 2048 (A + 8MB) must be 8 (allocated, Order 8)
    ; index 2304 (A + 9MB) must be 0x88 (free, Order 8)
    ; index 0 (A) must be 0x8B (free, Order 11)
    mov rdx, [buddy_metadata]
    test rdx, rdx
    jz .buddy_fail_split_metadata

    mov al, [rdx + 2048]
    cmp al, 8
    jne .buddy_fail_split_metadata

    mov al, [rdx + 2304]
    cmp al, 0x88
    jne .buddy_fail_split_metadata

    mov al, [rdx + 0]
    cmp al, 0x8B
    jne .buddy_fail_split_metadata

    ; Buddy Allocator Splitting Test PASSED!
    mov rsi, msg_buddy_split_test_passed
    call uart_print_str
    jmp .run_buddy_coalesce_test

.buddy_fail_split_alloc:
    mov rsi, msg_buddy_fail_split_alloc_str
    call uart_print_str
    jmp .panic

.buddy_fail_split_ptr:
    mov rsi, msg_buddy_fail_split_ptr_str
    call uart_print_str
    jmp .panic

.buddy_fail_split_lists:
    mov rsi, msg_buddy_fail_split_lists_str
    call uart_print_str
    jmp .panic

.buddy_fail_split_metadata:
    mov rsi, msg_buddy_fail_split_metadata_str
    call uart_print_str
    jmp .panic

.run_buddy_coalesce_test:
    mov rsi, msg_buddy_coalesce_test_start
    call uart_print_str

    ; Step A: Free the allocated Order 8 block (R15, which is A + 8MB)
    mov rdi, r15                    ; RDI = A + 8MB
    call buddy_free

    ; Step B: Verify list heads after coalescing:
    ; buddy_free_heads[11] = A (R13)
    ; buddy_free_heads[9]  = A + 8MB (R13 + 8,388,608)
    ; buddy_free_heads[8]  = NULL (0)
    ; All other heads must be NULL.
    xor rcx, rcx                    ; RCX = order
.verify_coal_list_loop:
    cmp rcx, 12
    jae .verify_coal_list_done

    lea rax, [buddy_free_heads]
    mov rbx, [rax + rcx * 8]        ; RBX = buddy_free_heads[RCX]

    cmp rcx, 11
    je .check_coal_order_11
    cmp rcx, 9
    je .check_coal_order_9

    ; For other orders, head must be NULL
    test rbx, rbx
    jnz .buddy_fail_coal_lists
    jmp .next_coal_verify

.check_coal_order_11:
    cmp rbx, r13
    jne .buddy_fail_coal_lists
    jmp .next_coal_verify

.check_coal_order_9:
    mov rdx, r13
    add rdx, 8388608                ; A + 8MB
    cmp rbx, rdx
    jne .buddy_fail_coal_lists

.next_coal_verify:
    inc rcx
    jmp .verify_coal_list_loop

.verify_coal_list_done:
    ; Step C: Verify metadata array after coalescing:
    ; index 2048 (A + 8MB) must be 0x89 (free, Order 9)
    ; index 2304 (A + 9MB) must be 0
    ; index 0 (A) must be 0x8B (free, Order 11)
    mov rdx, [buddy_metadata]
    test rdx, rdx
    jz .buddy_fail_coal_metadata

    mov al, [rdx + 2048]
    cmp al, 0x89
    jne .buddy_fail_coal_metadata

    mov al, [rdx + 2304]
    test al, al
    jnz .buddy_fail_coal_metadata

    mov al, [rdx + 0]
    cmp al, 0x8B
    jne .buddy_fail_coal_metadata

    ; Step D: Clean up resources
    mov rdi, [buddy_metadata]
    call heap_free
    mov qword [buddy_metadata], 0

    mov rdi, r12
    call heap_free

    mov qword [buddy_start_addr], 0
    mov qword [buddy_end_addr], 0

    lea rdi, [buddy_free_heads]
    mov rcx, 12
    xor rax, rax
    cld
    rep stosq

    ; Buddy Allocator Coalescing Test PASSED!
    mov rsi, msg_buddy_coalesce_test_passed
    call uart_print_str
    jmp .run_arena_test

.buddy_fail_coal_lists:
    mov rsi, msg_buddy_fail_coal_lists_str
    call uart_print_str
    jmp .panic

.buddy_fail_coal_metadata:
    mov rsi, msg_buddy_fail_coal_metadata_str
    call uart_print_str
    jmp .panic

.run_arena_test:
    mov rsi, msg_arena_test_start
    call uart_print_str

    ; Step A: Create an Arena of 1MB (1048576 bytes)
    mov rdi, 1048576
    call arena_create
    test rax, rax
    jz .arena_fail_create
    mov r12, rax                    ; R12 = arena pointer

    ; Verify arena configuration
    ; 1. start address must be 16-byte aligned
    mov rax, [r12 + arena_t.start]
    test rax, 15
    jnz .arena_fail_align

    ; 2. current pointer must equal start address
    mov rbx, [r12 + arena_t.current]
    cmp rax, rbx
    jne .arena_fail_config

    ; 3. end address must equal arena pointer + 1MB
    mov rcx, [r12 + arena_t.end]
    mov rdx, r12
    add rdx, 1048576
    cmp rcx, rdx
    jne .arena_fail_config

    ; Step B: Allocate block A (64 bytes)
    mov rdi, r12
    mov rsi, 64
    call arena_alloc
    test rax, rax
    jz .arena_fail_alloc
    mov r13, rax                    ; R13 = allocation A (expected at start address)

    ; Verify A's alignment
    test r13, 15
    jnz .arena_fail_align

    ; Verify A points to start address
    mov rax, [r12 + arena_t.start]
    cmp r13, rax
    jne .arena_fail_ptr

    ; Step C: Allocate block B (16 bytes)
    mov rdi, r12
    mov rsi, 16
    call arena_alloc
    test rax, rax
    jz .arena_fail_alloc
    mov r14, rax                    ; R14 = allocation B

    ; Verify B's alignment
    test r14, 15
    jnz .arena_fail_align

    ; Verify B is contiguous to A (A + 64)
    mov rax, r13
    add rax, 64
    cmp r14, rax
    jne .arena_fail_spacing

    ; Step D: Allocate block C (5 bytes)
    mov rdi, r12
    mov rsi, 5
    call arena_alloc
    test rax, rax
    jz .arena_fail_alloc
    mov r15, rax                    ; R15 = allocation C

    ; Verify C's alignment (must be 16-byte aligned)
    test r15, 15
    jnz .arena_fail_align

    ; Verify C spacing: should be at B + 16 (since 5 is padded to 16)
    mov rax, r14
    add rax, 16
    cmp r15, rax
    jne .arena_fail_spacing

    ; Step E: Test Checkpoint Save/Restore
    push rbp
    mov rdi, r12
    call arena_checkpoint_save
    test rax, rax
    jz .arena_fail_checkpoint_pop
    mov rbp, rax                    ; RBP = checkpoint pointer

    ; Verify checkpoint value matches current pointer
    mov rbx, [r12 + arena_t.current]
    cmp rbp, rbx
    jne .arena_fail_checkpoint_pop

    ; Allocate block D (100 bytes)
    mov rdi, r12
    mov rsi, 100
    call arena_alloc
    test rax, rax
    jz .arena_fail_alloc_pop

    ; Restore checkpoint
    mov rdi, r12
    mov rsi, rbp
    call arena_checkpoint_restore

    ; Verify current pointer is restored to checkpoint value (RBP)
    mov rax, [r12 + arena_t.current]
    cmp rax, rbp
    jne .arena_fail_checkpoint_pop
    pop rbp

    ; Step F: Test Out Of Memory (OOM) handling
    mov rdi, r12
    mov rsi, 1048576                ; request space larger than total arena
    call arena_alloc
    test rax, rax
    jnz .arena_fail_oom             ; should return 0 (NULL)

    ; Step G: Test Arena Reset
    mov rdi, r12
    call arena_reset
    mov rax, [r12 + arena_t.current]
    mov rbx, [r12 + arena_t.start]
    cmp rax, rbx
    jne .arena_fail_reset

    ; Step H: Test Thread-Local/Core-Local Arenas (Lock-Free)
    ; 1. Initialize local arena (2MB)
    mov rdi, 2097152
    call arena_init_local
    test rax, rax
    jz .arena_fail_local_init

    ; Verify it is bound to the core (stored in [gs:24])
    mov rbx, [gs:24]
    cmp rax, rbx
    jne .arena_fail_local_init

    ; 2. Allocate 128 bytes from local arena
    mov rdi, 128
    call arena_alloc_local
    test rax, rax
    jz .arena_fail_local_alloc

    ; Verify aligned pointer
    test rax, 15
    jnz .arena_fail_align

    ; 3. Reset local arena
    call arena_reset_local
    mov rdx, [gs:24]
    mov rax, [rdx + arena_t.current]
    mov rbx, [rdx + arena_t.start]
    cmp rax, rbx
    jne .arena_fail_local_reset

    ; 4. Destroy local arena
    call arena_destroy_local
    mov rax, [gs:24]
    test rax, rax
    jnz .arena_fail_local_destroy

    ; Step I: Destroy the 1MB arena
    mov rdi, r12
    call arena_destroy

    ; Arena & Region Allocator Test PASSED!
    mov rsi, msg_arena_test_passed
    call uart_print_str
    jmp .run_pool_test

.arena_fail_checkpoint_pop:
    pop rbp
.arena_fail_checkpoint:
    mov rsi, msg_arena_fail_checkpoint_str
    call uart_print_str
    jmp .panic

.arena_fail_alloc_pop:
    pop rbp
.arena_fail_alloc:
    mov rsi, msg_arena_fail_alloc_str
    call uart_print_str
    jmp .panic

.arena_fail_create:
    mov rsi, msg_arena_fail_create_str
    call uart_print_str
    jmp .panic

.arena_fail_config:
    mov rsi, msg_arena_fail_config_str
    call uart_print_str
    jmp .panic

.arena_fail_align:
    mov rsi, msg_arena_fail_align_str
    call uart_print_str
    jmp .panic

.arena_fail_ptr:
    mov rsi, msg_arena_fail_ptr_str
    call uart_print_str
    jmp .panic

.arena_fail_spacing:
    mov rsi, msg_arena_fail_spacing_str
    call uart_print_str
    jmp .panic

.arena_fail_oom:
    mov rsi, msg_arena_fail_oom_str
    call uart_print_str
    jmp .panic

.arena_fail_reset:
    mov rsi, msg_arena_fail_reset_str
    call uart_print_str
    jmp .panic

.arena_fail_local_init:
    mov rsi, msg_arena_fail_local_init_str
    call uart_print_str
    jmp .panic

.arena_fail_local_alloc:
    mov rsi, msg_arena_fail_local_alloc_str
    call uart_print_str
    jmp .panic

.arena_fail_local_reset:
    mov rsi, msg_arena_fail_local_reset_str
    call uart_print_str
    jmp .panic

.arena_fail_local_destroy:
    mov rsi, msg_arena_fail_local_destroy_str
    call uart_print_str
    jmp .panic

.run_pool_test:
    mov rsi, msg_pool_test_start
    call uart_print_str

    ; Step A: Create a pool of object size 32 and capacity 4
    mov rdi, 32
    mov rsi, 4
    call pool_create
    test rax, rax
    jz .pool_fail_create
    mov r12, rax                    ; R12 = pool descriptor pointer

    ; Verify pool configuration
    ; 1. obj_size must be 32
    mov rax, [r12 + pool_t.obj_size]
    cmp rax, 32
    jne .pool_fail_config

    ; 2. capacity must be 4
    mov rax, [r12 + pool_t.capacity]
    cmp rax, 4
    jne .pool_fail_config

    ; 3. count must be 0
    mov rax, [r12 + pool_t.count]
    test rax, rax
    jnz .pool_fail_config

    ; 4. free_head must equal memory pointer
    mov rax, [r12 + pool_t.free_head]
    mov rbx, [r12 + pool_t.memory]
    cmp rax, rbx
    jne .pool_fail_config

    ; Step B: Allocate slot 0
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_alloc
    mov r13, rax                    ; R13 = slot 0 (expected at pool.memory)

    ; Verify slot 0 points to start of memory
    mov rbx, [r12 + pool_t.memory]
    cmp r13, rbx
    jne .pool_fail_ptr

    ; Step C: Allocate slot 1
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_alloc
    mov r14, rax                    ; R14 = slot 1 (expected at slot 0 + 32)

    ; Verify slot 1 is contiguous
    mov rax, r13
    add rax, 32
    cmp r14, rax
    jne .pool_fail_ptr

    ; Step D: Allocate slot 2
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_alloc
    mov r15, rax                    ; R15 = slot 2

    ; Step E: Allocate slot 3 (use pushed rbp)
    push rbp
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_alloc_pop
    mov rbp, rax                    ; RBP = slot 3

    ; Step F: Verify OOM (5th allocation must return NULL)
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jnz .pool_fail_oom_pop

    ; Verify used count is 4
    mov rax, [r12 + pool_t.count]
    cmp rax, 4
    jne .pool_fail_count_pop

    ; Verify generation tag value is 4 (4 allocations)
    mov rax, [r12 + pool_t.free_tag]
    cmp rax, 4
    jne .pool_fail_tag_pop

    ; Step G: Free slot 1 (R14) and slot 3 (RBP)
    mov rdi, r12
    mov rsi, r14
    call pool_free

    mov rdi, r12
    mov rsi, rbp
    call pool_free

    ; Verify used count is 2
    mov rax, [r12 + pool_t.count]
    cmp rax, 2
    jne .pool_fail_count_pop

    ; Verify generation tag value is 6 (4 allocs + 2 frees)
    mov rax, [r12 + pool_t.free_tag]
    cmp rax, 6
    jne .pool_fail_tag_pop

    ; Verify free list structure:
    ; 1. free_head must now point to slot 3 (RBP)
    mov rax, [r12 + pool_t.free_head]
    cmp rax, rbp
    jne .pool_fail_free_list_pop

    ; 2. slot 3 (RBP) must point to slot 1 (R14) in its first 8 bytes
    mov rax, [rbp]
    cmp rax, r14
    jne .pool_fail_free_list_pop

    ; 3. slot 1 (R14) must point to NULL (0)
    mov rax, [r14]
    test rax, rax
    jnz .pool_fail_free_list_pop

    ; Step H: Allocate again and verify O(1) list head reuse
    mov rdi, r12
    call pool_alloc
    cmp rax, rbp                    ; must return slot 3 (RBP) first
    jne .pool_fail_reuse_pop

    mov rdi, r12
    call pool_alloc
    cmp rax, r14                    ; must return slot 1 (R14) next
    jne .pool_fail_reuse_pop

    ; Verify used count is back to 4
    mov rax, [r12 + pool_t.count]
    cmp rax, 4
    jne .pool_fail_count_pop

    ; Verify generation tag value is 8 (4 allocs + 2 frees + 2 re-allocs)
    mov rax, [r12 + pool_t.free_tag]
    cmp rax, 8
    jne .pool_fail_tag_pop

    ; Step I: Test bounds and alignment safety checks in pool_free
    ; 1. Free out-of-bounds address (R12, the descriptor)
    mov rdi, r12
    mov rsi, r12
    call pool_free
    mov rax, [r12 + pool_t.count]
    cmp rax, 4                      ; count must remain 4 (invalid free ignored)
    jne .pool_fail_safety_pop

    ; 2. Free misaligned address
    mov rax, [r12 + pool_t.memory]
    add rax, 15                     ; not aligned to 32 bytes
    mov rdi, r12
    mov rsi, rax
    call pool_free
    mov rax, [r12 + pool_t.count]
    cmp rax, 4                      ; count must remain 4 (invalid free ignored)
    jne .pool_fail_safety_pop

    ; Step J: Test Dynamic Pool Expansion (Subfeature 13.3)
    ; We currently have 4 slots allocated (capacity = 4, count = 4, free_head = NULL).
    ; Request a 5th allocation. This must trigger pool_grow.
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_grow_alloc
    mov r8, rax                     ; R8 = 5th slot (in the new 4KB page)

    ; Verify that pool capacity grew
    ; Expected capacity = 4 + (4080 / 32) = 4 + 127 = 131
    mov rax, [r12 + pool_t.capacity]
    cmp rax, 131
    jne .pool_fail_capacity_grow

    ; Verify used count is 5
    mov rax, [r12 + pool_t.count]
    cmp rax, 5
    jne .pool_fail_count_grow

    ; Request a 6th allocation
    mov rdi, r12
    call pool_alloc
    test rax, rax
    jz .pool_fail_grow_alloc
    mov r9, rax                     ; R9 = 6th slot

    ; Verify used count is 6
    mov rax, [r12 + pool_t.count]
    cmp rax, 6
    jne .pool_fail_count_grow

    ; Free the 5th slot (R8)
    mov rdi, r12
    mov rsi, r8
    call pool_free

    ; Free the 6th slot (R9)
    mov rdi, r12
    mov rsi, r9
    call pool_free

    ; Verify used count is back to 4
    mov rax, [r12 + pool_t.count]
    cmp rax, 4
    jne .pool_fail_count_grow

    ; Verify that freeing invalid/misaligned slots inside the grown block is ignored
    ; Let's get an address inside the grown page that is misaligned: R8 + 15
    mov rsi, r8
    add rsi, 15
    mov rdi, r12
    call pool_free
    mov rax, [r12 + pool_t.count]
    cmp rax, 4                      ; count must remain 4
    jne .pool_fail_safety_pop

    pop rbp                         ; restore RBP

    ; Step K: Clean up pool using pool_destroy
    mov rdi, r12
    call pool_destroy

    ; Pool Allocator Test PASSED!
    mov rsi, msg_pool_test_passed
    call uart_print_str
    jmp .run_memcpy_test

.run_memcpy_test:
    mov rsi, msg_memcpy_test_start
    call uart_print_str

    push r12
    push r13

    ; Allocate source buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcpy_fail_alloc
    mov r12, rax                    ; R12 = Src buffer

    ; Allocate destination buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcpy_fail_alloc
    mov r13, rax                    ; R13 = Dst buffer

    ; Populate Src buffer with 0, 1, 2, ..., 127
    xor rcx, rcx
.populate_loop:
    mov [r12 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .populate_loop

    ; Run cases
    mov rcx, 0
    call .run_one_memcpy_case
    mov rcx, 1
    call .run_one_memcpy_case
    mov rcx, 7
    call .run_one_memcpy_case
    mov rcx, 15
    call .run_one_memcpy_case
    mov rcx, 16
    call .run_one_memcpy_case
    mov rcx, 23
    call .run_one_memcpy_case
    mov rcx, 31
    call .run_one_memcpy_case
    mov rcx, 32
    call .run_one_memcpy_case
    mov rcx, 35
    call .run_one_memcpy_case
    mov rcx, 64
    call .run_one_memcpy_case
    mov rcx, 100
    call .run_one_memcpy_case

    ; Free buffers
    mov rdi, r12
    call heap_free
    mov rdi, r13
    call heap_free

    pop r13
    pop r12

    ; memcpy Test PASSED!
    mov rsi, msg_memcpy_test_passed
    call uart_print_str
    jmp .run_memset_test

.run_memset_test:
    mov rsi, msg_memset_test_start
    call uart_print_str

    push r12
    push r13

    ; Allocate destination buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memset_fail_alloc
    mov r12, rax                    ; R12 = Dst buffer

    ; Run cases with fill value 0xAA (R13 = 0xAA)
    mov r13, 0xAA

    mov rcx, 0
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 1
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 7
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 15
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 16
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 23
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 31
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 32
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 35
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 64
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 100
    mov rsi, r13
    call .run_one_memset_case

    ; Run cases with fill value 0xFF (R13 = 0xFF)
    mov r13, 0xFF

    mov rcx, 7
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 32
    mov rsi, r13
    call .run_one_memset_case

    mov rcx, 35
    mov rsi, r13
    call .run_one_memset_case

    ; Free destination buffer
    mov rdi, r12
    call heap_free

    pop r13
    pop r12

    ; memset Test PASSED!
    mov rsi, msg_memset_test_passed
    call uart_print_str
    jmp .run_memzero_test

.run_memzero_test:
    mov rsi, msg_memzero_test_start
    call uart_print_str

    push r12
    push r13

    ; Allocate destination buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memzero_fail_alloc
    mov r12, rax                    ; R12 = Dst buffer

    ; Run cases
    mov rcx, 0
    call .run_one_memzero_case
    mov rcx, 1
    call .run_one_memzero_case
    mov rcx, 7
    call .run_one_memzero_case
    mov rcx, 15
    call .run_one_memzero_case
    mov rcx, 16
    call .run_one_memzero_case
    mov rcx, 23
    call .run_one_memzero_case
    mov rcx, 31
    call .run_one_memzero_case
    mov rcx, 32
    call .run_one_memzero_case
    mov rcx, 35
    call .run_one_memzero_case
    mov rcx, 64
    call .run_one_memzero_case
    mov rcx, 100
    call .run_one_memzero_case

    ; Free destination buffer
    mov rdi, r12
    call heap_free

    pop r13
    pop r12

    ; memzero Test PASSED!
    mov rsi, msg_memzero_test_passed
    call uart_print_str
    jmp .run_memcmp_test

.run_memcmp_test:
    mov rsi, msg_memcmp_test_start
    call uart_print_str

    push r12
    push r13
    push r14

    ; Allocate Buffer 1
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcmp_fail_alloc
    mov r12, rax                    ; R12 = Buffer 1

    ; Allocate Buffer 2
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcmp_fail_alloc
    mov r13, rax                    ; R13 = Buffer 2

    ; Allocate Buffer 3
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memcmp_fail_alloc
    mov r14, rax                    ; R14 = Buffer 3

    ; Populate all buffers with sequence 0..127
    xor rcx, rcx
.populate_loop_memcmp:
    mov [r12 + rcx], cl
    mov [r13 + rcx], cl
    mov [r14 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .populate_loop_memcmp

    ; Test 1: Compare identical buffers (R12 and R13)
    mov rcx, 0
    call .run_match_case
    mov rcx, 1
    call .run_match_case
    mov rcx, 7
    call .run_match_case
    mov rcx, 15
    call .run_match_case
    mov rcx, 16
    call .run_match_case
    mov rcx, 23
    call .run_match_case
    mov rcx, 31
    call .run_match_case
    mov rcx, 32
    call .run_match_case
    mov rcx, 35
    call .run_match_case
    mov rcx, 64
    call .run_match_case
    mov rcx, 100
    call .run_match_case

    ; Test 2: Mismatch in first chunk (index 5)
    mov byte [r14 + 5], 99
    mov rdi, r12
    mov rsi, r14
    mov rdx, 10
    call memcmp
    cmp rax, -94                    ; 5 - 99 = -94
    jne .memcmp_fail_mismatch_val

    mov rdi, r14
    mov rsi, r12
    mov rdx, 10
    call memcmp
    cmp rax, 94                     ; 99 - 5 = 94
    jne .memcmp_fail_mismatch_val
    mov byte [r14 + 5], 5           ; restore

    ; Test 3: Mismatch in second chunk (index 45)
    mov byte [r14 + 45], 2
    mov rdi, r12
    mov rsi, r14
    mov rdx, 50
    call memcmp
    cmp rax, 43                     ; 45 - 2 = 43
    jne .memcmp_fail_mismatch_val
    mov byte [r14 + 45], 45         ; restore

    ; Test 4: Mismatch in sub-32 remainder (index 75)
    mov byte [r14 + 75], 0
    mov rdi, r12
    mov rsi, r14
    mov rdx, 100
    call memcmp
    cmp rax, 75                     ; 75 - 0 = 75
    jne .memcmp_fail_mismatch_val
    mov byte [r14 + 75], 75         ; restore

    ; Test 5: Mismatch outside compared range (index 50 with size 10)
    mov byte [r14 + 50], 99
    mov rdi, r12
    mov rsi, r14
    mov rdx, 10
    call memcmp
    test rax, rax                   ; must be 0 (identical in first 10 bytes)
    jnz .memcmp_fail_mismatch_val
    mov byte [r14 + 50], 50         ; restore

    ; Free all buffers
    mov rdi, r12
    call heap_free
    mov rdi, r13
    call heap_free
    mov rdi, r14
    call heap_free

    pop r14
    pop r13
    pop r12

    ; memcmp Test PASSED!
    mov rsi, msg_memcmp_test_passed
    call uart_print_str
    jmp .run_memmove_test

.run_memmove_test:
    mov rsi, msg_memmove_test_start
    call uart_print_str

    push r12

    ; Allocate Buffer (128 bytes)
    mov rdi, 128
    call heap_alloc
    test rax, rax
    jz .memmove_fail_alloc
    mov r12, rax                    ; R12 = working buffer

    ; -------------------------------------------------------------------------
    ; Test Case A: Forward copy, non-overlapping
    ; -------------------------------------------------------------------------
    ; Reset buffer
    xor rcx, rcx
.reset_a:
    mov [r12 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .reset_a

    mov rdi, r12
    add rdi, 64                     ; RDI = dest = R12 + 64
    mov rsi, r12                    ; RSI = src = R12 + 0
    mov rdx, 32                     ; RDX = size = 32
    call memmove

    ; Verify return value
    mov rbx, r12
    add rbx, 64
    cmp rax, rbx
    jne .memmove_fail_ret

    ; Verify payload at dest
    xor rcx, rcx
.verify_a:
    mov al, [r12 + 64 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 32
    jb .verify_a

    ; -------------------------------------------------------------------------
    ; Test Case B: Reverse copy, overlapping (Dest > Src)
    ; -------------------------------------------------------------------------
    ; Reset buffer
    xor rcx, rcx
.reset_b:
    mov [r12 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .reset_b

    mov rdi, r12
    add rdi, 30                     ; RDI = dest = R12 + 30
    mov rsi, r12
    add rsi, 10                     ; RSI = src = R12 + 10
    mov rdx, 40                     ; RDX = size = 40 (overlapping)
    call memmove

    ; Verify return value
    mov rbx, r12
    add rbx, 30
    cmp rax, rbx
    jne .memmove_fail_ret

    ; Verify unchanged range [0..29]
    xor rcx, rcx
.verify_b_pre:
    mov al, [r12 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 30
    jb .verify_b_pre

    ; Verify moved payload [30..69] from [10..49]
    xor rcx, rcx
.verify_b_payload:
    mov al, [r12 + 30 + rcx]
    mov r8b, cl
    add r8b, 10
    cmp al, r8b
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 40
    jb .verify_b_payload

    ; Verify unchanged range [70..127]
    mov rcx, 70
.verify_b_post:
    mov al, [r12 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 128
    jb .verify_b_post

    ; -------------------------------------------------------------------------
    ; Test Case C: Forward copy, overlapping (Dest < Src)
    ; -------------------------------------------------------------------------
    ; Reset buffer
    xor rcx, rcx
.reset_c:
    mov [r12 + rcx], cl
    inc rcx
    cmp rcx, 128
    jb .reset_c

    mov rdi, r12
    add rdi, 10                     ; RDI = dest = R12 + 10
    mov rsi, r12
    add rsi, 30                     ; RSI = src = R12 + 30
    mov rdx, 40                     ; RDX = size = 40 (overlapping)
    call memmove

    ; Verify return value
    mov rbx, r12
    add rbx, 10
    cmp rax, rbx
    jne .memmove_fail_ret

    ; Verify unchanged range [0..9]
    xor rcx, rcx
.verify_c_pre:
    mov al, [r12 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 10
    jb .verify_c_pre

    ; Verify moved payload [10..49] from [30..69]
    xor rcx, rcx
.verify_c_payload:
    mov al, [r12 + 10 + rcx]
    mov r8b, cl
    add r8b, 30
    cmp al, r8b
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 40
    jb .verify_c_payload

    ; Verify unchanged range [50..127]
    mov rcx, 50
.verify_c_post:
    mov al, [r12 + rcx]
    cmp al, cl
    jne .memmove_fail_data
    inc rcx
    cmp rcx, 128
    jb .verify_c_post

    ; Free buffer
    mov rdi, r12
    call heap_free

    pop r12

    ; memmove Test PASSED!
    mov rsi, msg_memmove_test_passed
    call uart_print_str
    jmp .run_numa_test

.run_numa_test:
    mov rsi, msg_numa_test_start
    call uart_print_str

    ; 1. Verify range count is > 0
    mov rax, [numa_range_count]
    test rax, rax
    jz .numa_fail_count

    ; Print ranges
    mov rsi, msg_numa_ranges_found
    call uart_print_str

    push r12
    push r13
    push r14

    xor r12, r12                    ; r12 = index i = 0
.loop_print:
    mov rcx, [numa_range_count]
    cmp r12, rcx
    jae .done_print

    mov rax, r12
    imul rax, numa_range_t_size
    lea r13, [numa_ranges + rax]

    ; Print base
    mov rsi, msg_numa_range_base
    call uart_print_str
    mov rax, [r13 + numa_range_t.base]
    call uart_print_hex64

    ; Print length
    mov rsi, msg_numa_range_len
    call uart_print_str
    mov rax, [r13 + numa_range_t.length]
    call uart_print_hex64

    ; Print Node ID
    mov rsi, msg_numa_range_node
    call uart_print_str
    movzx rax, dword [r13 + numa_range_t.node_id]
    call uart_print_hex64

    mov rsi, msg_crlf
    call uart_print_str

    inc r12
    jmp .loop_print

.done_print:
    ; 2. Test address translation API: numa_get_node_by_phys
    ; Query address 0 (should return first node, usually Node 0)
    xor rdi, rdi
    call numa_get_node_by_phys
    ; We just verify it returns a valid node ID (rax should be a node ID like 0 or 1, etc.)
    ; We can also check that query beyond max memory defaults to Node 0.
    mov rdi, [phys_state + phys_state_t.max_phys_addr]
    add rdi, 0x1000                 ; just past max physical RAM
    call numa_get_node_by_phys
    test rax, rax
    jnz .numa_fail_lookup_pop       ; should fall back to 0 for out-of-bounds/unmapped addresses

    ; 3. Print numa_node_count
    mov rsi, msg_numa_node_count
    call uart_print_str
    mov rax, [numa_node_count]
    call uart_print_dec
    mov rsi, msg_crlf
    call uart_print_str

    ; 4. Print relative distance matrix
    mov rsi, msg_numa_matrix_header
    call uart_print_str

    xor r12, r12                    ; r12 = node_from = 0
.loop_node_from:
    mov rcx, [numa_node_count]
    cmp r12, rcx
    jae .done_matrix_print

    xor r13, r13                    ; r13 = node_to = 0
.loop_node_to:
    mov rcx, [numa_node_count]
    cmp r13, rcx
    jae .next_node_from

    ; Print "  Node "
    mov rsi, msg_numa_node_prefix
    call uart_print_str
    mov rax, r12
    call uart_print_dec
    ; Print " -> "
    mov rsi, msg_numa_node_arrow
    call uart_print_str
    mov rax, r13
    call uart_print_dec
    ; Print ": "
    mov rsi, msg_numa_node_colon
    call uart_print_str

    ; Call numa_get_distance
    mov rdi, r12
    mov rsi, r13
    call numa_get_distance          ; RAX = distance
    call uart_print_dec
    
    mov rsi, msg_crlf
    call uart_print_str

    inc r13
    jmp .loop_node_to

.next_node_from:
    inc r12
    jmp .loop_node_from

.done_matrix_print:
    ; 5. Verify numa_get_distance bounds checking by querying invalid nodes and checking for 255.
    ; Case A: node_from >= count
    mov rdi, [numa_node_count]
    xor rsi, rsi
    call numa_get_distance
    cmp rax, 255
    jne .numa_fail_distance_pop

    ; Case B: node_to >= count
    xor rdi, rdi
    mov rsi, [numa_node_count]
    call numa_get_distance
    cmp rax, 255
    jne .numa_fail_distance_pop

    ; Case C: very large node ID (99)
    mov rdi, 99
    xor rsi, rsi
    call numa_get_distance
    cmp rax, 255
    jne .numa_fail_distance_pop

    ; 6. Verify Node-Local Bitmaps Active
    mov rax, [numa_local_bitmaps_active]
    test rax, rax
    jz .numa_fail_bitmaps_init_pop

    ; 7. Print Node-Local Bitmap Info
    mov rsi, msg_numa_local_info_header
    call uart_print_str

    xor r12, r12                    ; r12 = index J = 0
.loop_node_info:
    mov rcx, [numa_node_count]
    cmp r12, rcx
    jae .test_numa_allocation

    ; Print "  Node "
    mov rsi, msg_numa_node_prefix
    call uart_print_str
    mov rax, r12
    call uart_print_dec

    ; Print " Bitmap: Base=0x"
    mov rsi, msg_numa_node_bmp_base
    call uart_print_str

    mov rax, r12
    imul rax, numa_node_t_size
    lea r13, [numa_nodes + rax]     ; R13 = node descriptor pointer

    mov rax, [r13 + numa_node_t.bitmap_addr]
    call uart_print_hex64

    ; Print " Size=0x"
    mov rsi, msg_numa_node_bmp_size
    call uart_print_str
    mov rax, [r13 + numa_node_t.bitmap_size]
    call uart_print_hex64

    ; Print " FreePages="
    mov rsi, msg_numa_node_bmp_free
    call uart_print_str
    mov rax, [r13 + numa_node_t.free_pages]
    call uart_print_dec

    mov rsi, msg_crlf
    call uart_print_str

    inc r12
    jmp .loop_node_info

.test_numa_allocation:
    ; 8. Test allocate page from Node 0
    xor rdi, rdi                    ; target node 0
    call phys_alloc_page_node
    test rax, rax
    jz .numa_fail_alloc_node_pop
    mov r14, rax                    ; save allocated address in R14

    ; Verify node affinity of returned address
    mov rdi, r14
    call numa_get_node_by_phys      ; RAX = Node ID
    test rax, rax
    jnz .numa_fail_node_affinity_pop

    ; Free the page
    mov rdi, r14
    call phys_free_page

    ; 9. Test fallback lookup for invalid node (99)
    mov rdi, 99
    call phys_alloc_page_node
    test rax, rax
    jz .numa_fail_fallback_alloc_pop
    mov r14, rax

    ; Free fallback page
    mov rdi, r14
    call phys_free_page

    ; 10. Test fallback under simulated Node 0 memory exhaustion
    mov rax, [numa_node_count]
    cmp rax, 1
    jbe .numa_sim_oom_done

    mov rsi, msg_numa_sim_oom_start
    call uart_print_str

    ; Save Node 0's end_page
    mov rax, [numa_nodes + numa_node_t.end_page]
    push rax

    ; Simulate Node 0 exhaustion: set Node 0's end_page equal to its start_page
    mov rcx, [numa_nodes + numa_node_t.start_page]
    mov [numa_nodes + numa_node_t.end_page], rcx

    ; Allocate from Node 0 (should fail on Node 0 and fallback to Node 1)
    xor rdi, rdi                    ; requested node 0
    call phys_alloc_page_node
    test rax, rax
    jz .numa_fail_sim_oom_alloc_pop

    mov r14, rax                    ; save allocated address in R14

    ; Verify node affinity of returned address: should be Node 1
    mov rdi, r14
    call numa_get_node_by_phys      ; RAX = Node ID
    cmp rax, 1
    jne .numa_fail_sim_oom_affinity_pop

    ; Free the page
    mov rdi, r14
    call phys_free_page

    ; Restore Node 0's end_page
    pop rax
    mov [numa_nodes + numa_node_t.end_page], rax

    mov rsi, msg_numa_sim_oom_ok
    call uart_print_str

.numa_sim_oom_done:
    pop r14
    pop r13
    pop r12

    ; NUMA Test PASSED!
    mov rsi, msg_numa_test_passed
    call uart_print_str
    jmp .smep_smap_test

.smep_smap_test:
    ; -------------------------------------------------------------
    ; SMEP/SMAP Protection Test
    ; -------------------------------------------------------------
    mov rsi, msg_smep_smap_test_start
    call uart_print_str

    ; 1. Allocate a physical page for user mapping
    call phys_alloc_page
    test rax, rax
    jz .smep_smap_fail_alloc
    mov r12, rax                    ; R12 = user page physical address

    ; 2. Create a VMA for user space test address
    ; start=0x40000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_USER (0x0B)
    mov rdi, 0x40000000
    mov rsi, 4096
    mov rdx, 0x0B                   ; VMA_READ | VMA_WRITE | VMA_USER
    call vma_create
    test rax, rax
    jz .smep_smap_fail_vma
    mov r13, rax                    ; R13 = VMA pointer

    ; 3. Map user space address
    mov rdi, 0x40000000
    mov rsi, r12
    mov rdx, 0x07                   ; PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .smep_smap_fail_map

    ; 4. Test copy_to_user
    mov rdi, 0x40000000             ; user destination
    mov rsi, msg_smep_smap_test_data ; kernel source
    mov rdx, 20                     ; length of msg_smep_smap_test_data ("SMAP_TEST_SIGNATURE" + null = 20)
    call copy_to_user
    test rax, rax
    jz .smep_smap_fail_copy_to

    ; 5. Test copy_from_user
    mov rdi, smep_smap_test_buf     ; kernel destination buffer
    mov rsi, 0x40000000             ; user source
    mov rdx, 20
    call copy_from_user
    test rax, rax
    jz .smep_smap_fail_copy_from

    ; 6. Verify data integrity
    mov rsi, smep_smap_test_buf
    mov rdi, msg_smep_smap_test_data
    mov rdx, 20
    call memcmp
    test rax, rax
    jnz .smep_smap_fail_data

    ; Clean up
    mov rdi, 0x40000000
    call virt_unmap

    mov rdi, r12
    call phys_free_page

    mov rdi, r13
    call vma_destroy

    ; SMEP/SMAP Test PASSED!
    mov rsi, msg_smep_smap_test_passed
    call uart_print_str

    jmp .zero_on_free_test

.zero_on_free_test:
    ; -------------------------------------------------------------
    ; Zero on Free Test
    ; -------------------------------------------------------------
    mov rsi, msg_zof_test_start
    call uart_print_str

    ; --- 1. Test Heap Allocator Zeroing ---
    mov rdi, 64
    call heap_alloc                 ; RAX = allocated pointer
    test rax, rax
    jz .zof_fail_heap_alloc
    mov r12, rax                    ; R12 = heap block pointer

    ; Write signature to the block
    mov qword [r12], 0x123456789ABCDEF0
    mov qword [r12 + 8], 0x123456789ABCDEF0
    mov qword [r12 + 16], 0x123456789ABCDEF0
    mov qword [r12 + 24], 0x123456789ABCDEF0

    ; Free the block
    mov rdi, r12
    call heap_free

    ; Verify that the payload is zeroed out
    cmp qword [r12], 0
    jne .zof_fail_heap_zero
    cmp qword [r12 + 8], 0
    jne .zof_fail_heap_zero
    cmp qword [r12 + 16], 0
    jne .zof_fail_heap_zero
    cmp qword [r12 + 24], 0
    jne .zof_fail_heap_zero

    ; --- 2. Test Physical Page Allocator Zeroing ---
    call phys_alloc_page            ; RAX = physical page address
    test rax, rax
    jz .zof_fail_phys_alloc
    mov r13, rax                    ; R13 = physical page address

    ; Write signature
    mov qword [r13], 0xDEADBEEFCAFEBAB1
    mov qword [r13 + 4088], 0xDEADBEEFCAFEBAB2

    ; Free page
    mov rdi, r13
    call phys_free_page

    ; Verify zeroed
    cmp qword [r13], 0
    jne .zof_fail_phys_zero
    cmp qword [r13 + 4088], 0
    jne .zof_fail_phys_zero

    ; VMM Zeroing on Free Tests PASSED!
    mov rsi, msg_zof_test_passed
    call uart_print_str

    jmp .mmap_test_start

    ; =========================================================================
    ; Memory-Mapped Files (mmap) Tests (Section 17)
    ; =========================================================================
.mmap_test_start:
    mov rsi, msg_mmap_test_start
    call uart_print_str

    ; 1. Create a mock file with size 8192 (2 pages)
    mov rdi, 8192
    call mock_file_create
    test rax, rax
    jz .mmap_fail_create
    mov r12, rax                    ; R12 = file_ptr (mock_file_t)

    ; 2. Map the file to virtual address 0x80000000 with VMA_READ | VMA_WRITE
    mov rdi, 0x80000000
    mov rsi, 8192                   ; 2 pages
    mov rdx, 0x03                   ; VMA_READ | VMA_WRITE
    mov r8, r12                     ; file_ptr
    mov r9, 0                       ; file offset 0
    call vma_map_file
    test rax, rax
    jz .mmap_fail_map

    ; 3. Access virtual address to trigger demand paging load (Read test)
    ; Virtual address: 0x80000000.
    ; This triggers a #PF, loads from mock storage, maps, and resumes execution.
    mov rsi, 0x80000000
    mov rax, [rsi]
    cmp rax, 0x4154544154544154     ; Compare first 8 bytes: "TATTVA_M"
    jne .mmap_fail_read_val

    ; Check offset value at 0x80000020 (decimal 32)
    mov rax, [rsi + 32]
    cmp rax, 0                      ; offset should be 0
    jne .mmap_fail_read_offset

    ; 4. Write data to the memory-mapped file (Write test)
    ; This sets the PAGE_DIRTY bit in the PTE.
    mov qword [rsi], 0xDEADBEEFCAFEBABY
    mov qword [rsi + 32], 0x1234567890ABCDEF

    ; 5. Verify the dirty bit is set in the PTE
    mov rdi, 0x80000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .mmap_fail_pte
    mov rcx, [rax]
    test rcx, 0x40                  ; PAGE_DIRTY (bit 6)
    jz .mmap_fail_dirty             ; If not set, error

    ; 6. Synchronize dirty pages back to mock storage via mmap_msync
    mov rdi, 0x80000000
    mov rsi, 8192
    call mmap_msync
    test rax, rax
    jz .mmap_fail_sync

    ; 7. Verify that the dirty bit is now cleared in the PTE
    mov rdi, 0x80000000
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .mmap_fail_pte
    mov rcx, [rax]
    test rcx, 0x40                  ; PAGE_DIRTY should be cleared
    jnz .mmap_fail_not_cleared

    ; 8. Verify the backing mock file blocks actually contain the synchronized data
    mov rbx, [r12 + mock_file_t.blocks + 0] ; First block physical page address
    test rbx, rbx
    jz .mmap_fail_backing

    mov rax, [rbx]
    cmp rax, 0xDEADBEEFCAFEBABY
    jne .mmap_fail_backing_data
    mov rax, [rbx + 32]
    cmp rax, 0x1234567890ABCDEF
    jne .mmap_fail_backing_data

    ; 9. Unmap the range via mmap_munmap
    mov rdi, 0x80000000
    mov rsi, 8192
    call mmap_munmap
    test rax, rax
    jz .mmap_fail_unmap

    ; 10. Destroy the mock file structure
    mov rdi, r12
    call mock_file_destroy

    jmp .ipc_test_start

    ; =========================================================================
    ; Shared Memory & IPC Primitives Tests (Section 18)
    ; =========================================================================
.ipc_test_start:
    mov rsi, msg_ipc_test_start
    call uart_print_str

    ; -------------------------------------------------------------------------
    ; 1. Test Shared Physical Frames (Subfeature 18.1)
    ; -------------------------------------------------------------------------
    ; Create a secondary User PML4
    xor rdi, rdi                    ; 0 = read current CR3
    call virt_create_user_pml4
    test rax, rax
    jz .ipc_fail_pml4
    mov r12, rax                    ; R12 = secondary PML4 physical address

    ; Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .ipc_fail_alloc
    mov r13, rax                    ; R13 = physical page

    ; Map it to 0x90000000 in current address space (CR3) with present & writable flags
    mov rdi, 0x90000000
    mov rsi, r13
    mov rdx, 0x03                   ; PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz .ipc_fail_map

    ; Write test signature to 0x90000000
    mov rdi, 0x90000000
    mov rax, 0x5348415245445f4d     ; "SHARED_M"
    mov [rdi], rax
    mov rax, 0x454d4f52595f4f4b     ; "EMORY_OK"
    mov [rdi + 8], rax

    ; Share this page with the secondary PML4 at destination address 0x90000000
    mov rdi, 0x90000000             ; vaddr_src
    mov rsi, r12                    ; pml4_dest
    mov rdx, 0x90000000             ; vaddr_dest
    mov rcx, 0x03                   ; flags (PAGE_PRESENT | PAGE_WRITABLE)
    call ipc_share_frame
    test rax, rax
    jz .ipc_fail_share

    ; Temporarily switch CR3 to secondary PML4 to verify mapping
    mov r14, cr3                    ; R14 = original CR3
    mov cr3, r12                    ; switch to secondary PML4

    ; Verify that 0x90000000 is readable and contains our signature
    mov rdi, 0x90000000
    mov rax, [rdi]
    cmp rax, 0x5348415245445f4d     ; "SHARED_M"
    jne .ipc_fail_shared_val
    mov rax, [rdi + 8]
    cmp rax, 0x454d4f52595f4f4b     ; "EMORY_OK"
    jne .ipc_fail_shared_val

    ; Switch back to original CR3
    mov cr3, r14

    ; Clean up the shared page from both address spaces
    mov rdi, 0x90000000
    call virt_unmap
    
    ; Switch to secondary PML4 to unmap it there as well
    mov cr3, r12
    mov rdi, 0x90000000
    call virt_unmap
    mov cr3, r14                    ; restore original CR3

    ; Free the physical page frame
    mov rdi, r13
    call phys_free_page

    ; Free the secondary PML4 physical page itself
    mov rdi, r12
    call phys_free_page

    ; -------------------------------------------------------------------------
    ; 2. Test Zero-Copy Ring Buffers (Subfeature 18.2)
    ; -------------------------------------------------------------------------
    ; Create a double-mapped ring buffer at 0xA0000000 of size 4096 (total 8192 bytes mapped)
    mov rdi, 0xA0000000
    mov rsi, 4096                   ; size N = 4096 (1 page)
    mov rdx, 0x03                   ; VMA flags (VMA_READ | VMA_WRITE)
    call ipc_create_ring_buffer
    test rax, rax
    jz .ipc_fail_ring_create

    ; Write test data at the beginning of the first half (0xA0000000)
    mov rdi, 0xA0000000
    mov rax, 0x52494e475f425546     ; "RING_BUF"
    mov [rdi], rax
    mov rax, 0x4645525f444f5542     ; "FER_DOUB"
    mov [rdi + 8], rax
    mov rax, 0x4c455f4d41505f21     ; "LE_MAP_!"
    mov [rdi + 16], rax

    ; Read back from the second half at 0xA0001000 (offset 4096) and verify it's identical
    mov rsi, 0xA0001000
    mov rax, [rsi]
    cmp rax, 0x52494e475f425546
    jne .ipc_fail_ring_val
    mov rax, [rsi + 8]
    cmp rax, 0x4645525f444f5542
    jne .ipc_fail_ring_val
    mov rax, [rsi + 16]
    cmp rax, 0x4c455f4d41505f21
    jne .ipc_fail_ring_val

    ; Write a value at offset 32 in the second half (0xA0001020)
    mov qword [rsi + 32], 0x90ABCDEFAABBCCDD

    ; Read it back from the first half at 0xA0000020 and verify it matches
    mov rax, [rdi + 32]
    cmp rax, 0x90ABCDEFAABBCCDD
    jne .ipc_fail_ring_cross_val

    ; Clean up the ring buffer
    mov rdi, 0xA0000000
    mov rsi, 4096
    call ipc_destroy_ring_buffer

    ; VMM Shared Memory & IPC Tests PASSED!
    mov rsi, msg_ipc_test_passed
    call uart_print_str

    jmp .leak_test_start

    ; =========================================================================
    ; Memory Leak Tracker Tests (Subfeature 19.1)
    ; =========================================================================
.leak_test_start:
    mov rsi, msg_leak_test_start
    call uart_print_str

    ; 1. Reset/Initialize leak tracker
    call leak_tracker_init

    ; 2. Run report, verify RAX = 0 leaks initially
    call heap_leak_report
    cmp rax, 0
    jne .leak_fail_initial

    ; 3. Allocate two memory blocks
    mov rdi, 128
    call heap_alloc                 ; RAX = block 1
    test rax, rax
    jz .leak_fail_alloc
    mov r12, rax                    ; R12 = block 1 pointer

    mov rdi, 256
    call heap_alloc                 ; RAX = block 2
    test rax, rax
    jz .leak_fail_alloc
    mov r13, rax                    ; R13 = block 2 pointer

    ; 4. Free block 1
    mov rdi, r12
    call heap_free

    ; 5. Run leak report, verify RAX = 1 leak is detected
    call heap_leak_report
    cmp rax, 1
    jne .leak_fail_count

    ; Verify that block 2 address in our leak table matches r13
    ; Each leak_entry_t is 24 bytes (0=.ptr, 8=.size, 16=.caller)
    lea rbx, [leak_table]
    xor rcx, rcx
    xor rdx, rdx                    ; RDX = count of active leak pointers matched
.verify_loop:
    cmp rcx, 512                    ; LEAK_MAX_ENTRIES
    jge .verify_done
    mov rax, [rbx + rcx * 24 + 0]   ; offset 0 is .ptr
    test rax, rax
    jz .next_verify
    cmp rax, r13
    jne .next_verify
    inc rdx                         ; found block 2!
.next_verify:
    inc rcx
    jmp .verify_loop

.verify_done:
    cmp rdx, 1
    jne .leak_fail_verify

    ; 6. Free block 2
    mov rdi, r13
    call heap_free

    ; 7. Run leak report, verify RAX = 0 leaks
    call heap_leak_report
    cmp rax, 0
    jne .leak_fail_final

    ; =========================================================================
    ; Hardware Transactional Memory (TSX) Fault Handling Test (Subfeature 25.1)
    ; =========================================================================
    jmp .tsx_test_start

.tsx_test_start:
    mov rsi, msg_tsx_test_start
    call uart_print_str

    ; Step A: Create a VMA for TSX demand paging test
    ; start=0x80000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_ONDEMAND (0x83)
    mov rdi, 0x80000000
    mov rsi, 4096
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .tsx_test_fail_vma

    ; Step B: Set current thread to index 0 (Thread 100)
    mov qword [current_thread_idx], 0

    ; Step C: Enter TSX transaction (Success Case)
    ; Fallback path is .tsx_success_fallback
    lea rdi, [.tsx_success_transaction]
    lea rsi, [.tsx_success_fallback]
    call tsx_begin

.tsx_success_transaction:
    ; Access the demand-paging address. This should trigger a page fault!
    ; Since it's inside TSX, the fault handler will resolve it and redirect RIP to .tsx_success_transaction.
    ; On the retry, the access will succeed without a fault!
    mov rdi, 0x80000000
    mov byte [rdi], 0xAA

    ; Commit transaction
    call tsx_end

    ; Verify data was written correctly
    mov al, [0x80000000]
    cmp al, 0xAA
    jne .tsx_test_fail_data

    mov rsi, msg_tsx_success_ok
    call uart_print_str
    jmp .tsx_run_abort_case

.tsx_success_fallback:
    ; We should not reach here in the success case
    mov rsi, msg_tsx_fail_success_fallback
    call uart_print_str
    jmp .panic

.tsx_run_abort_case:
    ; Step D: Enter TSX transaction (Abort Fallback Case)
    ; We access an unmapped address 0x90000000 (no VMA).
    ; This should abort the transaction and redirect RIP to the fallback handler .tsx_abort_fallback.
    lea rdi, [.tsx_abort_transaction]
    lea rsi, [.tsx_abort_fallback]
    call tsx_begin

.tsx_abort_transaction:
    mov rdi, 0x90000000
    mov al, [rdi]                   ; Unresolvable page fault!

    ; We should never reach here because the handler redirects RIP to fallback
    mov rsi, msg_tsx_fail_no_abort
    call uart_print_str
    jmp .panic

.tsx_abort_fallback:
    ; This is the expected path for the abort case!
    mov rsi, msg_tsx_abort_ok
    call uart_print_str

    ; Clean up the TSX VMA
    mov rdi, 0x80000000
    call virt_translate
    mov r14, rax                    ; physical address

    mov rdi, 0x80000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    ; TSX Test PASSED!
    mov rsi, msg_tsx_test_passed
    call uart_print_str

    ; =========================================================================
    ; TSX Speculative Directory Walk Engine Test (Subfeature 25.2)
    ; =========================================================================
.tsx_spec_walk_test_start:
    mov rsi, msg_tsx_spec_walk_test_start
    call uart_print_str

    ; 1. Initialise the transaction log
    call tsx_log_init

    ; 2. Create a VMA for our test address (0x85000000)
    ; start=0x85000000, size=4096, flags=VMA_READ|VMA_WRITE|VMA_ONDEMAND (0x83)
    mov rdi, 0x85000000
    mov rsi, 4096
    mov rdx, 0x83                   ; VMA_READ | VMA_WRITE | VMA_ONDEMAND
    call vma_create
    test rax, rax
    jz .tsx_spec_walk_fail_vma
    mov r12, rax                    ; R12 = VMA pointer

    ; 3. Cache flush
    call trans_cache_flush

    ; 4. Log the test address (not yet present/mapped in page tables)
    mov rdi, 0x85000000
    call tsx_log_address

    ; 5. Verify that it is NOT in the cache before walk
    mov rdi, 0x85000000
    call trans_cache_lookup
    test rax, rax
    jnz .tsx_spec_walk_fail_initial_cache

    ; 6. Run the speculative walk engine. It should read the log, see 0x85000000 is not present,
    ; speculatively map it (via virt_page_fault_handler), and load it into the translation cache.
    call tsx_spec_walk_engine

    ; 7. Verify that 0x85000000 IS now present in the cache and lookup returns its physical address
    mov rdi, 0x85000000
    call trans_cache_lookup         ; RAX = physical address
    test rax, rax
    jz .tsx_spec_walk_fail_lookup

    ; Let's translate it normally to verify the physical address matches
    mov r14, rax                    ; R14 = cached physical address
    mov rdi, 0x85000000
    call virt_translate             ; RAX = translated physical address
    cmp rax, r14
    jne .tsx_spec_walk_fail_mismatch

    ; 8. Clean up
    mov rdi, 0x85000000
    call virt_unmap

    mov rdi, r14
    call phys_free_page

    mov rdi, r12
    call vma_destroy

    ; 9. Invalidate entry and verify it is gone from cache
    mov rdi, 0x85000000
    call trans_cache_invalidate
    mov rdi, 0x85000000
    call trans_cache_lookup
    test rax, rax
    jnz .tsx_spec_walk_fail_invalidate

    mov rsi, msg_tsx_spec_walk_test_passed
    call uart_print_str

    ; =========================================================================
    ; TSX Lock-Free Directory Updates (Lock Elision) Test (Subfeature 25.3)
    ; =========================================================================
.tsx_lock_test_start:
    mov rsi, msg_tsx_lock_test_start
    call uart_print_str

    ; Step A: Verify Speculative lock-free directory update (Bypass mutex)
    ; 1. Set current thread to index 0 (TSX enabled)
    mov qword [current_thread_idx], 0

    ; 2. Calculate lock address to check
    ; Virtual address = 0xA0000000. PML4 index = (0xA0000000 >> 39) & 0x1FF = 0.
    ; So it uses pgtable_locks + 0.
    lea r12, [pgtable_locks]        ; R12 = &pgtable_locks[0]
    mov byte [r12], 0               ; Make sure it is unlocked

    ; 3. Call pgtable_lock_acquire
    mov rdi, 0xA0000000
    call pgtable_lock_acquire

    ; 4. Check results: tsx_active should be 1, but the lock byte MUST remain 0! (lock elision)
    call sched_get_current_thread   ; RAX = current thread pointer
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 1
    jne .tsx_lock_fail_active
    
    mov cl, [r12]
    cmp cl, 0
    jne .tsx_lock_fail_bypass

    mov rsi, msg_tsx_lock_bypass_ok
    call uart_print_str

    ; 5. Call pgtable_lock_release
    mov rdi, 0xA0000000
    call pgtable_lock_release

    ; 6. Check results: tsx_active should return to 0, and the lock byte should remain 0
    call sched_get_current_thread
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 0
    jne .tsx_lock_fail_release_active
    
    mov cl, [r12]
    cmp cl, 0
    jne .tsx_lock_fail_release_lock

    ; Step B: Verify Traditional lock fallback (when TSX disabled)
    ; 1. Set current thread to 99 (invalid/inactive) to disable TSX
    mov qword [current_thread_idx], 99

    ; 2. Call pgtable_lock_acquire
    mov rdi, 0xA0000000
    call pgtable_lock_acquire

    ; 3. Check results: lock byte MUST be 1 (traditional lock acquired!)
    mov cl, [r12]
    cmp cl, 1
    jne .tsx_lock_fail_traditional

    mov rsi, msg_tsx_lock_traditional_ok
    call uart_print_str

    ; 4. Call pgtable_lock_release
    mov rdi, 0xA0000000
    call pgtable_lock_release

    ; 5. Check results: lock byte should be cleared back to 0
    mov cl, [r12]
    cmp cl, 0
    jne .tsx_lock_fail_traditional_release

    ; Lock-Free Directory Updates Test PASSED!
    mov rsi, msg_tsx_lock_test_passed
    call uart_print_str

    jmp .hle_test_start

    ; =========================================================================
    ; Hardware Lock Elision (HLE) Protection Test (Subfeature 25.4)
    ; =========================================================================
.hle_test_start:
    mov rsi, msg_hle_test_start
    call uart_print_str

    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .hle_fail_alloc
    mov r12, rax                    ; R12 = physical page

    ; 2. Map page to virtual address 0xC0000000 with cache disabled & write-through flags
    ; Flags: PAGE_PRESENT (1) | PAGE_WRITABLE (2) | PAGE_PWT (8) | PAGE_PCD (16) = 27 = 0x1B
    mov rdi, 0xC0000000
    mov rsi, r12
    mov rdx, 0x1B
    call virt_map
    test rax, rax
    jz .hle_fail_map

    ; 3. Verify page is mapped and has PWT and PCD set
    mov rdi, 0xC0000000
    mov rsi, 0                      ; current CR3
    call virt_walk_table            ; RAX = physical address of PTE
    test rax, rax
    jz .hle_fail_walk1

    mov rcx, [rax]
    test rcx, 0x18                  ; 0x18 = PAGE_PWT | PAGE_PCD
    jz .hle_fail_flags1             ; failure if either flag is missing

    ; 4. Call hle_protect_range to clear caching flags (enforcing WB caching)
    mov rdi, 0xC0000000
    mov rsi, 4096                   ; 1 page
    call hle_protect_range

    ; 5. Verify page table entry has PWT and PCD cleared to 0 (Write-Back)
    mov rdi, 0xC0000000
    mov rsi, 0                      ; current CR3
    call virt_walk_table            ; RAX = physical address of PTE
    test rax, rax
    jz .hle_fail_walk2

    mov rcx, [rax]
    test rcx, 0x18                  ; 0x18 = PAGE_PWT | PAGE_PCD
    jnz .hle_fail_flags2            ; failure if flags are still set

    ; 6. Clean up mapping
    mov rdi, 0xC0000000
    call virt_unmap

    mov rdi, r12
    call phys_free_page

    ; 7. Test cache line alignment checker (hle_is_cache_aligned)
    ; Aligned address (multiple of 64): 0x1000
    mov rdi, 0x1000
    call hle_is_cache_aligned
    cmp rax, 1
    jne .hle_fail_align1

    ; Unaligned address: 0x1005
    mov rdi, 0x1005
    call hle_is_cache_aligned
    cmp rax, 0
    jne .hle_fail_align2

    ; HLE Protection & Caching Test PASSED!
    mov rsi, msg_hle_test_passed
    call uart_print_str

    jmp .tsx_fallback_lock_test_start

    ; =========================================================================
    ; TSX Fallback Page-Directory Lock Manager Test (Subfeature 25.5)
    ; =========================================================================
.tsx_fallback_lock_test_start:
    mov rsi, msg_tsx_fallback_lock_test_start
    call uart_print_str

    ; 1. Set current thread to index 0 (TSX enabled)
    mov qword [current_thread_idx], 0

    ; 2. Initialize lock PML4 index 10 (address = 10 << 39)
    mov r14, 10
    shl r14, 39                     ; R14 = test virtual address

    ; Reset lock and abort count
    lea rbx, [pgtable_locks]
    mov byte [rbx + 10], 0
    lea rbx, [pgtable_lock_abort_counts]
    mov byte [rbx + 10], 0

    ; 3. Verify initial acquire uses TSX (speculative block)
    mov rdi, r14
    call pgtable_lock_acquire

    call sched_get_current_thread   ; RAX = current thread pointer
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 1
    jne .tsx_fallback_lock_fail_init_active

    lea rbx, [pgtable_locks]
    mov cl, [rbx + 10]
    cmp cl, 0
    jne .tsx_fallback_lock_fail_init_lock

    ; Release it
    mov rdi, r14
    call pgtable_lock_release

    ; 4. Manually set abort count to 3 (simulating exceeding limits)
    lea rbx, [pgtable_lock_abort_counts]
    mov byte [rbx + 10], 3

    ; 5. Call pgtable_lock_acquire. It should bypass TSX and use traditional lock!
    mov rdi, r14
    call pgtable_lock_acquire

    ; Verify: tsx_active should be 0, and the lock byte MUST be 1
    call sched_get_current_thread   ; RAX = current thread pointer
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 0
    jne .tsx_fallback_lock_fail_bypass_active

    lea rbx, [pgtable_locks]
    mov cl, [rbx + 10]
    cmp cl, 1
    jne .tsx_fallback_lock_fail_bypass_lock

    mov rsi, msg_tsx_fallback_lock_limit_ok
    call uart_print_str

    ; 6. Call pgtable_lock_release.
    ; It should traditionally release the lock, decay the abort count to 2, and clear the lock byte to 0.
    mov rdi, r14
    call pgtable_lock_release

    lea rbx, [pgtable_locks]
    mov cl, [rbx + 10]
    cmp cl, 0
    jne .tsx_fallback_lock_fail_decay_lock

    lea rbx, [pgtable_lock_abort_counts]
    mov cl, [rbx + 10]
    cmp cl, 2
    jne .tsx_fallback_lock_fail_decay_count

    mov rsi, msg_tsx_fallback_lock_decay_ok
    call uart_print_str

    ; 7. Call pgtable_lock_acquire again. Since count is 2 (which is < 3), it should try TSX again!
    mov rdi, r14
    call pgtable_lock_acquire

    call sched_get_current_thread   ; RAX = current thread pointer
    mov rcx, [rax + thread_t.tsx_active]
    cmp rcx, 1
    jne .tsx_fallback_lock_fail_retry_active

    lea rbx, [pgtable_locks]
    mov cl, [rbx + 10]
    cmp cl, 0
    jne .tsx_fallback_lock_fail_retry_lock

    ; 8. Call pgtable_lock_release. It should reset the abort count to 0.
    mov rdi, r14
    call pgtable_lock_release

    lea rbx, [pgtable_lock_abort_counts]
    mov cl, [rbx + 10]
    cmp cl, 0
    jne .tsx_fallback_lock_fail_final_count

    ; TSX Fallback Lock Manager Tests PASSED!
    mov rsi, msg_tsx_fallback_lock_test_passed
    call uart_print_str

    jmp .aslr_test_start

    ; =========================================================================
    ; ASLR Symbol Offset Randomization Test (Subfeature 26.1)
    ; =========================================================================
.aslr_test_start:
    mov rsi, msg_aslr_test_start
    call uart_print_str

    ; 1. Allocate block A (64 bytes)
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .aslr_fail_alloc
    mov r12, rax                    ; R12 = pointer A (offsetted)

    ; 2. Allocate block B (64 bytes)
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .aslr_fail_alloc
    mov r13, rax                    ; R13 = pointer B (offsetted)

    ; 3. Verify alignment of pointers
    test r12, 15
    jnz .aslr_fail_align
    test r13, 15
    jnz .aslr_fail_align

    ; 4. Retrieve gap sizes
    mov r14, [r12 - 8]              ; R14 = gap size A
    mov r15, [r13 - 8]              ; R15 = gap size B

    ; 5. Verify gap A is in range [16, 256] and is a multiple of 16
    cmp r14, 16
    jl .aslr_fail_bounds
    cmp r14, 256
    jg .aslr_fail_bounds
    test r14, 15
    jnz .aslr_fail_bounds

    ; 6. Verify gap B is in range [16, 256] and is a multiple of 16
    cmp r15, 16
    jl .aslr_fail_bounds
    cmp r15, 256
    jg .aslr_fail_bounds
    test r15, 15
    jnz .aslr_fail_bounds

    ; 7. Free allocations
    mov rdi, r12
    call heap_free
    mov rdi, r13
    call heap_free

    ; ASLR Symbol Offset Randomization Test PASSED!
    mov rsi, msg_aslr_test_passed
    call uart_print_str

    jmp .xo_test_start

    ; =========================================================================
    ; Execute-Only (XO) Pages Security Test (Subfeature 26.2)
    ; =========================================================================
.xo_test_start:
    push r12
    mov rsi, msg_xo_test_start
    call uart_print_str

    ; Check CPUID for PKU support (CPUID.07H.0H:EBX.PKU [bit 3])
    push rbx
    push rcx
    push rdx
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, (1 << 3)
    pop rdx
    pop rcx
    pop rbx
    jz .xo_test_fallback_path

    ; --- Hardware PKU Path ---
    mov rsi, msg_xo_pku_supported
    call uart_print_str

    ; Enable CR4.PKE and program PKRU
    mov rax, cr4
    or rax, (1 << 22)
    mov cr4, rax

    xor ecx, ecx
    rdpkru
    or eax, 0x0C                    ; AD1=1, WD1=1
    and eax, ~0x03                  ; Key 0 fully accessible
    xor edx, edx
    wrpkru

    ; Allocate a physical page for mapping
    call phys_alloc_page
    test rax, rax
    jz .xo_fail_alloc
    mov r12, rax                    ; R12 = physical page

    ; Map page at 0xA0000000 with PAGE_XO
    mov rdi, 0xA0000000
    mov rsi, r12
    mov rdx, PAGE_XO
    call virt_map
    test rax, rax
    jz .xo_fail_map

    ; Walk page table to verify PTE
    mov rdi, 0xA0000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .xo_fail_walk

    mov rbx, [rax]
    ; Verify PAGE_PRESENT = 1
    test rbx, PAGE_PRESENT
    jz .xo_fail_pte_present
    ; Verify PAGE_KEY_1 is set
    mov rcx, PAGE_KEY_1
    test rbx, rcx
    jz .xo_fail_pte_key
    ; Verify PAGE_NX is 0
    mov rcx, PAGE_NX
    test rbx, rcx
    jnz .xo_fail_pte_nx

    mov rsi, msg_xo_pte_verify_ok
    call uart_print_str

    ; Attempt read from 0xA0000000 -> should panic and halt
    mov rdi, 0xA0000000
    mov rax, [rdi]

    ; If we reach here, the protection check failed!
    jmp .xo_fail_trap

.xo_test_fallback_path:
    ; --- Software Fallback Path ---
    mov rsi, msg_xo_pku_unsupported
    call uart_print_str

    ; Allocate a physical page for mapping
    call phys_alloc_page
    test rax, rax
    jz .xo_fail_alloc
    mov r12, rax

    ; Map page at 0xA0000000 with PAGE_XO
    mov rdi, 0xA0000000
    mov rsi, r12
    mov rdx, PAGE_XO
    call virt_map
    test rax, rax
    jz .xo_fail_map

    ; Walk page table to verify PTE
    mov rdi, 0xA0000000
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .xo_fail_walk

    mov rbx, [rax]
    ; Verify PAGE_PRESENT = 0
    test rbx, PAGE_PRESENT
    jnz .xo_fail_pte_absent
    ; Verify PAGE_XO is set
    test rbx, PAGE_XO
    jz .xo_fail_pte_xo

    mov rsi, msg_xo_pte_verify_ok
    call uart_print_str

    ; Attempt read from 0xA0000000 -> should panic and halt
    mov rdi, 0xA0000000
    mov rax, [rdi]

    ; If we reach here, the protection check failed!
    jmp .xo_fail_trap

.xo_fail_alloc:
    pop r12
    mov rsi, msg_xo_fail_alloc_str
    call uart_print_str
    jmp .panic

.xo_fail_map:
    pop r12
    mov rsi, msg_xo_fail_map_str
    call uart_print_str
    jmp .panic

.xo_fail_walk:
    pop r12
    mov rsi, msg_xo_fail_walk_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_present:
    pop r12
    mov rsi, msg_xo_fail_pte_present_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_key:
    pop r12
    mov rsi, msg_xo_fail_pte_key_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_nx:
    pop r12
    mov rsi, msg_xo_fail_pte_nx_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_absent:
    pop r12
    mov rsi, msg_xo_fail_pte_absent_str
    call uart_print_str
    jmp .panic

.xo_fail_pte_xo:
    pop r12
    mov rsi, msg_xo_fail_pte_xo_str
    call uart_print_str
    jmp .panic

.xo_fail_trap:
    pop r12
    mov rsi, msg_xo_fail_trap_str
    call uart_print_str
    jmp .panic

.aslr_fail_alloc:
    mov rsi, msg_aslr_fail_alloc_str
    call uart_print_str
    jmp .panic

.aslr_fail_align:
    mov rsi, msg_aslr_fail_align_str
    call uart_print_str
    jmp .panic

.aslr_fail_bounds:
    mov rsi, msg_aslr_fail_bounds_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_init_active:
    mov rsi, msg_tsx_fallback_lock_fail_init_active_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_init_lock:
    mov rsi, msg_tsx_fallback_lock_fail_init_lock_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_bypass_active:
    mov rsi, msg_tsx_fallback_lock_fail_bypass_active_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_bypass_lock:
    mov rsi, msg_tsx_fallback_lock_fail_bypass_lock_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_decay_lock:
    mov rsi, msg_tsx_fallback_lock_fail_decay_lock_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_decay_count:
    mov rsi, msg_tsx_fallback_lock_fail_decay_count_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_retry_active:
    mov rsi, msg_tsx_fallback_lock_fail_retry_active_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_retry_lock:
    mov rsi, msg_tsx_fallback_lock_fail_retry_lock_str
    call uart_print_str
    jmp .panic

.tsx_fallback_lock_fail_final_count:
    mov rsi, msg_tsx_fallback_lock_fail_final_count_str
    call uart_print_str
    jmp .panic

.hle_fail_alloc:
    mov rsi, msg_hle_fail_alloc_str
    call uart_print_str
    jmp .panic

.hle_fail_map:
    mov rsi, msg_hle_fail_map_str
    call uart_print_str
    jmp .panic

.hle_fail_walk1:
    mov rsi, msg_hle_fail_walk1_str
    call uart_print_str
    jmp .panic

.hle_fail_flags1:
    mov rsi, msg_hle_fail_flags1_str
    call uart_print_str
    jmp .panic

.hle_fail_walk2:
    mov rsi, msg_hle_fail_walk2_str
    call uart_print_str
    jmp .panic

.hle_fail_flags2:
    mov rsi, msg_hle_fail_flags2_str
    call uart_print_str
    jmp .panic

.hle_fail_align1:
    mov rsi, msg_hle_fail_align1_str
    call uart_print_str
    jmp .panic

.hle_fail_align2:
    mov rsi, msg_hle_fail_align2_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_active:
    mov rsi, msg_tsx_lock_fail_active_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_bypass:
    mov rsi, msg_tsx_lock_fail_bypass_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_release_active:
    mov rsi, msg_tsx_lock_fail_rel_active_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_release_lock:
    mov rsi, msg_tsx_lock_fail_rel_lock_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_traditional:
    mov rsi, msg_tsx_lock_fail_trad_str
    call uart_print_str
    jmp .panic

.tsx_lock_fail_traditional_release:
    mov rsi, msg_tsx_lock_fail_trad_rel_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_vma:
    mov rsi, msg_tsx_spec_walk_fail_vma_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_initial_cache:
    mov rsi, msg_tsx_spec_walk_fail_init_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_lookup:
    mov rsi, msg_tsx_spec_walk_fail_lookup_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_mismatch:
    mov rsi, msg_tsx_spec_walk_fail_mismatch_str
    call uart_print_str
    jmp .panic

.tsx_spec_walk_fail_invalidate:
    mov rsi, msg_tsx_spec_walk_fail_inval_str
    call uart_print_str
    jmp .panic

.tsx_test_fail_vma:
    mov rsi, msg_tsx_test_fail_vma
    call uart_print_str
    jmp .panic

.tsx_test_fail_data:
    mov rsi, msg_tsx_test_fail_data
    call uart_print_str
    jmp .panic

    ; =========================================================================
    ; Use-After-Free (UAF) Trap Tests (Subfeature 19.2)
    ; =========================================================================
.uaf_test_start:
    mov rsi, msg_uaf_test_start
    call uart_print_str

    ; Initialize UAF quarantine table
    call uaf_init

    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .uaf_fail_alloc
    mov r12, rax                    ; R12 = physical page

    ; 2. Map page to virtual address 0xB0000000 with present & writable permissions
    mov rdi, 0xB0000000
    mov rsi, r12
    mov rdx, 0x03                   ; PAGE_PRESENT | PAGE_WRITABLE
    call virt_map
    test rax, rax
    jz .uaf_fail_map

    ; 3. Write data to make sure it is mapped and present
    mov rdi, 0xB0000000
    mov qword [rdi], 0xDEADBEEF12345678

    ; 4. Unmap/Free the virtual page (calls uaf_quarantine_add internally)
    mov rdi, 0xB0000000
    call virt_unmap

    mov rdi, r12
    call phys_free_page             ; Free physical frame

    ; 5. Read access from unmapped address 0xB0000000
    ; This triggers a page fault, which queries the quarantine table,
    ; prints "Use-After-Free detected at address 0x00000000B0000000! (UAF_TEST_SUCCESS)"
    ; and panics.
    mov rdi, 0xB0000000
    mov rax, [rdi]                  ; should trigger UAF Trap and halt!

    ; If we reach here, the trap failed!
    mov rsi, msg_uaf_fail_trap
    call uart_print_str
    jmp .panic

.uaf_fail_alloc:
    mov rsi, msg_uaf_fail_alloc_str
    call uart_print_str
    jmp .panic

.uaf_fail_map:
    mov rsi, msg_uaf_fail_map_str
    call uart_print_str
    jmp .panic


.leak_fail_initial:
    mov rsi, msg_leak_fail_initial
    call uart_print_str
    jmp .panic

.leak_fail_alloc:
    mov rsi, msg_leak_fail_alloc
    call uart_print_str
    jmp .panic

.leak_fail_count:
    mov rsi, msg_leak_fail_count
    call uart_print_str
    jmp .panic

.leak_fail_verify:
    mov rsi, msg_leak_fail_verify
    call uart_print_str
    jmp .panic

.leak_fail_final:
    mov rsi, msg_leak_fail_final
    call uart_print_str
    jmp .panic


.ipc_fail_pml4:
    mov rsi, msg_ipc_fail_pml4
    call uart_print_str
    jmp .panic

.ipc_fail_alloc:
    mov rsi, msg_ipc_fail_alloc
    call uart_print_str
    jmp .panic

.ipc_fail_map:
    mov rsi, msg_ipc_fail_map
    call uart_print_str
    jmp .panic

.ipc_fail_share:
    mov rsi, msg_ipc_fail_share
    call uart_print_str
    jmp .panic

.ipc_fail_shared_val:
    mov cr3, r14                    ; restore original CR3
    mov rsi, msg_ipc_fail_shared_val
    call uart_print_str
    jmp .panic

.ipc_fail_ring_create:
    mov rsi, msg_ipc_fail_ring_create
    call uart_print_str
    jmp .panic

.ipc_fail_ring_val:
    mov rsi, msg_ipc_fail_ring_val
    call uart_print_str
    jmp .panic

.ipc_fail_ring_cross_val:
    mov rsi, msg_ipc_fail_ring_cross_val
    call uart_print_str
    jmp .panic


.mmap_fail_create:
    mov rsi, msg_mmap_fail_create
    call uart_print_str
    jmp .panic

.mmap_fail_map:
    mov rsi, msg_mmap_fail_map
    call uart_print_str
    jmp .panic

.mmap_fail_read_val:
    mov rsi, msg_mmap_fail_read_val
    call uart_print_str
    jmp .panic

.mmap_fail_read_offset:
    mov rsi, msg_mmap_fail_read_offset
    call uart_print_str
    jmp .panic

.mmap_fail_pte:
    mov rsi, msg_mmap_fail_pte
    call uart_print_str
    jmp .panic

.mmap_fail_dirty:
    mov rsi, msg_mmap_fail_dirty
    call uart_print_str
    jmp .panic

.mmap_fail_sync:
    mov rsi, msg_mmap_fail_sync
    call uart_print_str
    jmp .panic

.mmap_fail_not_cleared:
    mov rsi, msg_mmap_fail_not_cleared
    call uart_print_str
    jmp .panic

.mmap_fail_backing:
    mov rsi, msg_mmap_fail_backing
    call uart_print_str
    jmp .panic

.mmap_fail_backing_data:
    mov rsi, msg_mmap_fail_backing_data
    call uart_print_str
    jmp .panic

.mmap_fail_unmap:
    mov rsi, msg_mmap_fail_unmap
    call uart_print_str
    jmp .panic


.smep_smap_fail_alloc:
    mov rsi, msg_smep_smap_fail_alloc_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_vma:
    mov rdi, r12
    call phys_free_page
    mov rsi, msg_smep_smap_fail_vma_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_map:
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_smep_smap_fail_map_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_copy_to:
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_smep_smap_fail_copy_to_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_copy_from:
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_smep_smap_fail_copy_from_str
    call uart_print_str
    jmp .panic

.smep_smap_fail_data:
    mov rdi, 0x40000000
    call virt_unmap
    mov rdi, r12
    call phys_free_page
    mov rdi, r13
    call vma_destroy
    mov rsi, msg_smep_smap_fail_data_str
    call uart_print_str
    jmp .panic

.numa_fail_count:
    mov rsi, msg_numa_fail_count_str
    call uart_print_str
    jmp .panic

.numa_fail_lookup_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_lookup:
    mov rsi, msg_numa_fail_lookup_str
    call uart_print_str
    jmp .panic

.numa_fail_distance_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_distance_bounds:
    mov rsi, msg_numa_fail_dist_bounds_str
    call uart_print_str
    jmp .panic

.numa_fail_bitmaps_init_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_bitmaps_init:
    mov rsi, msg_numa_fail_bmp_init_str
    call uart_print_str
    jmp .panic

.numa_fail_alloc_node_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_alloc_node:
    mov rsi, msg_numa_fail_alloc_node_str
    call uart_print_str
    jmp .panic

.numa_fail_node_affinity_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_node_affinity:
    mov rsi, msg_numa_fail_affinity_str
    call uart_print_str
    jmp .panic

.numa_fail_fallback_alloc_pop:
    pop r14
    pop r13
    pop r12
.numa_fail_fallback_alloc:
    mov rsi, msg_numa_fail_fallback_str
    call uart_print_str
    jmp .panic

.numa_fail_sim_oom_alloc_pop:
    pop rax
    mov [numa_nodes + numa_node_t.end_page], rax
    pop r14
    pop r13
    pop r12
.numa_fail_sim_oom_alloc:
    mov rsi, msg_numa_fail_sim_oom_alloc_str
    call uart_print_str
    jmp .panic

.numa_fail_sim_oom_affinity_pop:
    mov rdi, r14
    call phys_free_page
    pop rax
    mov [numa_nodes + numa_node_t.end_page], rax
    pop r14
    pop r13
    pop r12
.numa_fail_sim_oom_affinity:
    mov rsi, msg_numa_fail_sim_oom_affinity_str
    call uart_print_str
    jmp .panic



.memmove_fail_alloc:
    pop r12
    mov rsi, msg_memmove_fail_alloc_str
    call uart_print_str
    jmp .panic

.memmove_fail_ret:
    pop r12
    mov rsi, msg_memmove_fail_ret_str
    call uart_print_str
    jmp .panic

.memmove_fail_data:
    pop r12
    mov rsi, msg_memmove_fail_data_str
    call uart_print_str
    jmp .panic

.run_match_case:
    mov rdi, r12
    mov rsi, r13
    mov rdx, rcx
    call memcmp
    test rax, rax
    jnz .memcmp_fail_match_pop
    ret

.memcmp_fail_match_pop:
    pop rax                         ; clean up call return address
    pop r14
    pop r13
    pop r12
    jmp .memcmp_fail_match

.memcmp_fail_mismatch_val:
    pop r14
    pop r13
    pop r12
    jmp .memcmp_fail_mismatch

.memcmp_fail_alloc:
    pop r14
    pop r13
    pop r12
    mov rsi, msg_memcmp_fail_alloc_str
    call uart_print_str
    jmp .panic

.memcmp_fail_match:
    mov rsi, msg_memcmp_fail_match_str
    call uart_print_str
    jmp .panic

.memcmp_fail_mismatch:
    mov rsi, msg_memcmp_fail_mismatch_str
    call uart_print_str
    jmp .panic

.run_one_memzero_case:
    push rcx

    ; 1. Reset destination buffer with sentinel values (1..128)
    mov rdi, r12
    xor rdx, rdx
.sentinel_loop_memzero:
    mov r8b, dl
    inc r8b
    mov [rdi + rdx], r8b
    inc rdx
    cmp rdx, 128
    jb .sentinel_loop_memzero

    ; 2. Call memzero(r12, rcx)
    mov rdi, r12
    mov rsi, rcx                    ; RSI = size N
    call memzero                    ; RAX = dest pointer

    ; 3. Verify return value
    cmp rax, r12
    jne .memzero_fail_ret_pop

    ; Restore parameters for verification
    mov rcx, [rsp]                  ; RCX = size N

    ; 4. Verify first N bytes match 0
    test rcx, rcx
    jz .check_tail_memzero          ; if N == 0, skip checking payload
    xor rdx, rdx                    ; RDX = index i
.payload_loop_memzero:
    mov al, [r12 + rdx]
    test al, al
    jnz .memzero_fail_data_pop
    inc rdx
    cmp rdx, rcx
    jb .payload_loop_memzero

.check_tail_memzero:
    mov rcx, [rsp]                  ; RCX = size N
    ; 5. Verify remaining 128-N bytes are original sentinels (i + 1)
    mov rdx, rcx                    ; RDX = index i = N
.tail_loop_memzero:
    cmp rdx, 128
    jae .done_case_memzero
    mov al, [r12 + rdx]
    mov r8b, dl
    inc r8b                         ; R8B = index + 1
    cmp al, r8b                     ; Dst[i] must be i + 1
    jne .memzero_fail_extra_pop
    inc rdx
    jmp .tail_loop_memzero

.done_case_memzero:
    pop rcx
    ret

.memzero_fail_ret_pop:
    pop rcx
    pop r13
    pop r12
    jmp .memzero_fail_ret

.memzero_fail_data_pop:
    pop rcx
    pop r13
    pop r12
    jmp .memzero_fail_data

.memzero_fail_extra_pop:
    pop rcx
    pop r13
    pop r12
    jmp .memzero_fail_extra

.memzero_fail_alloc:
    pop r13
    pop r12
    mov rsi, msg_memzero_fail_alloc_str
    call uart_print_str
    jmp .panic

.memzero_fail_ret:
    mov rsi, msg_memzero_fail_ret_str
    call uart_print_str
    jmp .panic

.memzero_fail_data:
    mov rsi, msg_memzero_fail_data_str
    call uart_print_str
    jmp .panic

.memzero_fail_extra:
    mov rsi, msg_memzero_fail_extra_str
    call uart_print_str
    jmp .panic

.run_one_memset_case:
    push rcx
    push rsi

    ; 1. Reset destination buffer with sentinel values (0..127)
    mov rdi, r12
    xor rdx, rdx
.sentinel_loop:
    mov [rdi + rdx], dl
    inc rdx
    cmp rdx, 128
    jb .sentinel_loop

    ; 2. Call memset(r12, rsi, rcx)
    mov rdi, r12
    ; RSI is already the fill byte
    mov rdx, rcx                    ; RDX = size N
    call memset                     ; RAX = dest pointer

    ; 3. Verify return value
    cmp rax, r12
    jne .memset_fail_ret_pop

    ; Restore parameters for verification
    mov rcx, [rsp + 8]              ; RCX = size N
    mov rsi, [rsp]                  ; RSI = fill byte

    ; 4. Verify first N bytes match the fill value
    test rcx, rcx
    jz .check_tail_memset           ; if N == 0, skip checking payload
    xor rdx, rdx                    ; RDX = index i
.payload_loop_memset:
    mov al, [r12 + rdx]
    cmp al, sil
    jne .memset_fail_data_pop
    inc rdx
    cmp rdx, rcx
    jb .payload_loop_memset

.check_tail_memset:
    mov rcx, [rsp + 8]              ; RCX = size N
    ; 5. Verify remaining 128-N bytes are original sentinels (i)
    mov rdx, rcx                    ; RDX = index i = N
.tail_loop_memset:
    cmp rdx, 128
    jae .done_case_memset
    mov al, [r12 + rdx]
    cmp al, dl                      ; Dst[i] must be i
    jne .memset_fail_extra_pop
    inc rdx
    jmp .tail_loop_memset

.done_case_memset:
    pop rsi
    pop rcx
    ret

.memset_fail_ret_pop:
    pop rsi
    pop rcx
    pop r13
    pop r12
    jmp .memset_fail_ret

.memset_fail_data_pop:
    pop rsi
    pop rcx
    pop r13
    pop r12
    jmp .memset_fail_data

.memset_fail_extra_pop:
    pop rsi
    pop rcx
    pop r13
    pop r12
    jmp .memset_fail_extra

.memset_fail_alloc:
    pop r13
    pop r12
    mov rsi, msg_memset_fail_alloc_str
    call uart_print_str
    jmp .panic

.memset_fail_ret:
    mov rsi, msg_memset_fail_ret_str
    call uart_print_str
    jmp .panic

.memset_fail_data:
    mov rsi, msg_memset_fail_data_str
    call uart_print_str
    jmp .panic

.memset_fail_extra:
    mov rsi, msg_memset_fail_extra_str
    call uart_print_str
    jmp .panic

.run_one_memcpy_case:
    push rcx

    ; Zero out destination buffer (128 bytes)
    mov rdi, r13
    mov rdx, 128
.zero_loop:
    mov byte [rdi], 0
    inc rdi
    dec rdx
    jnz .zero_loop

    ; Call memcpy(r13, r12, rcx)
    mov rdi, r13
    mov rsi, r12
    pop rdx                         ; RDX = size N
    push rdx                        ; save for verification
    call memcpy                     ; RAX = dest pointer

    ; Verify return value
    cmp rax, r13
    jne .memcpy_fail_ret_pop

    pop rdx                         ; RDX = size N
    push rdx

    ; Verify first N bytes match
    test rdx, rdx
    jz .check_tail                  ; if N == 0, skip checking payload
    xor rcx, rcx                    ; RCX = index i
.payload_loop:
    mov al, [r13 + rcx]
    cmp al, cl                      ; since Src[i] == i, [r13 + i] must be i
    jne .memcpy_fail_data_pop
    inc rcx
    cmp rcx, rdx
    jb .payload_loop

.check_tail:
    pop rdx                         ; RDX = size N
    push rdx
    ; Verify remaining 128-N bytes are 0
    mov rcx, rdx                    ; RCX = index i = N
.tail_loop:
    cmp rcx, 128
    jae .done_case
    mov al, [r13 + rcx]
    test al, al
    jnz .memcpy_fail_extra_pop
    inc rcx
    jmp .tail_loop

.done_case:
    pop rdx
    ret

.memcpy_fail_ret_pop:
    pop rdx
    pop r13
    pop r12
    jmp .memcpy_fail_ret

.memcpy_fail_data_pop:
    pop rdx
    pop r13
    pop r12
    jmp .memcpy_fail_data

.memcpy_fail_extra_pop:
    pop rdx
    pop r13
    pop r12
    jmp .memcpy_fail_extra

.memcpy_fail_alloc:
    pop r13
    pop r12
    mov rsi, msg_memcpy_fail_alloc_str
    call uart_print_str
    jmp .panic

.memcpy_fail_ret:
    mov rsi, msg_memcpy_fail_ret_str
    call uart_print_str
    jmp .panic

.memcpy_fail_data:
    mov rsi, msg_memcpy_fail_data_str
    call uart_print_str
    jmp .panic

.memcpy_fail_extra:
    mov rsi, msg_memcpy_fail_extra_str
    call uart_print_str
    jmp .panic

.pool_fail_grow_alloc:
    pop rbp
    mov rsi, msg_pool_fail_grow_alloc_str
    call uart_print_str
    jmp .panic

.pool_fail_capacity_grow:
    pop rbp
    mov rsi, msg_pool_fail_capacity_grow_str
    call uart_print_str
    jmp .panic

.pool_fail_count_grow:
    pop rbp
    mov rsi, msg_pool_fail_count_grow_str
    call uart_print_str
    jmp .panic

.pool_fail_alloc_pop:
    pop rbp
.pool_fail_alloc:
    mov rsi, msg_pool_fail_alloc_str
    call uart_print_str
    jmp .panic

.pool_fail_oom_pop:
    pop rbp
.pool_fail_oom:
    mov rsi, msg_pool_fail_oom_str
    call uart_print_str
    jmp .panic

.pool_fail_count_pop:
    pop rbp
.pool_fail_count:
    mov rsi, msg_pool_fail_count_str
    call uart_print_str
    jmp .panic

.pool_fail_free_list_pop:
    pop rbp
.pool_fail_free_list:
    mov rsi, msg_pool_fail_free_list_str
    call uart_print_str
    jmp .panic

.pool_fail_reuse_pop:
    pop rbp
.pool_fail_reuse:
    mov rsi, msg_pool_fail_reuse_str
    call uart_print_str
    jmp .panic

.pool_fail_safety_pop:
    pop rbp
.pool_fail_safety:
    mov rsi, msg_pool_fail_safety_str
    call uart_print_str
    jmp .panic

.pool_fail_tag_pop:
    pop rbp
.pool_fail_tag:
    mov rsi, msg_pool_fail_tag_str
    call uart_print_str
    jmp .panic

.pool_fail_create:
    mov rsi, msg_pool_fail_create_str
    call uart_print_str
    jmp .panic

.pool_fail_config:
    mov rsi, msg_pool_fail_config_str
    call uart_print_str
    jmp .panic

.pool_fail_ptr:
    mov rsi, msg_pool_fail_ptr_str
    call uart_print_str
    jmp .panic

.heap_fail_active:
    mov rsi, msg_heap_fail_active_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc:
    mov rsi, msg_heap_fail_alloc_str
    call uart_print_str
    jmp .panic

.heap_fail_align:
    mov rsi, msg_heap_fail_align_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc2:
    mov rsi, msg_heap_fail_alloc2_str
    call uart_print_str
    jmp .panic

.heap_fail_align2:
    mov rsi, msg_heap_fail_align2_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc3:
    mov rsi, msg_heap_fail_alloc3_str
    call uart_print_str
    jmp .panic

.heap_fail_align3:
    mov rsi, msg_heap_fail_align3_str
    call uart_print_str
    jmp .panic

.heap_fail_spacing:
    mov rsi, msg_heap_fail_spacing_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc_split:
    mov rsi, msg_heap_fail_alloc_split_str
    call uart_print_str
    jmp .panic

.heap_fail_split_ptr:
    mov rsi, msg_heap_fail_split_ptr_str
    call uart_print_str
    jmp .panic

.heap_fail_alloc_split2:
    mov rsi, msg_heap_fail_alloc_split2_str
    call uart_print_str
    jmp .panic

.heap_fail_split_rem:
    mov rsi, msg_heap_fail_split_rem_str
    call uart_print_str
    jmp .panic

.heap_fail_coalesce:
    mov rsi, msg_heap_fail_coalesce_str
    call uart_print_str
    jmp .panic

.heap_fail_coalesce_ptr:
    mov rsi, msg_heap_fail_coalesce_ptr_str
    call uart_print_str
    jmp .panic


.pat_skip_test:
    mov rsi, msg_pat_skipped_str
    call uart_print_str
    jmp .idle

.pat_fail_get:
    mov rsi, msg_pat_fail_get_str
    call uart_print_str
    jmp .panic

.pat_fail_wb_index:
    mov rsi, msg_pat_fail_wb_index_str
    call uart_print_str
    jmp .panic

.pat_fail_wt_index:
    mov rsi, msg_pat_fail_wt_index_str
    call uart_print_str
    jmp .panic

.pat_fail_wc_index:
    mov rsi, msg_pat_fail_wc_index_str
    call uart_print_str
    jmp .panic

.pat_fail_uc_index:
    mov rsi, msg_pat_fail_uc_index_str
    call uart_print_str
    jmp .panic

.pat_fail_set:
    mov rsi, msg_pat_fail_set_str
    call uart_print_str
    jmp .panic

.pat_fail_wc_swap:
    mov rsi, msg_pat_fail_wc_swap_str
    call uart_print_str
    jmp .panic

.pat_fail_wp_swap:
    mov rsi, msg_pat_fail_wp_swap_str
    call uart_print_str
    jmp .panic

.pat_fail_restore:
    mov rsi, msg_pat_fail_restore_str
    call uart_print_str
    jmp .panic

.pat_fail_restore_verify:
    mov rsi, msg_pat_fail_rest_ver_str
    call uart_print_str
    jmp .panic

.mtrr_fail_set:
    mov rsi, msg_mtrr_fail_set_str
    call uart_print_str
    jmp .panic

.mtrr_fail_get_active:
    mov rsi, msg_mtrr_fail_get_act_str
    call uart_print_str
    jmp .panic

.mtrr_fail_base:
    mov rsi, msg_mtrr_fail_base_str
    call uart_print_str
    jmp .panic

.mtrr_fail_size:
    mov rsi, msg_mtrr_fail_size_str
    call uart_print_str
    jmp .panic

.mtrr_fail_type:
    mov rsi, msg_mtrr_fail_type_str
    call uart_print_str
    jmp .panic

.mtrr_fail_disable:
    mov rsi, msg_mtrr_fail_disable_str
    call uart_print_str
    jmp .panic

.mtrr_fail_still_active:
    mov rsi, msg_mtrr_fail_still_act_str
    call uart_print_str
    jmp .panic

.zswap_fail_init_telemetry:
    mov rsi, msg_zswap_fail_init_tel_str
    call uart_print_str
    jmp .panic

.zswap_fail_alloc1:
    mov rsi, msg_zswap_fail_alloc1_str
    call uart_print_str
    jmp .panic

.zswap_fail_vma1:
    mov rsi, msg_zswap_fail_vma1_str
    call uart_print_str
    jmp .panic

.zswap_fail_map1:
    mov rsi, msg_zswap_fail_map1_str
    call uart_print_str
    jmp .panic

.zswap_fail_walk1:
    mov rsi, msg_zswap_fail_walk1_str
    call uart_print_str
    jmp .panic

.zswap_fail_evict1:
    mov rsi, msg_zswap_fail_evict1_str
    call uart_print_str
    jmp .panic

.zswap_fail_walk_ev1:
    mov rsi, msg_zswap_fail_walk_ev1_str
    call uart_print_str
    jmp .panic

.zswap_fail_still_present1:
    mov rsi, msg_zswap_fail_still_pres1_str
    call uart_print_str
    jmp .panic

.zswap_fail_not_swapped1:
    mov rsi, msg_zswap_fail_not_swap1_str
    call uart_print_str
    jmp .panic

.zswap_fail_not_zswapped1:
    mov rsi, msg_zswap_fail_not_zswap1_str
    call uart_print_str
    jmp .panic

.zswap_fail_telemetry1:
    mov rsi, msg_zswap_fail_telemetry1_str
    call uart_print_str
    jmp .panic

.zswap_fail_data_corrupt1:
    mov rsi, msg_zswap_fail_data1_str
    call uart_print_str
    jmp .panic

.zswap_fail_telemetry_res1:
    mov rsi, msg_zswap_fail_tel_res1_str
    call uart_print_str
    jmp .panic

.zswap_fail_alloc2:
    mov rsi, msg_zswap_fail_alloc2_str
    call uart_print_str
    jmp .panic

.zswap_fail_vma2:
    mov rsi, msg_zswap_fail_vma2_str
    call uart_print_str
    jmp .panic

.zswap_fail_map2:
    mov rsi, msg_zswap_fail_map2_str
    call uart_print_str
    jmp .panic

.zswap_fail_walk2:
    mov rsi, msg_zswap_fail_walk2_str
    call uart_print_str
    jmp .panic

.zswap_fail_evict2:
    mov rsi, msg_zswap_fail_evict2_str
    call uart_print_str
    jmp .panic

.zswap_fail_walk_ev2:
    mov rsi, msg_zswap_fail_walk_ev2_str
    call uart_print_str
    jmp .panic

.zswap_fail_still_present2:
    mov rsi, msg_zswap_fail_still_pres2_str
    call uart_print_str
    jmp .panic

.zswap_fail_not_swapped2:
    mov rsi, msg_zswap_fail_not_swap2_str
    call uart_print_str
    jmp .panic

.zswap_fail_is_zswapped2:
    mov rsi, msg_zswap_fail_is_zswap2_str
    call uart_print_str
    jmp .panic

.zswap_fail_telemetry2:
    mov rsi, msg_zswap_fail_telemetry2_str
    call uart_print_str
    jmp .panic

.zswap_fail_data_corrupt2:
    mov rsi, msg_zswap_fail_data2_str
    call uart_print_str
    jmp .panic

.rep_fail_init_count:
    mov rsi, msg_rep_fail_init_str
    call uart_print_str
    jmp .panic

.rep_fail_alloc:
    mov rsi, msg_rep_fail_alloc_str
    call uart_print_str
    jmp .panic

.rep_fail_vma:
    mov rsi, msg_rep_fail_vma_str
    call uart_print_str
    jmp .panic

.rep_fail_map:
    mov rsi, msg_rep_fail_map_str
    call uart_print_str
    jmp .panic

.rep_fail_active_count:
    mov rsi, msg_rep_fail_active_str
    call uart_print_str
    jmp .panic

.rep_fail_inactive_count:
    mov rsi, msg_rep_fail_inactive_str
    call uart_print_str
    jmp .panic

.rep_fail_active_count_inactive:
    mov rsi, msg_rep_fail_active_in_str
    call uart_print_str
    jmp .panic

.rep_fail_inactive_count_inactive:
    mov rsi, msg_rep_fail_inactive_in_str
    call uart_print_str
    jmp .panic

.rep_fail_active_count_back:
    mov rsi, msg_rep_fail_active_back_str
    call uart_print_str
    jmp .panic

.rep_fail_inactive_count_back:
    mov rsi, msg_rep_fail_inactive_back_str
    call uart_print_str
    jmp .panic

.rep_fail_final_count:
    mov rsi, msg_rep_fail_final_str
    call uart_print_str
    jmp .panic

.test_fail_vma:
    mov rsi, msg_fail_vma_str
    call uart_print_str
    jmp .panic

.test_fail_val:
    mov rsi, msg_fail_val_str
    call uart_print_str
    jmp .panic

.test_fail_addr:
    mov rsi, msg_fail_addr_str
    call uart_print_str
    jmp .panic

.cow_fail_alloc:
    mov rsi, msg_cow_fail_alloc_str
    call uart_print_str
    jmp .panic

.cow_fail_vma:
    mov rsi, msg_cow_fail_vma_str
    call uart_print_str
    jmp .panic

.cow_fail_map:
    mov rsi, msg_cow_fail_map_str
    call uart_print_str
    jmp .panic

.cow_fail_isolation:
    mov rsi, msg_cow_fail_iso_str
    call uart_print_str
    jmp .panic

.cow_fail_same_page:
    mov rsi, msg_cow_fail_same_str
    call uart_print_str
    jmp .panic

.zfod_fail_vma:
    mov rsi, msg_zfod_fail_vma_str
    call uart_print_str
    jmp .panic

.zfod_fail_read_val:
    mov rsi, msg_zfod_fail_read_str
    call uart_print_str
    jmp .panic

.zfod_fail_zero_ptr:
    mov rsi, msg_zfod_fail_ptr_str
    call uart_print_str
    jmp .panic

.zfod_fail_write_val:
    mov rsi, msg_zfod_fail_write_str
    call uart_print_str
    jmp .panic

.zfod_fail_isolation:
    mov rsi, msg_zfod_fail_iso_str
    call uart_print_str
    jmp .panic

.zfod_fail_same_page:
    mov rsi, msg_zfod_fail_same_str
    call uart_print_str
    jmp .panic

.zfod_fail_page2_val:
    mov rsi, msg_zfod_fail_p2val_str
    call uart_print_str
    jmp .panic

.zfod_fail_page2_same:
    mov rsi, msg_zfod_fail_p2same_str
    call uart_print_str
    jmp .panic

.stack_fail_vma:
    mov rsi, msg_stack_fail_vma_str
    call uart_print_str
    jmp .panic

.stack_fail_val:
    mov rsi, msg_stack_fail_val_str
    call uart_print_str
    jmp .panic

.stack_fail_map:
    mov rsi, msg_stack_fail_map_str
    call uart_print_str
    jmp .panic

.clock_fail_alloc:
    mov rsi, msg_clock_fail_alloc_str
    call uart_print_str
    jmp .panic

.clock_fail_vma:
    mov rsi, msg_clock_fail_vma_str
    call uart_print_str
    jmp .panic

.clock_fail_map:
    mov rsi, msg_clock_fail_map_str
    call uart_print_str
    jmp .panic

.clock_fail_inactive:
    mov rsi, msg_clock_fail_inactive_str
    call uart_print_str
    jmp .panic

.clock_fail_walk:
    mov rsi, msg_clock_fail_walk_str
    call uart_print_str
    jmp .panic

.clock_fail_evict:
    mov rsi, msg_clock_fail_evict_str
    call uart_print_str
    jmp .panic

.clock_fail_walk_evicted:
    mov rsi, msg_clock_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.clock_fail_still_present:
    mov rsi, msg_clock_fail_still_pres_str
    call uart_print_str
    jmp .panic

.clock_fail_not_swapped:
    mov rsi, msg_clock_fail_not_swap_str
    call uart_print_str
    jmp .panic

.clock_fail_stats:
    mov rsi, msg_clock_fail_stats_str
    call uart_print_str
    jmp .panic

.clock_fail_list_counts:
    mov rsi, msg_clock_fail_list_str
    call uart_print_str
    jmp .panic

.clock_fail_data_corrupt:
    mov rsi, msg_clock_fail_data_str
    call uart_print_str
    jmp .panic

.clock_fail_stats_restore:
    mov rsi, msg_clock_fail_stats_res_str
    call uart_print_str
    jmp .panic

.clock_fail_active_restore:
    mov rsi, msg_clock_fail_act_res_str
    call uart_print_str
    jmp .panic

.clock_fail_inactive_restore:
    mov rsi, msg_clock_fail_inact_res_str
    call uart_print_str
    jmp .panic

.ata_fail_alloc:
    mov rsi, msg_ata_fail_alloc_str
    call uart_print_str
    jmp .panic

.ata_fail_vma:
    mov rsi, msg_ata_fail_vma_str
    call uart_print_str
    jmp .panic

.ata_fail_map:
    mov rsi, msg_ata_fail_map_str
    call uart_print_str
    jmp .panic

.ata_fail_inactive:
    mov rsi, msg_ata_fail_inactive_str
    call uart_print_str
    jmp .panic

.ata_fail_walk:
    mov rsi, msg_ata_fail_walk_str
    call uart_print_str
    jmp .panic

.ata_fail_evict:
    mov rsi, msg_ata_fail_evict_str
    call uart_print_str
    jmp .panic

.ata_fail_walk_evicted:
    mov rsi, msg_ata_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.ata_fail_still_present:
    mov rsi, msg_ata_fail_still_pres_str
    call uart_print_str
    jmp .panic

.ata_fail_not_swapped:
    mov rsi, msg_ata_fail_not_swap_str
    call uart_print_str
    jmp .panic

.ata_fail_data_corrupt:
    mov rsi, msg_ata_fail_data_str
    call uart_print_str
    jmp .panic

.nvme_fail_alloc:
    mov rsi, msg_nvme_fail_alloc_str
    call uart_print_str
    jmp .panic

.nvme_fail_vma:
    mov rsi, msg_nvme_fail_vma_str
    call uart_print_str
    jmp .panic

.nvme_fail_map:
    mov rsi, msg_nvme_fail_map_str
    call uart_print_str
    jmp .panic

.nvme_fail_inactive:
    mov rsi, msg_nvme_fail_inactive_str
    call uart_print_str
    jmp .panic

.nvme_fail_walk:
    mov rsi, msg_nvme_fail_walk_str
    call uart_print_str
    jmp .panic

.nvme_fail_evict:
    mov rsi, msg_nvme_fail_evict_str
    call uart_print_str
    jmp .panic

.nvme_fail_walk_evicted:
    mov rsi, msg_nvme_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.nvme_fail_still_present:
    mov rsi, msg_nvme_fail_still_pres_str
    call uart_print_str
    jmp .panic

.nvme_fail_not_swapped:
    mov rsi, msg_nvme_fail_not_swap_str
    call uart_print_str
    jmp .panic

.nvme_fail_data_corrupt:
    mov rsi, msg_nvme_fail_data_str
    call uart_print_str
    jmp .panic

.kswapd_fail_alloc_setup:
    mov rsi, msg_kswapd_fail_alloc_setup_str
    call uart_print_str
    jmp .panic

.kswapd_fail_vma_setup:
    mov rsi, msg_kswapd_fail_vma_setup_str
    call uart_print_str
    jmp .panic

.kswapd_fail_map_setup:
    mov rsi, msg_kswapd_fail_map_setup_str
    call uart_print_str
    jmp .panic

.kswapd_fail_walk_setup:
    mov rsi, msg_kswapd_fail_walk_setup_str
    call uart_print_str
    jmp .panic

.kswapd_fail_alloc_trigger:
    mov rsi, msg_kswapd_fail_alloc_trigger_str
    call uart_print_str
    jmp .panic

.kswapd_fail_walk_evicted:
    mov rsi, msg_kswapd_fail_walk_ev_str
    call uart_print_str
    jmp .panic

.kswapd_fail_still_present:
    mov rsi, msg_kswapd_fail_still_pres_str
    call uart_print_str
    jmp .panic

.kswapd_fail_not_swapped:
    mov rsi, msg_kswapd_fail_not_swap_str
    call uart_print_str
    jmp .panic

.kswapd_fail_data_corrupt:
    mov rsi, msg_kswapd_fail_data_str
    call uart_print_str
    jmp .panic

.panic:
    mov rsi, msg_test_failed
    call uart_print_str
    cli
.hlt_loop:
    hlt
    jmp .hlt_loop

.idle:
    ; 4. Disable interrupts (no external interrupt handlers registered yet)
    cli

    ; 5. Enter CPU idle loop
.idle_loop:
    hlt                             ; halt the processor until next interrupt
    jmp .idle_loop                  ; jump back if an NMI or interrupt wakes us

; -----------------------------------------------------------------------------
; Messages
; -----------------------------------------------------------------------------
section .data

msg_kernel_ready:     db "Tattva Kernel Ready. Entering main execution.", 0x0D, 0x0A, 0
msg_test_start:       db "Running VMM On-Demand Paging Exception Test...", 0x0D, 0x0A, 0
msg_vma_ok:           db "VMA created at 0x70000000. Triggering read/write page fault...", 0x0D, 0x0A, 0
msg_crlf:             db 0x0D, 0x0A, 0
msg_test_passed:      db "VMM On-Demand Paging Test PASSED!", 0x0D, 0x0A, 0
msg_test_failed:      db "VMM Test Suite FAILED! Halting.", 0x0D, 0x0A, 0

msg_fail_vma_str:     db "Failure: Could not create on-demand VMA.", 0x0D, 0x0A, 0
msg_fail_val_str:     db "Failure: Resumed byte value is incorrect.", 0x0D, 0x0A, 0
msg_fail_addr_str:    db "Failure: Unique address verification at offset 32 failed.", 0x0D, 0x0A, 0

msg_cow_test_start:   db "Running VMM Copy-on-Write (COW) Exception Test...", 0x0D, 0x0A, 0
msg_cow_before_write: db "Initial mapping reads (expected COW_PARENT_ORIGINAL_DATA): ", 0
msg_cow_after_write:  db "After write, virtual page reads (expected CHILD_DATA): ", 0
msg_cow_parent_check: db "Parent physical page reads (expected COW_PARENT_ORIGINAL_DATA): ", 0
msg_cow_test_passed:  db "VMM Copy-on-Write (COW) Test PASSED!", 0x0D, 0x0A, 0

msg_cow_parent_data:  db "COW_PARENT_ORIGINAL_DATA", 0
msg_cow_child_data:   db "CHILD_DATA", 0

msg_cow_fail_alloc_str: db "Failure: Could not allocate physical page for COW parent.", 0x0D, 0x0A, 0
msg_cow_fail_vma_str:   db "Failure: Could not create COW VMA.", 0x0D, 0x0A, 0
msg_cow_fail_map_str:   db "Failure: Could not map COW parent page.", 0x0D, 0x0A, 0
msg_cow_fail_iso_str:   db "Failure: Isolation check failed! Parent or child data incorrect.", 0x0D, 0x0A, 0
msg_cow_fail_same_str:  db "Failure: Virtual address still maps to parent physical page (no COW allocate).", 0x0D, 0x0A, 0

msg_zfod_test_start:   db "Running VMM Zero-Fill-on-Demand (ZFOD) Exception Test...", 0x0D, 0x0A, 0
msg_zfod_read_ok:     db "ZFOD Page 1 read verify (returned 0). Shared zero page successfully mapped.", 0x0D, 0x0A, 0
msg_zfod_page1_ok:    db "ZFOD Page 1 write verify & isolation check passed.", 0x0D, 0x0A, 0
msg_zfod_test_passed:  db "VMM Zero-Fill-on-Demand (ZFOD) Test PASSED!", 0x0D, 0x0A, 0

msg_zfod_fail_vma_str:  db "Failure: Could not create ZFOD VMA.", 0x0D, 0x0A, 0
msg_zfod_fail_read_str: db "Failure: Initial ZFOD read returned non-zero value.", 0x0D, 0x0A, 0
msg_zfod_fail_ptr_str:  db "Failure: Shared zero page address pointer not initialized.", 0x0D, 0x0A, 0
msg_zfod_fail_write_str: db "Failure: Value read back from ZFOD Page 1 after write is incorrect.", 0x0D, 0x0A, 0
msg_zfod_fail_iso_str:   db "Failure: Shared zero page was modified by COW write!", 0x0D, 0x0A, 0
msg_zfod_fail_same_str:  db "Failure: Page 1 still maps to shared zero page after write.", 0x0D, 0x0A, 0
msg_zfod_fail_p2val_str: db "Failure: Value read back from ZFOD Page 2 after direct write is incorrect.", 0x0D, 0x0A, 0
msg_zfod_fail_p2same_str: db "Failure: Page 2 maps to shared zero page after direct write.", 0x0D, 0x0A, 0

msg_stack_test_start:  db "Running VMM Stack Auto-Grow Exception Test...", 0x0D, 0x0A, 0
msg_stack_test_passed: db "VMM Stack Auto-Grow Test PASSED!", 0x0D, 0x0A, 0

msg_stack_fail_vma_str: db "Failure: Could not create Stack Auto-Grow VMA.", 0x0D, 0x0A, 0
msg_stack_fail_val_str: db "Failure: Value read back from grown Stack address is incorrect.", 0x0D, 0x0A, 0
msg_stack_fail_map_str: db "Failure: Stack address not mapped in page table after write.", 0x0D, 0x0A, 0

msg_rep_test_start:            db "Running VMM Active/Inactive Page Lists Test...", 0x0D, 0x0A, 0
msg_rep_test_passed:           db "VMM Active/Inactive Page Lists Test PASSED!", 0x0D, 0x0A, 0
msg_rep_fail_init_str:         db "Failure: Initial active/inactive counts not 0.", 0x0D, 0x0A, 0
msg_rep_fail_alloc_str:        db "Failure: Could not allocate physical page for replacement test.", 0x0D, 0x0A, 0
msg_rep_fail_vma_str:          db "Failure: Could not create replacement test VMA.", 0x0D, 0x0A, 0
msg_rep_fail_map_str:          db "Failure: Could not map replacement test page.", 0x0D, 0x0A, 0
msg_rep_fail_active_str:       db "Failure: Page not tracked in active list after mapping.", 0x0D, 0x0A, 0
msg_rep_fail_inactive_str:     db "Failure: Inactive count non-zero after mapping to active.", 0x0D, 0x0A, 0
msg_rep_fail_active_in_str:    db "Failure: Active count non-zero after moving to inactive.", 0x0D, 0x0A, 0
msg_rep_fail_inactive_in_str:  db "Failure: Inactive count not 1 after moving to inactive.", 0x0D, 0x0A, 0
msg_rep_fail_active_back_str:  db "Failure: Active count not 1 after moving back to active.", 0x0D, 0x0A, 0
msg_rep_fail_inactive_back_str:db "Failure: Inactive count non-zero after moving back to active.", 0x0D, 0x0A, 0
msg_rep_fail_final_str:        db "Failure: Counts non-zero after unmapping page.", 0x0D, 0x0A, 0

msg_clock_test_start:          db "Running VMM Clock/Second-Chance Eviction Test...", 0x0D, 0x0A, 0
msg_clock_evicted_ok:          db "Clock eviction successful. Page marked swapped in PTE and physical frame freed.", 0x0D, 0x0A, 0
msg_clock_test_passed:         db "VMM Clock/Second-Chance Eviction Test PASSED!", 0x0D, 0x0A, 0
msg_clock_test_data:           db "SWAP_MOCK_TEST_DATA", 0

msg_clock_fail_alloc_str:      db "Failure: Could not allocate physical page for clock test.", 0x0D, 0x0A, 0
msg_clock_fail_vma_str:        db "Failure: Could not create VMA for clock test.", 0x0D, 0x0A, 0
msg_clock_fail_map_str:        db "Failure: Could not map page for clock test.", 0x0D, 0x0A, 0
msg_clock_fail_inactive_str:   db "Failure: Page not in inactive list before eviction.", 0x0D, 0x0A, 0
msg_clock_fail_walk_str:       db "Failure: Could not walk page table for virtual address.", 0x0D, 0x0A, 0
msg_clock_fail_evict_str:      db "Failure: Clock eviction routine returned failure.", 0x0D, 0x0A, 0
msg_clock_fail_walk_ev_str:    db "Failure: Walk failed for evicted page virtual address.", 0x0D, 0x0A, 0
msg_clock_fail_still_pres_str: db "Failure: Evicted page is still marked present in PTE.", 0x0D, 0x0A, 0
msg_clock_fail_not_swap_str:   db "Failure: Evicted page does not have PAGE_SWAPPED set in PTE.", 0x0D, 0x0A, 0
msg_clock_fail_stats_str:      db "Failure: Swap pages telemetry count not 1 after eviction.", 0x0D, 0x0A, 0
msg_clock_fail_list_str:       db "Failure: Active or inactive counts not 0 after eviction.", 0x0D, 0x0A, 0
msg_clock_fail_data_str:       db "Failure: Swapped-in data is corrupt or mismatch.", 0x0D, 0x0A, 0
msg_clock_fail_stats_res_str:  db "Failure: Telemetry swap pages count not 0 after swap-in.", 0x0D, 0x0A, 0
msg_clock_fail_act_res_str:    db "Failure: Active list count not 1 after swap-in.", 0x0D, 0x0A, 0
msg_clock_fail_inact_res_str:  db "Failure: Inactive list count not 0 after swap-in.", 0x0D, 0x0A, 0

msg_ata_test_start:            db "Running VMM ATA Swap Partition Test...", 0x0D, 0x0A, 0
msg_ata_test_passed:           db "VMM ATA Swap Partition Test PASSED!", 0x0D, 0x0A, 0
msg_ata_test_data:             db "MOCK_ATA_SWAP_DATA", 0

msg_ata_fail_alloc_str:        db "Failure: Could not allocate page for ATA swap test.", 0x0D, 0x0A, 0
msg_ata_fail_vma_str:          db "Failure: Could not create VMA for ATA swap test.", 0x0D, 0x0A, 0
msg_ata_fail_map_str:          db "Failure: Could not map page for ATA swap test.", 0x0D, 0x0A, 0
msg_ata_fail_inactive_str:     db "Failure: Page not inactive before ATA eviction.", 0x0D, 0x0A, 0
msg_ata_fail_walk_str:         db "Failure: Could not walk page table for ATA test.", 0x0D, 0x0A, 0
msg_ata_fail_evict_str:        db "Failure: ATA eviction command returned error.", 0x0D, 0x0A, 0
msg_ata_fail_walk_ev_str:      db "Failure: Walk failed for ATA evicted address.", 0x0D, 0x0A, 0
msg_ata_fail_still_pres_str:   db "Failure: Page still present after ATA eviction.", 0x0D, 0x0A, 0
msg_ata_fail_not_swap_str:     db "Failure: Page not marked swapped in ATA PTE.", 0x0D, 0x0A, 0
msg_ata_fail_data_str:         db "Failure: Swapped-in data corrupt on ATA partition.", 0x0D, 0x0A, 0

msg_nvme_test_start:           db "Running VMM Direct NVMe Swap Queue Test...", 0x0D, 0x0A, 0
msg_nvme_test_passed:          db "VMM Direct NVMe Swap Queue Test PASSED!", 0x0D, 0x0A, 0
msg_nvme_test_data:            db "MOCK_NVME_SWAP_DATA", 0

msg_nvme_fail_alloc_str:       db "Failure: Could not allocate page for NVMe swap test.", 0x0D, 0x0A, 0
msg_nvme_fail_vma_str:         db "Failure: Could not create VMA for NVMe swap test.", 0x0D, 0x0A, 0
msg_nvme_fail_map_str:         db "Failure: Could not map page for NVMe swap test.", 0x0D, 0x0A, 0
msg_nvme_fail_inactive_str:    db "Failure: Page not inactive before NVMe eviction.", 0x0D, 0x0A, 0
msg_nvme_fail_walk_str:        db "Failure: Could not walk page table for NVMe test.", 0x0D, 0x0A, 0
msg_nvme_fail_evict_str:       db "Failure: NVMe eviction command returned error.", 0x0D, 0x0A, 0
msg_nvme_fail_walk_ev_str:     db "Failure: Walk failed for NVMe evicted address.", 0x0D, 0x0A, 0
msg_nvme_fail_still_pres_str:  db "Failure: Page still present after NVMe eviction.", 0x0D, 0x0A, 0
msg_nvme_fail_not_swap_str:    db "Failure: Page not marked swapped in NVMe PTE.", 0x0D, 0x0A, 0
msg_nvme_fail_data_str:        db "Failure: Swapped-in data corrupt on NVMe queue.", 0x0D, 0x0A, 0

msg_kswapd_test_start:         db "Running VMM Page-Out Daemon (kswapd) Watermark Test...", 0x0D, 0x0A, 0
msg_kswapd_test_passed:        db "VMM Page-Out Daemon (kswapd) Watermark Test PASSED!", 0x0D, 0x0A, 0
msg_kswapd_test_data:          db "MOCK_KSWAPD_SWAP_DATA", 0

msg_kswapd_fail_alloc_setup_str: db "Failure: Setup physical page allocation failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_vma_setup_str:   db "Failure: Setup VMA creation failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_map_setup_str:   db "Failure: Setup virtual mapping failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_walk_setup_str:  db "Failure: Setup page table walk failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_alloc_trigger_str: db "Failure: Allocation with watermark trigger failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_walk_ev_str:     db "Failure: Evicted walk failed.", 0x0D, 0x0A, 0
msg_kswapd_fail_still_pres_str:  db "Failure: Page still present after kswapd eviction.", 0x0D, 0x0A, 0
msg_kswapd_fail_not_swap_str:    db "Failure: Page not marked swapped after kswapd eviction.", 0x0D, 0x0A, 0
msg_kswapd_fail_data_str:        db "Failure: Swapped-in data corrupt after kswapd reclaim.", 0x0D, 0x0A, 0

msg_zswap_test_start:         db "Running VMM Zswap Compressed Cache Test...", 0x0D, 0x0A, 0
msg_zswap_evicted_ok:         db "Zswap eviction successful: page compressed and stored in RAM cache.", 0x0D, 0x0A, 0
msg_zswap_comp_passed:        db "Zswap Compressible Page Test PASSED!", 0x0D, 0x0A, 0
msg_zswap_disk_evicted_ok:    db "Zswap uncompressible bypass successful: page evicted directly to disk.", 0x0D, 0x0A, 0
msg_zswap_test_passed:        db "VMM Zswap Compressed Cache Test PASSED!", 0x0D, 0x0A, 0

msg_zswap_comp_sig:           db "COMPRESSIBLE_SIG", 0
msg_zswap_uncomp_sig:         db "UNCOMPRESSIBLE_SIG", 0

msg_zswap_fail_init_tel_str:  db "Failure: Initial Zswap telemetry is not 0.", 0x0D, 0x0A, 0
msg_zswap_fail_alloc1_str:     db "Failure: Could not allocate physical page for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_vma1_str:       db "Failure: Could not create VMA for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_map1_str:       db "Failure: Could not map page for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_walk1_str:      db "Failure: Could not walk page table for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_evict1_str:     db "Failure: clock eviction failed for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_walk_ev1_str:   db "Failure: walk failed after eviction for Zswap Part 1.", 0x0D, 0x0A, 0
msg_zswap_fail_still_pres1_str:db "Failure: Zswap page still present after clock eviction.", 0x0D, 0x0A, 0
msg_zswap_fail_not_swap1_str:  db "Failure: Zswap page does not have PAGE_SWAPPED set.", 0x0D, 0x0A, 0
msg_zswap_fail_not_zswap1_str: db "Failure: Zswap page does not have PAGE_ZSWAPPED set.", 0x0D, 0x0A, 0
msg_zswap_fail_telemetry1_str: db "Failure: Zswap compressed pages telemetry is not 1 after eviction.", 0x0D, 0x0A, 0
msg_zswap_fail_data1_str:      db "Failure: Decompressed data is corrupt or signature mismatch.", 0x0D, 0x0A, 0
msg_zswap_fail_tel_res1_str:   db "Failure: Zswap compressed pages telemetry did not return to 0.", 0x0D, 0x0A, 0

msg_zswap_fail_alloc2_str:     db "Failure: Could not allocate physical page for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_vma2_str:       db "Failure: Could not create VMA for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_map2_str:       db "Failure: Could not map page for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_walk2_str:      db "Failure: Could not walk page table for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_evict2_str:     db "Failure: clock eviction failed for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_walk_ev2_str:   db "Failure: walk failed after eviction for Zswap Part 2.", 0x0D, 0x0A, 0
msg_zswap_fail_still_pres2_str:db "Failure: Page still present after disk bypass eviction.", 0x0D, 0x0A, 0
msg_zswap_fail_not_swap2_str:  db "Failure: Page does not have PAGE_SWAPPED set after disk bypass eviction.", 0x0D, 0x0A, 0
msg_zswap_fail_is_zswap2_str:  db "Failure: Page has PAGE_ZSWAPPED set but should have bypassed Zswap.", 0x0D, 0x0A, 0
msg_zswap_fail_telemetry2_str: db "Failure: Zswap telemetry non-zero for uncompressible page.", 0x0D, 0x0A, 0
msg_zswap_fail_data2_str:      db "Failure: Swapped-in data from disk bypass is corrupt or mismatch.", 0x0D, 0x0A, 0

msg_mtrr_test_start:         db "Running VMM MTRR Cache Programming Test...", 0x0D, 0x0A, 0
msg_mtrr_vcnt_str:            db "MTRR supported. Count of variable registers: ", 0
msg_mtrr_test_passed:         db "VMM MTRR Cache Programming Test PASSED!", 0x0D, 0x0A, 0
msg_mtrr_skipped_str:         db "MTRR Cache Programming Test skipped: MTRRs not supported.", 0x0D, 0x0A, 0

msg_mtrr_fail_set_str:        db "Failure: mtrr_set_variable returned 0.", 0x0D, 0x0A, 0
msg_mtrr_fail_get_act_str:    db "Failure: mtrr_get_variable returned 0 for active slot.", 0x0D, 0x0A, 0
msg_mtrr_fail_base_str:       db "Failure: mtrr_get_variable returned incorrect base.", 0x0D, 0x0A, 0
msg_mtrr_fail_size_str:       db "Failure: mtrr_get_variable returned incorrect size.", 0x0D, 0x0A, 0
msg_mtrr_fail_type_str:       db "Failure: mtrr_get_variable returned incorrect type.", 0x0D, 0x0A, 0
msg_mtrr_fail_disable_str:    db "Failure: mtrr_disable_variable returned 0.", 0x0D, 0x0A, 0
msg_mtrr_fail_still_act_str:  db "Failure: mtrr_get_variable indicates slot is active after disable.", 0x0D, 0x0A, 0

; PAT Configuration Test messages
msg_pat_test_start:         db "Running VMM PAT Cache Configuration Test...", 0x0D, 0x0A, 0
msg_pat_test_passed:        db "VMM PAT Cache Configuration Test PASSED!", 0x0D, 0x0A, 0
msg_pat_skipped_str:        db "PAT Cache Configuration Test skipped: PAT not supported.", 0x0D, 0x0A, 0
msg_pat_fail_get_str:       db "Failure: pat_get_msr returned 0.", 0x0D, 0x0A, 0
msg_pat_fail_wb_index_str:  db "Failure: WB index search returned incorrect slot.", 0x0D, 0x0A, 0
msg_pat_fail_wt_index_str:  db "Failure: WT index search returned incorrect slot.", 0x0D, 0x0A, 0
msg_pat_fail_wc_index_str:  db "Failure: WC index search returned incorrect slot.", 0x0D, 0x0A, 0
msg_pat_fail_uc_index_str:  db "Failure: UC index search returned incorrect slot.", 0x0D, 0x0A, 0
msg_pat_fail_set_str:       db "Failure: pat_set_msr returned 0.", 0x0D, 0x0A, 0
msg_pat_fail_wc_swap_str:   db "Failure: WC index search returned incorrect slot after swap.", 0x0D, 0x0A, 0
msg_pat_fail_wp_swap_str:   db "Failure: WP index search returned incorrect slot after swap.", 0x0D, 0x0A, 0
msg_pat_fail_restore_str:   db "Failure: pat_set_msr returned 0 during restore.", 0x0D, 0x0A, 0
msg_pat_fail_rest_ver_str:  db "Failure: WC index search returned incorrect slot after restore.", 0x0D, 0x0A, 0

; Write-Combining Framebuffer messages
msg_fb_test_start_str:      db "Running VMM Write-Combining Video Buffer mapping test...", 0x0D, 0x0A, 0
msg_fb_test_passed_str:     db "VMM Write-Combining Video Buffer mapping test PASSED!", 0x0D, 0x0A, 0
msg_fb_skipped_str:         db "Write-Combining Video Buffer test skipped: No linear framebuffer.", 0x0D, 0x0A, 0
msg_fb_fail_init_str:       db "Failure: Framebuffer mapping initialization failed.", 0x0D, 0x0A, 0
msg_fb_fail_bench_str:      db "Failure: Framebuffer write speed benchmark failed.", 0x0D, 0x0A, 0

; General-Purpose Heap Allocator messages
msg_heap_test_start:        db "Running General-Purpose Heap Allocator Test...", 0x0D, 0x0A, 0
msg_heap_test_passed:       db "General-Purpose Heap Allocator Test PASSED!", 0x0D, 0x0A, 0
msg_heap_fail_active_str:   db "Failure: Heap allocator was not transitioned to free-list mode.", 0x0D, 0x0A, 0
msg_heap_fail_alloc_str:    db "Failure: First heap allocation (64 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_align_str:    db "Failure: First heap allocation pointer is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_heap_fail_alloc2_str:   db "Failure: Second heap allocation (64 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_align2_str:   db "Failure: Second heap allocation pointer is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_heap_fail_alloc3_str:   db "Failure: Third heap allocation (64 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_align3_str:   db "Failure: Third heap allocation pointer is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_heap_fail_spacing_str:  db "Failure: Heap block spacing does not match block_size + header_size.", 0x0D, 0x0A, 0
msg_heap_fail_alloc_split_str: db "Failure: Split heap allocation (16 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_split_ptr_str: db "Failure: Split allocation did not reuse original block B start address.", 0x0D, 0x0A, 0
msg_heap_fail_alloc_split2_str: db "Failure: Second split allocation (16 bytes) returned null.", 0x0D, 0x0A, 0
msg_heap_fail_split_rem_str: db "Failure: Second split did not return expected remainder address (B+48).", 0x0D, 0x0A, 0
msg_heap_fail_coalesce_str:  db "Failure: Allocation (256 bytes) from coalesced block returned null.", 0x0D, 0x0A, 0
msg_heap_fail_coalesce_ptr_str: db "Failure: Coalesced allocation did not return block A start address.", 0x0D, 0x0A, 0

; Heap Defragmenter Test Variables & Messages
align 8
ptr_A: dq 0
ptr_B: dq 0
ptr_C: dq 0

msg_defrag_test_start:         db "Running VMM Heap Compaction/Defragmentation Test...", 0x0D, 0x0A, 0
msg_defrag_test_passed:        db "VMM Heap Compaction/Defragmentation Test PASSED!", 0x0D, 0x0A, 0
msg_defrag_fail_alloc_A_str:   db "Failure: Allocation A returned null.", 0x0D, 0x0A, 0
msg_defrag_fail_alloc_B_str:   db "Failure: Allocation B returned null.", 0x0D, 0x0A, 0
msg_defrag_fail_alloc_C_str:   db "Failure: Allocation C returned null.", 0x0D, 0x0A, 0
msg_defrag_fail_reg_str:       db "Failure: Pointer registration returned 0.", 0x0D, 0x0A, 0
msg_defrag_fail_compact_str:   db "Failure: heap_compact returned 0.", 0x0D, 0x0A, 0
msg_defrag_fail_assert_A_str:  db "Failure: A was moved or corrupted during compaction.", 0x0D, 0x0A, 0
msg_defrag_fail_assert_C_str:  db "Failure: C pointer was not updated to B's old address.", 0x0D, 0x0A, 0

; Slab Allocator Test Messages
msg_slab_test_start:         db "Running VMM Slab Allocator Cache Definitions Test...", 0x0D, 0x0A, 0
msg_slab_test_passed:        db "VMM Slab Allocator Cache Definitions Test PASSED!", 0x0D, 0x0A, 0
msg_slab_fail_name_str:      db "Failure: Slab cache name is missing or incorrect.", 0x0D, 0x0A, 0
msg_slab_fail_size_str:      db "Failure: Slab cache object size verification failed.", 0x0D, 0x0A, 0
msg_slab_fail_align_str:     db "Failure: Slab cache alignment verification failed.", 0x0D, 0x0A, 0
msg_slab_fail_lists_str:     db "Failure: Slab cache slab lists are not empty.", 0x0D, 0x0A, 0

; Slab Lists Tracking & Grow Test Messages
msg_slab_grow_test_start:      db "Running VMM Slab Lists Tracking & Grow Test...", 0x0D, 0x0A, 0
msg_slab_grow_test_passed:     db "VMM Slab Lists Tracking & Grow Test PASSED!", 0x0D, 0x0A, 0
msg_slab_fail_grow_str:        db "Failure: kmem_slab_grow returned NULL.", 0x0D, 0x0A, 0
msg_slab_fail_free_list_str:   db "Failure: New slab was not added to the slabs_free list.", 0x0D, 0x0A, 0
msg_slab_fail_magic_str:       db "Failure: Slab magic number is incorrect or corrupt.", 0x0D, 0x0A, 0
msg_slab_fail_count_str:       db "Failure: Slab object capacity (obj_count) is incorrect.", 0x0D, 0x0A, 0
msg_slab_fail_used_str:        db "Failure: New slab used_count is non-zero.", 0x0D, 0x0A, 0
msg_slab_fail_free_head_str:   db "Failure: New slab free_head does not point to mem_start.", 0x0D, 0x0A, 0
msg_slab_fail_free_chain_str:  db "Failure: Slab free objects chain link verification failed.", 0x0D, 0x0A, 0
msg_slab_fail_transition_str:  db "Failure: Slab transition between lists did not update lists correctly.", 0x0D, 0x0A, 0

; Slab Object Constructor Reuse Test Messages
msg_slab_ctor_test_start:      db "Running VMM Slab Object Constructor Reuse Test...", 0x0D, 0x0A, 0
msg_slab_ctor_test_passed:     db "VMM Slab Object Constructor Reuse Test PASSED!", 0x0D, 0x0A, 0
msg_test_cache_name:           db "kmem_test_ctor", 0
msg_slab_fail_ctor_str:        db "Failure: Slab object constructor magic value not found.", 0x0D, 0x0A, 0
msg_slab_fail_ctor_chain_str:  db "Failure: Slab constructor chain contains null next pointer.", 0x0D, 0x0A, 0

; Slab Reaping Test Messages
msg_slab_reap_test_start:       db "Running VMM Slab Reaping Test...", 0x0D, 0x0A, 0
msg_slab_reap_test_passed:      db "VMM Slab Reaping Test PASSED!", 0x0D, 0x0A, 0
msg_slab_reap_fail_setup_str:   db "Failure: Could not setup empty slab in kmem_cache_vma slabs_free.", 0x0D, 0x0A, 0
msg_slab_reap_fail_eviction_str:db "Failure: Empty slab not reaped/removed from slabs_free under RAM pressure.", 0x0D, 0x0A, 0
msg_slab_reap_fail_count_str:   db "Failure: Physical free pages count not incremented after reaping slab.", 0x0D, 0x0A, 0

; Slab Cache Coloring Test Messages
msg_slab_color_test_start:      db "Running VMM Slab Cache Coloring Test...", 0x0D, 0x0A, 0
msg_slab_color_test_passed:     db "VMM Slab Cache Coloring Test PASSED!", 0x0D, 0x0A, 0
msg_test_color_cache_name:      db "kmem_test_color", 0
msg_slab_color_fail_max_str:    db "Failure: Slab cache colour_max calculation is incorrect.", 0x0D, 0x0A, 0
msg_slab_color_fail_offset_str: db "Failure: Slab starting offset is not correctly colored (staggered by 64 bytes).", 0x0D, 0x0A, 0

; Buddy Allocator Test Messages
msg_buddy_test_start:          db "Running Buddy Allocator Initialization Test...", 0x0D, 0x0A, 0
msg_buddy_test_passed:         db "Buddy Allocator Initialization Test PASSED!", 0x0D, 0x0A, 0
msg_buddy_fail_alloc_str:      db "Failure: Could not allocate memory for buddy test.", 0x0D, 0x0A, 0
msg_buddy_fail_config_str:     db "Failure: Buddy allocator config variables (start/end) are incorrect.", 0x0D, 0x0A, 0
msg_buddy_fail_lists_str:      db "Failure: Buddy free list heads are incorrect or not partitioned properly.", 0x0D, 0x0A, 0
msg_buddy_fail_metadata_str:   db "Failure: Buddy page metadata array contents are incorrect.", 0x0D, 0x0A, 0

; Buddy Allocator Splitting Test Messages
msg_buddy_split_test_start:          db "Running Buddy Allocator Block Splitting Test...", 0x0D, 0x0A, 0
msg_buddy_split_test_passed:         db "Buddy Allocator Block Splitting Test PASSED!", 0x0D, 0x0A, 0
msg_buddy_fail_split_alloc_str:      db "Failure: buddy_alloc returned NULL for requested order.", 0x0D, 0x0A, 0
msg_buddy_fail_split_ptr_str:        db "Failure: Allocated pointer is not at expected block address.", 0x0D, 0x0A, 0
msg_buddy_fail_split_lists_str:      db "Failure: Buddy free lists are incorrect after block splitting.", 0x0D, 0x0A, 0
msg_buddy_fail_split_metadata_str:   db "Failure: Buddy page metadata array contents are incorrect after splitting.", 0x0D, 0x0A, 0

; Buddy Allocator Coalescing Test Messages
msg_buddy_coalesce_test_start:       db "Running Buddy Allocator Block Coalescing Test...", 0x0D, 0x0A, 0
msg_buddy_coalesce_test_passed:      db "Buddy Allocator Block Coalescing Test PASSED!", 0x0D, 0x0A, 0
msg_buddy_fail_coal_lists_str:      db "Failure: Buddy free lists are incorrect after block coalescing.", 0x0D, 0x0A, 0
msg_buddy_fail_coal_metadata_str:   db "Failure: Buddy page metadata array contents are incorrect after coalescing.", 0x0D, 0x0A, 0

; Arena Allocator Test Messages
msg_arena_test_start:                db "Running VMM Arena Allocator Test...", 0x0D, 0x0A, 0
msg_arena_test_passed:               db "VMM Arena Allocator Test PASSED!", 0x0D, 0x0A, 0
msg_arena_fail_create_str:           db "Failure: arena_create returned NULL.", 0x0D, 0x0A, 0
msg_arena_fail_config_str:           db "Failure: Arena starting, current, or ending bounds config is incorrect.", 0x0D, 0x0A, 0
msg_arena_fail_alloc_str:            db "Failure: arena_alloc returned NULL.", 0x0D, 0x0A, 0
msg_arena_fail_align_str:            db "Failure: Arena allocation address is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_arena_fail_ptr_str:              db "Failure: First arena allocation did not return aligned start address.", 0x0D, 0x0A, 0
msg_arena_fail_spacing_str:          db "Failure: Arena allocations are not contiguous/spaced correctly.", 0x0D, 0x0A, 0
msg_arena_fail_checkpoint_str:       db "Failure: Arena checkpoint save/restore check failed.", 0x0D, 0x0A, 0
msg_arena_fail_oom_str:              db "Failure: Arena allocation succeeded when it should have returned NULL (OOM).", 0x0D, 0x0A, 0
msg_arena_fail_reset_str:            db "Failure: Arena current pointer was not reset back to start address.", 0x0D, 0x0A, 0
msg_arena_fail_local_init_str:       db "Failure: Thread-local arena init failed or pointer was not stored in gs:[24].", 0x0D, 0x0A, 0
msg_arena_fail_local_alloc_str:      db "Failure: Thread-local arena allocation returned NULL.", 0x0D, 0x0A, 0
msg_arena_fail_local_reset_str:      db "Failure: Thread-local arena reset failed.", 0x0D, 0x0A, 0
msg_arena_fail_local_destroy_str:    db "Failure: Thread-local arena destroy did not clear gs:[24] to NULL.", 0x0D, 0x0A, 0

; Fixed-Size Pool Allocator Test Messages
msg_pool_test_start:                 db "Running VMM Fixed-Size Pool Allocator Test...", 0x0D, 0x0A, 0
msg_pool_test_passed:                db "VMM Fixed-Size Pool Allocator Test PASSED!", 0x0D, 0x0A, 0
msg_pool_fail_create_str:            db "Failure: pool_create returned NULL.", 0x0D, 0x0A, 0
msg_pool_fail_config_str:            db "Failure: Pool config fields (obj_size, capacity, count, memory, free_head) are incorrect.", 0x0D, 0x0A, 0
msg_pool_fail_alloc_str:             db "Failure: pool_alloc returned NULL.", 0x0D, 0x0A, 0
msg_pool_fail_ptr_str:               db "Failure: Allocated pool slot is not at the expected memory address.", 0x0D, 0x0A, 0
msg_pool_fail_oom_str:               db "Failure: pool_alloc succeeded when the pool was fully exhausted.", 0x0D, 0x0A, 0
msg_pool_fail_count_str:             db "Failure: Pool active count value is incorrect.", 0x0D, 0x0A, 0
msg_pool_fail_free_list_str:         db "Failure: Intrusive stack-based free list links are incorrect.", 0x0D, 0x0A, 0
msg_pool_fail_reuse_str:             db "Failure: pool_alloc did not pop the head slot from the free list.", 0x0D, 0x0A, 0
msg_pool_fail_safety_str:            db "Failure: Invalid pool_free call was not ignored or corrupted the count.", 0x0D, 0x0A, 0
msg_pool_fail_tag_str:               db "Failure: Pool generation tag was not updated correctly after CAS operations.", 0x0D, 0x0A, 0
msg_pool_fail_grow_alloc_str:        db "Failure: pool_alloc returned NULL during dynamic pool expansion.", 0x0D, 0x0A, 0
msg_pool_fail_capacity_grow_str:     db "Failure: Pool capacity did not grow correctly.", 0x0D, 0x0A, 0
msg_pool_fail_count_grow_str:        db "Failure: Pool count after growth/free operations is incorrect.", 0x0D, 0x0A, 0

; AVX2 Optimized Memory Primitives Test Messages
msg_memcpy_test_start:               db "Running VMM AVX2-Optimized memcpy Test...", 0x0D, 0x0A, 0
msg_memcpy_test_passed:              db "VMM AVX2-Optimized memcpy Test PASSED!", 0x0D, 0x0A, 0
msg_memcpy_fail_alloc_str:           db "Failure: Could not allocate memory for memcpy test buffers.", 0x0D, 0x0A, 0
msg_memcpy_fail_ret_str:             db "Failure: memcpy did not return the destination pointer.", 0x0D, 0x0A, 0
msg_memcpy_fail_data_str:            db "Failure: memcpy did not copy the data payload correctly.", 0x0D, 0x0A, 0
msg_memcpy_fail_extra_str:           db "Failure: memcpy corrupted memory past the requested copy size.", 0x0D, 0x0A, 0

msg_memset_test_start:               db "Running VMM AVX2-Optimized memset Test...", 0x0D, 0x0A, 0
msg_memset_test_passed:              db "VMM AVX2-Optimized memset Test PASSED!", 0x0D, 0x0A, 0
msg_memset_fail_alloc_str:           db "Failure: Could not allocate memory for memset test buffer.", 0x0D, 0x0A, 0
msg_memset_fail_ret_str:             db "Failure: memset did not return the destination pointer.", 0x0D, 0x0A, 0
msg_memset_fail_data_str:            db "Failure: memset did not fill the data payload correctly.", 0x0D, 0x0A, 0
msg_memset_fail_extra_str:           db "Failure: memset corrupted memory past the requested fill size.", 0x0D, 0x0A, 0

msg_memzero_test_start:              db "Running VMM AVX2-Optimized memzero Test...", 0x0D, 0x0A, 0
msg_memzero_test_passed:             db "VMM AVX2-Optimized memzero Test PASSED!", 0x0D, 0x0A, 0
msg_memzero_fail_alloc_str:          db "Failure: Could not allocate memory for memzero test buffer.", 0x0D, 0x0A, 0
msg_memzero_fail_ret_str:            db "Failure: memzero did not return the destination pointer.", 0x0D, 0x0A, 0
msg_memzero_fail_data_str:           db "Failure: memzero did not zero the data payload correctly.", 0x0D, 0x0A, 0
msg_memzero_fail_extra_str:          db "Failure: memzero corrupted memory past the requested zero size.", 0x0D, 0x0A, 0

msg_memcmp_test_start:               db "Running VMM AVX2-Optimized memcmp Test...", 0x0D, 0x0A, 0
msg_memcmp_test_passed:              db "VMM AVX2-Optimized memcmp Test PASSED!", 0x0D, 0x0A, 0
msg_memcmp_fail_alloc_str:           db "Failure: Could not allocate memory for memcmp test buffers.", 0x0D, 0x0A, 0
msg_memcmp_fail_match_str:           db "Failure: memcmp returned non-zero for identical memory blocks.", 0x0D, 0x0A, 0
msg_memcmp_fail_mismatch_str:        db "Failure: memcmp did not calculate mismatch sign or magnitude correctly.", 0x0D, 0x0A, 0

msg_memmove_test_start:              db "Running VMM AVX2-Optimized memmove Test...", 0x0D, 0x0A, 0
msg_memmove_test_passed:             db "VMM AVX2-Optimized memmove Test PASSED!", 0x0D, 0x0A, 0
msg_memmove_fail_alloc_str:          db "Failure: Could not allocate memory for memmove test buffer.", 0x0D, 0x0A, 0
msg_memmove_fail_ret_str:            db "Failure: memmove did not return the destination pointer.", 0x0D, 0x0A, 0
msg_memmove_fail_data_str:           db "Failure: memmove did not copy/shift the data payload correctly.", 0x0D, 0x0A, 0

msg_numa_test_start:            db "Running VMM NUMA ACPI SRAT/SLIT Parsing & Fallback Test...", 0x0D, 0x0A, 0
msg_numa_test_passed:           db "VMM NUMA ACPI SRAT/SLIT Parsing & Fallback Test PASSED!", 0x0D, 0x0A, 0
msg_numa_ranges_found:          db "NUMA Memory Ranges found in SRAT:", 0x0D, 0x0A, 0
msg_numa_range_base:            db "  Range base: 0x", 0
msg_numa_range_len:             db "  length: 0x", 0
msg_numa_range_node:            db "  Node ID: ", 0
msg_numa_node_count:           db "NUMA Node Count: ", 0
msg_numa_matrix_header:        db "NUMA Node Distance Matrix:", 0x0D, 0x0A, 0
msg_numa_node_prefix:          db "  Node ", 0
msg_numa_node_arrow:           db " -> ", 0
msg_numa_node_colon:           db ": ", 0
msg_numa_local_info_header:  db "NUMA Node-Local Bitmap Info:", 0x0D, 0x0A, 0
msg_numa_node_bmp_base:     db " Bitmap: Base=0x", 0
msg_numa_node_bmp_size:     db " Size=0x", 0
msg_numa_node_bmp_free:     db " FreePages=", 0
msg_numa_sim_oom_start:      db "NUMA: Starting simulated Node 0 memory exhaustion test...", 0x0D, 0x0A, 0
msg_numa_sim_oom_ok:         db "NUMA: Simulated Node 0 memory exhaustion test PASSED!", 0x0D, 0x0A, 0
msg_numa_fail_count_str:        db "Failure: NUMA range count is 0.", 0x0D, 0x0A, 0
msg_numa_fail_lookup_str:       db "Failure: NUMA Node ID lookup for out-of-bounds address did not return 0.", 0x0D, 0x0A, 0
msg_numa_fail_dist_bounds_str: db "Failure: NUMA distance out-of-bounds check did not return 255.", 0x0D, 0x0A, 0
msg_numa_fail_bmp_init_str:  db "Failure: Node-Local bitmaps not initialized or active flag is 0.", 0x0D, 0x0A, 0
msg_numa_fail_alloc_node_str:db "Failure: phys_alloc_page_node returned 0 for Node 0.", 0x0D, 0x0A, 0
msg_numa_fail_affinity_str:  db "Failure: Allocated page Node ID does not match requested Node ID.", 0x0D, 0x0A, 0
msg_numa_fail_fallback_str:  db "Failure: Fallback allocation for out-of-bounds node 99 returned 0.", 0x0D, 0x0A, 0
msg_numa_fail_sim_oom_alloc_str: db "Failure: Fallback allocation under simulated OOM returned 0.", 0x0D, 0x0A, 0
msg_numa_fail_sim_oom_affinity_str: db "Failure: Fallback allocation under simulated OOM did not allocate from adjacent Node 1.", 0x0D, 0x0A, 0

msg_smep_smap_test_start:      db "Running VMM SMEP/SMAP Protection Test...", 0x0D, 0x0A, 0
msg_smep_smap_test_passed:     db "VMM SMEP/SMAP Protection Test PASSED!", 0x0D, 0x0A, 0
msg_smep_smap_test_data:       db "SMAP_TEST_SIGNATURE", 0
msg_smep_smap_fail_alloc_str:  db "Failure: Could not allocate user page.", 0x0D, 0x0A, 0
msg_smep_smap_fail_vma_str:    db "Failure: Could not create user VMA.", 0x0D, 0x0A, 0
msg_smep_smap_fail_map_str:    db "Failure: Could not map user page.", 0x0D, 0x0A, 0
msg_smep_smap_fail_copy_to_str: db "Failure: copy_to_user returned error or failed.", 0x0D, 0x0A, 0
msg_smep_smap_fail_copy_from_str: db "Failure: copy_from_user returned error or failed.", 0x0D, 0x0A, 0
msg_smep_smap_fail_data_str:   db "Failure: Data read back from user page does not match signature.", 0x0D, 0x0A, 0

msg_zof_test_start:             db "Running VMM Zeroing on Free Tests...", 0x0D, 0x0A, 0
msg_zof_test_passed:            db "VMM Zeroing on Free Tests PASSED!", 0x0D, 0x0A, 0
msg_zof_fail_heap_alloc_str:    db "Failure: Could not allocate memory from heap for Zero on Free test.", 0x0D, 0x0A, 0
msg_zof_fail_heap_zero_str:     db "Failure: Heap memory was not zeroed out on free.", 0x0D, 0x0A, 0
msg_zof_fail_phys_alloc_str:    db "Failure: Could not allocate physical page for Zero on Free test.", 0x0D, 0x0A, 0
msg_zof_fail_phys_zero_str:     db "Failure: Physical page was not zeroed out on free.", 0x0D, 0x0A, 0

msg_mmap_test_start:            db "Running VMM Memory-Mapped Files (mmap) Tests...", 0x0D, 0x0A, 0
msg_mmap_test_passed:           db "VMM Memory-Mapped Files (mmap) Tests PASSED!", 0x0D, 0x0A, 0
msg_mmap_fail_create:           db "Failure: Could not create mock file.", 0x0D, 0x0A, 0
msg_mmap_fail_map:              db "Failure: Could not map file to VMA.", 0x0D, 0x0A, 0
msg_mmap_fail_read_val:         db "Failure: Read value from memory-mapped file does not match signature.", 0x0D, 0x0A, 0
msg_mmap_fail_read_offset:      db "Failure: Offset read from memory-mapped file does not match expected.", 0x0D, 0x0A, 0
msg_mmap_fail_pte:              db "Failure: Walk table returned null PTE for memory-mapped page.", 0x0D, 0x0A, 0
msg_mmap_fail_dirty:            db "Failure: PAGE_DIRTY bit not set in PTE after memory write.", 0x0D, 0x0A, 0
msg_mmap_fail_sync:             db "Failure: mmap_msync returned error.", 0x0D, 0x0A, 0
msg_mmap_fail_not_cleared:      db "Failure: PAGE_DIRTY bit not cleared in PTE after msync.", 0x0D, 0x0A, 0
msg_mmap_fail_backing:          db "Failure: Backing mock file block is null after msync.", 0x0D, 0x0A, 0
msg_mmap_fail_backing_data:     db "Failure: backing mock file block data does not match synced RAM page.", 0x0D, 0x0A, 0
msg_mmap_fail_unmap:            db "Failure: mmap_munmap returned error.", 0x0D, 0x0A, 0

msg_ipc_test_start:             db "Running VMM Shared Memory & IPC Tests...", 0x0D, 0x0A, 0
msg_ipc_test_passed:            db "VMM Shared Memory & IPC Tests PASSED!", 0x0D, 0x0A, 0
msg_ipc_fail_pml4:              db "Failure: Could not create secondary PML4.", 0x0D, 0x0A, 0
msg_ipc_fail_alloc:             db "Failure: Could not allocate physical page for shared memory.", 0x0D, 0x0A, 0
msg_ipc_fail_map:               db "Failure: Could not map page in current address space.", 0x0D, 0x0A, 0
msg_ipc_fail_share:             db "Failure: ipc_share_frame returned error.", 0x0D, 0x0A, 0
msg_ipc_fail_shared_val:        db "Failure: Value in shared frame does not match signature.", 0x0D, 0x0A, 0
msg_ipc_fail_ring_create:       db "Failure: Could not create consecutive ring buffer.", 0x0D, 0x0A, 0
msg_ipc_fail_ring_val:          db "Failure: Consecutive ring buffer second half read failed or mismatch.", 0x0D, 0x0A, 0
msg_ipc_fail_ring_cross_val:    db "Failure: Consecutive ring buffer write/read cross-validation mismatch.", 0x0D, 0x0A, 0

msg_leak_test_start:            db "Running VMM Memory Leak Tracker Tests...", 0x0D, 0x0A, 0
msg_leak_test_passed:           db "VMM Memory Leak Tracker Tests PASSED!", 0x0D, 0x0A, 0
msg_leak_fail_initial:          db "Failure: Leak tracker reported non-zero leaks initially.", 0x0D, 0x0A, 0
msg_leak_fail_alloc:            db "Failure: Could not allocate heap memory for leak tracker test.", 0x0D, 0x0A, 0
msg_leak_fail_count:            db "Failure: Leak tracker did not report exactly 1 leak after partial free.", 0x0D, 0x0A, 0
msg_leak_fail_verify:           db "Failure: Logged leak pointer did not match the leaked block.", 0x0D, 0x0A, 0
msg_leak_fail_final:            db "Failure: Leak tracker reported non-zero leaks after all blocks freed.", 0x0D, 0x0A, 0

msg_uaf_test_start:             db "Running VMM Use-After-Free Trap Tests...", 0x0D, 0x0A, 0
msg_uaf_fail_alloc_str:         db "Failure: Could not allocate physical page for UAF test.", 0x0D, 0x0A, 0
msg_uaf_fail_map_str:           db "Failure: Could not map page for UAF test.", 0x0D, 0x0A, 0
msg_uaf_fail_trap:              db "Failure: Access to freed memory did not trigger UAF Trap panic.", 0x0D, 0x0A, 0

msg_tsx_test_start:            db "Running VMM TSX Fault Handling Tests...", 0x0D, 0x0A, 0
msg_tsx_success_ok:            db "  TSX Success Case: Transaction successfully retried and committed.", 0x0D, 0x0A, 0
msg_tsx_abort_ok:              db "  TSX Abort Case: Unresolvable fault successfully redirected to fallback.", 0x0D, 0x0A, 0
msg_tsx_test_passed:           db "VMM TSX Fault Handling Tests PASSED!", 0x0D, 0x0A, 0

msg_tsx_test_fail_vma:         db "Failure: Could not create TSX VMA.", 0x0D, 0x0A, 0
msg_tsx_test_fail_data:        db "Failure: TSX success case data mismatch.", 0x0D, 0x0A, 0
msg_tsx_fail_success_fallback: db "Failure: TSX success case entered fallback path.", 0x0D, 0x0A, 0
msg_tsx_fail_no_abort:         db "Failure: Unresolvable fault did not abort transaction to fallback.", 0x0D, 0x0A, 0

msg_tsx_spec_walk_test_start:        db "Running TSX Speculative Directory Walk Engine Tests...", 0x0D, 0x0A, 0
msg_tsx_spec_walk_test_passed:       db "TSX Speculative Directory Walk Engine Tests PASSED!", 0x0D, 0x0A, 0

msg_tsx_spec_walk_fail_vma_str:      db "Failure: Could not create speculative walk VMA.", 0x0D, 0x0A, 0
msg_tsx_spec_walk_fail_init_str:     db "Failure: Initial cache hit on unmapped address before walk.", 0x0D, 0x0A, 0
msg_tsx_spec_walk_fail_lookup_str:   db "Failure: Speculative walk did not cache translation mapping.", 0x0D, 0x0A, 0
msg_tsx_spec_walk_fail_mismatch_str: db "Failure: Cached physical address does not match page table walk result.", 0x0D, 0x0A, 0
msg_tsx_spec_walk_fail_inval_str:    db "Failure: Invalidate did not clear cached translation entry.", 0x0D, 0x0A, 0

msg_tsx_lock_test_start:             db "Running TSX Lock-Free Directory Updates (Lock Elision) Tests...", 0x0D, 0x0A, 0
msg_tsx_lock_bypass_ok:              db "  Lock Elision Success: Speculative block bypassed spinlock write.", 0x0D, 0x0A, 0
msg_tsx_lock_traditional_ok:         db "  Lock Fallback Success: Traditional lock acquired when TSX disabled.", 0x0D, 0x0A, 0
msg_tsx_lock_test_passed:            db "TSX Lock-Free Directory Updates Tests PASSED!", 0x0D, 0x0A, 0

msg_tsx_lock_fail_active_str:        db "Failure: Speculative acquire did not set tsx_active to 1.", 0x0D, 0x0A, 0
msg_tsx_lock_fail_bypass_str:        db "Failure: Speculative acquire modified lock byte (bypass failed).", 0x0D, 0x0A, 0
msg_tsx_lock_fail_rel_active_str:    db "Failure: Speculative release did not clear tsx_active.", 0x0D, 0x0A, 0
msg_tsx_lock_fail_rel_lock_str:      db "Failure: Speculative release modified lock byte.", 0x0D, 0x0A, 0
msg_tsx_lock_fail_trad_str:          db "Failure: Traditional acquire did not set lock byte to 1.", 0x0D, 0x0A, 0
msg_tsx_lock_fail_trad_rel_str:      db "Failure: Traditional release did not clear lock byte to 0.", 0x0D, 0x0A, 0

msg_hle_test_start:            db "Running HLE Protection & Caching Tests...", 0x0D, 0x0A, 0
msg_hle_test_passed:           db "HLE Protection & Caching Tests PASSED!", 0x0D, 0x0A, 0
msg_hle_fail_alloc_str:        db "Failure: Could not allocate page for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_map_str:          db "Failure: Could not map page for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_walk1_str:        db "Failure: Initial walk failed for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_flags1_str:       db "Failure: Caching flags not set on map for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_walk2_str:        db "Failure: Post-protect walk failed for HLE test.", 0x0D, 0x0A, 0
msg_hle_fail_flags2_str:       db "Failure: hle_protect_range did not clear cache flags.", 0x0D, 0x0A, 0
msg_hle_fail_align1_str:       db "Failure: hle_is_cache_aligned returned 0 for aligned address.", 0x0D, 0x0A, 0
msg_hle_fail_align2_str:       db "Failure: hle_is_cache_aligned returned 1 for unaligned address.", 0x0D, 0x0A, 0

msg_tsx_fallback_lock_test_start:          db "Running TSX Fallback Page-Directory Lock Manager Tests...", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_limit_ok:            db "  Fallback Success: Traditional spinlock acquired when limits exceeded.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_decay_ok:            db "  Decay Success: Abort count decayed and lock released traditionally.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_test_passed:          db "TSX Fallback Page-Directory Lock Manager Tests PASSED!", 0x0D, 0x0A, 0

msg_tsx_fallback_lock_fail_init_active_str:    db "Failure: Speculative acquire did not set tsx_active on clean lock.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_init_lock_str:      db "Failure: Speculative acquire modified lock byte on clean lock.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_bypass_active_str:  db "Failure: Acquire set tsx_active when abort limits exceeded.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_bypass_lock_str:    db "Failure: Acquire did not write lock byte when abort limits exceeded.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_decay_lock_str:     db "Failure: Traditional release did not clear lock byte.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_decay_count_str:    db "Failure: Traditional release did not decay abort count.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_retry_active_str:   db "Failure: Acquire did not attempt TSX after abort count decayed.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_retry_lock_str:     db "Failure: Acquire modified lock byte after abort count decayed.", 0x0D, 0x0A, 0
msg_tsx_fallback_lock_fail_final_count_str:    db "Failure: Speculative release did not reset abort count to 0.", 0x0D, 0x0A, 0

msg_aslr_test_start:          db "Running ASLR Symbol Offset Randomization Tests...", 0x0D, 0x0A, 0
msg_aslr_test_passed:         db "ASLR Symbol Offset Randomization Test PASSED!", 0x0D, 0x0A, 0
msg_aslr_fail_alloc_str:      db "Failure: heap_alloc returned NULL for ASLR test.", 0x0D, 0x0A, 0
msg_aslr_fail_align_str:      db "Failure: ASLR offsetted pointer is not 16-byte aligned.", 0x0D, 0x0A, 0
msg_aslr_fail_bounds_str:     db "Failure: ASLR random gap size is out of bounds or misaligned.", 0x0D, 0x0A, 0

msg_xo_test_start:            db "Running Execute-Only (XO) Pages Security Tests...", 0x0D, 0x0A, 0
msg_xo_pku_supported:         db "  [XO Test] Hardware PKU support detected. Enabling CR4.PKE...", 0x0D, 0x0A, 0
msg_xo_pku_unsupported:       db "  [XO Test] Hardware PKU not supported. Using software-fallback (P=0)...", 0x0D, 0x0A, 0
msg_xo_pte_verify_ok:         db "  [XO Test] PTE verification succeeded. Attempting read access...", 0x0D, 0x0A, 0
msg_xo_fail_alloc_str:        db "Failure: Could not allocate physical page for XO test.", 0x0D, 0x0A, 0
msg_xo_fail_map_str:          db "Failure: Could not map page with PAGE_XO for XO test.", 0x0D, 0x0A, 0
msg_xo_fail_walk_str:         db "Failure: virt_walk_table returned 0 for mapped XO page.", 0x0D, 0x0A, 0
msg_xo_fail_pte_present_str:  db "Failure: Hardware PKU mapped page is not present in PTE.", 0x0D, 0x0A, 0
msg_xo_fail_pte_key_str:      db "Failure: Hardware PKU mapped page does not have Key 1 in PTE.", 0x0D, 0x0A, 0
msg_xo_fail_pte_nx_str:       db "Failure: Hardware PKU mapped page has NX set (must be 0 for execution).", 0x0D, 0x0A, 0
msg_xo_fail_pte_absent_str:   db "Failure: Software fallback mapped page is present in PTE (must be 0).", 0x0D, 0x0A, 0
msg_xo_fail_pte_xo_str:       db "Failure: Software fallback mapped page does not have PAGE_XO bit set.", 0x0D, 0x0A, 0
msg_xo_fail_trap:             db "Failure: Read access to Execute-Only page did not trigger page fault violation.", 0x0D, 0x0A, 0





section .bss
align 8
smep_smap_test_buf:            resb 32



