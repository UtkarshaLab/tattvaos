; =============================================================================
; Tattva OS — lib/mem/virt/stack.asm
; =============================================================================
; Thread Stack Page Allocator (Subfeature 20.1).
; Allocates page-aligned stack frames for newly spawned tasks.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_STACK_ASM
%define LIB_MEM_VIRT_STACK_ASM

[BITS 64]

; Local Constants
%ifndef VMA_READ
    %define VMA_READ    (1 << 0)
%endif
%ifndef VMA_WRITE
    %define VMA_WRITE   (1 << 1)
%endif
%ifndef VMA_STACK
    %define VMA_STACK   (1 << 6)
%endif

STACK_VIRT_START equ 0x700000000000

section .text

; External symbols
extern vma_list_head
extern vma_create
extern vma_find
extern vma_destroy
extern phys_alloc_page
extern phys_free_page
extern virt_map
extern virt_unmap
extern virt_translate

; -----------------------------------------------------------------------------
; virt_find_free_range — finds a free virtual address range of a given size
; Input:
;   RDI = size in bytes (page-aligned)
;   RSI = base address to start searching from
; Output:
;   RAX = start virtual address of the free range, or 0 if not found
; Clobbers: RAX, RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
global virt_find_free_range
virt_find_free_range:
    mov r8, rsi                     ; R8 = current candidate address
    mov r9, [vma_list_head]         ; R9 = current VMA node
    
.loop:
    test r9, r9
    jz .end_of_list                 ; no more VMAs, candidate is valid
    
    mov rax, [r9 + vma_t.start]
    mov rdx, [r9 + vma_t.end]
    
    ; If the VMA is completely below our current candidate, skip it
    cmp rdx, r8
    jbe .next_vma
    
    ; If there is a gap between r8 and the start of this VMA
    cmp rax, r8
    jbe .no_gap                     ; VMA starts at or below candidate (overlap)
    
    ; Check if the gap is large enough: rax - r8 >= RDI (requested size)
    mov rcx, rax
    sub rcx, r8
    cmp rcx, rdi
    jae .found                      ; gap is large enough!
    
.no_gap:
    ; Candidate overlaps or gap is too small. Move candidate to end of this VMA
    mov r8, rdx
    
.next_vma:
    mov r9, [r9 + vma_t.next]
    jmp .loop
    
.end_of_list:
    ; Check if candidate + size exceeds canonical address space limit (0x00007FFFFFFFFFFF)
    mov rcx, r8
    add rcx, rdi
    mov rax, 0x00007FFFFFFFFFFF
    cmp rcx, rax
    ja .error
    
.found:
    mov rax, r8
    ret
    
.error:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; thread_stack_alloc — allocates a page-aligned virtual stack frame
; Input:
;   RDI = size of stack in bytes (must be page-aligned, e.g. 16384)
; Output:
;   RAX = virtual address of the TOP of the stack (initial RSP value),
;         or 0 on failure
; -----------------------------------------------------------------------------
global thread_stack_alloc
thread_stack_alloc:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; 1. Page-align size just to be safe
    mov rbx, rdi                    ; RBX = requested size
    add rbx, 4095
    and rbx, -4096                  ; RBX = aligned size
    
    ; Calculate total size including 4KB guard page
    mov r12, rbx
    add r12, 4096                   ; R12 = total size (stack + guard page)
    
    ; 2. Find a free virtual range
    mov rdi, r12
    mov rsi, STACK_VIRT_START
    call virt_find_free_range
    test rax, rax
    jz .fail
    
    mov r13, rax                    ; R13 = start virtual address (guard page base)
    
    ; 3. Create VMA for this total range
    mov rdi, r13
    mov rsi, r12
    mov rdx, (VMA_STACK | VMA_READ | VMA_WRITE)
    call vma_create
    test rax, rax
    jz .fail
    
    mov r15, rax                    ; R15 = VMA pointer
    
    ; 4. Allocate and map physical pages only for the actual stack (exclude first 4KB)
    mov r14, r13
    add r14, 4096                   ; R14 = current virtual address cursor (first stack page)
    
    mov rbx, r13
    add rbx, r12                    ; RBX = end virtual address of stack (top)
    
