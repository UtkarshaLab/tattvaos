; =============================================================================
; Tattva OS — lib/mem/virt/vtlb.asm
; =============================================================================
; Virtual TLB Cache Invalidation Subsystem (Milestone 22.3).
; Intercepts guest TLB flushes on VM exits and issues EPT/VPID hardware
; invalidations or maps them to host shadow TLB invalidation instructions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_VTLB_ASM
%define LIB_MEM_VIRT_VTLB_ASM

[BITS 64]

; Intel VMX VM-Exit reasons for TLB operations
EXIT_REASON_INVLPG      equ 12
EXIT_REASON_CR_ACCESS   equ 28

section .text

; External TLB and Shadow Page Table symbols
extern tlb_flush_page
extern tlb_flush_all
extern spt_unmap_entry

; -----------------------------------------------------------------------------
; vtlb_invept — Executes hardware Extended Page Table cache invalidation (INVEPT)
; Input:
;   RDI = Invalidation type:
;         1 = Single-Context invalidation (invalidates EPT mappings for one context)
;         2 = All-Context invalidation (invalidates all EPT mappings)
;   RSI = EPT Pointer (EPTP) value (for single-context type)
; Output: none
; Clobbers: RAX
; -----------------------------------------------------------------------------
global vtlb_invept
vtlb_invept:
    ; Create a 128-bit (16-byte) EPT descriptor on the stack
    sub rsp, 16
    mov [rsp], rsi                  ; Bits 63:0   = EPTP
    mov qword [rsp + 8], 0          ; Bits 127:64 = Reserved (0)
    
    ; Execute INVEPT instruction
    invept rdi, [rsp]
    
    add rsp, 16
    ret

; -----------------------------------------------------------------------------
; vtlb_invvpid — Executes hardware Virtual Processor ID cache invalidation (INVVPID)
; Input:
;   RDI = Invalidation type:
;         0 = Individual-address invalidation
;         1 = Single-context invalidation
;         2 = All-contexts invalidation
;         3 = Single-context invalidation, retaining global translations
;   RSI = Virtual Processor ID (VPID, 16-bit)
;   RDX = Linear address to invalidate (for type 0)
; Output: none
; Clobbers: RAX
; -----------------------------------------------------------------------------
global vtlb_invvpid
vtlb_invvpid:
    ; Create a 128-bit (16-byte) VPID descriptor on the stack
    sub rsp, 16
    mov [rsp], si                   ; Bits 15:0   = VPID
    mov word [rsp + 2], 0           ; Bits 31:16  = Reserved (0)
    mov dword [rsp + 4], 0          ; Bits 63:32  = Reserved (0)
    mov [rsp + 8], rdx              ; Bits 127:64 = Linear Address
    
    ; Execute INVVPID instruction
    invvpid rdi, [rsp]
    
    add rsp, 16
    ret

; -----------------------------------------------------------------------------
; vtlb_handle_guest_tlb_flush — Dispatches guest TLB flushes trapped by VM exit
; Input:
;   RDI = VM-exit reason (e.g. EXIT_REASON_CR_ACCESS or EXIT_REASON_INVLPG)
;   RSI = VM-exit qualification (contains GVA for INVLPG, details for CR3 access)
;   RDX = Physical address of Shadow PML4 base (HPA) (needed if EPT is disabled)
;   RCX = Guest Virtual Processor ID (VPID, 16-bit, if 0 then VPID is inactive)
; Output:
;   RAX = 1 on success, 0 on unsupported exit reason
; -----------------------------------------------------------------------------
global vtlb_handle_guest_tlb_flush
vtlb_handle_guest_tlb_flush:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = exit reason
    mov r12, rsi                    ; R12 = exit qualification (contains GVA / info)
    mov r13, rdx                    ; R13 = Shadow PML4 base HPA
    mov r14, rcx                    ; R14 = VPID (16-bit)

    ; 1. Dispatch based on exit reason
    cmp rbx, EXIT_REASON_CR_ACCESS
    je .handle_cr_access
    
    cmp rbx, EXIT_REASON_INVLPG
    je .handle_invlpg
    
    ; Unsupported exit reason
    xor rax, rax
    jmp .exit

.handle_cr_access:
    ; Check if access was a write to CR3 (Exit qualification bit 5:4 = 00b for CR3 write)
    mov rax, r12
    and rax, 0x3F                   ; Mask control register index and access type
    cmp rax, 0                      ; index 0 (CR3), type 0 (write)
    jne .unsupported_cr_access

    ; Guest wrote to CR3 -> Flush TLB entries for this guest context
    test r14, r14
    jz .shadow_cr3_flush            ; If VPID is 0, fall back to software shadow flush

    ; Hardware VPID is active: execute INVVPID type 1 (Single-context invalidation)
    mov rdi, 1                      ; Type 1: Single-context invalidation
    mov rsi, r14                    ; VPID
    xor rdx, rdx                    ; Address is ignored
    call vtlb_invvpid
    jmp .success

.shadow_cr3_flush:
    ; Software Shadow Page Tables: Reload CR3 on the host to flush shadow entries
    call tlb_flush_all
    jmp .success

.unsupported_cr_access:
    xor rax, rax
    jmp .exit

.handle_invlpg:
    ; Guest executed INVLPG. The exit qualification contains the Guest Linear Address (GVA).
    test r14, r14
    jz .shadow_invlpg_flush         ; If VPID is 0, fall back to software shadow invalidation

    ; Hardware VPID active: execute INVVPID type 0 (Individual-address invalidation)
    mov rdi, 0                      ; Type 0: Individual-address invalidation
    mov rsi, r14                    ; VPID
    mov rdx, r12                    ; RDX = GVA from exit qualification
    call vtlb_invvpid
    jmp .success

.shadow_invlpg_flush:
    ; Software Shadow Page Tables:
    ; A. Unmap the entry from the Shadow PML4 structure
    mov rdi, r13                    ; Shadow PML4 HPA
    mov rsi, r12                    ; GVA
    call spt_unmap_entry

    ; B. Execute a physical host INVLPG on the linear address (GVA)
    mov rdi, r12                    ; GVA
    call tlb_flush_page

.success:
    mov rax, 1

.exit:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_VTLB_ASM
