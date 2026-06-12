; =============================================================================
; Tattva OS — lib/mem/virt/gpummu.asm
; =============================================================================
; GPU Page Table Shadowing Subsystem (Milestone 23.4).
; Replicates virtual page structures and mirrors CPU page tables inside
; secondary level-4 GPU MMU hardware paging trees to facilitate SVM.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_GPUMMU_ASM
%define LIB_MEM_VIRT_GPUMMU_ASM

[BITS 64]

; GPU MMU Paging Flags (compatible with standard x86-64 paging structures)
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

; External VM allocations and memory limits
extern phys_alloc_page
extern phys_free_page
extern virt_walk_table
extern kernel_end
extern phys_state

; -----------------------------------------------------------------------------
; is_valid_gpu_phys_addr — Validates GPU/CPU table page alignment and limits
; Input:
;   RDI = physical address
; Output:
;   RAX = 1 if valid, 0 if invalid
; -----------------------------------------------------------------------------
is_valid_gpu_phys_addr:
    ; 1. Alignment check (4KB aligned)
    test rdi, 4095
    jnz .invalid

    ; 2. Must not overlap host kernel code range
    cmp rdi, 0x100000
    jb .valid

    mov rax, kernel_end
    cmp rdi, rax
    jb .invalid

.valid:
    ; 3. Must be below max physical address
    mov rax, [phys_state + 32]       ; offset of max_phys_addr (5th qword)
    cmp rdi, rax
    jae .invalid

    mov rax, 1
    ret
.invalid:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; gpummu_init — Allocates and zeroes a root level-4 GPU PML4 table
; Output:
;   RAX = physical address of GPU PML4 base (HPA), or 0 on failure
; -----------------------------------------------------------------------------
global gpummu_init
gpummu_init:
    call phys_alloc_page
    test rax, rax
    jz .fail

    ; Zero out the 4KB page frame
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax
.fail:
    ret

; -----------------------------------------------------------------------------
; gpummu_map — Maps a Virtual Address (GVA) to Physical Address inside GPU MMU
; Input:
;   RDI = physical address of GPU PML4 table base (HPA)
;   RSI = Guest Virtual Address (GVA) (must be page aligned)
;   RDX = Host Physical Address (HPA) (must be page aligned)
;   RCX = mapping flags (e.g. PAGE_PRESENT | PAGE_WRITABLE)
; Output:
;   RAX = 1 on success, 0 on failure (OOM)
; -----------------------------------------------------------------------------
global gpummu_map
gpummu_map:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = GPU PML4 HPA
    mov r13, rsi                    ; R13 = GVA (aligned)
    mov r14, rdx                    ; R14 = Physical HPA (aligned)
    mov r15, rcx                    ; R15 = mapping flags

    ; Validate inputs
    test r12, r12
    jz .fail
    test r13, 4095
    jnz .fail
    test r14, 4095
    jnz .fail

    ; Verify base and mapping physical addresses are valid
    mov rdi, r12
    call is_valid_gpu_phys_addr
    test rax, rax
    jz .fail

    mov rdi, r14
    call is_valid_gpu_phys_addr
    test rax, rax
    jz .fail

    ; 1. Walk PML4 (Level 4)
    mov rax, r13
    shr rax, 39
    and rax, 0x1FF                  ; PML4 index
    lea r8, [r12 + rax * 8]         ; R8 = PML4 entry address
    mov r9, [r8]                    ; R9 = entry value
    test r9, PAGE_PRESENT
    jnz .pml4_valid

    ; Allocate GPU PDPT
    call phys_alloc_page
    test rax, rax
    jz .fail

    ; Zero out table
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax

    ; Link PDPT to PML4
    mov r9, rax
    or r9, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [r8], r9

.pml4_valid:
    and r9, 0xFFFFFFFFFFFFF000      ; R9 = PDPT physical address

    ; 2. Walk PDPT (Level 3)
    mov rax, r13
    shr rax, 30
    and rax, 0x1FF                  ; PDPT index
    lea r8, [r9 + rax * 8]          ; R8 = PDPT entry address
    mov r9, [r8]                    ; R9 = entry value
    test r9, PAGE_PRESENT
    jnz .pdpt_valid

    ; Allocate GPU PD
    call phys_alloc_page
    test rax, rax
    jz .fail

    ; Zero out table
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax

    ; Link PD to PDPT
    mov r9, rax
    or r9, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [r8], r9

.pdpt_valid:
    and r9, 0xFFFFFFFFFFFFF000      ; R9 = PD physical address

    ; 3. Walk PD (Level 2)
    mov rax, r13
    shr rax, 21
    and rax, 0x1FF                  ; PD index
    lea r8, [r9 + rax * 8]          ; R8 = PD entry address
    mov r9, [r8]                    ; R9 = entry value
    test r9, PAGE_PRESENT
    jnz .pd_valid

    ; Allocate GPU PT
    call phys_alloc_page
    test rax, rax
    jz .fail

    ; Zero out table
    push rax
    mov rdi, rax
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    pop rax

    ; Link PT to PD
    mov r9, rax
    or r9, (PAGE_PRESENT | PAGE_WRITABLE | PAGE_USER)
    mov [r8], r9

