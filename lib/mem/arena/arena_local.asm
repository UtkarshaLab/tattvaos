; =============================================================================
; Tattva OS — lib/mem/arena/arena_local.asm
; =============================================================================
; Thread-Local Arenas: Bind and allocate from core-local memory arenas lock-free.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_ARENA_ARENA_LOCAL_ASM
%define LIB_MEM_ARENA_ARENA_LOCAL_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern arena_create
extern arena_alloc
extern arena_reset
extern arena_destroy

; -----------------------------------------------------------------------------
; arena_init_local — initializes a thread-local arena bound to the current core
; Input:
;   RDI = size of the arena in bytes
; Output:
;   RAX = pointer to the created arena, or 0 if OOM
; Clobbers: none (preserves registers)
; -----------------------------------------------------------------------------
global arena_init_local
arena_init_local:
    ; Call arena_create to allocate and initialize (RDI = size)
    call arena_create               ; RAX = arena_t pointer
    test rax, rax
    jz .fail

    ; Store the arena pointer in GS offset 24 (.arena)
    mov [gs:24], rax

.fail:
    ret

; -----------------------------------------------------------------------------
; arena_alloc_local — bump allocates memory from the current core's local arena
; Input:
;   RDI = size of allocation in bytes
; Output:
;   RAX = allocated pointer, or 0 if no local arena bound or OOM
; Clobbers: none (preserves registers)
; -----------------------------------------------------------------------------
global arena_alloc_local
arena_alloc_local:
    mov rsi, rdi                    ; RSI = size
    mov rdi, [gs:24]                ; RDI = arena pointer
    test rdi, rdi
    jz .fail

    jmp arena_alloc                 ; tail call optimization

.fail:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; arena_reset_local — resets the current core's local arena
; Input: none
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
global arena_reset_local
arena_reset_local:
    mov rdi, [gs:24]
    test rdi, rdi
    jz .exit

    jmp arena_reset                 ; tail call optimization

.exit:
    ret

; -----------------------------------------------------------------------------
; arena_destroy_local — destroys the current core's local arena
; Input: none
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
global arena_destroy_local
arena_destroy_local:
    mov rdi, [gs:24]
    test rdi, rdi
    jz .exit

    call arena_destroy
    mov qword [gs:24], 0            ; clear local arena pointer

.exit:
    ret

%endif ; LIB_MEM_ARENA_ARENA_LOCAL_ASM
