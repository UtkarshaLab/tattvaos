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
    jmp .idle

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