.pd_valid:
    and r9, 0xFFFFFFFFFFFFF000      ; R9 = PT physical address

    ; 4. Walk PT (Level 1)
    mov rax, r13
    shr rax, 12
    and rax, 0x1FF                  ; PT index
    lea r8, [r9 + rax * 8]          ; R8 = PT entry address (leaf GPU PTE)

    ; Write physical target address and flags
    mov r9, r14
    and r9, 0xFFFFFFFFFFFFF000
    or r9, r15                      ; Link flags
    mov [r8], r9

    mov rax, 1                      ; return success
    jmp .exit

.fail:
    xor rax, rax                    ; return failure
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpummu_unmap — Clears a GVA mapping from the GPU page tables
; Input:
;   RDI = physical address of GPU PML4 base (HPA)
;   RSI = Guest Virtual Address (GVA) (must be page aligned)
; Output:
;   RAX = 1 on success (cleared), 0 if not mapped
; -----------------------------------------------------------------------------
global gpummu_unmap
gpummu_unmap:
    ; Walk PML4
    mov rax, rsi
    shr rax, 39
    and rax, 0x1FF
    mov r8, [rdi + rax * 8]
    test r8, PAGE_PRESENT
    jz .not_mapped

    ; Walk PDPT
    and r8, 0xFFFFFFFFFFFFF000
    mov rax, rsi
    shr rax, 30
    and rax, 0x1FF
    mov r9, [r8 + rax * 8]
    test r9, PAGE_PRESENT
    jz .not_mapped

    ; Walk PD
    and r9, 0xFFFFFFFFFFFFF000
    mov rax, rsi
    shr rax, 21
    and rax, 0x1FF
    mov r8, [r9 + rax * 8]
    test r8, PAGE_PRESENT
    jz .not_mapped

    ; Walk PT
    and r8, 0xFFFFFFFFFFFFF000
    mov rax, rsi
    shr rax, 12
    and rax, 0x1FF
    lea rcx, [r8 + rax * 8]         ; RCX = leaf PTE address
    mov rax, [rcx]
    test rax, PAGE_PRESENT
    jz .not_mapped

    ; Clear the leaf mapping
    mov qword [rcx], 0
    mov rax, 1                      ; success
    ret

.not_mapped:
    xor rax, rax                    ; return 0 (not mapped)
    ret

; -----------------------------------------------------------------------------
; gpummu_sync_cpu_range — Replicates a CPU virtual range into GPU page tables
; Input:
;   RDI = physical address of GPU PML4 base (HPA)
;   RSI = starting virtual address (GVA, page-aligned)
;   RDX = size of virtual range in bytes (page-aligned)
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global gpummu_sync_cpu_range
gpummu_sync_cpu_range:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; r12 = GPU PML4 base
    mov r13, rsi                    ; r13 = start GVA
    mov r14, rdx                    ; r14 = size

    ; Validate inputs
    test r12, r12
    jz .fail
    test r13, 4095
    jnz .fail
    test r14, 4095
    jnz .fail

    xor rbx, rbx                    ; rbx = offset loop index

.loop_sync:
    cmp rbx, r14
    jae .success

    ; Target virtual address
    mov rdi, r13
    add rdi, rbx                    ; RDI = GVA

    ; Walk CPU page tables (RSI = 0 to load CR3)
    xor rsi, rsi
    call virt_walk_table            ; RAX = CPU PTE pointer, RDX = level
    test rax, rax
    jz .next_page                   ; skip if not mapped on CPU
    cmp rdx, 1                      ; leaf level
    jne .next_page

    mov r8, [rax]                   ; R8 = CPU PTE value
    test r8, PAGE_PRESENT
    jz .next_page                   ; skip if non-present

    ; Extract HPA page frame
    mov rdx, r8
    and rdx, 0xFFFFFFFFFFFFF000     ; RDX = HPA

    ; Extract mapping flags
    mov rcx, r8
    and rcx, 0xFFF
    mov r10, (1 << 63)
    and r10, r8
    or rcx, r10                     ; RCX = flags (with NX)

    ; Shadow GVA -> HPA in GPU page tables
    mov rdi, r12                    ; GPU PML4 base
    mov rsi, r13
    add rsi, rbx                    ; GVA
    
    push rbx
    call gpummu_map
    pop rbx
    test rax, rax
    jz .fail                        ; OOM mapping failure

.next_page:
    add rbx, 4096
    jmp .loop_sync

.success:
    mov rax, 1
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
; gpummu_free_level — Recursive helper to deallocate GPU page tables
; Input:
;   RDI = table physical address (HPA)
;   RSI = paging level (1 = PT, 2 = PD, 3 = PDPT, 4 = PML4)
; -----------------------------------------------------------------------------
gpummu_free_level:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = table base
    mov r12, rsi                    ; R12 = paging level

    cmp r12, 1                      ; PT level
    je .free_self

    xor r13, r13                    ; R13 = entry index
.loop:
    cmp r13, 512
    jae .free_self

    mov rax, [rbx + r13 * 8]
    test rax, PAGE_PRESENT
    jz .next

    and rax, 0xFFFFFFFFFFFFF000     ; RAX = child table HPA
    
    mov rdi, rax
    mov rsi, r12
    dec rsi                         ; level - 1
    call gpummu_free_level

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
; gpummu_destroy — Deallocates GPU MMU structures recursively
; Input:
;   RDI = physical address of GPU PML4 base (HPA)
; Output: none
; -----------------------------------------------------------------------------
global gpummu_destroy
gpummu_destroy:
    test rdi, rdi
    jz .done
    mov rsi, 4                      ; PML4 is level 4
    call gpummu_free_level
.done:
    ret

%endif ; LIB_MEM_VIRT_GPUMMU_ASM
