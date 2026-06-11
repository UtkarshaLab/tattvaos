; =============================================================================
; Tattva OS — lib/mem/virt/spt.asm
; =============================================================================
; Software Page Table Virtualization — Shadow Page Tables (SPT) (Milestone 22.2).
; Synchronizes guest virtual-to-physical structures to host page tables in
; software for processors that do not support hardware nested paging (EPT/NPT).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_SPT_ASM
%define LIB_MEM_VIRT_SPT_ASM

[BITS 64]

; Standard x86-64 Page Table Entry flags
%ifndef PAGE_PRESENT
    %define PAGE_PRESENT    (1 << 0)
%endif
%ifndef PAGE_WRITABLE
    %define PAGE_WRITABLE   (1 << 1)
%endif
%ifndef PAGE_USER
    %define PAGE_USER       (1 << 2)
%endif
%ifndef PAGE_NX
    %define PAGE_NX         (1 << 63)
%endif

section .text

; External VM & Physical memory allocators
extern phys_alloc_page
extern phys_free_page
extern ept_translate

; -----------------------------------------------------------------------------
; spt_init — Allocates and initializes the root Shadow PML4 page table
; Output:
;   RAX = physical address of the Shadow PML4 page table base, or 0 on failure
; -----------------------------------------------------------------------------
global spt_init
spt_init:
    call phys_alloc_page
    test rax, rax
    jz .fail
    
    ; Zero out the allocated PML4 page
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    
    mov rax, rdi
.fail:
    ret

