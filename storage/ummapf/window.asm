; =============================================================================
; Tattva OS — storage/ummapf/window.asm
; =============================================================================
; NVDIMM static hardware window mappings (Subfeature 27.3).
; Routes block access commands through static hardware windows.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef STORAGE_UMMAPF_WINDOW_ASM
%define STORAGE_UMMAPF_WINDOW_ASM

[BITS 64]

%ifndef VMA_READ
VMA_READ        equ (1 << 0)
VMA_WRITE       equ (1 << 1)
VMA_EXEC        equ (1 << 2)
VMA_USER        equ (1 << 3)
%endif

VMA_PMEM_WINDOW equ (1 << 12)

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
    .file_ptr   resq 1          ; Pointer to mapped file structure (or pmem_window_t)
    .file_off   resq 1          ; Offset inside the file
    .file_size  resq 1          ; Original mapped size of the file
endstruc

struc pmem_window_t
    .ctrl_reg       resq 1          ; Current selected block index
    .data_page      resq 1          ; Physical page of the static data window
    .pmem_array     resq 32         ; Array of 32 persistent physical block addresses
    .dirty          resq 1          ; Is the active window dirty?
endstruc

section .text

; External symbols
extern vma_create
extern phys_alloc_page
extern memzero
extern memcpy
extern virt_map

; -----------------------------------------------------------------------------
; pmem_window_init — initializes a pmem hardware window structure
; Input:
;   RDI = pointer to pmem_window_t
; Output: none
; -----------------------------------------------------------------------------
global pmem_window_init
pmem_window_init:
    push rbx
    mov rbx, rdi                    ; RBX = pmem_window_t pointer

    ; 1. Zero out the descriptor
    mov rdi, rbx
    mov rsi, pmem_window_t_size
    call memzero

    ; 2. Allocate data page
    call phys_alloc_page
    test rax, rax
    jz .err
    mov [rbx + pmem_window_t.data_page], rax

    ; 3. Zero the data page
    mov rdi, rax
    mov rsi, 4096
    call memzero

.err:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; pmem_window_select_block — selects block index, flushing current active block
; Input:
;   RDI = pointer to pmem_window_t
;   RSI = new block index (0..31)
; Output: none
; -----------------------------------------------------------------------------
global pmem_window_select_block
pmem_window_select_block:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = pointer to pmem_window_t
    mov r12, rsi                    ; R12 = new block index (0..31)

    cmp r12, 32
    jae .done

    ; 1. Check if window is dirty
    mov rax, [rbx + pmem_window_t.dirty]
    test rax, rax
    jz .no_flush

    ; Static window is dirty! Flush to persistent array.
    mov r13, [rbx + pmem_window_t.ctrl_reg] ; R13 = current block index
    mov r14, [rbx + pmem_window_t.pmem_array + r13 * 8] ; R14 = backing block physical address
    test r14, r14
    jnz .do_flush

    ; Backing block not allocated, allocate one
    call phys_alloc_page
    test rax, rax
    jz .done
    mov r14, rax
    mov [rbx + pmem_window_t.pmem_array + r13 * 8], r14

.do_flush:
    ; Copy from static window to backing block
    mov rdi, r14                    ; dest = backing page
    mov rsi, [rbx + pmem_window_t.data_page] ; source = static data page
    mov rdx, 4096                   ; 4KB
    call memcpy

.no_flush:
    ; 2. Load new block
    mov [rbx + pmem_window_t.ctrl_reg], r12 ; update current block
    mov r14, [rbx + pmem_window_t.pmem_array + r12 * 8] ; R14 = new backing block page
    test r14, r14
    jnz .do_load

    ; Backing block does not exist: zero static window page & write signature
    mov rdi, [rbx + pmem_window_t.data_page]
    mov rsi, 4096
    call memzero

    mov rcx, [rbx + pmem_window_t.data_page]
    mov qword [rcx], 0x505f415654544154      ; "TATTVA_P"
    mov qword [rcx + 8], 0x444e49575f4d454d  ; "MEM_WIND"
    mov qword [rcx + 16], 0x4544414f4c5f574f ; "OW_LOADE"
    mov qword [rcx + 24], 0x5f4b434f4c425f44 ; "D_BLOCK_"
    mov [rcx + 32], r12                      ; new block index
    jmp .clear_dirty

.do_load:
    ; Copy backing block page to static window data page
    mov rdi, [rbx + pmem_window_t.data_page] ; dest = static window page
    mov rsi, r14                            ; source = backing block page
    mov rdx, 4096
    call memcpy

.clear_dirty:
    mov qword [rbx + pmem_window_t.dirty], 0

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; vma_map_pmem_window — maps the static hardware window to a virtual address
; Input:
;   RDI = start virtual address
;   RSI = mapping size in bytes (normally 4096)
;   RDX = VMA flags (read, write, exec, user, etc.)
;   R8  = pointer to pmem_window_t
; Output:
;   RAX = pointer to the created VMA structure, or 0 if overlap/OOM
; -----------------------------------------------------------------------------
global vma_map_pmem_window
vma_map_pmem_window:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = start
    mov r13, rsi                    ; R13 = size
    mov r14, rdx                    ; R14 = flags
    mov r15, r8                     ; R15 = pointer to pmem_window_t

    ; Add the VMA_PMEM_WINDOW flag
    or r14, VMA_PMEM_WINDOW

    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call vma_create
    test rax, rax
    jz .err

    ; Store pmem_window_t pointer in file_ptr
    mov [rax + vma_t.file_ptr], r15

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
; virt_handle_pmem_window_map — maps static hardware window to virtual page on fault
; Input:
;   RDI = faulting virtual address
;   RSI = VMA pointer
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global virt_handle_pmem_window_map
virt_handle_pmem_window_map:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = fault virtual address
    mov r13, rsi                    ; R13 = VMA pointer

    mov r14, r12
    and r14, -4096                  ; page-aligned virtual page address

    mov r15, [r13 + vma_t.file_ptr] ; R15 = pointer to pmem_window_t
    test r15, r15
    jz .err

    mov rcx, [r15 + pmem_window_t.data_page] ; RCX = static physical window page address

    ; Map virtual page directly to static window physical page
    mov rsi, rcx                    ; arg 2 = physical address
    mov rdx, [r13 + vma_t.flags]    ; RDX = vma->flags
    xor rbx, rbx                    ; RBX = mapping flags

    test rdx, VMA_WRITE
    jz .no_write
    or rbx, PAGE_WRITABLE
    mov qword [r15 + pmem_window_t.dirty], 1 ; Set dirty since it is writable
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

    mov rdi, r14                    ; arg 1 = virtual page address
    mov rdx, rbx                    ; arg 3 = mapping flags
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

%endif ; STORAGE_UMMAPF_WINDOW_ASM
