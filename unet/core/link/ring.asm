; =============================================================================
; Tattva OS — unet/core/link/ring.asm
; =============================================================================
; Shared packet rings creation and user-space directory mapping.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_RING_ASM
%define UNET_CORE_LINK_RING_ASM

[BITS 64]

%include "unet/core/link/net_ring.inc"

section .text

; -----------------------------------------------------------------------------
; net_ring_create — Allocates and initializes a shared packet ring
; Input:
;   RDI = descriptor count (must be power of two, e.g. 512, 1024)
;   RSI = flags (0 = RX, 1 = TX)
; Output:
;   RAX = pointer to net_ring_t on success, or 0 on failure
; -----------------------------------------------------------------------------
global net_ring_create
net_ring_create:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = descriptor count
    mov r12, rsi                    ; R12 = flags (RX/TX)

    ; Calculate descriptor array size in bytes: count * 32 (size of net_desc_t)
    mov rax, rbx
    shl rax, 5                      ; RAX = size of desc array
    mov r13, rax                    ; R13 = desc array size (page-aligned)

    ; Total allocation size: desc array + 4096 (head page) + 4096 (tail page)
    mov r14, r13
    add r14, 8192                   ; R14 = total virtual range size

    ; Find free virtual range
    mov rdi, r14
    mov rsi, NET_RING_VIRT_START
    call virt_find_free_range
    test rax, rax
    jz .fail
    mov r15, rax                    ; R15 = virtual base of mapped region

    ; Create backing VMA
    mov rdi, r15
    mov rsi, r14
    mov rdx, (VMA_READ | VMA_WRITE)
    call vma_create
    test rax, rax
    jz .fail
    push rax                        ; save VMA pointer on stack

    ; Map physical pages for the virtual range
    mov rcx, r15                    ; RCX = current virtual cursor
    mov rdx, r15
    add rdx, r14                    ; RDX = end address
.map_loop:
    cmp rcx, rdx
    jae .map_done
    
    push rcx
    push rdx
    call phys_alloc_page
    test rax, rax
    jz .oom_cleanup
    mov rsi, rax                    ; RSI = physical address
    pop rdx
    pop rcx
    
    push rcx
    push rdx
    push rsi
    mov rdi, rcx                    ; RDI = virtual address
    mov rdx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_NX)
    call virt_map
    test rax, rax
    jz .oom_cleanup_mapped
    
    pop rsi
    pop rdx
    pop rcx
    add rcx, 4096
    jmp .map_loop

.map_done:
    ; Zero out the allocated memory to avoid uninitialized leaks
    mov rdi, r15
    xor rax, rax
    mov rcx, r14
    shr rcx, 3                      ; convert size to qwords
    cld
    rep stosq

    ; Allocate net_ring_t structure header
    mov rdi, 40                     ; size of net_ring_t
    call heap_alloc
    test rax, rax
    jz .oom_cleanup
    pop rdi                         ; RDI = VMA pointer
    
    ; Setup ring structure fields
    mov [rax + net_ring_t.desc_array], r15
    mov [rax + net_ring_t.desc_count], ebx
    
    ; Store page-aligned head and tail pointers
    mov rcx, r15
    add rcx, r13                    ; RCX = head page base address
    mov [rax + net_ring_t.head_ptr], rcx
    
    add rcx, 4096                   ; RCX = tail page base address
    mov [rax + net_ring_t.tail_ptr], rcx
    
    mov [rax + net_ring_t.flags], r12d
    mov [rax + net_ring_t.vma], rdi
    
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.oom_cleanup_mapped:
    ; Free the physical page that failed to map
    pop rdi
    call phys_free_page
    pop rdx
    pop rcx
.oom_cleanup:
    ; Unmap everything from r15 to current RCX cursor
    mov rdi, r15
.unmap_loop:
    cmp rdi, rcx
    jae .destroy_vma
    
    push rdi
    push rcx
    call virt_translate
    test rax, rax
    jz .skip_free
    mov r12, rax
    
    mov rdi, r12
    call phys_free_page
.skip_free:
    pop rcx
    pop rdi
    
    push rdi
    push rcx
    call virt_unmap
    pop rcx
    pop rdi
    add rdi, 4096
    jmp .unmap_loop

.destroy_vma:
    pop rdi                         ; restore saved VMA pointer
    call vma_destroy
.fail:
    xor rax, rax
    jmp .exit

; -----------------------------------------------------------------------------
; net_ring_map_to_user — Maps a shared ring directly into application address space
; Input:
;   RDI = pointer to net_ring_t structure (in kernel memory)
;   RSI = user-space virtual base address (must be page-aligned)
;   RDX = target user PML4 CR3
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global net_ring_map_to_user
net_ring_map_to_user:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = ring pointer
    mov r12, rsi                    ; R12 = user base address
    mov r13, rdx                    ; R13 = user PML4 CR3

    ; Security verification: check if user base address is within canonical user space limit
    mov rax, 0x00007FFFFFFFFFFF
    cmp r12, rax
    ja .fail                        ; out of user bounds!

    ; Calculate descriptor size
    mov eax, [rbx + net_ring_t.desc_count]
    shl rax, 5                      ; array size in bytes
    mov r14, rax                    ; R14 = desc array size

    ; Calculate total page count to map: (desc array size + 8192) / 4096
    add rax, 8192
    shr rax, 12                     ; RAX = total pages
    mov r15, rax                    ; R15 = total pages

    ; Map kernel pages to user space
    mov rcx, 0                      ; RCX = page index loop variable
.map_loop:
    cmp rcx, r15
    jae .success
    
    ; 1. Find physical address of the kernel page
    mov rax, [rbx + net_ring_t.desc_array]
    mov rdi, rcx
    shl rdi, 12                     ; offset in bytes
    add rdi, rax                    ; kernel virtual address of page
    
    push rcx
    call virt_translate
    pop rcx
    test rax, rax
    jz .fail                        ; failed to translate page!
    
    ; 2. Switch CR3 to target user process PML4 if R13 != 0
    mov rdi, cr3                    ; RDI = current kernel CR3
    test r13, r13
    jz .map_page
    mov cr3, r13                    ; load user PML4
.map_page:
    ; Map the physical frame to user virtual address
    mov rdx, rcx
    shl rdx, 12
    add rdx, r12                    ; RDX = target user virtual address
    
    push rdi
    push rcx
    mov rdi, rdx                    ; virtual destination
    mov rsi, rax                    ; physical frame
    mov rdx, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER | PAGE_NX)
    call virt_map
    pop rcx
    pop rdi
    
    test r13, r13
    jz .next
    mov cr3, rdi                    ; restore kernel CR3
.next:
    test rax, rax
    jz .fail                        ; mapping failed!
    
    inc rcx
    jmp .map_loop

.success:
    mov rax, 1
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    xor rax, rax
    jmp .exit

%endif ; UNET_CORE_LINK_RING_ASM
