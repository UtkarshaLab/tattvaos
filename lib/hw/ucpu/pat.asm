; =============================================================================
; Tattva OS — lib/hw/ucpu/pat.asm
; =============================================================================
; Page Attribute Table (PAT) cache controls (Subfeature 8.2).
; Configures and queries page-level caching properties in IA32_PAT MSR (0x277).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UCPU_PAT_ASM
%define LIB_HW_UCPU_PAT_ASM

[BITS 64]

; MSR Address
IA32_PAT equ 0x277

section .text

; -----------------------------------------------------------------------------
; pat_supported — checks standard PAT capability via CPUID
; Output:
;   RAX = 1 if supported, 0 otherwise
; Clobbers: RAX, RBX, RCX, RDX
; -----------------------------------------------------------------------------
global pat_supported
pat_supported:
    mov eax, 1
    cpuid
    test edx, 1 << 16               ; EDX bit 16: PAT support
    jz .no_support
    mov rax, 1
    ret
.no_support:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; pat_get_msr — reads the current IA32_PAT MSR value
; Output:
;   RAX = 64-bit MSR value, or 0 if unsupported
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global pat_get_msr
pat_get_msr:
    call pat_supported
    test rax, rax
    jz .no_pat

    mov ecx, IA32_PAT
    rdmsr                           ; EDX:EAX = MSR value
    shl rdx, 32
    or rax, rdx                     ; RAX = 64-bit value
    ret
.no_pat:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; pat_set_msr — programs the IA32_PAT MSR value under safe protocol
; Input:
;   RDI = 64-bit value to write
; Output:
;   RAX = 1 on success, 0 on unsupported
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global pat_set_msr
pat_set_msr:
    push rbx
    push r12

    mov r12, rdi                    ; R12 = target value

    call pat_supported
    test rax, rax
    jz .fail

    ; --- Safe Programming Protocol ---
    pushfq
    cli

    ; 1. Enter Cache Disable (CD) state: CR0.CD=1, CR0.NW=0
    mov rax, cr0
    or rax, 1 << 30                 ; CD bit
    and rax, ~(1 << 29)             ; NW bit
    mov cr0, rax

    ; 2. Flush internal processor caches
    wbinvd

    ; 3. Program PAT MSR
    mov ecx, IA32_PAT
    mov eax, r12d                   ; low 32 bits
    mov rdx, r12
    shr rdx, 32                     ; high 32 bits
    wrmsr

    ; 4. Flush caches again
    wbinvd

    ; 5. Restore Cache Enable state: CR0.CD=0, CR0.NW=0
    mov rax, cr0
    and rax, ~(1 << 30)             ; clear CD
    mov cr0, rax

    popfq

    mov rax, 1                      ; success
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; pat_find_entry — finds the PAT index corresponding to a specific memory type
; Input:
;   RDI = memory type (0=UC, 1=WC, 4=WT, 5=WP, 6=WB, 7=UC-)
; Output:
;   RAX = PAT slot index (0-7) if found, or -1 if not found/unsupported
; Clobbers: RAX, RCX, RDX, RSI, R8-R11
; -----------------------------------------------------------------------------
global pat_find_entry
pat_find_entry:
    push rbx
    push rcx
    push rdx

    mov rbx, rdi                    ; RBX = target memory type (lower 8 bits)

    call pat_supported
    test rax, rax
    jz .not_found

    call pat_get_msr                ; RAX = 64-bit PAT MSR value
    mov r8, rax                     ; R8 = PAT MSR value

    xor rcx, rcx                    ; RCX = loop index (0 to 7)
.loop:
    cmp rcx, 8
    jge .not_found

    mov rdx, rcx
    shl rdx, 3                      ; RDX = rcx * 8 (shift amount)
    
    mov r9, r8
    push rcx
    mov rcx, rdx
    shr r9, cl                      ; shift PAT MSR value
    pop rcx
    
    and r9, 0xFF                    ; R9 = memory type at entry RCX
    cmp r9b, bl
    je .found

    inc rcx
    jmp .loop

.found:
    mov rax, rcx                    ; RAX = index
    jmp .done

.not_found:
    mov rax, -1

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

%endif ; LIB_HW_UCPU_PAT_ASM
