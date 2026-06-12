; =============================================================================
; Tattva OS — lib/mem/virt/dmabuf.asm
; =============================================================================
; DMA-BUF direct NVMe-to-GPU Routing (Milestone 23.3).
; Establishes VRAM-backed DMA-BUF descriptors and submits direct NVMe read
; commands mapping target destinations to GPU physical memory, bypassing CPU RAM.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_DMABUF_ASM
%define LIB_MEM_VIRT_DMABUF_ASM

[BITS 64]

; DMA-BUF structure definition
struc dma_buf_t
    .gpu_phys      resq 1      ; 64-bit physical target frame address (GPU VRAM)
    .size          resq 1      ; Buffer capacity in bytes (page aligned)
    .flags         resq 1      ; Properties/permissions
    .ref_count     resd 1      ; Reference counter for life cycle tracking
endstruc

section .text

; External allocator and driver symbols
extern heap_alloc
extern heap_free
extern kernel_end

; -----------------------------------------------------------------------------
; is_valid_dmabuf_phys_addr — Verifies GPU physical target address is safe
; Input:
;   RDI = target physical address
; Output:
;   RAX = 1 if valid, 0 if invalid (reserved or kernel-protected region)
; -----------------------------------------------------------------------------
is_valid_dmabuf_phys_addr:
    ; 1. Alignment check
    test rdi, 4095
    jnz .invalid

    ; 2. Must not overlap host kernel text/data
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
; dmabuf_create — Allocates and registers a new DMA-BUF descriptor
; Input:
;   RDI = GPU VRAM physical base address (4KB page-aligned)
;   RSI = buffer size in bytes (4KB page-aligned)
;   RDX = descriptor flags
; Output:
;   RAX = pointer to dma_buf_t, or 0 on failure
; -----------------------------------------------------------------------------
global dmabuf_create
dmabuf_create:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = GPU physical address
    mov r12, rsi                    ; R12 = size
    mov r13, rdx                    ; R13 = flags

    ; 1. Alignment checks
    test rbx, 4095
    jnz .fail
    test r12, 4095
    jnz .fail
    test r12, r12
    jz .fail

    ; 2. Security audit on physical destination base
    mov rdi, rbx
    call is_valid_dmabuf_phys_addr
    test rax, rax
    jz .fail

    ; 3. Allocate descriptor structure
    mov rdi, dma_buf_t_size
    call heap_alloc
    test rax, rax
    jz .fail

    ; 4. Initialize fields
    mov [rax + dma_buf_t.gpu_phys], rbx
    mov [rax + dma_buf_t.size], r12
    mov [rax + dma_buf_t.flags], r13
    mov dword [rax + dma_buf_t.ref_count], 1

    jmp .exit

.fail:
    xor rax, rax
.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dmabuf_destroy — Releases reference and frees the descriptor when 0
; Input:
;   RDI = pointer to dma_buf_t
; Output: none
; -----------------------------------------------------------------------------
global dmabuf_destroy
dmabuf_destroy:
    test rdi, rdi
    jz .done

    push rbx
    mov rbx, rdi

    ; Atomically decrement reference count
    lock dec dword [rbx + dma_buf_t.ref_count]
    jnz .exit

    ; Free node if reference dropped to 0
    mov rdi, rbx
    call heap_free

.exit:
    pop rbx
.done:
    ret

; -----------------------------------------------------------------------------
; dmabuf_direct_route_nvme_read — Route NVMe read streams directly to GPU VRAM
; Input:
;   RDI = pointer to dma_buf_t
;   RSI = NVMe starting block/slot index
;   RDX = offset in DMA-BUF (4KB page-aligned)
;   RCX = transfer size in bytes (4KB page-aligned)
; Output:
;   RAX = 1 on success, 0 on failure (OOB or driver read error)
; -----------------------------------------------------------------------------
global dmabuf_direct_route_nvme_read
dmabuf_direct_route_nvme_read:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = dma_buf pointer
    mov r12, rsi                    ; R12 = NVMe starting slot
    mov r13, rdx                    ; R13 = offset in DMA-BUF
    mov r14, rcx                    ; R14 = transfer size

    ; 1. Validate inputs
    test rbx, rbx
    jz .fail

    ; Enforce page alignment
    test r13, 4095
    jnz .fail
    test r14, 4095
    jnz .fail
    test r14, r14
    jz .fail

    ; 2. Bound check offset and size
    mov rax, r13
    add rax, r14
    cmp rax, [rbx + dma_buf_t.size]
    ja .fail                        ; out of bounds

    ; 3. Calculate destination GPU physical address
    mov r15, [rbx + dma_buf_t.gpu_phys]
    add r15, r13                    ; R15 = starting GPU VRAM physical address

    ; 4. Route NVMe reads page-by-page directly to GPU VRAM
    xor rbx, rbx                    ; RBX = page loop index (byte offset)

.loop_pages:
    cmp rbx, r14
    jae .success

    ; Target GPU physical address for this page
    mov rsi, r15
    add rsi, rbx                    ; RSI = physical destination (VRAM page)

    ; Security verification: validate physical target range
    mov rdi, rsi
    call is_valid_dmabuf_phys_addr
    test rax, rax
    jz .fail

    ; Calculate slot index for this page (each page is 1 slot in NVMe swap)
    mov rdi, rbx
    shr rdi, 12                     ; page offset index
    add rdi, r12                    ; RDI = NVMe slot index

    ; Call NVMe driver read directly (RDI = slot, RSI = dest_phys)
    ; This triggers peer-to-peer DMA over PCIe, bypassing host CPU RAM entirely!
    push rbx
    extern nvme_read_page
    call nvme_read_page
    pop rbx
    test rax, rax
    jz .fail                        ; NVMe driver read failed!

    add rbx, 4096
    jmp .loop_pages

.success:
    mov rax, 1
    jmp .exit

.fail:
    xor rax, rax
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_DMABUF_ASM
