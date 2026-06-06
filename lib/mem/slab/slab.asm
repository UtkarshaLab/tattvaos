; =============================================================================
; Tattva OS — lib/mem/slab/slab.asm
; =============================================================================
; Slab Allocator Main Entry and Static Cache Definitions (Subfeature 10.1).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_SLAB_SLAB_ASM
%define LIB_MEM_SLAB_SLAB_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

; External functions from other slab allocator parts
extern kmem_cache_create_in_place

; -----------------------------------------------------------------------------
; kmem_cache_init_all — initializes the fixed slab caches during system boot
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI
; -----------------------------------------------------------------------------
global kmem_cache_init_all
kmem_cache_init_all:
    push rbp
    mov rbp, rsp

    ; 1. Initialize kmem_cache_file: obj_size = 256, align = 8
    mov rdi, kmem_cache_file
    mov rsi, name_cache_file
    mov rdx, 256
    mov rcx, 8
    call kmem_cache_create_in_place

    ; 2. Initialize kmem_cache_task: obj_size = 512, align = 16
    mov rdi, kmem_cache_task
    mov rsi, name_cache_task
    mov rdx, 512
    mov rcx, 16
    call kmem_cache_create_in_place

    ; 3. Initialize kmem_cache_vma: obj_size = 64, align = 8
    mov rdi, kmem_cache_vma
    mov rsi, name_cache_vma
    mov rdx, 64
    mov rcx, 8
    call kmem_cache_create_in_place

    pop rbp
    ret

section .data

name_cache_file: db "kmem_cache_file", 0
name_cache_task: db "kmem_cache_task", 0
name_cache_vma:  db "kmem_cache_vma", 0

section .bss

align 8
global kmem_cache_file
global kmem_cache_task
global kmem_cache_vma

kmem_cache_file: resb kmem_cache_t_size
kmem_cache_task: resb kmem_cache_t_size
kmem_cache_vma:  resb kmem_cache_t_size

%endif ; LIB_MEM_SLAB_SLAB_ASM
