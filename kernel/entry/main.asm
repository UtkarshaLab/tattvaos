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

    jmp .idle

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
