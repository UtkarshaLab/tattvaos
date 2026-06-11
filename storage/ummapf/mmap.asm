; =============================================================================
; Tattva OS — storage/ummapf/mmap.asm
; =============================================================================
; Memory-Mapped Files (mmap) implementation (Subfeatures 17.1, 17.2, 17.3).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef STORAGE_UMMAPF_MMAP_ASM
%define STORAGE_UMMAPF_MMAP_ASM

[BITS 64]

%ifndef VMA_READ
VMA_READ        equ (1 << 0)
VMA_WRITE       equ (1 << 1)
VMA_EXEC        equ (1 << 2)
VMA_USER        equ (1 << 3)
VMA_FILE        equ (1 << 8)
%endif


; Page Table Flags (matching pgtable.asm)
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_DIRTY      equ (1 << 6)
PAGE_NX         equ (1 << 63)

; Mock file structure (representing a file in our NVMe/extent log-structured filesystem)
struc mock_file_t
    .size       resq 1          ; File size in bytes
    .blocks     resq 32         ; Array of 32 physical page backing pointers (up to 128KB)
endstruc

section .text

; External symbols
extern vma_create
extern vma_destroy
extern vma_find
extern phys_alloc_page
extern phys_free_page
extern memzero
extern memcpy
extern virt_map
extern virt_unmap
extern virt_walk_table
extern heap_alloc
extern heap_free

; -----------------------------------------------------------------------------
; mock_file_create — allocates and initializes a mock file structure
; Input:
;   RDI = file size in bytes
; Output:
;   RAX = pointer to mock_file_t, or 0 on OOM
; -----------------------------------------------------------------------------
global mock_file_create
mock_file_create:
    push rbx
    mov rbx, rdi                    ; RBX = file size

    ; Allocate memory for mock_file_t
    mov rdi, mock_file_t_size
    call heap_alloc
    test rax, rax
    jz .done

    ; Zero out the structure
    push rax
    mov rdi, rax
    mov rsi, mock_file_t_size
    call memzero
    pop rax

    ; Set file size
    mov [rax + mock_file_t.size], rbx

.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; mock_file_destroy — destroys mock file and releases backing pages
; Input:
;   RDI = pointer to mock_file_t
; -----------------------------------------------------------------------------
global mock_file_destroy
mock_file_destroy:
    test rdi, rdi
    jz .exit

    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = file_ptr
    xor r12, r12                    ; R12 = block index

.loop:
    cmp r12, 32
    jge .free_struct

    ; Check if physical backing page is allocated
    mov r13, [rbx + mock_file_t.blocks + r12 * 8]
    test r13, r13
    jz .next

    ; Free the physical page
    mov rdi, r13
    call phys_free_page

.next:
    inc r12
    jmp .loop

.free_struct:
    mov rdi, rbx
    call heap_free

    pop r13
    pop r12
    pop rbx
.exit:
    ret

; -----------------------------------------------------------------------------
; storage_read_file_page — reads a 4KB file page from mock storage
; Input:
;   RDI = pointer to mock_file_t
;   RSI = file offset (in bytes, page-aligned)
;   RDX = destination physical page address
; Output: none
; -----------------------------------------------------------------------------
global storage_read_file_page
storage_read_file_page:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = file_ptr
    mov r12, rsi                    ; R12 = file_offset
    mov r13, rdx                    ; R13 = dest_phys

    ; Calculate block index (offset / 4096)
    mov r14, r12
    shr r14, 12                     ; R14 = block index

    cmp r14, 32                     ; check limit
    jae .fill_default

    ; Get backing physical page address
    mov rax, [rbx + mock_file_t.blocks + r14 * 8]
    test rax, rax
    jz .fill_default

    ; Copy content from backing physical page to destination
    mov rdi, r13                    ; dest
    mov rsi, rax                    ; source
    mov rdx, 4096                   ; 4KB
    call memcpy
    jmp .done

