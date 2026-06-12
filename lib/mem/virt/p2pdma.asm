; =============================================================================
; Tattva OS — lib/mem/virt/p2pdma.asm
; =============================================================================
; PCIe Peer-to-Peer (P2P) DMA mapping subsystem (Milestone 23.5).
; Configures direct, secure peer-to-peer DMA mappings between PCIe devices
; (e.g. NVMe and GPU) bypassing system host RAM.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_P2PDMA_ASM
%define LIB_MEM_VIRT_P2PDMA_ASM

[BITS 64]

; p2p_map_t tracking descriptor structure
struc p2p_map_t
    .provider_phys resq 1      ; Provider physical BAR base address (e.g. GPU VRAM)
    .size          resq 1      ; Size in bytes (page aligned)
    .consumer_bdf  resw 1      ; Consumer 16-bit BDF (Bus/Device/Function)
    .dma_addr      resq 1      ; Resolved P2P DMA address
    .flags         resq 1      ; Properties/permissions
    .next          resq 1      ; Pointer to next mapping in global list
endstruc

section .text

; External allocator symbols
extern heap_alloc
extern heap_free
extern kernel_end
extern phys_state

; -----------------------------------------------------------------------------
; is_valid_p2p_phys_addr — Validates physical memory alignment and boundaries
; Input:
;   RDI = physical address
; Output:
;   RAX = 1 if valid, 0 if invalid (kernel-protected or misaligned)
; -----------------------------------------------------------------------------
is_valid_p2p_phys_addr:
    ; 1. Alignment check
    test rdi, 4095
    jnz .invalid

    ; 2. Overlap check with kernel code [0x100000, kernel_end]
    cmp rdi, 0x100000
    jb .valid

    mov rax, kernel_end
    cmp rdi, rax
    jb .invalid

.valid:
    mov rax, 1
    ret
.invalid:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; p2pdma_map_device — Sets up direct DMA mapping between peer PCIe devices
; Input:
;   RDI = provider physical BAR address (e.g. GPU VRAM base HPA/GPA)
;   RSI = mapping size in bytes
;   RDX = consumer device 16-bit BDF identifier
;   RCX = mapping flags
; Output:
;   RAX = resolved P2P DMA address, or 0 on failure
; -----------------------------------------------------------------------------
global p2pdma_map_device
p2pdma_map_device:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; rbx = provider BAR address
    mov r12, rsi                    ; r12 = size
    mov r13, rdx                    ; r13 = consumer BDF
    mov r15, rcx                    ; r15 = flags

    ; 1. Validate inputs
    test rbx, rbx
    jz .fail
    test r12, r12
    jz .fail

    ; Enforce page alignment
    test rbx, 4095
    jnz .fail
    test r12, 4095
    jnz .fail

    ; 2. Enforce strict physical boundary validations to secure memory
    mov rdi, rbx
    call is_valid_p2p_phys_addr
    test rax, rax
    jz .fail

    ; 3. BDF must be non-zero
    test r13w, r13w
    jz .fail

    ; 4. Allocate tracking structure
    mov rdi, p2p_map_t_size
    call heap_alloc
    test rax, rax
    jz .fail
    mov r14, rax                    ; r14 = p2p_map_t pointer

    ; 5. Populate tracking entry
    mov [r14 + p2p_map_t.provider_phys], rbx
    mov [r14 + p2p_map_t.size], r12
    mov [r14 + p2p_map_t.consumer_bdf], r13w
    mov [r14 + p2p_map_t.dma_addr], rbx            ; Identity mapping (direct BAR address)
    mov [r14 + p2p_map_t.flags], r15
    mov qword [r14 + p2p_map_t.next], 0

    ; 6. Link to global tracking list (head insertion)
    mov rdx, [p2p_list_head]
    mov [r14 + p2p_map_t.next], rdx
    mov [p2p_list_head], r14

    mov rax, rbx                    ; Return mapped P2P DMA address
    jmp .exit

.fail:
    xor rax, rax                    ; return 0 (failure)
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; p2pdma_unmap_device — Removes P2P DMA mappings between peer devices
; Input:
;   RDI = resolved P2P DMA address
;   RSI = mapping size in bytes
;   RDX = consumer device 16-bit BDF identifier
; Output:
;   RAX = 1 on success, 0 on failure (not found)
; -----------------------------------------------------------------------------
global p2pdma_unmap_device
p2pdma_unmap_device:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = target dma_addr
    mov r12, rsi                    ; R12 = size
    mov r13, rdx                    ; R13 = BDF

    lea rsi, [p2p_list_head]        ; RSI = address of pointer to current node
    mov rdi, [rsi]                  ; RDI = current node pointer

.loop:
    test rdi, rdi
    jz .fail                        ; not found

    ; Match check
    cmp [rdi + p2p_map_t.dma_addr], rbx
    jne .next
    cmp [rdi + p2p_map_t.size], r12
    jne .next
    cmp [rdi + p2p_map_t.consumer_bdf], r13w
    jne .next

    ; Match found! Unlink node
    mov rax, [rdi + p2p_map_t.next]
    mov [rsi], rax                  ; previous_node->next = node->next

    ; Free tracking structure
    call heap_free
    mov rax, 1                      ; return success
    jmp .exit

.next:
    lea rsi, [rdi + p2p_map_t.next]
    mov rdi, [rsi]
    jmp .loop

.fail:
    xor rax, rax                    ; return 0
.exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data

align 8
global p2p_list_head
p2p_list_head: dq 0

%endif ; LIB_MEM_VIRT_P2PDMA_ASM
