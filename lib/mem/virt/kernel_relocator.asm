; =============================================================================
; Tattva OS — lib/mem/virt/kernel_relocator.asm
; =============================================================================
; Dynamic Kernel Page Relocator.
; Checks if physical pages are located inside hot-pluggable memory zones.
; Moves active mappings out of hot-pluggable physical frames to secure,
; non-hotpluggable nodes (Node 0) to prevent kernel crashes on memory removal.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_KERNEL_RELOCATOR_ASM
%define LIB_MEM_VIRT_KERNEL_RELOCATOR_ASM

[BITS 64]

; External symbols
extern numa_ranges
extern numa_range_count
extern virt_walk_table
extern virt_unmap
extern virt_map
extern phys_alloc_page_node
extern phys_free_page
extern buddy_metadata
extern buddy_start_addr
extern buddy_end_addr
extern uart_print_str
extern uart_print_hex64

section .text

; -----------------------------------------------------------------------------
; is_phys_addr_hotpluggable — checks if a physical address falls in a hot-pluggable zone
; Input:  RDI = physical address
; Output: RAX = 1 if hot-pluggable, 0 if secure
; -----------------------------------------------------------------------------
global is_phys_addr_hotpluggable
is_phys_addr_hotpluggable:
    push rbx
    push rcx
    push rdx

    mov rcx, [numa_range_count]
    test rcx, rcx
    jz .secure                      ; if no range count, assume secure

    lea rbx, [numa_ranges]
    xor rdx, rdx                    ; i = 0
.loop:
    cmp rdx, rcx
    jge .secure

    mov rax, rdx
    imul rax, numa_range_t_size
    lea r8, [rbx + rax]             ; R8 = &numa_ranges[i]

    ; Check if entry is enabled
    mov eax, [r8 + numa_range_t.flags]
    test al, 1
    jz .next

    ; Check if RDI >= base
    mov rax, [r8 + numa_range_t.base]
    cmp rdi, rax
    jb .next

    ; Check if RDI < base + length
    add rax, [r8 + numa_range_t.length]
    cmp rdi, rax
    jae .next

    ; Found range! Check if hot-pluggable (bit 1 of flags)
    mov eax, [r8 + numa_range_t.flags]
    test al, 2
    jnz .hotpluggable               ; if bit 1 is set, it is hotpluggable!

.next:
    inc rdx
    jmp .loop

.hotpluggable:
    mov rax, 1
    jmp .exit

.secure:
    xor rax, rax

.exit:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; kernel_relocate_page — Moves a virtual page out of hot-pluggable physical zones
; Input:  RDI = virtual address (4KB aligned)
; Output: RAX = 1 if relocated, 0 if already in secure zone, -1 on error
; -----------------------------------------------------------------------------
global kernel_relocate_page
kernel_relocate_page:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = virtual address (aligned)

    ; 1. Get physical address of PTE
    mov rsi, 0                      ; current CR3
    call virt_walk_table            ; RAX = physical address of PTE, RDX = level
    test rax, rax
    jz .not_mapped

    ; RAX is a physical address, but since physical memory is identity-mapped,
    ; we can read the PTE value directly!
    mov r13, [rax]                  ; R13 = PTE value (address + flags)

    ; Extract current physical frame base address
    mov r15, r13
    mov rbx, 0x000FFFFFFFFFF000
    and r15, rbx                    ; R15 = current physical page address (P_old)

    ; 2. Check if P_old is hot-pluggable
    mov rdi, r15
    call is_phys_addr_hotpluggable
    test rax, rax
    jz .not_needed                  ; already in secure zone

    ; 3. Extract original attributes/flags from R13
    mov rbx, 0xFFF0000000000FFF
    and r13, rbx                    ; R13 = attributes (flags + NX)

    ; 4. Allocate a new page in secure Node 0
    mov rdi, 0                      ; Node 0
    call phys_alloc_page_node
    test rax, rax
    jz .oom
    mov r14, rax                    ; R14 = P_new

    ; 5. Copy the 4KB data using identity mapping
    mov rsi, r12                    ; source = virtual address (still active)
    mov rdi, r14                    ; dest = P_new (identity mapped)
    mov rcx, 512                    ; 512 quadwords
    cld
    rep movsq

    ; Print relocation notice
    mov rsi, msg_reloc_page_start
    call uart_print_str
    mov rax, r12
    call uart_print_hex64
    mov rsi, msg_reloc_page_mid
    call uart_print_str
    mov rax, r15
    call uart_print_hex64
    mov rsi, msg_reloc_page_to
    call uart_print_str
    mov rax, r14
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 6. Unmap old physical page
    mov rdi, r12
    call virt_unmap

    ; 7. Map new physical page with the same attributes
    mov rdi, r12                    ; virtual address
    mov rsi, r14                    ; new physical page
    mov rdx, r13                    ; attributes
    call virt_map

    ; 8. Flush TLB locally
    invlpg [r12]

    ; 9. Free old physical page
    mov rdi, r15
    call phys_free_page

    mov rax, 1                      ; return 1 (relocated)
    jmp .exit

.not_needed:
    xor rax, rax                    ; return 0 (no relocation needed)
    jmp .exit

.not_mapped:
.oom:
    mov rax, -1                     ; return -1 on error

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
    ret

; -----------------------------------------------------------------------------
; kernel_relocate_critical_tables — relocate buddy allocator metadata out of pluggable zones
; Input: none
; Output: none
; -----------------------------------------------------------------------------
global kernel_relocate_critical_tables
kernel_relocate_critical_tables:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rsi, msg_reloc_init
    call uart_print_str

    ; 1. Relocate Buddy Allocator Metadata
    mov rdi, [buddy_metadata]
    test rdi, rdi
    jz .done

    ; Metadata page count calculation
    mov rax, [buddy_end_addr]
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = total managed page count / bytes in metadata array
    
    mov rbx, [buddy_metadata]       ; start virtual address of metadata
    mov rcx, rax
    add rcx, 4095
    shr rcx, 12                     ; RCX = page count of metadata array

.reloc_loop:
    test rcx, rcx
    jz .done

    mov rdi, rbx
    call kernel_relocate_page

    add rbx, 4096
    dec rcx
    jmp .reloc_loop

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; Data Section
; -----------------------------------------------------------------------------
section .data

msg_reloc_init:         db "Relocator: Checking critical kernel tables for relocation...", 0x0D, 0x0A, 0
msg_reloc_page_start:   db "Relocator: Relocating page ", 0
msg_reloc_page_mid:     db " from hot-pluggable physical frame ", 0
msg_reloc_page_to:      db " to secure frame ", 0
msg_crlf:               db 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_KERNEL_RELOCATOR_ASM
