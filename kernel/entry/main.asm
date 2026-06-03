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
