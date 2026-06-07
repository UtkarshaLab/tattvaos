; =============================================================================
; Tattva OS — lib/mem/phys/bitmap.asm
; =============================================================================
; Page bitmap allocator helper functions (set, clear, test, find free bits).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_PHYS_BITMAP_ASM
%define LIB_MEM_PHYS_BITMAP_ASM

[BITS 64]

; -----------------------------------------------------------------------------
; bitmap_set_bit — set a bit to 1 in the physical memory bitmap
; Input:
;   RDI = page index
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
bitmap_set_bit:
    mov rax, [phys_state + phys_state_t.bitmap_addr]
    mov rcx, rdi
    shr rcx, 3                      ; byte offset = index / 8
    and rdi, 7                      ; bit offset = index % 8
    bts [rax + rcx], rdi            ; set bit (atomically if needed, bts is safe)
    ret

; -----------------------------------------------------------------------------
; bitmap_clear_bit — clear a bit to 0 in the physical memory bitmap
; Input:
;   RDI = page index
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
bitmap_clear_bit:
    mov rax, [phys_state + phys_state_t.bitmap_addr]
    mov rcx, rdi
    shr rcx, 3                      ; byte offset = index / 8
    and rdi, 7                      ; bit offset = index % 8
    btr [rax + rcx], rdi            ; clear bit
    ret

; -----------------------------------------------------------------------------
; bitmap_test_bit — check if a bit in the bitmap is set (1) or clear (0)
; Input:
;   RDI = page index
; Output:
;   RAX = 1 if set (reserved/used), 0 if clear (free)
; Clobbers: RCX
; -----------------------------------------------------------------------------
bitmap_test_bit:
    mov rax, [phys_state + phys_state_t.bitmap_addr]
    mov rcx, rdi
    shr rcx, 3
    and rdi, 7
    bt [rax + rcx], rdi             ; test bit, CF = bit value
    jc .set
    xor rax, rax                    ; return 0
    ret
.set:
    mov rax, 1                      ; return 1
    ret

; -----------------------------------------------------------------------------
; bitmap_find_free — scan the bitmap for N contiguous free (0) bits
; Input:
;   RDI = number of contiguous bits needed (count)
; Output:
;   RAX = starting page index, or -1 if no contiguous range is found (OOM)
; Clobbers: RCX, RDX, R8, R9, R10, R11
; -----------------------------------------------------------------------------
bitmap_find_free:
    push rbx
    push rsi

    mov rsi, [phys_state + phys_state_t.bitmap_addr]
    mov r8, [phys_state + phys_state_t.bitmap_size]
    xor r9, r9                      ; R9 = current byte index in bitmap

.byte_loop:
    cmp r9, r8
    jge .not_found

    ; If byte is 0xFF, all 8 pages are allocated, skip to next byte
    mov al, [rsi + r9]
    cmp al, 0xFF
    je .next_byte

    ; Scan bits inside the current byte
    xor r10, r10                    ; R10 = bit index in current byte (0 to 7)

.bit_loop:
    cmp r10, 8
    jge .next_byte

    ; Calculate overall page index = R9 * 8 + R10
    mov rdx, r9
    shl rdx, 3                      ; rdx = r9 * 8
    add rdx, r10

    ; Verify if page range would exceed max pages
    mov r11, [phys_state + phys_state_t.total_pages]
    mov rbx, rdx
    add rbx, rdi                    ; end page index = start + count
    cmp rbx, r11
    ja .not_found

    ; Check if 'rdi' contiguous bits starting at 'rdx' are all zero
    xor rbx, rbx                    ; rbx = relative check offset (0 to count-1)

.check_loop:
    cmp rbx, rdi
    jge .found_range                ; all checked bits are zero!

    ; Calculate test bit index = rdx + rbx
    mov rcx, rdx
    add rcx, rbx

    ; Test bit 'rcx' in bitmap
    mov r11, rcx
    shr r11, 3                      ; byte offset
    and rcx, 7                      ; bit offset
    bt [rsi + r11], rcx
    jc .bit_occupied                ; if bit is set (1), this run is blocked

    inc rbx
    jmp .check_loop

.bit_occupied:
    ; Skip our search index past this blocked run to optimize search
    add r10, rbx
    inc r10
    jmp .bit_loop

.next_byte:
    inc r9
    jmp .byte_loop

.not_found:
    mov rax, -1                     ; return -1
    jmp .exit

.found_range:
    mov rax, rdx                    ; return starting page index

