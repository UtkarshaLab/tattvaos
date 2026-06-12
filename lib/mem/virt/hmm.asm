; =============================================================================
; Tattva OS — lib/mem/virt/hmm.asm
; =============================================================================
; Heterogeneous Memory Management (HMM) & GPU BAR Mappings (Milestone 23.1).
; Maps device PCIe physical BAR aperture memory ranges into the kernel virtual
; address space and tracks the mapping via VMA descriptors.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HMM_ASM
%define LIB_MEM_VIRT_HMM_ASM

[BITS 64]

; Virtual memory page flags
%ifndef PAGE_PRESENT
    %define PAGE_PRESENT    (1 << 0)
%endif
%ifndef PAGE_WRITABLE
    %define PAGE_WRITABLE   (1 << 1)
%endif
%ifndef PAGE_PWT
    %define PAGE_PWT        (1 << 3)
%endif
%ifndef PAGE_PCD
    %define PAGE_PCD        (1 << 4)
%endif
%ifndef PAGE_PAT
    %define PAGE_PAT        (1 << 7)
%endif
%ifndef PAGE_NX
    %define PAGE_NX         (1 << 63)
%endif

; VMA Flags
%ifndef VMA_READ
    %define VMA_READ        (1 << 0)
%endif
%ifndef VMA_WRITE
    %define VMA_WRITE       (1 << 1)
%endif

; Base virtual address to start searching free ranges for GPU BAR mappings
GPU_BAR_VIRT_START      equ 0x9000000000    ; 576GB mark

section .text

; External VM allocations and page table routines
extern vma_create
extern vma_destroy
extern vma_find
extern virt_find_free_range
extern virt_map
extern virt_unmap
extern pat_find_entry
extern kernel_end
extern phys_state

; -----------------------------------------------------------------------------
; is_valid_bar_phys_addr — Verifies target physical address does not overlap kernel
; Input:
;   RDI = Physical Address (must be 4KB page aligned)
; Output:
;   RAX = 1 if valid, 0 if invalid
; -----------------------------------------------------------------------------
is_valid_bar_phys_addr:
    ; 1. Alignment check
    test rdi, 4095
    jnz .invalid

    ; 2. Overlap check with kernel code [0x100000, kernel_end]
    cmp rdi, 0x100000
    jb .valid                       ; below 1MB (BIOS ROM/legacy memory, but usually not BAR)

    mov rax, kernel_end
    cmp rdi, rax
    jb .invalid                     ; overlap detected!

.valid:
    mov rax, 1
    ret
.invalid:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; hmm_map_bar — Maps physical device BAR registers to kernel virtual space
; Input:
;   RDI = physical BAR base address (must be 4KB page-aligned)
;   RSI = aperture size in bytes (must be 4KB page-aligned)
;   RDX = caching mode (0 = Uncached UC, 1 = Write-Combining WC)
; Output:
;   RAX = virtual mapping base address, or 0 on failure
; -----------------------------------------------------------------------------
global hmm_map_bar
hmm_map_bar:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = phys BAR base
    mov r12, rsi                    ; R12 = BAR size
    mov r15, rdx                    ; R15 = caching flag

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
    call is_valid_bar_phys_addr
    test rax, rax
    jz .fail

    ; 3. Scan for a free virtual memory range
    mov rdi, r12
    mov rsi, GPU_BAR_VIRT_START
    call virt_find_free_range
    test rax, rax
    jz .fail
    mov r13, rax                    ; R13 = virtual base address

    ; 4. Allocate backing VMA descriptor
    mov rdi, r13
    mov rsi, r12
    mov rdx, (VMA_READ | VMA_WRITE)
    call vma_create
    test rax, rax
    jz .fail
    mov r14, rax                    ; R14 = VMA pointer

    ; 5. Find caching PAT entry and build mappings
    ; Base flags: present, writable, no-execute (protecting register executions)
    mov r8, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_NX)

    test r15, r15
    jz .setup_uc                    ; mode 0: Uncached (UC)

    ; Write-Combining (WC) Mode
    mov rdi, 1                      ; type 1 = Write-Combining (WC)
    call pat_find_entry
    cmp rax, -1
    je .uc_fallback

    ; Decode PAT index (0-7) to PWT/PCD/PAT paging flags
    xor r9, r9
    test rax, 1                     ; Bit 0: PWT
    jz .pwt_wc_clear
    or r9, PAGE_PWT
.pwt_wc_clear:
    test rax, 2                     ; Bit 1: PCD
    jz .pcd_wc_clear
    or r9, PAGE_PCD
.pcd_wc_clear:
    test rax, 4                     ; Bit 2: PAT
    jz .pat_wc_clear
    or r9, PAGE_PAT
.pat_wc_clear:
    or r8, r9
    jmp .map_aperture

.uc_fallback:
.setup_uc:
    ; Uncached (UC) Mode
    mov rdi, 0                      ; type 0 = Uncached (UC)
    call pat_find_entry
    cmp rax, -1
    je .uc_default

    xor r9, r9
    test rax, 1
    jz .pwt_uc_clear
    or r9, PAGE_PWT
.pwt_uc_clear:
    test rax, 2
    jz .pcd_uc_clear
    or r9, PAGE_PCD
.pcd_uc_clear:
    test rax, 4
    jz .pat_uc_clear
    or r9, PAGE_PAT
.pat_uc_clear:
    or r8, r9
    jmp .map_aperture

.uc_default:
    ; Fallback to standard paging Uncached flags
    or r8, (PAGE_PCD | PAGE_PWT)

.map_aperture:
    xor rcx, rcx                    ; RCX = offset

.map_loop:
    cmp rcx, r12
    jae .success

    mov rdi, r13
    add rdi, rcx                    ; RDI = virtual address
    mov rsi, rbx
    add rsi, rcx                    ; RSI = physical address
    mov rdx, r8                     ; RDX = mapping flags

    push rcx
    push r8
    call virt_map
    pop r8
    pop rcx
    test rax, rax
    jz .cleanup                     ; OOM mapping failure!

    add rcx, 4096
    jmp .map_loop

.success:
    mov rax, r13                    ; Return virtual base address
    jmp .exit

.cleanup:
    ; Unmap partially mapped range
    mov rdi, r13
.cleanup_loop:
    cmp rdi, r13
    add rdi, rcx
    jae .destroy_vma

    push rdi
    push rcx
    push r8
    call virt_unmap
    pop r8
    pop rcx
    pop rdi

    add rdi, 4096
    jmp .cleanup_loop

.destroy_vma:
    mov rdi, r14
    call vma_destroy
.fail:
    xor rax, rax
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hmm_unmap_bar — Removes BAR aperture maps and releases the associated VMA
; Input:
;   RDI = virtual mapping base address
;   RSI = aperture size in bytes
; Output: none
; -----------------------------------------------------------------------------
global hmm_unmap_bar
hmm_unmap_bar:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = virtual base address
    mov r12, rsi                    ; R12 = size in bytes

    test rbx, rbx
    jz .done
    test r12, r12
    jz .done

    ; Find VMA
    mov rdi, rbx
    call vma_find
    mov r13, rax                    ; R13 = VMA pointer

    ; Unmap pages in loop
    xor rcx, rcx
.unmap_loop:
    cmp rcx, r12
    jae .destroy_vma

    mov rdi, rbx
    add rdi, rcx
    push rcx
    call virt_unmap
    pop rcx

    add rcx, 4096
    jmp .unmap_loop

.destroy_vma:
    test r13, r13
    jz .done
    mov rdi, r13
    call vma_destroy

.done:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_HMM_ASM
