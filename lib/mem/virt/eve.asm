; =============================================================================
; Tattva OS — lib/mem/virt/eve.asm
; =============================================================================
; EPT Violation & Virtualization Exception (#VE) Handler (Milestone 22.4).
; Intercepts EPT violation faults (exit reason 48) on VM exits, resolving
; present page faults and Copy-on-Write write violations on read-only pages.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_EVE_ASM
%define LIB_MEM_VIRT_EVE_ASM

[BITS 64]

; Intel EPT Flags (matching ept.asm)
EPT_READ        equ (1 << 0)        ; Bit 0: Read access
EPT_WRITE       equ (1 << 1)        ; Bit 1: Write access
EPT_EXEC        equ (1 << 2)        ; Bit 2: Execute access
EPT_MT_WB       equ (6 << 3)        ; Bits 5:3: Memory Type (Write-Back)

section .text

; External EPT and memory allocator functions
extern phys_alloc_page
extern phys_free_page
extern ept_map_page
extern ept_translate
extern vtlb_invept

; -----------------------------------------------------------------------------
; eve_init_ve_info — Initializes the 4KB Virtualization Exception info page
; Input:
;   RDI = physical address of the #VE info page (HPA)
; Output: none
; -----------------------------------------------------------------------------
global eve_init_ve_info
eve_init_ve_info:
    push rdi
    
    ; Zero out the entire 4KB page
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq
    
    pop rdi
    ret

; -----------------------------------------------------------------------------
; eve_handle_ept_violation — Resolves guest EPT violations (present & COW faults)
; Input:
;   RDI = exit qualification (from VMCS)
;   RSI = Guest Physical Address (GPA) causing the violation (page-aligned)
;   RDX = Guest Linear Address (GLA) (page-aligned)
;   RCX = physical address of EPT PML4 table base (HPA)
; Output:
;   RAX = 1 on successful resolution, 0 on fatal violation (propagate fault/abort)
; -----------------------------------------------------------------------------
global eve_handle_ept_violation
eve_handle_ept_violation:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = exit qualification
    mov r13, rsi                    ; R13 = faulting GPA
    mov r14, rdx                    ; R14 = faulting GLA
    mov r15, rcx                    ; R15 = EPT PML4 HPA

    ; 1. Analyze EPT permissions in exit qualification
    ; Bits 2:0 represent EPT Read, Write, and Execute permissions respectively.
    ; If all are 0, it is a PRESENT violation (page is missing in EPT).
    mov rax, r12
    and rax, 7                      ; Check EPT permissions
    jz .handle_present_violation

    ; 2. Check for Copy-on-Write write violation
    ; Condition: Write violation on a read-only present page
    ; - Exit qualification bit 1 = 1 (write access caused fault)
    ; - Leaf EPT PTE has EPT_READ = 1, EPT_WRITE = 0
    test r12, EPT_WRITE
    jz .fail                        ; Not a write fault!

    ; Walk guest's EPT to retrieve the leaf PTE address for the GPA
    ; PML4 Walk
    mov rax, r13
    shr rax, 39
    and rax, 0x1FF                  ; PML4 index
    mov r8, [r15 + rax * 8]
    test r8, 7
    jz .fail

    ; PDPT Walk
    and r8, 0xFFFFFFFFFFFFF000
    mov rax, r13
    shr rax, 30
    and rax, 0x1FF                  ; PDPT index
    mov r9, [r8 + rax * 8]
    test r9, 7
    jz .fail

    ; PD Walk
    and r9, 0xFFFFFFFFFFFFF000
    mov rax, r13
    shr rax, 21
    and rax, 0x1FF                  ; PD index
    mov r8, [r9 + rax * 8]
    test r8, 7
    jz .fail

    ; PT Walk (Leaf entry)
    and r8, 0xFFFFFFFFFFFFF000
    mov rax, r13
    shr rax, 12
    and rax, 0x1FF                  ; PT index
    lea r10, [r8 + rax * 8]         ; R10 = EPT PTE address
    mov r11, [r10]                 ; R11 = EPT PTE value

    ; Verify that page is mapped read-only in EPT
    test r11, EPT_WRITE             ; Is writable?
    jnz .fail                       ; If writable, why the fault?
    test r11, EPT_READ              ; Is present/readable?
    jz .fail                        ; If not readable, not a COW fault.

    ; Handle Copy-on-Write (COW):
    ; A. Allocate new host page frame (HPA)
    call phys_alloc_page
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = new HPA

    ; B. Copy 4KB page payload from old physical page to new physical page
    push rsi
    push rdi
    push rcx
    
    mov rsi, r11
    and rsi, 0xFFFFFFFFFFFFF000      ; Source physical address (old HPA page)
    mov rdi, rbx                    ; Destination physical address (new HPA page)
    mov rcx, 512                    ; 512 qwords (4096 bytes)
    cld
    rep movsq
    
    pop rcx
    pop rdi
    pop rsi

    ; C. Update EPT entry to map GPA to the new HPA with Write permissions enabled
    mov r9, rbx
    or r9, (EPT_READ | EPT_WRITE | EPT_EXEC | EPT_MT_WB)
    mov [r10], r9                 ; Map new physical page

    ; D. Invalidate host EPT TLB cache (Type 2 = All-contexts EPT invalidate)
    mov rdi, 2
    xor rsi, rsi
    call vtlb_invept

    mov rax, 1                      ; Return success
    jmp .exit

.handle_present_violation:
    ; On-Demand mapping: Page not present in EPT.
    ; A. Allocate host physical frame
    call phys_alloc_page
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = allocated HPA

    ; B. Zero out the allocated page frame
    mov rdi, rbx
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq

    ; C. Map guest GPA directly to new HPA in EPT with full access
    mov rdi, r15                    ; EPT PML4
    mov rsi, r13                    ; GPA
    mov rdx, rbx                    ; HPA
    mov rcx, (EPT_READ | EPT_WRITE | EPT_EXEC | EPT_MT_WB)
    call ept_map_page
    test rax, rax
    jz .oom_cleanup

    ; D. Invalidate host EPT TLB cache
    mov rdi, 2
    xor rsi, rsi
    call vtlb_invept

    mov rax, 1                      ; Return success
    jmp .exit

.oom_cleanup:
    mov rdi, rbx
    call phys_free_page
.fail:
    xor rax, rax                    ; Return failure
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_EVE_ASM