.fill_default:
    ; If backing page does not exist or index is out of bounds, write default pattern containing the offset.
    ; This allows testing and verifying page loads deterministically.
    mov rdi, r13
    mov rsi, 4096
    call memzero

    ; Write debug signature: "TATTVA_MOCK_FILE_SECTOR_LOADED_AT_OFFSET_"
    mov rdi, r13
    mov rax, 0x4154544154544154     ; "TATTVA_M"
    mov [rdi], rax
    mov rax, 0x465f4b434f4d5f4f     ; "OCK_FILE"
    mov [rdi + 8], rax
    mov rax, 0x544f535f41544144     ; "_DATA_SO"
    mov [rdi + 16], rax
    mov rax, 0x5f54455346464f5f     ; "_OFFSET_"
    mov [rdi + 24], rax

    ; Write offset in hex at offset 32
    mov [rdi + 32], r12

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; storage_write_file_page — writes a 4KB file page to mock storage
; Input:
;   RDI = pointer to mock_file_t
;   RSI = file offset (in bytes, page-aligned)
;   RDX = source physical page address
; Output: none
; -----------------------------------------------------------------------------
global storage_write_file_page
storage_write_file_page:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = file_ptr
    mov r12, rsi                    ; R12 = file_offset
    mov r13, rdx                    ; R13 = src_phys

    ; Calculate block index (offset / 4096)
    mov r14, r12
    shr r14, 12                     ; R14 = block index

    cmp r14, 32                     ; check limit
    jae .done

    ; Get backing physical page address
    mov rax, [rbx + mock_file_t.blocks + r14 * 8]
    test rax, rax
    jnz .write_data

    ; If backing page does not exist, allocate one
    call phys_alloc_page
    test rax, rax
    jz .done
    mov [rbx + mock_file_t.blocks + r14 * 8], rax

.write_data:
    ; Copy content from source physical page to backing page
    mov rdi, rax                    ; dest
    mov rsi, r13                    ; source
    mov rdx, 4096                   ; 4KB
    call memcpy

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; vma_map_file — binds a file range directly to a new VMA (Subfeature 17.1)
; Input:
;   RDI = start virtual address
;   RSI = mapping size in bytes
;   RDX = VMA flags (read, write, exec, user, etc.)
;   R8  = pointer to mock_file_t
;   R9  = offset inside the file (page-aligned)
; Output:
;   RAX = pointer to the created VMA structure, or 0 if overlap/OOM
; -----------------------------------------------------------------------------
global vma_map_file
vma_map_file:
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

    ; Add the VMA_FILE flag to mark it as file-backed
    or r14, VMA_FILE

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
; virt_handle_file_map — loads disk sector and maps page on page fault (Subfeature 17.2)
; Input:
;   RDI = faulting virtual address
;   RSI = VMA pointer
; Output:
;   RAX = 1 on success, 0 on failure (OOM)
; -----------------------------------------------------------------------------
global virt_handle_file_map
virt_handle_file_map:
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

    ; 3. Allocate a physical RAM page
    call phys_alloc_page
    test rax, rax
    jz .err
    mov r15, rax                    ; R15 = physical page address

    ; 4. Zero the page
    mov rdi, r15
    mov rsi, 4096
    call memzero

    ; 5. Load file page from mock storage
    mov rdi, [r13 + vma_t.file_ptr] ; file_ptr
    mov rsi, rbx                    ; file offset
    mov rdx, r15                    ; dest physical address
    call storage_read_file_page

    ; 6. Map the physical page with VMA permissions
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

    mov rdi, r14                    ; virtual address
    mov rsi, r15                    ; physical address
    mov rdx, rbx                    ; mapping flags
    call virt_map
    test rax, rax
    jz .map_fail

    mov rax, 1                      ; return 1 (success)
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.map_fail:
    mov rdi, r15
    call phys_free_page
.err:
    xor rax, rax                    ; return 0 (failure)
    jmp .exit

; -----------------------------------------------------------------------------
; mmap_msync — writes modified (dirty) cache pages back to storage (Subfeature 17.3)
; Input:
;   RDI = start virtual address
;   RSI = range size in bytes
; Output:
;   RAX = 1 on success, 0 on error
; -----------------------------------------------------------------------------
global mmap_msync
mmap_msync:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = current virtual address (page-aligned)
    and r12, -4096
    
    mov r13, rdi
    add r13, rsi
    add r13, 4095
    and r13, -4096                  ; R13 = end virtual address (exclusive, page-aligned)

