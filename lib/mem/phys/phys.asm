; =============================================================================
; Tattva OS — lib/mem/phys/phys.asm
; =============================================================================
; Physical memory manager. Coordinates E820 parsing, bitmap allocation,
; page booking, and runtime PMM APIs.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_PHYS_PHYS_ASM
%define LIB_MEM_PHYS_PHYS_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; phys_init — discovers system RAM, calculates bitmap requirements, locates
;             a safe memory slot for the page bitmap, and initializes it.
; Input:  none (reads from global boot_info_ptr)
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
phys_init:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10

    ; 1. Load BootInfo pointer
    mov rdi, [boot_info_ptr]
    test rdi, rdi
    jz .error_halt                  ; crash early if BootInfo is null

    ; 2. Extract E820 map address and entry count
    mov rsi, [rdi + 0]              ; rsi = physical pointer to e820 entries (offset 0)
    mov rdx, [rdi + 8]              ; rdx = e820 entry count (offset 8)
    test rsi, rsi
    jz .error_halt
    test rdx, rdx
    jz .error_halt

    ; 3. Parse E820 map to get max RAM address and total usable page count
    mov rdi, rsi                    ; RDI = e820 map pointer
    mov rsi, rdx                    ; RSI = entry count
    call phys_parse_e820            ; RAX = max_phys_addr, RCX = total_pages
    test rax, rax
    jz .error_halt

    ; Store results in state
    mov [phys_state + phys_state_t.max_phys_addr], rax
    mov [phys_state + phys_state_t.total_pages], rcx
    mov [phys_state + phys_state_t.free_pages], rcx

    ; 4. Calculate bitmap size in bytes: (max_phys_addr / 4096) / 8
    ; which is max_phys_addr / 32768 (shr 15)
    mov rbx, rax
    shr rbx, 15                     ; rbx = bitmap_size in bytes
    test rbx, rbx
    jnz .store_bitmap_size
    mov rbx, 1                      ; ensure size is at least 1 byte
.store_bitmap_size:
    mov [phys_state + phys_state_t.bitmap_size], rbx

    ; 5. Scan the E820 map to find a free RAM region above 1MB to place the bitmap
    mov rdi, [boot_info_ptr]
    mov rsi, [rdi + 0]              ; rsi = E820 map pointer
    mov rdx, [rdi + 8]              ; rdx = entry count
    xor r8, r8                      ; r8 = index loop

.scan_loop:
    cmp r8, rdx
    jge .no_bitmap_mem

    ; Calculate pointer to current entry: RSI + R8 * 24
    mov r9, r8
    imul r9, 24
    add r9, rsi

    ; Check type == 1 (usable RAM)
    mov r10d, [r9 + e820_entry.type]
    cmp r10d, 1
    jne .next_entry

    mov r10, [r9 + e820_entry.base]
    mov r11, [r9 + e820_entry.length]

    ; Check if base is below 1MB (0x100000). If so, shrink or skip.
    cmp r10, 0x100000
    jae .check_size

    ; Base is below 1MB. Adjust base and length.
    mov rcx, 0x100000
    sub rcx, r10                    ; rcx = offset from base to 1MB
    cmp r11, rcx
    jbe .next_entry                 ; not enough memory left in this region
    add r10, rcx                    ; shift base to 1MB
    sub r11, rcx                    ; shrink length

.check_size:
    ; Check if this adjusted region has enough bytes to hold the bitmap
    cmp r11, rbx
    jb .next_entry

    ; Found a suitable block! Place bitmap at the base address of this region (R10)
    mov [phys_state + phys_state_t.bitmap_addr], r10
    jmp .init_bitmap

.next_entry:
    inc r8
    jmp .scan_loop

.no_bitmap_mem:
    ; Panics if we cannot find memory for the allocator bitmap
    mov rsi, msg_err_bitmap_oom
    call uart_print_str
    cli
.halt_loop:
    hlt
    jmp .halt_loop

.init_bitmap:
    ; 6. Fill the entire bitmap memory with 0xFF (all pages reserved by default)
    ; Target address: bitmap_addr, Fill value: 0xFF, Count: bitmap_size bytes
    mov rdi, [phys_state + phys_state_t.bitmap_addr]
    mov rcx, rbx                    ; RCX = bitmap_size in bytes
    mov al, 0xFF
    cld
    rep stosb                       ; fill the bitmap

    ; 7. Re-scan E820 map and clear bits for usable RAM regions (Subfeature 1.3)
    mov rdi, [boot_info_ptr]
    mov rsi, [rdi + 0]              ; rsi = E820 map pointer
    mov rdx, [rdi + 8]              ; rdx = entry count
    xor r8, r8                      ; r8 = index loop

.clear_loop:
    cmp r8, rdx
    jge .clear_done

    mov r9, r8
    imul r9, 24
    add r9, rsi                     ; r9 = e820_entry pointer

    mov r10d, [r9 + e820_entry.type]
    cmp r10d, 1                      ; type == 1 (usable)?
    jne .next_clear

    mov r10, [r9 + e820_entry.base]
    mov r11, [r9 + e820_entry.length]

    ; Calculate start page index = base / 4096 (shr 12)
    mov rbx, r10
    shr rbx, 12                     ; rbx = start page index

    ; Calculate page count = length / 4096 (shr 12)
    mov rcx, r11
    shr rcx, 12                     ; rcx = page count

.clear_page_loop:
    test rcx, rcx
    jz .next_clear

    ; Clear bit for page index rbx
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r9
    
    mov rdi, rbx
    call bitmap_clear_bit
    
    pop r9
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi

    inc rbx                         ; next page
    dec rcx
    jmp .clear_page_loop

.next_clear:
    inc r8
    jmp .clear_loop

.clear_done:
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

.error_halt:
    cli
    hlt
    jmp .error_halt

; -----------------------------------------------------------------------------
; Physical State and Error Messages
; -----------------------------------------------------------------------------
section .data

align 8
global phys_state
phys_state:
    istruc phys_state_t
        at phys_state_t.bitmap_addr,    dq 0
        at phys_state_t.bitmap_size,    dq 0
        at phys_state_t.total_pages,    dq 0
        at phys_state_t.free_pages,     dq 0
        at phys_state_t.max_phys_addr,  dq 0
    iend

msg_err_bitmap_oom: db "!!! KERNEL PANIC: Failed to locate free RAM above 1MB for Page Bitmap !!!", 0x0D, 0x0A, 0

%endif ; LIB_MEM_PHYS_PHYS_ASM
