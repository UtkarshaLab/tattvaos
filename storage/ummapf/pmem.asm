; =============================================================================
; Tattva OS — storage/ummapf/pmem.asm
; =============================================================================
; PMEM Byte-Addressability (Subfeature 27.2).
; Maps NVDIMMs directly into virtual space, treating the drive as byte-addressable RAM.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef STORAGE_UMMAPF_PMEM_ASM
%define STORAGE_UMMAPF_PMEM_ASM

[BITS 64]

%ifndef VMA_READ
VMA_READ        equ (1 << 0)
VMA_WRITE       equ (1 << 1)
VMA_EXEC        equ (1 << 2)
VMA_USER        equ (1 << 3)
%endif

VMA_PMEM        equ (1 << 11)

; Page Table Flags
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_NX         equ (1 << 63)

struc vma_t
    .start      resq 1          ; Start virtual address (page-aligned)
    .end        resq 1          ; End virtual address (page-aligned, exclusive)
    .flags      resq 1          ; VMA flags
    .next       resq 1          ; Pointer to next VMA in the list
    .file_ptr   resq 1          ; Pointer to mapped file structure (or nvdimm_t pointer)
    .file_off   resq 1          ; Offset inside the file
    .file_size  resq 1          ; Original mapped size of the file
endstruc

struc nvdimm_t
    .phys_base  resq 1          ; Base physical address of NVDIMM range
    .size       resq 1          ; Size of NVDIMM region in bytes
endstruc

section .data

global nvdimm_dev
nvdimm_dev:
    istruc nvdimm_t
        at nvdimm_t.phys_base, dq 0
        at nvdimm_t.size,      dq 0
    iend

section .text

; External symbols
extern vma_create
extern virt_map

; -----------------------------------------------------------------------------
; vma_map_pmem — maps a persistent memory range into a VMA (Subfeature 27.2)
; Input:
;   RDI = start virtual address
;   RSI = mapping size in bytes
;   RDX = VMA flags (read, write, exec, user, etc.)
;   R8  = pointer to nvdimm_t structure
;   R9  = offset inside the NVDIMM (page-aligned)
; Output:
;   RAX = pointer to the created VMA structure, or 0 if overlap/OOM
; -----------------------------------------------------------------------------
global vma_map_pmem
vma_map_pmem:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = start
    mov r13, rsi                    ; R13 = size
    mov r14, rdx                    ; R14 = flags
    mov r15, r8                     ; R15 = nvdimm_ptr
    mov rbx, r9                     ; RBX = offset

    ; Add the VMA_PMEM flag to mark it as PMEM mapped
    or r14, VMA_PMEM

    ; Call standard vma_create to check overlaps & insert in sorting list
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call vma_create
    test rax, rax
    jz .err

    ; Populate file metadata fields (repurposed for NVDIMM mapping)
    mov [rax + vma_t.file_ptr], r15
    mov [rax + vma_t.file_off], rbx
    mov [rax + vma_t.file_size], r13

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.err:
    xor rax, rax
    jmp .done

; -----------------------------------------------------------------------------
; virt_handle_pmem_map — page fault handler for PMEM mappings
; Input:
;   RDI = faulting virtual address
;   RSI = VMA pointer
; Output:
;   RAX = 1 on success, 0 on failure (OOM/out of bounds)
; -----------------------------------------------------------------------------
global virt_handle_pmem_map
virt_handle_pmem_map:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = faulting virtual address
    mov r13, rsi                    ; R13 = VMA pointer

    ; 1. Page-align the faulting virtual address
    mov r14, r12
    and r14, -4096                  ; R14 = virtual page address

    ; 2. Compute the offset inside the mapping
    ; offset = virtual_page - vma->start + vma->file_off
    mov rbx, r14
    sub rbx, [r13 + vma_t.start]
    add rbx, [r13 + vma_t.file_off] ; RBX = NVDIMM offset

    ; 3. Retrieve NVDIMM device structure
    mov r15, [r13 + vma_t.file_ptr] ; R15 = pointer to nvdimm_t
    test r15, r15
    jz .err

    ; Check if offset is within NVDIMM limits
    mov rax, [r15 + nvdimm_t.size]
    cmp rbx, rax
    jae .err

    ; 4. Calculate physical address of the persistent storage
    ; phys_addr = nvdimm->phys_base + offset
    mov rcx, [r15 + nvdimm_t.phys_base]
    test rcx, rcx
    jz .err
    add rcx, rbx                    ; RCX = physical block address

    ; 5. Map the physical address directly to the virtual address
    mov rsi, rcx                    ; RSI = physical address (arg 2 of virt_map)
    mov rdx, [r13 + vma_t.flags]    ; RDX = vma->flags
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

    mov rdi, r14                    ; RDI = virtual page (arg 1 of virt_map)
    mov rdx, rbx                    ; RDX = mapping flags (arg 3 of virt_map)
    call virt_map
    test rax, rax
    jz .err

    mov rax, 1                      ; return 1 (success)
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.err:
    xor rax, rax                    ; return 0 (failure)
    jmp .exit

%endif ; STORAGE_UMMAPF_PMEM_ASM