.page_loop:
    cmp r12, r13
    jae .success

    ; Find VMA containing this page
    mov rdi, r12
    call vma_find
    test rax, rax
    jz .next_page
    mov r14, rax                    ; R14 = VMA pointer

    ; Check if VMA is file-backed
    mov rax, [r14 + vma_t.flags]
    test rax, VMA_FILE
    jz .next_page

    ; Walk page table to retrieve leaf PTE
    mov rdi, r12
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .next_page                   ; page not mapped

    mov rcx, [rax]                  ; RCX = PTE value
    test rcx, PAGE_PRESENT
    jz .next_page

    test rcx, PAGE_DIRTY
    jz .next_page                   ; page is not modified, no need to write back

    ; Page is dirty! Sync it back to mock storage.
    mov r15, rax                    ; R15 = PTE address
    mov rbx, rcx                    ; RBX = PTE value

    ; Extract physical address of page frame
    mov rdi, rbx
    mov rax, 0xFFFFFFFFFFFFF000
    and rdi, rax                    ; RDI = physical address of RAM page

    ; Compute file offset corresponding to this page
    ; offset = current_page - vma->start + vma->file_off
    mov rsi, r12
    sub rsi, [r14 + vma_t.start]
    add rsi, [r14 + vma_t.file_off] ; RSI = file offset

    ; Call storage_write_file_page
    mov rdx, rdi                    ; RDX = src physical page
    mov rdi, [r14 + vma_t.file_ptr] ; RDI = file pointer
    push r12
    push r13
    push r14
    push r15
    call storage_write_file_page
    pop r15
    pop r14
    pop r13
    pop r12

    ; Clear the dirty bit in the PTE
    and qword [r15], ~PAGE_DIRTY

    ; Flush TLB for this page
    invlpg [r12]

.next_page:
    add r12, 4096
    jmp .page_loop

.success:
    mov rax, 1
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; mmap_munmap — unmaps, synchronizes dirty pages, and destroys file VMA
; Input:
;   RDI = start virtual address
;   RSI = size in bytes
; Output:
;   RAX = 1 on success, 0 on error
; -----------------------------------------------------------------------------
global mmap_munmap
mmap_munmap:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov rbp, rdi                    ; RBP = original start address
    mov r12, rdi                    ; R12 = current page address (page-aligned)
    and r12, -4096

    mov r13, rdi
    add r13, rsi
    add r13, 4095
    and r13, -4096                  ; R13 = end page address (page-aligned)

    ; 1. First sync any dirty page in the range to mock disk storage
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    call mmap_msync

    ; 2. Iterate and clear mappings, freeing physical page frames
.unmap_loop:
    cmp r12, r13
    jae .destroy_vma

    ; Find VMA
    mov rdi, r12
    call vma_find
    test rax, rax
    jz .next_unmap
    mov r14, rax                    ; R14 = VMA pointer

    ; Check if VMA is file-mapped
    mov rax, [r14 + vma_t.flags]
    test rax, VMA_FILE
    jz .next_unmap

    ; Walk page table to extract physical page address
    mov rdi, r12
    xor rsi, rsi
    call virt_walk_table            ; RAX = PTE address
    test rax, rax
    jz .do_unmap

    mov rcx, [rax]
    test rcx, PAGE_PRESENT
    jz .do_unmap

    ; Extract physical address of the page frame
    and rcx, 0xFFFFFFFFFFFFF000
    mov r15, rcx                    ; R15 = physical page to free

    ; Unmap virtual address (clears PTE, invalidates TLB)
    mov rdi, r12
    call virt_unmap

    ; Free the physical RAM page frame
    mov rdi, r15
    call phys_free_page
    jmp .next_unmap

.do_unmap:
    mov rdi, r12
    call virt_unmap

.next_unmap:
    add r12, 4096
    jmp .unmap_loop

.destroy_vma:
    ; Find the VMA containing the original start address and destroy it
    mov rdi, rbp
    call vma_find
    test rax, rax
    jz .done

    mov rdi, rax
    call vma_destroy

.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; STORAGE_UMMAPF_MMAP_ASM
