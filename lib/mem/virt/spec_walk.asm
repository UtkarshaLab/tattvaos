; =============================================================================
; Tattva OS — lib/mem/virt/spec_walk.asm
; =============================================================================
; Speculative Directory Walk Engine (Subfeature 25.2).
; Reads memory access transaction logs to speculatively resolve page table walks
; and caches virtual-to-physical address mappings in a software table cache.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_SPEC_WALK_ASM
%define LIB_MEM_VIRT_SPEC_WALK_ASM

[BITS 64]

; Translation Cache Entry Structure (32 bytes)
struc trans_cache_entry_t
    .vaddr      resq 1      ; Virtual address key
    .paddr      resq 1      ; Physical address value
    .flags      resq 1      ; Page table entry flags
    .valid      resq 1      ; 1 if valid, 0 if empty
endstruc

; TSX Transaction Log Structure (count + 128 entry pointers)
struc tsx_log_t
    .count      resq 1      ; Number of logged addresses
    .entries    resq 128    ; Array of logged virtual addresses
endstruc

section .text

; External symbols
extern virt_walk_table
extern virt_page_fault_handler

; -----------------------------------------------------------------------------
; tsx_log_init — clears the transaction log
; -----------------------------------------------------------------------------
global tsx_log_init
tsx_log_init:
    mov qword [tsx_log + tsx_log_t.count], 0
    ret

; -----------------------------------------------------------------------------
; tsx_log_address — records a virtual address access in the transaction log
; Input:  RDI = virtual address
; -----------------------------------------------------------------------------
global tsx_log_address
tsx_log_address:
    push rbx
    mov rax, [tsx_log + tsx_log_t.count]
    cmp rax, 128
    jae .done                       ; log full, discard speculative address

    mov [tsx_log + tsx_log_t.entries + rax * 8], rdi
    inc rax
    mov [tsx_log + tsx_log_t.count], rax
.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; trans_cache_insert — caches a translated mapping
; Input:  RDI = vaddr, RSI = paddr, RDX = flags
; -----------------------------------------------------------------------------
global trans_cache_insert
trans_cache_insert:
    push rbx
    mov rax, rdi
    shr rax, 12                     ; discard offset bits
    and rax, 63                     ; hash index: index = (vaddr >> 12) & 63

    imul rax, trans_cache_entry_t_size
    lea rbx, [trans_cache + rax]

    mov [rbx + trans_cache_entry_t.vaddr], rdi
    mov [rbx + trans_cache_entry_t.paddr], rsi
    mov [rbx + trans_cache_entry_t.flags], rdx
    mov qword [rbx + trans_cache_entry_t.valid], 1

    pop rbx
    ret

; -----------------------------------------------------------------------------
; trans_cache_lookup — queries translation cache
; Input:  RDI = virtual address
; Output: RAX = physical address (or 0 if miss), RDX = flags (or 0 if miss)
; -----------------------------------------------------------------------------
global trans_cache_lookup
trans_cache_lookup:
    push rbx
    mov rax, rdi
    shr rax, 12
    and rax, 63

    imul rax, trans_cache_entry_t_size
    lea rbx, [trans_cache + rax]

    mov rcx, [rbx + trans_cache_entry_t.valid]
    test rcx, rcx
    jz .miss

    mov rcx, [rbx + trans_cache_entry_t.vaddr]
    cmp rcx, rdi
    jne .miss

    ; Hit!
    mov rax, [rbx + trans_cache_entry_t.paddr]
    mov rdx, [rbx + trans_cache_entry_t.flags]
    jmp .exit

.miss:
    xor rax, rax
    xor rdx, rdx

.exit:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; trans_cache_invalidate — invalidates one address in translation cache
; Input:  RDI = virtual address
; -----------------------------------------------------------------------------
global trans_cache_invalidate
trans_cache_invalidate:
    push rbx
    mov rax, rdi
    shr rax, 12
    and rax, 63

    imul rax, trans_cache_entry_t_size
    lea rbx, [trans_cache + rax]

    mov rcx, [rbx + trans_cache_entry_t.vaddr]
    cmp rcx, rdi
    jne .done

    mov qword [rbx + trans_cache_entry_t.valid], 0
.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; trans_cache_flush — invalidates all cached entries
; -----------------------------------------------------------------------------
global trans_cache_flush
trans_cache_flush:
    push rbx
    lea rbx, [trans_cache]
    xor rcx, rcx
.loop:
    cmp rcx, 64
    jae .done

    mov qword [rbx + rcx * trans_cache_entry_t_size + trans_cache_entry_t.valid], 0
    inc rcx
    jmp .loop
.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tsx_spec_walk_engine — reads transaction log, walks page directories,
;                       caches mappings, and pre-allocates/pre-maps if unmapped
; -----------------------------------------------------------------------------
global tsx_spec_walk_engine
tsx_spec_walk_engine:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, [tsx_log + tsx_log_t.count]
    test r12, r12
    jz .done

    xor r15, r15                    ; R15 = loop index i = 0

.loop_entries:
    cmp r15, [tsx_log + tsx_log_t.count]
    jae .clear_log

    mov r13, [tsx_log + tsx_log_t.entries + r15 * 8]
    test r13, r13
    jz .next_entry

    ; Walk directories to translate virtual address
    mov rdi, r13
    mov rsi, 0
    call virt_walk_table            ; RAX = physical address of entry, RDX = level
    test rax, rax
    jz .unmapped

    mov r14, [rax]                  ; R14 = PTE entry
    test r14, 1                     ; present bit (bit 0) set?
    jz .unmapped

    ; Present! Cache it
    mov rdi, r13
    mov rsi, r14
    mov r8, 0xFFFFFFFFFFFFF000
    and rsi, r8                     ; physical page address
    mov rdx, r14
    and rdx, 0xFFF                  ; flags
    call trans_cache_insert

    invlpg [r13]                    ; Warm up CPU TLB
    jmp .next_entry

.unmapped:
    ; Not mapped/present. Resolve the fault speculatively
    mov rdi, r13                    ; virtual address
    mov rsi, 2                      ; error code: write, non-present
    mov rdx, rsp                    ; mock RSP

    ; Setup temporary mock stack return RIP slot
    push qword 0
    mov rcx, rsp
    call virt_page_fault_handler
    pop r8

    ; Re-walk to find translation after speculative mapping
    mov rdi, r13
    mov rsi, 0
    call virt_walk_table
    test rax, rax
    jz .next_entry

    mov r14, [rax]
    test r14, 1
    jz .next_entry

    ; Store the speculatively resolved mapping in cache
    mov rdi, r13
    mov rsi, r14
    mov r8, 0xFFFFFFFFFFFFF000
    and rsi, r8
    mov rdx, r14
    and rdx, 0xFFF
    call trans_cache_insert

    invlpg [r13]                    ; Warm up CPU TLB

.next_entry:
    inc r15
    jmp .loop_entries

.clear_log:
    mov qword [tsx_log + tsx_log_t.count], 0

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Speculative Walk Structures storage
; -----------------------------------------------------------------------------
section .bss
align 8
global tsx_log
tsx_log:     resb tsx_log_t_size

align 64
global trans_cache
trans_cache: resb 64 * trans_cache_entry_t_size

%endif ; LIB_MEM_VIRT_SPEC_WALK_ASM
