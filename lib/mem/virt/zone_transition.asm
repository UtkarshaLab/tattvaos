; =============================================================================
; Tattva OS — lib/mem/virt/zone_transition.asm
; =============================================================================
; Online/Offline Memory Zone Transition Manager.
; Locks memory buddy nodes to block allocations and performs reverse page table
; walks to locate and migrate active virtual mappings prior to safe zone removal.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ZONE_TRANSITION_ASM
%define LIB_MEM_VIRT_ZONE_TRANSITION_ASM

[BITS 64]

; External symbols
extern buddy_nodes
extern buddy_node_count
extern buddy_active_node_index
extern kernel_relocate_page
extern uart_print_str
extern uart_print_hex64
extern uart_print_dec

section .text

; -----------------------------------------------------------------------------
; find_virtual_for_phys — Walks active page tables to find virtual address for physical frame
; Input:  RDI = physical page base address (4KB aligned)
; Output: RAX = virtual address mapped to RDI, or 0 if not found
; -----------------------------------------------------------------------------
global find_virtual_for_phys
find_virtual_for_phys:
    push rbx
    push rcx
    push rdx
    push rsi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    
    mov r12, rdi                    ; R12 = target physical address
    
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = PML4 base physical address
    
    ; PML4 loop (index i)
    xor r8, r8                      ; r8 = PML4 index (0 to 511)
.pml4_loop:
    cmp r8, 512
    jae .not_found
    
    mov rsi, rax
    mov rcx, [rsi + r8 * 8]         ; RCX = PML4 entry
    test rcx, 1                     ; Present?
    jz .pml4_next
    
    and rcx, 0xFFFFFFFFFFFFF000     ; RCX = PDPT physical address
    
    ; PDPT loop (index j)
    xor r9, r9                      ; r9 = PDPT index
.pdpt_loop:
    cmp r9, 512
    jae .pml4_next
    
    mov rdx, [rcx + r9 * 8]         ; RDX = PDPT entry
    test rdx, 1                     ; Present?
    jz .pdpt_next
    
    test rdx, 0x80                  ; 1GB page?
    jz .go_pd
    
    ; 1GB page comparison
    mov rdi, rdx
    and rdi, 0xFFFFFFFFC0000000     ; isolate base
    mov rsi, r12
    and rsi, 0xFFFFFFFFC0000000     ; isolate base
    cmp rdi, rsi
    je .found_1gb
    jmp .pdpt_next
    
.go_pd:
    and rdx, 0xFFFFFFFFFFFFF000     ; RDX = PD physical address
    
    ; PD loop (index k)
    xor r10, r10                    ; r10 = PD index
.pd_loop:
    cmp r10, 512
    jae .pdpt_next
    
    mov rsi, [rdx + r10 * 8]         ; RSI = PD entry
    test rsi, 1                     ; Present?
    jz .pd_next
    
    test rsi, 0x80                  ; 2MB page?
    jz .go_pt
    
    ; 2MB page comparison
    mov rdi, rsi
    and rdi, 0xFFFFFFFFFFE00000
    mov rsi, r12
    and rsi, 0xFFFFFFFFFFE00000
    cmp rdi, rsi
    je .found_2mb
    jmp .pd_next
    
.go_pt:
    and rsi, 0xFFFFFFFFFFFFF000     ; RSI = PT physical address
    
    ; PT loop (index l)
    xor r11, r11                    ; r11 = PT index
.pt_loop:
    cmp r11, 512
    jae .pd_next
    
    mov rax, [rsi + r11 * 8]         ; RAX = PT entry (PTE)
    test rax, 1                     ; Present?
    jz .pt_next
    
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = physical frame address
    cmp rax, r12
    je .found_4kb
    
.pt_next:
    inc r11
    jmp .pt_loop
.pd_next:
    inc r10
    jmp .pd_loop
.pdpt_next:
    inc r9
    jmp .pdpt_loop
.pml4_next:
    inc r8
    jmp .pml4_loop
    
.found_4kb:
    ; Compute virtual address:
    ; PML4 index in r8, PDPT index in r9, PD index in r10, PT index in r11
    mov rax, r8
    shl rax, 39
    mov rbx, r9
    shl rbx, 30
    or rax, rbx
    mov rbx, r10
    shl rbx, 21
    or rax, rbx
    mov rbx, r11
    shl rbx, 12
    or rax, rbx
    
    ; Sign extend (canonical form check for bit 47)
    bt rax, 47
    jnc .exit
    mov rbx, 0xFFFF000000000000
    or rax, rbx
    jmp .exit
    
.found_2mb:
    ; 2MB page virtual address
    mov rax, r8
    shl rax, 39
    mov rbx, r9
    shl rbx, 30
    or rax, rbx
    mov rbx, r10
    shl rbx, 21
    or rax, rbx
    
    ; Add offset within 2MB
    mov rbx, r12
    and rbx, 0x1FFFFF               ; offset within 2MB
    or rax, rbx
    
    bt rax, 47
    jnc .exit
    mov rbx, 0xFFFF000000000000
    or rax, rbx
    jmp .exit
    