.map_loop:
    cmp r14, rbx
    jae .map_success
    
    ; Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .oom_cleanup
    
    ; Map virtual page to physical frame
    mov rdi, r14                    ; virtual address
    mov rsi, rax                    ; physical address
    mov rdx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_NX)
    call virt_map
    
    add r14, 4096
    jmp .map_loop
    
.map_success:
    ; Generate canary using RDTSC (supported on all x86-64 processors)
    rdtsc
    shl rdx, 32
    or rax, rdx
    xor rax, rbx                    ; mix with stack top address for spatial uniqueness
    
    ; Stamp canary immediately below return pointer (at stack_top - 16)
    mov [rbx - 16], rax
    
    ; Store expected canary in VMA metadata (file_size field)
    mov [r15 + vma_t.file_size], rax

    ; Return the TOP of the stack (RBX)
    mov rax, rbx
    
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.oom_cleanup:
    ; Clean up previously mapped pages
    ; Loop from R13 + 4096 to R14 (exclusive)
    mov r12, r13
    add r12, 4096                   ; R12 = start of stack pages
.cleanup_loop:
    cmp r12, r14
    jae .destroy_vma
    
    ; Get mapped physical address to free it
    mov rdi, r12
    call virt_translate
    test rax, rax
    jz .skip_free
    
    mov rdi, rax
    call phys_free_page
.skip_free:
    ; Unmap virtual address
    mov rdi, r12
    call virt_unmap
    
    add r12, 4096
    jmp .cleanup_loop

.destroy_vma:
    mov rdi, r15
    call vma_destroy
    
.fail:
    xor rax, rax
    jmp .exit

; -----------------------------------------------------------------------------
; thread_stack_free — frees a previously allocated thread stack frame
; Input:
;   RDI = virtual address of the TOP of the stack (exclusive, returned by alloc)
;   RSI = size of the stack in bytes (excluding guard page)
; Output: none
; -----------------------------------------------------------------------------
global thread_stack_free
thread_stack_free:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = top of stack (exclusive)
    mov r12, rsi                    ; R12 = stack size
    
    ; Calculate total size including 4KB guard page
    mov rdx, r12
    add rdx, 4096                   ; RDX = total size
    
    ; Calculate start address (start = top - total_size)
    mov r13, rbx
    sub r13, rdx                    ; R13 = start address of guard page (page-aligned)
    
    ; Find the VMA corresponding to the start address (guard page base) to destroy it later
    mov rdi, r13
    call vma_find
    mov r14, rax                    ; R14 = VMA pointer (or 0)
    
    ; Verify stack canary before reclaiming stack pages
    test r14, r14
    jz .free_pages                  ; if no VMA, skip check (should not happen)
    
    ; Check if this is a stack VMA
    mov rax, [r14 + vma_t.flags]
    test rax, VMA_STACK
    jz .free_pages                  ; if not a stack VMA, skip check
    
    ; Read expected and actual canaries
    mov rcx, [r14 + vma_t.file_size] ; RCX = expected canary
    mov rdx, [rbx - 16]             ; RDX = actual canary
    cmp rcx, rdx
    jne .canary_corrupted
    
.free_pages:
    ; Free all physical pages and unmap virtual space for the actual stack pages
    mov rcx, r13
    add rcx, 4096                   ; RCX = current virtual address cursor (first stack page)
.free_loop:
    cmp rcx, rbx
    jae .unmap_guard
    
    push rcx
    
    ; Translate to physical address
    mov rdi, rcx
    call virt_translate
    test rax, rax
    jz .skip_phys_free
    
    ; Free the physical page frame
    mov rdi, rax
    call phys_free_page
    
.skip_phys_free:
    ; Unmap the virtual page
    pop rcx
    push rcx
    mov rdi, rcx
    call virt_unmap
    
    pop rcx
    add rcx, 4096
    jmp .free_loop

.unmap_guard:
    ; Also unmap the guard page virtual address to keep page tables clean
    mov rdi, r13
    call virt_unmap

.free_vma:
    ; Destroy the VMA if found
    test r14, r14
    jz .exit
    
    mov rdi, r14
    call vma_destroy

.exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.canary_corrupted:
    ; Print mismatch details to UART
    mov rsi, msg_canary_error_prefix
    call uart_print_str
    
    mov rdi, rbx                    ; stack top
    call uart_print_hex64
    
    mov rsi, msg_canary_error_infix1
    call uart_print_str
    
    mov rdi, [r14 + vma_t.file_size] ; expected canary
    call uart_print_hex64
    
    mov rsi, msg_canary_error_infix2
    call uart_print_str
    
    mov rdi, [rbx - 16]             ; found/actual canary
    call uart_print_hex64
    
    mov rsi, msg_newline
    call uart_print_str
    
    ; Trigger diagnostic panic
    mov rdi, msg_canary_error_reason
    mov rsi, [rsp + 32]             ; caller RIP (32 bytes offset due to 4 register pushes)
    call kernel_panic
    cli
.halt_canary:
    hlt
    jmp .halt_canary

; -----------------------------------------------------------------------------
; is_valid_stack_address — checks if a pointer is a valid stack address
; Input:
;   RDI = address to check
; Output:
;   RAX = 1 if valid, 0 if not
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global is_valid_stack_address
is_valid_stack_address:
    ; 1. Must be 8-byte aligned
    test rdi, 7
    jnz .invalid
    
    ; 2. Check early kernel stack
    extern kernel_stack_bottom
    extern kernel_stack_top
    mov rax, kernel_stack_bottom
    cmp rdi, rax
    jb .check_df_stack
    mov rax, kernel_stack_top
    cmp rdi, rax
    jb .valid                       ; inside kernel stack!
    
.check_df_stack:
    extern double_fault_stack_bottom
    extern double_fault_stack_top
    mov rax, double_fault_stack_bottom
    cmp rdi, rax
    jb .check_pf_stack
    mov rax, double_fault_stack_top
    cmp rdi, rax
    jb .valid                       ; inside DF stack!
    
.check_pf_stack:
    extern page_fault_stack_bottom
    extern page_fault_stack_top
    mov rax, page_fault_stack_bottom
    cmp rdi, rax
    jb .check_nmi_stack
    mov rax, page_fault_stack_top
    cmp rdi, rax
    jb .valid                       ; inside PF stack!
    
.check_nmi_stack:
    extern nmi_stack_bottom
    extern nmi_stack_top
    mov rax, nmi_stack_bottom
    cmp rdi, rax
    jb .check_vma_stacks
    mov rax, nmi_stack_top
    cmp rdi, rax
    jb .valid                       ; inside NMI stack!
    
.check_vma_stacks:
    ; Call vma_find
    push rdi
    call vma_find                   ; RAX = VMA pointer or 0
    pop rdi
    test rax, rax
    jz .invalid
    
    ; Check if VMA is stack VMA
    mov rcx, [rax + vma_t.flags]
    test rcx, VMA_STACK
    jz .invalid
    
.valid:
    mov rax, 1
    ret
