; =============================================================================
; Tattva OS — lib/mem/virt/pf.asm
; =============================================================================
; Page Fault Handler entry and dispatching (Subfeature 6.1).
; Hooks Vector 14 (#PF) to intercept faults, read CR2 and the exception error
; code, and log diagnostic details.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PF_ASM
%define LIB_MEM_VIRT_PF_ASM

[BITS 64]

section .text

; VMA Flags (matching virt.asm design)
VMA_READ        equ (1 << 0)
VMA_WRITE       equ (1 << 1)
VMA_EXEC        equ (1 << 2)
VMA_USER        equ (1 << 3)
VMA_COW         equ (1 << 4)
VMA_ZFOD        equ (1 << 5)
VMA_STACK       equ (1 << 6)
VMA_ONDEMAND    equ (1 << 7)
VMA_FILE        equ (1 << 8)
VMA_HMM         equ (1 << 9)


; Page Table Flags (from pgtable.asm)
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_COW        equ (1 << 9)
PAGE_SWAPPED    equ (1 << 10)
PAGE_ZSWAPPED   equ (1 << 11)
PAGE_NX         equ (1 << 63)

; External symbols
extern common_isr_handler
extern uart_print_str
extern uart_print_hex64
extern uart_print_dec
extern vma_find
extern phys_alloc_page
extern phys_free_page
extern memzero
extern memcpy
extern virt_map
extern virt_walk_table
extern virt_split_super_1gb
extern virt_split_huge_2mb
extern tlb_shootdown
extern swap_read_page
extern swap_free_slot
extern page_list_add_active
extern phys_state
extern zswap_decompress_and_free
extern kernel_stack_guard
extern kernel_panic
extern virt_handle_file_map


; -----------------------------------------------------------------------------
; page_fault_isr — Low-level assembly entry point for Vector 14 (#PF)
; -----------------------------------------------------------------------------
global page_fault_isr
page_fault_isr:
    ; Pushing GP registers
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    ; 1. Read CR2 (faulting virtual address)
    mov rdi, cr2                    ; RDI = faulting address (arg 1)

    ; 2. Read error code
    ; The error code is at: RSP + 120 (since we pushed 15 registers * 8 bytes = 120 bytes)
    mov rsi, [rsp + 120]            ; RSI = error code (arg 2)

    ; 3. Read original RSP (stack pointer at exception entry)
    mov rdx, [rsp + 152]            ; RDX = original RSP (arg 3)

    ; 4. Pass pointer to return RIP on stack frame as arg 4 (RCX)
    lea rcx, [rsp + 128]            ; RCX = RIP pointer

    ; 5. Call high-level handler
    call virt_page_fault_handler    ; RAX = 1 if handled, 0 if unhandled

    test rax, rax
    jz .unhandled

    ; Handled: restore registers and return
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax

    ; Clean up error code from the stack
    add rsp, 8                      ; pop error code
    iretq

.unhandled:
    ; Restore registers and let common_isr_handler panic
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax

    ; Vector index 14
    push qword 14
    jmp common_isr_handler

; -----------------------------------------------------------------------------
; virt_page_fault_handler — parses error code and prints detailed debug logs
; Input:
;   RDI = faulting virtual address (from CR2)
;   RSI = exception error code
; Output:
;   RAX = 1 if handled, 0 if unhandled
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global virt_page_fault_handler
virt_page_fault_handler:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = vaddr
    mov r13, rsi                    ; R13 = error_code
    mov r14, rdx                    ; R14 = original RSP
    mov r15, rcx                    ; R15 = pointer to return RIP on exception stack

    ; Check if faulting address is within the kernel stack guard page
    mov rax, r12
    and rax, -4096
    mov rcx, kernel_stack_guard
    cmp rax, rcx
    je .kernel_stack_overflow

    ; Check if it is a swap fault (Non-Present fault with PAGE_SWAPPED set in PTE)
    test r13, 1                     ; present fault (bit 0 set)?
    jnz .not_swap_fault             ; yes, cannot be swap fault

    ; Check if the faulting address was previously quarantined (Use-After-Free)
    mov rdi, r12                    ; faulting address
    extern uaf_quarantine_check
    call uaf_quarantine_check
    test rax, rax
    jz .not_uaf_trap

    ; Use-After-Free detected! Trigger diagnostic panic
    mov rsi, msg_uaf_panic_prefix
    call uart_print_str
    mov rax, r12
    call uart_print_hex64
    mov rsi, msg_uaf_panic_suffix
    call uart_print_str

    mov rdi, msg_uaf_reason
    mov rsi, [rsp + 160]            ; RIP of crash
    call kernel_panic
    cli
.halt:
    hlt
    jmp .halt

.not_uaf_trap:


    mov rdi, r12
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address, RDX = level
    test rax, rax
    jz .not_swap_fault

    mov rbx, [rax]                  ; RBX = PTE value
    test rbx, PAGE_SWAPPED
    jz .not_swap_fault

    ; It is a swap fault! Handle it
    mov rdi, r12                    ; vaddr
    mov rsi, rax                    ; PTE address
    mov rdx, rbx                    ; PTE value
    call virt_handle_swap_fault
    test rax, rax
    jz .do_diagnostics              ; if failed, panic/diagnostic

    mov rax, 1                      ; successfully handled
    jmp .exit

.not_swap_fault:
    ; 1. Find VMA containing the address
    mov rdi, r12
    call vma_find                   ; RAX = VMA pointer, or 0 if not found
    test rax, rax
    jz .do_diagnostics              ; no VMA, invalid address -> panic

    mov rbx, [rax + 16]             ; RBX = vma->flags

    ; Check if write fault (bit 1 of error code set) to a non-writable VMA (VMA_WRITE clear)
    test r13, 2                     ; write fault?
    jz .no_write_violation
    test rbx, VMA_WRITE             ; VMA writable?
    jz .do_diagnostics              ; write to non-writable VMA -> panic
.no_write_violation:

    ; 2. Determine if Present fault (bit 0 of error_code)
    test r13, 1                     ; bit 0 set?
    jnz .present_fault

    ; --- Non-Present Fault ---
    ; Check if HMM VMA
    test rbx, VMA_HMM
    jnz .hmm_path

    ; Check if file-mapped VMA
    test rbx, VMA_FILE
    jnz .file_map_path

    ; Check if on-demand paging VMA
    test rbx, VMA_ONDEMAND
    jnz .on_demand_path

    ; Check if ZFOD VMA
    test rbx, VMA_ZFOD
    jnz .zfod_path

    ; Check if Stack VMA
    test rbx, VMA_STACK
    jnz .stack_grow_path

    jmp .do_diagnostics              ; not on-demand, ZFOD, or Stack VMA -> panic

.hmm_path:
    ; Call handler for HMM page fault
    mov rdi, r12                    ; virtual address
    mov rsi, rax                    ; VMA pointer
    mov rdx, r13                    ; error code
    extern hmm_handle_page_fault
    call hmm_handle_page_fault
    test rax, rax
    jz .do_diagnostics              ; failed -> panic

    mov rax, 1
    jmp .exit

.file_map_path:
    ; Call handler for file-mapped paging
    mov rdi, r12                    ; virtual address
    mov rsi, rax                    ; VMA pointer
    call virt_handle_file_map
    test rax, rax
    jz .do_diagnostics              ; failed -> panic

    mov rax, 1
    jmp .exit

.on_demand_path:
    ; Call handler for on-demand paging
    mov rdi, r12                    ; virtual address
    mov rsi, rax                    ; VMA pointer
    call virt_handle_ondemand
    test rax, rax
    jz .do_diagnostics              ; failed -> panic

    mov rax, 1
    jmp .exit

.zfod_path:
    ; Call handler for Zero-Fill-on-Demand
    mov rdi, r12                    ; virtual address
    mov rsi, rax                    ; VMA pointer
    mov rdx, r13                    ; error code
    call virt_handle_zfod
    test rax, rax
    jz .do_diagnostics              ; failed -> panic

    mov rax, 1
    jmp .exit

.stack_grow_path:
    ; Call handler for Stack Auto-Grow
    mov rdi, r12                    ; virtual address
    mov rsi, rax                    ; VMA pointer
    mov rdx, r14                    ; original RSP
    call virt_handle_stack_grow
    test rax, rax
    jz .do_diagnostics              ; failed -> panic

    mov rax, 1
    jmp .exit

.present_fault:
    ; --- Present Fault (Protection Violation) ---
    ; Check if it is a write fault (bit 1 of error_code)
    test r13, 2                     ; bit 1 set?
    jz .do_diagnostics              ; read access protection fault -> panic

    ; Check if VMA is writable
    test rbx, VMA_WRITE
    jz .do_diagnostics              ; write to non-writable VMA -> panic

    ; Walk page table to check if it's a COW page
    mov rdi, r12
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address, RDX = level
    test rax, rax
    jz .do_diagnostics              ; not mapped -> panic

    mov rcx, [rax]                  ; RCX = PTE value
    test rcx, PAGE_COW              ; is COW page?
    jz .do_diagnostics              ; present write fault, but not marked COW -> panic

    ; Call Copy-On-Write handler
    mov rdi, r12                    ; virtual address
    call virt_handle_cow
    test rax, rax
    jz .do_diagnostics              ; failed -> panic

    mov rax, 1
    jmp .exit

.do_diagnostics:
    ; Print "#PF: Page Fault at "
    mov rsi, msg_pf_prefix
    call uart_print_str

    ; Print faulting address in hex
    mov rax, r12
    call uart_print_hex64

    ; Print " (Error Code: "
    mov rsi, msg_pf_err_code
    call uart_print_str

    ; Print error code in hex
    mov rax, r13
    call uart_print_hex64

    ; Print details divider
    mov rsi, msg_pf_details_start
    call uart_print_str

    ; 1. Check Present (Bit 0)
    test r13, 1
    jnz .present_violation
    mov rsi, msg_pf_absent
    call uart_print_str
    jmp .check_write
.present_violation:
    mov rsi, msg_pf_present
    call uart_print_str

.check_write:
    mov rsi, msg_comma_space
    call uart_print_str

    ; 2. Check Write (Bit 1)
    test r13, 2
    jnz .write_fault
    mov rsi, msg_pf_read
    call uart_print_str
    jmp .check_user
.write_fault:
    mov rsi, msg_pf_write
    call uart_print_str

.check_user:
    mov rsi, msg_comma_space
    call uart_print_str

    ; 3. Check User (Bit 2)
    test r13, 4
    jnz .user_fault
    mov rsi, msg_pf_supervisor
    call uart_print_str
    jmp .check_instruction
.user_fault:
    mov rsi, msg_pf_user
    call uart_print_str

.check_instruction:
    mov rsi, msg_comma_space
    call uart_print_str

    ; 4. Check Instruction Fetch (Bit 4)
    test r13, 16
    jnz .instruction_fault
    mov rsi, msg_pf_data
    call uart_print_str
    jmp .details_done
.instruction_fault:
    mov rsi, msg_pf_instruction
    call uart_print_str

.details_done:
    mov rsi, msg_pf_details_end
    call uart_print_str

    ; Return 0 (unhandled)
    xor rax, rax

.exit:
    test rax, rax                   ; was the fault handled?
    jz .exit_unhandled              ; if not handled, check for TSX abort fallback

    ; --- Handled Page Fault (rax == 1) ---
    push rcx
    push rdx
    extern sched_get_current_thread
    call sched_get_current_thread   ; RAX = current thread pointer
    pop rdx
    pop rcx
    test rax, rax
    jz .exit_done
    
    mov r8, [rax + thread_t.tsx_active]
    test r8, r8
    jz .exit_done
    
    ; TSX is active! Intercept the fault
    mov r9, [rax + thread_t.tsx_retries]
    inc r9
    mov [rax + thread_t.tsx_retries], r9
    
    cmp r9, 3                       ; limit to 3 retries
    jae .exit_fallback
    
    ; Retry: modify return RIP to tsx_xbegin_rip
    mov r10, [rax + thread_t.tsx_xbegin_rip]
    mov [r15], r10                  ; modify RIP on stack frame
    
    ; Print diagnostic message
    push rax
    push rsi
    push rdi
    mov rsi, msg_tsx_retry_prefix
    call uart_print_str
    mov rax, r9
    call uart_print_dec
    mov rsi, msg_tsx_retry_suffix
    call uart_print_str
    pop rdi
    pop rsi
    pop rax
    jmp .exit_done

.exit_fallback:
    ; Fallback: modify return RIP to tsx_fallback_rip
    mov r10, [rax + thread_t.tsx_fallback_rip]
    mov [r15], r10                  ; modify RIP on stack frame
    
    ; Reset TSX state
    mov qword [rax + thread_t.tsx_active], 0
    mov qword [rax + thread_t.tsx_retries], 0
    
    ; Print diagnostic message
    push rax
    push rsi
    push rdi
    mov rsi, msg_tsx_fallback_msg
    call uart_print_str
    pop rdi
    pop rsi
    pop rax
    jmp .exit_done

.exit_unhandled:
    ; --- Unhandled Page Fault (rax == 0) ---
    push rcx
    push rdx
    extern sched_get_current_thread
    call sched_get_current_thread   ; RAX = current thread pointer
    pop rdx
    pop rcx
    test rax, rax
    jz .exit_done
    
    mov r8, [rax + thread_t.tsx_active]
    test r8, r8
    jz .exit_done
    
    ; TSX is active! Abort transaction & redirect to fallback
    mov r10, [rax + thread_t.tsx_fallback_rip]
    mov [r15], r10                  ; modify RIP on stack frame
    
    ; Reset TSX state
    mov qword [rax + thread_t.tsx_active], 0
    mov qword [rax + thread_t.tsx_retries], 0
    
    ; Print diagnostic message
    push rax
    push rsi
    push rdi
    mov rsi, msg_tsx_abort_fallback
    call uart_print_str
    pop rdi
    pop rsi
    pop rax
    
    ; Return 1 (handled via fallback redirection!)
    mov rax, 1

.exit_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.kernel_stack_overflow:
    ; Print stack overflow diagnostic to UART
    mov rsi, msg_stack_overflow_panic
    call uart_print_str
    
    ; Print faulting address
    mov rax, r12
    call uart_print_hex64
    
    mov rsi, msg_pf_details_end
    call uart_print_str
    
    ; Call kernel_panic with reason string and RIP of crash
    mov rdi, msg_stack_overflow_reason
    mov rsi, [rsp + 160]            ; RIP of crash
    call kernel_panic
    cli
.halt:
    hlt
    jmp .halt

; -----------------------------------------------------------------------------
; virt_handle_ondemand — allocates, mock-loads, and maps an on-demand page
; Input:
;   RDI = faulting virtual address
;   RSI = VMA pointer
; Output:
;   RAX = 1 on success, 0 on failure (OOM)
; -----------------------------------------------------------------------------
global virt_handle_ondemand
virt_handle_ondemand:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi                    ; R12 = virtual address
    mov r13, rsi                    ; R13 = VMA pointer

    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .oom
    mov r14, rax                    ; R14 = new physical page base

    ; 2. Zero-out the new page
    mov rdi, r14
    mov rsi, 4096
    call memzero

    ; 3. Write mock loaded file data
    mov rdi, r14
    mov rsi, msg_pf_mock_data
    mov rdx, 31                     ; length of msg_pf_mock_data
    call memcpy

    ; Write the virtual address at offset 32 to verify
    mov [r14 + 32], r12

    ; 4. Map the physical page with VMA permissions
    mov rdx, [r13 + 16]             ; RDX = vma->flags
    xor rbx, rbx                    ; RBX = mapping flags

    test rdx, VMA_WRITE
    jz .no_write
    or rbx, PAGE_WRITABLE
.no_write:

    test rdx, VMA_USER
    jz .no_user
    or rbx, PAGE_USER
.no_user:

    test rdx, VMA_EXEC
    jnz .is_exec
    mov rcx, PAGE_NX
    or rbx, rcx
.is_exec:

    mov rdi, r12
    and rdi, -4096                  ; align virtual address to page
    mov rsi, r14                    ; physical address
    mov rdx, rbx                    ; flags
    call virt_map
    test rax, rax
    jz .map_fail

    mov rax, 1                      ; return 1 (success)
    jmp .done

.map_fail:
    mov rdi, r14
    call phys_free_page
.oom:
    xor rax, rax                    ; return 0 (failure)
.done:
    pop r14
    pop r13
    pop r12
    pop rbx

; -----------------------------------------------------------------------------
; virt_handle_cow — performs Copy-On-Write for a virtual address
; Input:
;   RDI = faulting virtual address
; Output:
;   RAX = 1 on success, 0 on failure (OOM/error)
; -----------------------------------------------------------------------------
global virt_handle_cow
virt_handle_cow:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = virtual address

.walk_loop:
    mov rdi, r12
    xor rsi, rsi
    call virt_walk_table
    test rax, rax
    jz .fail

    mov r13, rax                    ; R13 = PTE address
    mov r14, [rax]                  ; R14 = entry value
    
    test r14, PAGE_COW
    jz .fail                        ; double check: must have COW set

    cmp rdx, 4                      ; level 4?
    je .do_cow
    cmp rdx, 5                      ; level 5?
    je .do_cow

    ; It is huge/super. Split it!
    cmp rdx, 2                      ; 1GB?
    je .split_1gb
    cmp rdx, 3                      ; 2MB?
    je .split_2mb
    jmp .fail

.split_1gb:
    mov rdi, r12
    xor rsi, rsi
    call virt_split_super_1gb
    test rax, rax
    jz .fail
    jmp .walk_loop

.split_2mb:
    mov rdi, r12
    xor rsi, rsi
    call virt_split_huge_2mb
    test rax, rax
    jz .fail
    jmp .walk_loop

.do_cow:
    ; Allocate a new physical page
    call phys_alloc_page
    test rax, rax
    jz .fail
    mov r15, rax                    ; R15 = new physical address

    ; Copy page content: from virtual address r12 (aligned to 4KB) to r15
    mov rdi, r15
    mov rsi, r12
    and rsi, -4096                  ; align source address to 4KB
    mov rdx, 4096
    call memcpy

    ; Build new PTE: keep old flags except PAGE_COW, set PAGE_WRITABLE, set new physical address
    mov rcx, r14                    ; old PTE value
    
    mov r10, 0xFFFFFFFFFFFFF000
    not r10
    and rcx, r10                    ; RCX = old flags (bits 0-11)
    
    mov r10, (1 << 63)
    and r10, r14
    or rcx, r10                     ; RCX = flags + NX
    
    and rcx, ~PAGE_COW              ; clear COW
    or rcx, PAGE_WRITABLE           ; set writable
    or rcx, r15                     ; set new physical address

    ; Write back to page table (PTE is identity mapped, so we can write to R13 directly)
    mov [r13], rcx

    ; Flush TLB for this page
    mov rdi, r12
    mov rsi, 1
    call tlb_shootdown

    mov rax, 1                      ; success
    jmp .exit

.fail:
    xor rax, rax                    ; failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_handle_zfod — handles Zero-Fill-on-Demand paging
; Input:
;   RDI = faulting virtual address
;   RSI = VMA pointer
;   RDX = error code (bit 1 indicates write fault)
; Output:
;   RAX = 1 on success, 0 on failure (OOM/error)
; -----------------------------------------------------------------------------
global virt_handle_zfod
virt_handle_zfod:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = virtual address
    mov r13, rsi                    ; R13 = VMA pointer
    mov r14, rdx                    ; R14 = error code

    ; Check if write fault (bit 1 of error code)
    test r14, 2                     ; write fault?
    jnz .write_fault

    ; --- Read Fault: Map to Shared Zero Page ---
    ; 1. Check if shared zero page is allocated
    mov rax, [zero_page_addr]
    test rax, rax
    jnz .map_shared_zero

    ; 2. Allocate the shared zero page
    call phys_alloc_page
    test rax, rax
    jz .fail
    mov [zero_page_addr], rax

    ; 3. Zero out the shared zero page
    mov rdi, rax
    mov rsi, 4096
    call memzero

.map_shared_zero:
    mov r15, [zero_page_addr]       ; R15 = zero page physical address

    ; 4. Map it as read-only with PAGE_COW
    mov rdx, [r13 + 16]             ; RDX = vma->flags
    xor rbx, rbx                    ; RBX = mapping flags
    or rbx, PAGE_COW                ; set COW flag

    test rdx, VMA_USER
    jz .read_no_user
    or rbx, PAGE_USER
.read_no_user:

    test rdx, VMA_EXEC
    jnz .read_is_exec
    mov rcx, PAGE_NX
    or rbx, rcx
.read_is_exec:

    mov rdi, r12
    and rdi, -4096                  ; align virtual address to page
    mov rsi, r15                    ; physical address
    mov rdx, rbx                    ; flags
    call virt_map
    test rax, rax
    jz .fail

    mov rax, 1                      ; success
    jmp .exit

.write_fault:
    ; --- Write Fault: Allocate Private Zeroed Page Directly ---
    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .fail
    mov r15, rax                    ; R15 = new physical page

    ; 2. Zero-out the new page
    mov rdi, r15
    mov rsi, 4096
    call memzero

    ; 3. Map with writable permission
    mov rdx, [r13 + 16]             ; RDX = vma->flags
    xor rbx, rbx                    ; RBX = mapping flags
    test rdx, VMA_WRITE
    jz .zfod_no_write
    or rbx, PAGE_WRITABLE
.zfod_no_write:

    test rdx, VMA_USER
    jz .write_no_user
    or rbx, PAGE_USER
.write_no_user:

    test rdx, VMA_EXEC
    jnz .write_is_exec
    mov rcx, PAGE_NX
    or rbx, rcx
.write_is_exec:

    mov rdi, r12
    and rdi, -4096                  ; align virtual address
    mov rsi, r15                    ; physical address
    mov rdx, rbx                    ; flags
    call virt_map
    test rax, rax
    jz .map_fail

    mov rax, 1                      ; success
    jmp .exit

.map_fail:
    mov rdi, r15
    call phys_free_page
.fail:
    xor rax, rax                    ; failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_handle_stack_grow — grows the stack by allocating a page
; Input:
;   RDI = faulting virtual address
;   RSI = VMA pointer
;   RDX = original RSP
; Output:
;   RAX = 1 on success, 0 on failure (OOM/out of bounds)
; -----------------------------------------------------------------------------
global virt_handle_stack_grow
virt_handle_stack_grow:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = virtual address
    mov r13, rsi                    ; R13 = VMA pointer
    mov r14, rdx                    ; R14 = original RSP

    ; Check if within bounds: addr >= original_RSP - 4096 (allow 4KB stack allocation gap)
    mov rax, r14
    sub rax, 4096
    cmp r12, rax
    jb .fail_bounds

    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .fail
    mov r15, rax                    ; R15 = new physical page

    ; 2. Zero-out the new page
    mov rdi, r15
    mov rsi, 4096
    call memzero

    ; 3. Map the page with VMA permissions (enforcing NX since it's stack, PAGE_WRITABLE since stack)
    mov rdx, [r13 + 16]             ; RDX = vma->flags
    xor rbx, rbx                    ; RBX = mapping flags
    test rdx, VMA_WRITE
    jz .stack_no_write
    or rbx, PAGE_WRITABLE
.stack_no_write:

    test rdx, VMA_USER
    jz .no_user
    or rbx, PAGE_USER
.no_user:

    ; Always set PAGE_NX for stack safety (Subfeature 16.4)
    mov rcx, PAGE_NX
    or rbx, rcx

    mov rdi, r12
    and rdi, -4096                  ; align virtual address to page
    mov rsi, r15                    ; physical address
    mov rdx, rbx                    ; flags
    call virt_map
    test rax, rax
    jz .map_fail

    mov rax, 1                      ; success
    jmp .exit

.map_fail:
    mov rdi, r15
    call phys_free_page
.fail_bounds:
.fail:
    xor rax, rax                    ; failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data

msg_pf_prefix:          db "[#PF] Page Fault at ", 0
msg_pf_err_code:        db " (Error Code: ", 0
msg_pf_details_start:   db " - ", 0
msg_pf_absent:          db "Non-Present Page", 0
msg_pf_present:         db "Protection Violation", 0
msg_pf_read:            db "Read Access", 0
msg_pf_write:           db "Write Access", 0
msg_pf_supervisor:      db "Supervisor Mode", 0
msg_pf_user:            db "User Mode", 0
msg_pf_data:            db "Data Access", 0
msg_pf_instruction:     db "Instruction Fetch", 0
msg_comma_space:        db ", ", 0
msg_pf_details_end:     db ")", 0x0D, 0x0A, 0
msg_stack_overflow_panic:   db "KERNEL PANIC: Stack Overflow detected! Page fault in kernel stack guard page at ", 0
msg_stack_overflow_reason:  db "Double Fault / Kernel Stack Overflow", 0

msg_pf_mock_data:       db "TATTVA_OS_ONDEMAND_PAGE_LOADED", 0

msg_uaf_panic_prefix:  db "KERNEL PANIC: Use-After-Free detected at address 0x", 0
msg_uaf_panic_suffix:  db "! (UAF_TEST_SUCCESS)", 0x0D, 0x0A, 0
msg_uaf_reason:        db "Use-After-Free Memory Access Violation", 0

msg_tsx_retry_prefix:  db "[TSX] Page Fault resolved, retrying transaction (attempt ", 0
msg_tsx_retry_suffix:  db ")", 0x0D, 0x0A, 0
msg_tsx_fallback_msg:  db "[TSX] Page Fault retry limit exceeded, redirecting to fallback handler", 0x0D, 0x0A, 0
msg_tsx_abort_fallback: db "[TSX] Unresolvable Page Fault inside transaction, aborting and redirecting to fallback", 0x0D, 0x0A, 0


align 8
global zero_page_addr
zero_page_addr:         dq 0

; -----------------------------------------------------------------------------
; virt_handle_swap_fault — handles swap-in of a page from mock swap space
; Input:
;   RDI = faulting virtual address
;   RSI = PTE address
;   RDX = PTE value
; Output:
;   RAX = 1 on success, 0 on failure (OOM)
; -----------------------------------------------------------------------------
global virt_handle_swap_fault
virt_handle_swap_fault:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = vaddr
    mov r13, rsi                    ; R13 = PTE address
    mov r14, rdx                    ; R14 = PTE value

    ; 1. Extract swap slot index from PTE (bits 12-51)
    mov r15, r14
    shr r15, 12
    mov rax, 0xFFFFFFFFFFFFF        ; 40 bits of physical frame address
    and r15, rax                    ; R15 = swap slot index

    ; 2. Allocate a new physical page
    call phys_alloc_page
    test rax, rax
    jz .oom
    mov rbx, rax                    ; RBX = new physical address

    ; Check if this is a Zswap page or regular disk swap page
    test r14, PAGE_ZSWAPPED
    jnz .decompress_zswap

    ; --- Regular Disk Swap Path ---
    ; 3. Read content from swap slot to new page
    mov rdi, rbx                    ; dest physical address
    mov rsi, r15                    ; swap slot index
    call swap_read_page

    ; 4. Free the swap slot
    mov rdi, r15
    call swap_free_slot
    jmp .update_pte

.decompress_zswap:
    ; --- Zswap Path ---
    ; 3. Decompress from Zswap slot directly to new page
    mov rdi, r15                    ; Zswap slot index
    mov rsi, rbx                    ; dest physical address
    call zswap_decompress_and_free
    test rax, rax
    jz .zswap_fail                  ; decompression failed!

.update_pte:
    ; 5. Update the page table entry
    ; Keep original lower 12 flags and NX flag from old PTE (r14)
    ; Clear PAGE_SWAPPED, Clear PAGE_ZSWAPPED, set PAGE_PRESENT, set PAGE_ACCESSED
    mov rcx, r14
    and rcx, 0xFFF                  ; preserve lower 12 flags
    mov r10, (1 << 63)
    and r10, r14
    or rcx, r10                     ; preserve NX
    
    and rcx, ~PAGE_SWAPPED          ; clear Swapped
    and rcx, ~PAGE_ZSWAPPED         ; clear Zswapped
    or rcx, PAGE_PRESENT            ; set Present
    or rcx, PAGE_ACCESSED           ; set Accessed
    or rcx, rbx                     ; set new physical page frame address

    mov [r13], rcx                  ; write PTE

    ; 6. Flush TLB
    invlpg [r12]
    jmp .skip_tracking_ok           ; jump past failure handler

.zswap_fail:
    mov rdi, rbx
    call phys_free_page
    jmp .oom

.skip_tracking_ok:

    ; 7. Add page back to active list if PAGE_USER is set and PAGE_GLOBAL is clear
    test rcx, PAGE_USER
    jz .skip_tracking
    test rcx, PAGE_GLOBAL
    jnz .skip_tracking

    mov rdi, rbx                    ; physical address
    mov rsi, r12                    ; virtual address
    call page_list_add_active

.skip_tracking:
    ; 8. Decrement swap count statistics
    dec qword [phys_state + phys_state_t.swap_pages]

    mov rax, 1                      ; return 1 (success)
    jmp .done

.oom:
    xor rax, rax                    ; return 0 (failure)

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_PF_ASM