.exit:
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; bitmap_set_bit_local — set a bit in a node-local bitmap
; Input:
;   RDI = pointer to numa_node_t
;   RSI = relative page index
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global bitmap_set_bit_local
bitmap_set_bit_local:
    mov rax, [rdi + numa_node_t.bitmap_addr]
    mov rcx, rsi
    shr rcx, 3                      ; byte offset
    and rsi, 7                      ; bit offset
    bts [rax + rcx], rsi
    ret

; -----------------------------------------------------------------------------
; bitmap_clear_bit_local — clear a bit in a node-local bitmap
; Input:
;   RDI = pointer to numa_node_t
;   RSI = relative page index
; Output: none
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global bitmap_clear_bit_local
bitmap_clear_bit_local:
    mov rax, [rdi + numa_node_t.bitmap_addr]
    mov rcx, rsi
    shr rcx, 3                      ; byte offset
    and rsi, 7                      ; bit offset
    btr [rax + rcx], rsi
    ret

; -----------------------------------------------------------------------------
; bitmap_test_bit_local — test a bit in a node-local bitmap
; Input:
;   RDI = pointer to numa_node_t
;   RSI = relative page index
; Output:
;   RAX = 1 if set (reserved/used), 0 if clear (free)
; Clobbers: RCX
; -----------------------------------------------------------------------------
global bitmap_test_bit_local
bitmap_test_bit_local:
    mov rax, [rdi + numa_node_t.bitmap_addr]
    mov rcx, rsi
    shr rcx, 3                      ; byte offset
    and rsi, 7                      ; bit offset
    bt [rax + rcx], rsi             ; test bit, CF = bit value
    jc .set
    xor rax, rax
    ret
.set:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; bitmap_find_free_local — scan local bitmap for N contiguous free bits
; Input:
;   RDI = pointer to numa_node_t
;   RSI = number of contiguous bits needed (count)
; Output:
;   RAX = starting relative page index, or -1 if no contiguous range is found
; Clobbers: RCX, RDX, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global bitmap_find_free_local
bitmap_find_free_local:
    push rbx
    push rsi
    push r12
    push r13

    mov r12, rdi                    ; R12 = node_ptr
    mov r13, rsi                    ; R13 = count

    mov rsi, [r12 + numa_node_t.bitmap_addr]
    mov r8, [r12 + numa_node_t.bitmap_size]
    xor r9, r9                      ; R9 = current byte index in bitmap

.byte_loop:
    cmp r9, r8
    jge .not_found

    ; If byte is 0xFF, all 8 pages are allocated, skip to next byte
    mov al, [rsi + r9]
    cmp al, 0xFF
    je .next_byte

    ; Scan bits inside the current byte
    xor r10, r10                    ; R10 = bit index in current byte (0 to 7)

.bit_loop:
    cmp r10, 8
    jge .next_byte

    ; Calculate relative page index = R9 * 8 + R10
    mov rdx, r9
    shl rdx, 3                      ; rdx = r9 * 8
    add rdx, r10

    ; Verify if page range would exceed node boundaries
    mov r11, [r12 + numa_node_t.end_page]
    sub r11, [r12 + numa_node_t.start_page]
    mov rbx, rdx
    add rbx, r13                    ; end page index = start + count
    cmp rbx, r11
    ja .not_found

    ; Check if 'r13' contiguous bits starting at relative index 'rdx' are all zero
    xor rbx, rbx                    ; rbx = relative check offset (0 to count-1)

.check_loop:
    cmp rbx, r13
    jge .found_range                ; all checked bits are zero!

    ; Calculate test bit index = rdx + rbx
    mov rcx, rdx
    add rcx, rbx

    ; Test bit 'rcx' in local bitmap
    mov r11, rcx
    shr r11, 3                      ; byte offset
    and rcx, 7                      ; bit offset
    bt [rsi + r11], rcx
    jc .bit_occupied                ; if bit is set (1), this run is blocked

    inc rbx
    jmp .check_loop

.bit_occupied:
    ; Skip our search index past this blocked run to optimize search
    add r10, rbx
    inc r10
    jmp .bit_loop

.next_byte:
    inc r9
    jmp .byte_loop

.not_found:
    mov rax, -1                     ; return -1
    jmp .exit

.found_range:
    mov rax, rdx                    ; return starting relative page index

.exit:
    pop r13
    pop r12
    pop rsi
    pop rbx
    ret

%endif ; LIB_MEM_PHYS_BITMAP_ASM
