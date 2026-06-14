; =============================================================================
; Tattva OS — storage/ummapf/dax.asm
; =============================================================================
; Direct-Access (DAX) File System Mapping (Subfeature 27.1).
; Maps storage device blocks directly into VMAs without page cache RAM.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef STORAGE_UMMAPF_DAX_ASM
%define STORAGE_UMMAPF_DAX_ASM

[BITS 64]

%ifndef VMA_READ
VMA_READ        equ (1 << 0)
VMA_WRITE       equ (1 << 1)
VMA_EXEC        equ (1 << 2)
VMA_USER        equ (1 << 3)
%endif

VMA_DAX         equ (1 << 10)

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
    .file_ptr   resq 1          ; Pointer to mapped file structure
    .file_off   resq 1          ; Offset inside the file
    .file_size  resq 1          ; Original mapped size of the file
endstruc

struc mock_file_t
    .size       resq 1          ; File size in bytes
    .blocks     resq 32         ; Array of 32 physical page backing pointers (up to 128KB)
endstruc

section .text

; External symbols
extern vma_create
extern phys_alloc_page
extern memzero
extern virt_map

; -----------------------------------------------------------------------------
; vma_map_dax — maps storage device blocks directly into a VMA (Subfeature 27.1)
; Input:
;   RDI = start virtual address
;   RSI = mapping size in bytes
;   RDX = VMA flags (read, write, exec, user, etc.)
;   R8  = pointer to mock_file_t
;   R9  = offset inside the file (page-aligned)
; Output:
;   RAX = pointer to the created VMA structure, or 0 if overlap/OOM
; -----------------------------------------------------------------------------
global vma_map_dax
vma_map_dax:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = start
    mov r13, rsi                    ; R13 = size
    mov r14, rdx                    ; R14 = flags
    mov r15, r8                     ; R15 = file_ptr
    mov rbx, r9                     ; RBX = file_off

    ; Add the VMA_DAX flag to mark it as direct-access file mapped
    or r14, VMA_DAX

    ; Call standard vma_create to check overlaps & insert in sorting list
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call vma_create
    test rax, rax
    jz .err

    ; Populate file metadata fields
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
; virt_handle_dax_map — page fault handler for DAX mappings
; Input:
;   RDI = faulting virtual address
;   RSI = VMA pointer
; Output:
;   RAX = 1 on success, 0 on failure (OOM)
; -----------------------------------------------------------------------------
global virt_handle_dax_map
virt_handle_dax_map:
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

    ; 2. Compute the file offset corresponding to this virtual page
    ; offset = virtual_page - vma->start + vma->file_off
    mov rbx, r14
    sub rbx, [r13 + vma_t.start]
    add rbx, [r13 + vma_t.file_off] ; RBX = file offset

    ; 3. Calculate block index (offset / 4096)
    mov rax, rbx
    shr rax, 12                     ; RAX = block index
    cmp rax, 32                     ; Limit of 32 blocks (128KB)
    jae .err

    mov r15, [r13 + vma_t.file_ptr] ; R15 = pointer to mock_file_t
    test r15, r15
    jz .err

    ; Check if physical backing page is already allocated in the mock file
    mov rcx, [r15 + mock_file_t.blocks + rax * 8]
    test rcx, rcx
    jnz .map_page                   ; Already allocated, map directly

    ; 4. Not allocated, so allocate a physical frame for backing storage block
    push rax                        ; Save block index
    push rbx                        ; Save file offset
    call phys_alloc_page
    pop rbx                         ; Restore file offset to RBX
    pop rdi                         ; Pop block index to RDI
    test rax, rax
    jz .err
    mov rcx, rax                    ; RCX = physical block address

    ; Store in mock_file_t blocks
    mov [r15 + mock_file_t.blocks + rdi * 8], rcx

    ; 5. Zero-out the newly allocated backing storage block
    push rbx
    push rcx
    mov rdi, rcx
    mov rsi, 4096
    call memzero
    pop rcx
    pop rbx

    ; Write signature: "TATTVA_DAX_BLOCK_LOADED_AT_OFFSET_"
    mov qword [rcx], 0x445f415654544154      ; "TATTVA_D"
    mov qword [rcx + 8], 0x4b434f4c425f5841  ; "AX_BLOCK"
    mov qword [rcx + 16], 0x5f444544414f4c5f ; "_LOADED_"
    mov qword [rcx + 24], 0x455346464f5f5441 ; "AT_OFFSE"
    mov word [rcx + 32], 0x5f54              ; "T_"
    mov [rcx + 40], rbx                      ; Write file offset at offset 40

.map_page:
    ; 6. Map the persistent block directly to the VMA virtual page (No cache copy!)
    mov rsi, rcx                    ; RSI = physical block address (arg 2 of virt_map)
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

    mov rdi, r14                    ; Rdi = virtual address (arg 1 of virt_map)
    mov rdx, rbx                    ; Rdx = mapping flags (arg 3 of virt_map)
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

%endif ; STORAGE_UMMAPF_DAX_ASM
