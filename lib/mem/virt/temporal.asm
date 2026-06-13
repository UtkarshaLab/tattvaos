; =============================================================================
; Tattva OS — lib/mem/virt/temporal.asm
; =============================================================================
; Temporal Layout Obfuscation (Subfeature 26.5).
; Periodically relocates active code sections in the virtual address space
; to mitigate layout-based attacks (like JIT spraying or ROP page harvesting).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_TEMPORAL_ASM
%define LIB_MEM_VIRT_TEMPORAL_ASM

[BITS 64]

; Page Table Flags
PAGE_PRESENT    equ (1 << 0)
PAGE_WRITABLE   equ (1 << 1)
PAGE_USER       equ (1 << 2)
PAGE_NX         equ (1 << 63)

section .text

; External symbols
extern phys_alloc_page
extern phys_free_page
extern memzero
extern memset
extern virt_map
extern virt_unmap
extern virt_walk_table
extern virt_random_val
extern uart_print_str
extern uart_print_hex64

; -----------------------------------------------------------------------------
; virt_temporal_obfuscation_init — maps initial code page to 0x500000000
; Input:  none
; Output: RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global virt_temporal_obfuscation_init
virt_temporal_obfuscation_init:
    push rbx
    push rdi
    push rsi
    push rdx

    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .fail
    mov [temporal_code_phys], rax
    mov rbx, rax                    ; rbx = physical frame address

    ; 2. Initialize the page frame with NOPs (0x90)
    mov rdi, rbx                    ; destination (physical is identity mapped)
    mov rsi, 0x90                   ; fill byte: NOP instruction
    mov rdx, 4096                   ; 4KB size
    call memset

    ; 3. Place a RET instruction (0xC3) at the end of the page
    mov byte [rbx + 4095], 0xC3     ; RET instruction at offset 4095

    ; 4. Map the physical page to virtual address 0x500000000 (PML4 index 10)
    ; Flags: present, user, writable, executable (PAGE_NX clear)
    mov rdi, 0x500000000            ; starting virtual address
    mov rsi, rbx                    ; physical frame
    mov rdx, PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER
    call virt_map
    test rax, rax
    jz .fail_map

    ; 5. Set global virtual address tracker
    mov qword [temporal_code_vaddr], 0x500000000
    mov qword [temporal_ticks], 0   ; reset ticks
    mov rax, 1                      ; return 1 (success)
    jmp .done

.fail_map:
    mov rdi, [temporal_code_phys]
    call phys_free_page
    mov qword [temporal_code_phys], 0
.fail:
    xor rax, rax                    ; return 0 (failure)
.done:
    pop rdx
    pop rsi
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_temporal_obfuscation_tick — increments interval and migrates section
; Input:  none
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global virt_temporal_obfuscation_tick
virt_temporal_obfuscation_tick:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; 1. Increment local tick count
    mov rax, [temporal_ticks]
    inc rax
    mov [temporal_ticks], rax
    cmp rax, 5
    jl .exit                        ; if less than 5, skip migration

    ; 2. Reset tick count
    mov qword [temporal_ticks], 0

    ; 3. Generate a new random virtual address base
    ; Choose a random PML4 index between 100 and 400
    call virt_random_val            ; RAX = random 64-bit value
    xor rdx, rdx
    mov rcx, 301                    ; range: 400 - 100 + 1 = 301
    div rcx                         ; RDX = random % 301
    add rdx, 100                    ; RDX = 100 + (random % 301)
    
    shl rdx, 39                     ; RDX = RDX << 39 (new virtual address V_new)
    mov r14, rdx                    ; R14 = V_new

    ; 4. Retrieve current virtual address V_old
    mov r15, [temporal_code_vaddr]  ; R15 = V_old
    test r15, r15
    jz .exit                        ; safety check: must be initialized

    ; 5. Walk page table at V_old to locate physical page & flags
    mov rdi, r15
    xor rsi, rsi
    call virt_walk_table            ; RAX = physical address of PTE, RDX = level
    test rax, rax
    jz .exit                        ; safety check: must be mapped

    mov r13, [rax]                  ; R13 = PTE value (address + flags)

    ; Extract attributes/flags (clear physical address bits 12-51)
    mov r12, r13
    mov rbx, 0x000FFFFFFFFFF000
    not rbx                         ; RBX = ~0x000FFFFFFFFFF000 (flags mask)
    and r12, rbx                    ; R12 = flags (includes NX if set, though should be clear)

    ; Extract physical frame address
    not rbx                         ; restore 0x000FFFFFFFFFF000
    and r13, rbx                    ; R13 = physical frame address

    ; 6. Map new virtual address V_new to the same physical page
    mov rdi, r14                    ; V_new
    mov rsi, r13                    ; physical frame
    mov rdx, r12                    ; flags
    call virt_map
    test rax, rax
    jz .exit                        ; map failed, keep old mapping

    ; 7. Unmap old virtual address V_old
    mov rdi, r15
    call virt_unmap

    ; 8. Flush TLB
    invlpg [r15]
    invlpg [r14]

    ; 9. Update tracker pointer
    mov [temporal_code_vaddr], r14

    ; 10. Print relocation diagnostics
    mov rsi, msg_temporal_prefix
    call uart_print_str
    mov rax, r15
    call uart_print_hex64
    mov rsi, msg_temporal_to
    call uart_print_str
    mov rax, r14
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data

align 8
global temporal_code_vaddr
temporal_code_vaddr: dq 0

align 8
temporal_code_phys: dq 0

align 8
temporal_ticks: dq 0

msg_temporal_prefix: db "Temporal Layout: Migrated code section from 0x", 0
msg_temporal_to:     db " to 0x", 0
msg_crlf:            db 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_TEMPORAL_ASM