.invalid:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; stack_trace_walk — prints a backtrace starting from RBP
; Input:
;   RDI = initial RBP (if 0, starts from current RBP)
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10
; -----------------------------------------------------------------------------
global stack_trace_walk
stack_trace_walk:
    push rbp
    push rbx
    push r12
    push r13
    
    mov r12, rdi                    ; R12 = current RBP
    test r12, r12
    jnz .start_walk
    
    ; If RDI is 0, read current RBP (caller's RBP is RBP value before we pushed)
    mov r12, [rsp + 24]             ; RSP + 24 contains the pushed RBP value!
    
.start_walk:
    ; Print backtrace header
    mov rsi, msg_backtrace_header
    call uart_print_str
    
    mov r13, 0                      ; R13 = frame counter (max depth 20)
    
.walk_loop:
    cmp r13, 20                     ; Max depth 20 frames
    jae .done_walk
    
    ; 1. Check if current RBP is a valid stack address
    mov rdi, r12
    call is_valid_stack_address
    test rax, rax
    jz .done_walk                   ; invalid pointer, stop walking
    
    ; 2. Print frame index
    mov rsi, msg_frame_prefix
    call uart_print_str
    
    mov rdi, r13
    call uart_print_hex64
    
    mov rsi, msg_frame_infix
    call uart_print_str
    
    ; 3. Print return address: [R12 + 8]
    ; First verify if R12 + 8 is also a valid stack address!
    mov rdi, r12
    add rdi, 8
    call is_valid_stack_address
    test rax, rax
    jz .done_walk
    
    mov rdi, [r12 + 8]              ; RDI = RIP (return address)
    call uart_print_hex64
    
    mov rsi, msg_newline
    call uart_print_str
    
    ; 4. Update R12 = [R12] (next RBP)
    mov r12, [r12]
    
    inc r13
    jmp .walk_loop
    
.done_walk:
    mov rsi, msg_backtrace_footer
    call uart_print_str
    
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; MAX_CPUS limit
MAX_CPUS equ 16

; -----------------------------------------------------------------------------
; smp_stacks_init — allocates isolated stack sections for multi-core thread execution
; Input: none
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11, R12
; -----------------------------------------------------------------------------
global smp_stacks_init
smp_stacks_init:
    push r12
    
    ; Clear the stack array
    mov rdi, smp_cpu_stacks
    xor rax, rax
    mov rcx, MAX_CPUS
    cld
    rep stosq
    
    ; Retrieve active cores count
    extern smp_active_cores
    mov r12d, [smp_active_cores]    ; R12D = core count
    
    ; Core 0 (BSP) uses the statically defined kernel_stack_top.
    ; Store it in the array at index 0 just for completeness!
    extern kernel_stack_top
    mov rax, kernel_stack_top
    mov [smp_cpu_stacks], rax
    
    ; If only 1 core is active, we are done
    cmp r12d, 1
    jbe .done
    
    ; Loop from core_id = 1 to core_count - 1
    mov r8, 1                       ; R8 = current core_id
    
.alloc_loop:
    cmp r8, r12
    jae .done
    
    ; Save core_id
    push r8
    push r12
    
    ; Allocate a 16KB stack frame with 4KB guard page
    mov rdi, 16384                  ; 16KB size
    call thread_stack_alloc
    test rax, rax
    jz .fail
    
    pop r12
    pop r8
    
    ; Store the allocated stack top in the array at index core_id
    mov [smp_cpu_stacks + r8 * 8], rax
    
    inc r8
    jmp .alloc_loop
    
.done:
    pop r12
    ret
    
.fail:
    ; Print failure to UART
    mov rsi, msg_smp_stack_fail
    call uart_print_str
    
    ; Trigger diagnostic panic
    mov rdi, msg_smp_stack_reason
    mov rsi, [rsp + 24]             ; RIP of caller (since we pushed r12 at start, then r8, r12 in loop = 24 bytes)
    call kernel_panic
    cli
.halt:
    hlt
    jmp .halt

; -----------------------------------------------------------------------------
; smp_get_cpu_stack — retrieves the stack top address for a given CPU ID
; Input:
;   RDI = CPU ID (0 to MAX_CPUS - 1)
; Output:
;   RAX = stack top address, or 0 if invalid CPU ID or not allocated
; -----------------------------------------------------------------------------
global smp_get_cpu_stack
smp_get_cpu_stack:
    cmp rdi, MAX_CPUS
    jae .invalid
    
    mov rax, [smp_cpu_stacks + rdi * 8]
    ret
    
.invalid:
    xor rax, rax
    ret

section .data

align 8
msg_canary_error_prefix: db "ERROR: Stack canary mismatch detected for stack top ", 0
msg_canary_error_infix1: db "! Expected: ", 0
msg_canary_error_infix2: db " Found: ", 0
msg_canary_error_reason: db "Stack canary corruption detected", 0
msg_newline:             db 0x0D, 0x0A, 0

msg_backtrace_header:    db 0x0D, 0x0A, "--- STACK BACKTRACE ---", 0x0D, 0x0A, 0
msg_frame_prefix:        db "  [", 0
msg_frame_infix:         db "] RIP: ", 0
msg_backtrace_footer:    db "-----------------------", 0x0D, 0x0A, 0

msg_smp_stack_fail:      db "ERROR: Failed to allocate isolated execution stack for AP core!", 0x0D, 0x0A, 0
msg_smp_stack_reason:    db "Failed to allocate multi-core isolated stack", 0

section .bss
align 8
global smp_cpu_stacks
smp_cpu_stacks: resq MAX_CPUS

section .text

%endif ; LIB_MEM_VIRT_STACK_ASM
