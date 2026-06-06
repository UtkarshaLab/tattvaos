; =============================================================================
; Tattva OS — lib/mem/arena/arena_create.asm
; =============================================================================
; Arena Creation: Allocates a region and initializes the arena_t header.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_ARENA_ARENA_CREATE_ASM
%define LIB_MEM_ARENA_ARENA_CREATE_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern heap_alloc

; -----------------------------------------------------------------------------
; arena_create — allocates and initializes a new memory arena
; Input:
;   RDI = size of the arena in bytes
; Output:
;   RAX = pointer to the new arena (arena_t), or 0 if OOM or invalid size
; Clobbers: none (preserves all non-volatile registers)
; -----------------------------------------------------------------------------
global arena_create
arena_create:
    push rbx
    push rdi
    push rsi
    push rdx

    mov rsi, rdi                    ; RSI = requested size

    ; Validate size (must be at least arena_t_size + 16 bytes = 40 bytes)
    cmp rsi, 40
    jb .fail

    ; Call heap_alloc to allocate the block
    mov rdi, rsi
    call heap_alloc                 ; RAX = allocated address
    test rax, rax
    jz .fail

    mov rbx, rax                    ; RBX = arena pointer (block start)

    ; Calculate start address (aligned to 16 bytes, after 24-byte header)
    mov rdx, rbx
    add rdx, 24                     ; RDX = rbx + arena_t_size
    add rdx, 15
    and rdx, -16                    ; RDX = aligned start_addr

    ; Calculate end address
    mov rcx, rbx
    add rcx, rsi                    ; RCX = rbx + size (end_addr)

    ; Verify end_addr is strictly greater than start_addr
    cmp rcx, rdx
    jbe .free_and_fail

    ; Store headers
    mov [rbx + arena_t.start], rdx
    mov [rbx + arena_t.end], rcx
    mov [rbx + arena_t.current], rdx

    mov rax, rbx                    ; RAX = initialized arena pointer
    jmp .exit

.free_and_fail:
    mov rdi, rbx
    extern heap_free
    call heap_free

.fail:
    xor rax, rax

.exit:
    pop rdx
    pop rsi
    pop rdi
    pop rbx
    ret

%endif ; LIB_MEM_ARENA_ARENA_CREATE_ASM