.found_1gb:
    ; 1GB page virtual address
    mov rax, r8
    shl rax, 39
    mov rbx, r9
    shl rbx, 30
    or rax, rbx
    
    ; Add offset within 1GB
    mov rbx, r12
    and rbx, 0x3FFFFFFF             ; offset within 1GB
    or rax, rbx
    
    bt rax, 47
    jnc .exit
    mov rbx, 0xFFFF000000000000
    or rax, rbx
    jmp .exit
    
.not_found:
    xor rax, rax
.exit:
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; buddy_offline_node — Locks a memory node and evacuates active pages
; Input:  RDI = node index to offline (0 to 7)
; Output: RAX = number of active pages migrated, or -1 on error
; -----------------------------------------------------------------------------
global buddy_offline_node
buddy_offline_node:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = node index

    ; 1. Verify index range
    cmp r12, [buddy_node_count]
    jae .fail

    ; Calculate slot offset
    mov rax, r12
    imul rax, buddy_node_t_size
    lea rbx, [buddy_nodes + rax]

    ; Check if slot is enabled
    mov rax, [rbx + buddy_node_t.flags]
    test rax, rax
    jz .fail

    ; 2. Lock the memory zone by disabling slot allocations (flags = 0)
    mov qword [rbx + buddy_node_t.flags], 0

    ; Force context write-back if this node is currently active
    cmp r12, [buddy_active_node_index]
    jne .evacuate
    ; Force switch context to node 0 so this offline node is no longer active in globals
    mov qword [buddy_active_node_index], -1
    xor rax, rax                    ; index 0
    extern buddy_load_context
    call buddy_load_context

.evacuate:
    ; 3. Scan buddy metadata to find allocated pages
    mov r13, [rbx + buddy_node_t.start_addr] ; R13 = start physical address
    mov r14, [rbx + buddy_node_t.end_addr]
    sub r14, r13
    shr r14, 12                     ; R14 = page count (N)

    mov r15, [rbx + buddy_node_t.metadata] ; R15 = metadata pointer
    xor rcx, rcx                    ; RCX = index i = 0
    xor r8, r8                      ; R8 = migrated count = 0

.scan_loop:
    cmp rcx, r14
    jae .done

    movzx eax, byte [r15 + rcx]
    test al, 0x80                   ; check free flag (bit 7)
    jnz .next                       ; page is free, skip

    ; Page is allocated! Find its mapped virtual address
    ; physical address = start + i * 4096
    mov rax, rcx
    shl rax, 12
    add rax, r13                    ; RAX = physical frame address

    push rbx
    push r12
    push r13
    push r14
    push r15
    push rcx
    push r8
    mov rdi, rax
    call find_virtual_for_phys      ; RAX = virtual address mapped to it
    mov rbp, rax                    ; RBP = virtual address
    pop r8
    pop rcx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    test rbp, rbp
    jz .next                        ; not mapped or unmapped, skip

    ; Relocate virtual page to secure Node 0 physical frame
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rcx
    push r8
    mov rdi, rbp
    call kernel_relocate_page       ; RAX = 1 if migrated, 0 if not needed, -1 if err
    mov r9, rax
    pop r8
    pop rcx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    cmp r9, 1
    jne .next
    inc r8                          ; increment migrated count

.next:
    inc rcx
    jmp .scan_loop

.done:
    mov r14, r8                     ; Save count in R14
    
    ; Print status
    mov rsi, msg_offline_prefix
    call uart_print_str
    mov rax, r12
    call uart_print_dec
    mov rsi, msg_offline_mid
    call uart_print_str
    mov rax, r14
    call uart_print_dec
    mov rsi, msg_offline_suffix
    call uart_print_str

    mov rax, r14                    ; return migrated count
    jmp .exit

.fail:
    mov rax, -1

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; buddy_online_node — Re-enables a locked buddy allocator node
; Input:  RDI = node index to online (0 to 7)
; Output: RAX = 0 on success, -1 on failure
; -----------------------------------------------------------------------------
global buddy_online_node
buddy_online_node:
    push rbx
    push rcx
    push rdi

    mov rcx, rdi                    ; RCX = index
    cmp rcx, [buddy_node_count]
    jae .fail

    ; Set flag to active
    imul rax, rcx, buddy_node_t_size
    mov qword [buddy_nodes + rax + buddy_node_t.flags], 1

    ; Print status
    mov rsi, msg_online_prefix
    call uart_print_str
    mov rax, rcx
    call uart_print_dec
    mov rsi, msg_online_suffix
    call uart_print_str

    xor rax, rax
    jmp .exit

.fail:
    mov rax, -1
.exit:
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Data Section
; -----------------------------------------------------------------------------
section .data

msg_offline_prefix:     db "Zone Transition: Locked and Offlined Buddy Node ", 0
msg_offline_mid:        db ", migrated ", 0
msg_offline_suffix:     db " active memory pages safely.", 0x0D, 0x0A, 0

msg_online_prefix:      db "Zone Transition: Onlined Buddy Node ", 0
msg_online_suffix:      db " successfully.", 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_ZONE_TRANSITION_ASM
