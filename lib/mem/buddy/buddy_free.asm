; =============================================================================
; Tattva OS — lib/mem/buddy/buddy_free.asm
; =============================================================================
; Buddy Allocator Block Freeing and Coalescing (Subfeature 11.3).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_BUDDY_BUDDY_FREE_ASM
%define LIB_MEM_BUDDY_BUDDY_FREE_ASM

[BITS 64]

%include "lib/mem/mem.inc"

section .text

extern buddy_free_heads
extern buddy_start_addr
extern buddy_end_addr
extern buddy_metadata
extern buddy_link_block
extern buddy_unlink_block

; -----------------------------------------------------------------------------
; buddy_free — frees an allocated block and coalesces it with its buddy if possible
; Input:
;   RDI = physical address of the block to free
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
global buddy_free
buddy_free:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = block address to free (curr_addr)

    ; Validate address range
    cmp r12, [buddy_start_addr]
    jb .exit                        ; if below start, exit
    cmp r12, [buddy_end_addr]
    jae .exit                       ; if at or above end, exit

    ; Verify page alignment
    mov rax, r12
    and rax, 4095
    jnz .exit                       ; if not 4KB aligned, exit

    ; Retrieve page index of the block: i = (curr_addr - start_addr) / 4096
    mov rax, r12
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = page index (i)

    ; Retrieve metadata byte
    mov rbx, [buddy_metadata]
    mov r13b, [rbx + rax]           ; R13B = metadata byte (O)

    ; Verify block is allocated (bit 7 must be 0)
    test r13b, 0x80
    jnz .exit                       ; if already free (bit 7 set), exit (avoid double free)

    ; Get order (lower bits of metadata)
    and r13, 0x0F                   ; R13 = current order (O)

.coalesce_loop:
    cmp r13, 11
    jae .loop_done                  ; if order >= 11, cannot coalesce further

    ; Calculate buddy page index: buddy_index = curr_page_index ^ (1 << O)
    mov rax, r12
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = curr_page_index
    
    mov rsi, 1
    mov rcx, r13
    shl rsi, cl                     ; RSI = 1 << O
    xor rax, rsi                    ; RAX = buddy_page_index

    ; Calculate buddy physical address: buddy_addr = start_addr + buddy_page_index * 4096
    mov rdx, rax
    shl rdx, 12                     ; RDX = buddy_page_index * 4096
    add rdx, [buddy_start_addr]     ; RDX = buddy_addr

    ; Check if buddy_addr is within bounds
    cmp rdx, [buddy_start_addr]
    jb .loop_done
    cmp rdx, [buddy_end_addr]
    jae .loop_done

    ; Retrieve buddy metadata: buddy_meta = metadata[buddy_page_index]
    mov rbx, [buddy_metadata]
    mov r14b, [rbx + rax]           ; R14B = buddy_meta

    ; Check if buddy is free (bit 7 set) AND buddy order matches current order (R13)
    test r14b, 0x80
    jz .loop_done                   ; buddy is not free, stop coalescing

    and r14, 0x0F                   ; R14 = buddy order
    cmp r14, r13
    jne .loop_done                  ; buddy order doesn't match, stop

    ; We can merge! Unlink buddy from free list of order O
    push rdx                        ; save buddy_addr
    mov rdi, rdx
    mov rsi, r13
    call buddy_unlink_block
    pop rdx

    ; Clear buddy's metadata byte to 0
    mov rbx, [buddy_metadata]
    mov byte [rbx + rax], 0         ; clear metadata[buddy_page_index]

    ; Merged block starts at minimum of curr_addr (R12) and buddy_addr (RDX)
    cmp r12, rdx
    jbe .keep_left
    mov r12, rdx                    ; curr_addr = buddy_addr
.keep_left:

    ; Increment order: O = O + 1
    inc r13
    jmp .coalesce_loop

.loop_done:
    ; Link final coalesced block at R12 into free list of order R13
    mov rdi, r12
    mov rsi, r13
    call buddy_link_block

    ; Mark the block as free in metadata: metadata[final_index] = 0x80 | R13
    mov rax, r12
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = final page index
    
    mov rbx, [buddy_metadata]
    mov rdx, r13
    or rdx, 0x80
    mov [rbx + rax], dl

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

%endif ; LIB_MEM_BUDDY_BUDDY_FREE_ASM