; -----------------------------------------------------------------------------
; spt_map_entry — Maps a Guest Virtual Address directly to a Host Physical Address
; Input:
;   RDI = physical address of Shadow PML4 base (HPA)
;   RSI = Guest Virtual Address (GVA) (must be page-aligned)
;   RDX = Host Physical Address (HPA) (must be page-aligned)
;   RCX = mapping flags (e.g. PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
; Output:
;   RAX = 1 on success, 0 on failure (Out of Memory)
; -----------------------------------------------------------------------------
global spt_map_entry
spt_map_entry:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = Shadow PML4 base HPA
    mov r13, rsi                    ; R13 = GVA
    mov r14, rdx                    ; R14 = HPA
    mov r15, rcx                    ; R15 = mapping flags

    ; 1. Walk PML4 (Level 4)
    mov rax, r13
    shr rax, 39
    and rax, 0x1FF                  ; RAX = PML4 index
    lea r8, [r12 + rax * 8]         ; R8 = PML4 entry address
    mov r9, [r8]                    ; R9 = PML4 entry value
    test r9, PAGE_PRESENT
    jnz .pml4_valid

    ; Allocate PDPT page
    call phys_alloc_page
    test rax, rax
    jz .fail
    
    ; Zero out the allocated page
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax
    
    ; Link PDPT to PML4 entry
    mov r9, rax
    or r9, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [r8], r9

.pml4_valid:
    and r9, 0xFFFFFFFFFFFFF000      ; R9 = PDPT physical address

    ; 2. Walk PDPT (Level 3)
    mov rax, r13
    shr rax, 30
    and rax, 0x1FF                  ; RAX = PDPT index
    lea r8, [r9 + rax * 8]          ; R8 = PDPT entry address
    mov r9, [r8]                    ; R9 = PDPT entry value
    test r9, PAGE_PRESENT
    jnz .pdpt_valid

    ; Allocate PD page
    call phys_alloc_page
    test rax, rax
    jz .fail
    
    ; Zero out page
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax
    
    ; Link PD
    mov r9, rax
    or r9, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [r8], r9

.pdpt_valid:
    and r9, 0xFFFFFFFFFFFFF000      ; R9 = PD physical address

    ; 3. Walk PD (Level 2)
    mov rax, r13
    shr rax, 21
    and rax, 0x1FF                  ; RAX = PD index
    lea r8, [r9 + rax * 8]          ; R8 = PD entry address
    mov r9, [r8]                    ; R9 = PD entry value
    test r9, PAGE_PRESENT
    jnz .pd_valid

    ; Allocate PT page
    call phys_alloc_page
    test rax, rax
    jz .fail
    
    ; Zero out page
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax
    
    ; Link PT
    mov r9, rax
    or r9, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [r8], r9

.pd_valid:
    and r9, 0xFFFFFFFFFFFFF000      ; R9 = PT physical address

    ; 4. Walk PT (Level 1)
    mov rax, r13
    shr rax, 12
    and rax, 0x1FF                  ; RAX = PT index
    lea r8, [r9 + rax * 8]          ; R8 = PT entry address (leaf PTE)

    ; Write target Host Physical Address and flags
    mov r9, r14
    and r9, 0xFFFFFFFFFFFFF000
    or r9, r15
    mov [r8], r9

    mov rax, 1                      ; Return success
    
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.fail:
    xor rax, rax
    jmp .exit

; -----------------------------------------------------------------------------
; spt_unmap_entry — Clears the shadow mapping for a Guest Virtual Address
; Input:
;   RDI = physical address of Shadow PML4 base
;   RSI = Guest Virtual Address (GVA)
; Output:
;   RAX = 1 on success (cleared), 0 if not mapped
; -----------------------------------------------------------------------------
global spt_unmap_entry
spt_unmap_entry:
    ; PML4 Walk
    mov rax, rsi
    shr rax, 39
    and rax, 0x1FF
    mov r8, [rdi + rax * 8]
    test r8, PAGE_PRESENT
    jz .not_mapped
    
    ; PDPT Walk
    and r8, 0xFFFFFFFFFFFFF000
    mov rax, rsi
    shr rax, 30
    and rax, 0x1FF
    mov r9, [r8 + rax * 8]
    test r9, PAGE_PRESENT
    jz .not_mapped
    
    ; PD Walk
    and r9, 0xFFFFFFFFFFFFF000
    mov rax, rsi
    shr rax, 21
    and rax, 0x1FF
    mov r8, [r9 + rax * 8]
    test r8, PAGE_PRESENT
    jz .not_mapped
    
    ; PT Walk
    and r8, 0xFFFFFFFFFFFFF000
    mov rax, rsi
    shr rax, 12
    and rax, 0x1FF
    lea rcx, [r8 + rax * 8]         ; RCX = leaf PTE address
    mov rax, [rcx]
    test rax, PAGE_PRESENT
    jz .not_mapped
    
    ; Clear PTE
    mov qword [rcx], 0
    mov rax, 1
    ret
    
.not_mapped:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; spt_sync_page_fault — Resolves a shadow page fault by syncing guest tables
; Input:
;   RDI = physical address of Shadow PML4 base (HPA)
;   RSI = physical address of Guest PML4 base (GPA)
;   RDX = Faulting Guest Virtual Address (GVA)
;   RCX = physical address of EPT PML4 base (HPA) (used to translate GPAs to HPAs)
; Output:
;   RAX = 1 if fault is resolved and mapping is synchronized (retry guest execution)
;         0 if mapping is missing in guest tables (inject guest #PF)
; -----------------------------------------------------------------------------
global spt_sync_page_fault
spt_sync_page_fault:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = Shadow PML4 HPA
    mov r13, rsi                    ; R13 = Guest PML4 GPA (root table GPA)
    mov r14, rdx                    ; R14 = faulting GVA
    mov r15, rcx                    ; R15 = EPT PML4 HPA

    ; 0. Translate Guest PML4 GPA (R13) to host virtual address (HPA)
    mov rdi, r15                    ; EPT base
    mov rsi, r13                    ; GPA
    call ept_translate
    test rax, rax
    jz .guest_fault                 ; cannot resolve guest root PML4!
    mov r8, rax                     ; R8 = Guest PML4 HPA

    ; 1. Walk Guest PML4 (Level 4)
    mov rax, r14
    shr rax, 39
    and rax, 0x1FF                  ; PML4 index
    mov r9, [r8 + rax * 8]          ; R9 = Guest PML4 entry
    test r9, PAGE_PRESENT
    jz .guest_fault

    ; Extract child PDPT GPA
    and r9, 0xFFFFFFFFFFFFF000
    
    ; Translate PDPT GPA to HPA
    mov rdi, r15
    mov rsi, r9
    call ept_translate
    test rax, rax
    jz .guest_fault
    mov r8, rax                     ; R8 = Guest PDPT HPA

    ; 2. Walk Guest PDPT (Level 3)
    mov rax, r14
    shr rax, 30
    and rax, 0x1FF                  ; PDPT index
    mov r9, [r8 + rax * 8]          ; R9 = Guest PDPT entry
    test r9, PAGE_PRESENT
    jz .guest_fault
    
    ; Note: Assume standard 4KB paging (no huge PDPTE support in shadow tables)
    test r9, (1 << 7)               ; Check PS bit (huge page)
    jnz .guest_fault

    ; Extract child PD GPA
    and r9, 0xFFFFFFFFFFFFF000
    
    ; Translate PD GPA to HPA
    mov rdi, r15
    mov rsi, r9
    call ept_translate
    test rax, rax
    jz .guest_fault
    mov r8, rax                     ; R8 = Guest PD HPA

    ; 3. Walk Guest PD (Level 2)
    mov rax, r14
    shr rax, 21
    and rax, 0x1FF                  ; PD index
    mov r9, [r8 + rax * 8]          ; R9 = Guest PD entry
    test r9, PAGE_PRESENT
    jz .guest_fault

    ; Check PS bit (huge page)
    test r9, (1 << 7)
    jnz .guest_fault

    ; Extract child PT GPA
    and r9, 0xFFFFFFFFFFFFF000
    
    ; Translate PT GPA to HPA
    mov rdi, r15
    mov rsi, r9
    call ept_translate
    test rax, rax
    jz .guest_fault
    mov r8, rax                     ; R8 = Guest PT HPA

    ; 4. Walk Guest PT (Level 1)
    mov rax, r14
    shr rax, 12
    and rax, 0x1FF                  ; PT index
    mov r9, [r8 + rax * 8]          ; R9 = Guest PTE value
    test r9, PAGE_PRESENT
    jz .guest_fault

    ; Extract mapped Guest Physical Address (GPA)
    mov rbx, r9
    and rbx, 0xFFFFFFFFFFFFF000      ; RBX = GPA of guest page base

    ; Extract guest permissions flags (P, W, U, NX, etc.)
    mov rcx, 0xFFFFFFFFFFFFF000
    not rcx
    and r9, rcx                     ; R9 = guest permission flags

    ; 5. Translate target GPA (RBX) to target HPA
    mov rdi, r15
    mov rsi, rbx
    call ept_translate
    test rax, rax
    jz .guest_fault
    mov rdx, rax                    ; RDX = target Host Physical Address (HPA)

    ; 6. Map GVA (R14) directly to target HPA (RDX) in Shadow PML4 (R12)
    mov rdi, r12                    ; Shadow PML4 base
    mov rsi, r14                    ; GVA
    mov rcx, r9                     ; flags (copied from guest PTE)
    call spt_map_entry
    test rax, rax
    jz .fail

    mov rax, 1                      ; Fault successfully resolved and synced
    jmp .exit

.guest_fault:
    xor rax, rax                    ; Target not mapped in guest, propagate #PF
    jmp .exit

.fail:
    xor rax, rax
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; spt_free_level — Recursive helper to deallocate Shadow Page Tables
; Input:
;   RDI = table physical address (HPA)
;   RSI = paging level (1 = PT, 2 = PD, 3 = PDPT, 4 = PML4)
; -----------------------------------------------------------------------------
spt_free_level:
    push rbx
    push r12
    push r13
    
    mov rbx, rdi                    ; RBX = table physical address
    mov r12, rsi                    ; R12 = paging level
    
    ; If Level 1 (PT), do not traverse, free directly
    cmp r12, 1
    je .free_self
    
    ; Traverse entries (0 to 511)
    mov r13, 0                      ; R13 = entry index
.loop:
    cmp r13, 512
    jae .free_self
    
    mov rax, [rbx + r13 * 8]        ; RAX = shadow entry value
    test rax, PAGE_PRESENT
    jz .next
    
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = child table physical address
    
    ; Call recursively on child table
    mov rdi, rax
    mov rsi, r12
    dec rsi                         ; level - 1
    call spt_free_level
    
.next:
    inc r13
    jmp .loop
    
.free_self:
    mov rdi, rbx
    call phys_free_page
    
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; spt_destroy — Deallocates Shadow Page Table structures recursively
; Input:
;   RDI = physical address of Shadow PML4 base
; -----------------------------------------------------------------------------
global spt_destroy
spt_destroy:
    mov rsi, 4                      ; Start traversal at PML4 (Level 4)
    jmp spt_free_level

%endif ; LIB_MEM_VIRT_SPT_ASM
