; =============================================================================
; Tattva OS — lib/mem/virt/pml.asm
; =============================================================================
; Guest Page Modification Log (PML) Subsystem (Milestone 22.5).
; Configures hardware page write logging inside the VMCS to track guest writes
; and implements the PML Full exit handler to update dirty page tracking.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PML_ASM
%define LIB_MEM_VIRT_PML_ASM

[BITS 64]

; VMCS Field Encodings (Intel SDM Volume 3C)
VMCS_PML_ADDRESS                         equ 0x0000200E      ; 64-bit PML Address
VMCS_PML_INDEX                           equ 0x00004812      ; 16-bit PML Index
VMCS_CTRL_SECONDARY_PROC_BASED_EXEC_CTRL equ 0x0000401E      ; 32-bit Secondary Controls

; Secondary Processor-Based VM-Execution Controls bit
SECONDARY_EXEC_ENABLE_PML                equ (1 << 17)       ; Bit 17: Page Modification Logging

section .text

; -----------------------------------------------------------------------------
; pml_init_buffer — Zeroes out the 4KB PML buffer frame
; Input:
;   RDI = HPA of the PML buffer (must be 4KB aligned)
; Output: none
; -----------------------------------------------------------------------------
global pml_init_buffer
pml_init_buffer:
    ; Check alignment
    test rdi, 4095
    jnz .done

    push rdi
    push rcx
    push rax

    xor rax, rax
    mov rcx, 512                    ; 512 qwords (4096 bytes)
    cld
    rep stosq

    pop rax
    pop rcx
    pop rdi
.done:
    ret

; -----------------------------------------------------------------------------
; pml_configure — Configures PML fields in the current active VMCS
; Input:
;   RDI = HPA of the PML buffer (4KB aligned)
;   RSI = PML index (usually 511)
; Output:
;   RAX = 1 on success, 0 on failure (VMCS write error)
; -----------------------------------------------------------------------------
global pml_configure
pml_configure:
    ; 1. Validate alignment of PML buffer address
    test rdi, 4095
    jnz .fail

    ; 2. Write VMCS_PML_ADDRESS
    mov rax, VMCS_PML_ADDRESS
    vmwrite rax, rdi
    jc .fail                        ; CF=1 indicates VMwrite failed
    jz .fail                        ; ZF=1 indicates VMwrite failed with status

    ; 3. Write VMCS_PML_INDEX
    mov rax, VMCS_PML_INDEX
    vmwrite rax, rsi
    jc .fail
    jz .fail

    ; 4. Read Secondary Controls, modify, and write back
    mov rax, VMCS_CTRL_SECONDARY_PROC_BASED_EXEC_CTRL
    vmread rbx, rax
    jc .fail
    jz .fail

    or rbx, SECONDARY_EXEC_ENABLE_PML

    vmwrite rax, rbx
    jc .fail
    jz .fail

    mov rax, 1                      ; Return success
    ret

.fail:
    xor rax, rax                    ; Return failure
    ret

; -----------------------------------------------------------------------------
; pml_handle_full — Processes PML full VM exit and resets index
; Input:
;   RDI = virtual/mapped address of the 4KB PML buffer
;   RSI = base address of the host dirty tracking bitmap
;   RDX = max guest physical pages (bounds check limit)
; Output:
;   RAX = 1 on success, 0 on VMCS update failure
; -----------------------------------------------------------------------------
global pml_handle_full
pml_handle_full:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = PML buffer address
    mov r13, rsi                    ; R13 = dirty bitmap address
    mov r14, rdx                    ; R14 = max guest pages (limit)

    ; 1. Read current PML index from VMCS
    mov rax, VMCS_PML_INDEX
    vmread r15, rax
    jc .exit_fail
    jz .exit_fail

    ; Sanitize and clamp index: if it is > 511 or negative (PML full underflow to 0xFFFF),
    ; process the entire buffer (index = 0).
    cmp r15, 511
    jbe .start_processing
    xor r15, r15

.start_processing:
    ; Walk from r15 to 511 (inclusive)
    mov rcx, r15                    ; RCX = loop index

.loop_entries:
    cmp rcx, 512
    jae .done_processing

    ; Read Guest Physical Address from PML buffer
    mov rax, [r12 + rcx * 8]

    ; Verify page aligned or align it
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = guest page address

    ; STRICT PHYSICAL ADDRESS SECURITY AUDITS:
    ; 1. Check physical address size limits (avoid non-canonical / overflow range attacks)
    mov r8, 0xFFFF000000000000      ; Mask upper bits above 48-bit physical width
    test rax, r8
    jnz .skip_entry                 ; Skip if address is out of physical bounds

    ; 2. Translate address to page frame number (PFN)
    mov r8, rax
    shr r8, 12                      ; R8 = PFN

    ; 3. Bound check: check against max guest pages limit to prevent OOB bitmap writes
    cmp r8, r14
    jae .skip_entry

    ; 4. Set bit in dirty bitmap (thread-safe modification with lock prefix if multithreaded)
    lock bts [r13], r8

.skip_entry:
    inc rcx
    jmp .loop_entries

.done_processing:
    ; 2. Reset VMCS PML index back to 511
    mov rax, VMCS_PML_INDEX
    mov rsi, 511
    vmwrite rax, rsi
    jc .exit_fail
    jz .exit_fail

    mov rax, 1                      ; Return success
    jmp .exit

.exit_fail:
    xor rax, rax                    ; Return failure
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_PML_ASM
