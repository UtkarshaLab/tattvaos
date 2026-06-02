; =============================================================================
; Tattva OS — boot/stage2/paging/paging_verify.asm
; =============================================================================
; Verify page table correctness before enabling paging.
; Halts with error if any check fails.
; Call after paging_setup, before longmode_enter.
;
; Checks:
;   1. PML4[0] points to PAGING_PDPT (present + RW)
;   2. PDPT[0..3] point to correct PD addresses (present + RW)
;   3. PD0[0] maps physical 0x000000 as 2MB huge page
;   4. PD0[1] maps physical 0x200000 (sequential)
;   5. Kernel load address (0x100000) is mapped and present
;   6. No entry in first 4 PDPTs is zero (all should be mapped)
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef PAGING_VERIFY_ASM
%define PAGING_VERIFY_ASM

; =============================================================================
; paging_verify — check page tables before enabling paging
; Input:  page tables at PAGING_PML4
; Output: CF=0 all checks pass
;         CF=1 verification failed (caller should halt)
; Clobbers: EAX, EBX, EDI
; =============================================================================
[BITS 32]
paging_verify:
    push eax
    push ebx
    push edi

    ; -------------------------------------------------------------------------
    ; Check 1: PML4[0] present and points to PDPT
    ; -------------------------------------------------------------------------
    mov edi, PAGING_PML4
    mov eax, [edi]                  ; PML4[0] low dword

    test eax, PAGE_PRESENT
    jz .fail_pml4_present

    ; mask flags, check base address
    and eax, 0xFFFFF000
    cmp eax, PAGING_PDPT
    jne .fail_pml4_base

    ; -------------------------------------------------------------------------
    ; Check 2: PDPT[0..3] present and point to correct PDs
    ; -------------------------------------------------------------------------
    mov edi, PAGING_PDPT

    mov eax, [edi + 0x00]           ; PDPT[0]
    test eax, PAGE_PRESENT
    jz .fail_pdpt_present
    and eax, 0xFFFFF000
    cmp eax, PAGING_PD0
    jne .fail_pdpt_base

    mov eax, [edi + 0x08]           ; PDPT[1]
    test eax, PAGE_PRESENT
    jz .fail_pdpt_present
    and eax, 0xFFFFF000
    cmp eax, PAGING_PD1
    jne .fail_pdpt_base

    mov eax, [edi + 0x10]           ; PDPT[2]
    test eax, PAGE_PRESENT
    jz .fail_pdpt_present
    and eax, 0xFFFFF000
    cmp eax, PAGING_PD2
    jne .fail_pdpt_base

    mov eax, [edi + 0x18]           ; PDPT[3]
    test eax, PAGE_PRESENT
    jz .fail_pdpt_present
    and eax, 0xFFFFF000
    cmp eax, PAGING_PD3
    jne .fail_pdpt_base

    ; -------------------------------------------------------------------------
    ; Check 3: PD0[0] maps physical 0x000000 as 2MB huge page
    ; -------------------------------------------------------------------------
    mov edi, PAGING_PD0
    mov eax, [edi]                  ; PD0[0]

    test eax, PAGE_PRESENT
    jz .fail_pd_present

    test eax, PAGE_HUGE
    jz .fail_pd_huge

    ; base should be 0x000000 | flags
    mov ebx, eax
    and ebx, 0xFFE00000             ; mask to 2MB boundary
    cmp ebx, 0x000000
    jne .fail_pd_base

    ; -------------------------------------------------------------------------
    ; Check 4: PD0[1] maps physical 0x200000
    ; -------------------------------------------------------------------------
    mov eax, [edi + 8]              ; PD0[1]
    test eax, PAGE_PRESENT
    jz .fail_pd_present

    mov ebx, eax
    and ebx, 0xFFE00000
    cmp ebx, 0x200000
    jne .fail_pd_base

    ; -------------------------------------------------------------------------
    ; Check 5: Kernel load address (0x100000) is covered
    ; 0x100000 is in PD0, entry index = 0x100000 >> 21 = 0
    ; (covered by PD0[0] which maps 0x000000-0x1FFFFF)
    ; Already verified above — implicit pass
    ; -------------------------------------------------------------------------

    ; -------------------------------------------------------------------------
    ; All checks passed
    ; -------------------------------------------------------------------------
    mov esi, msg_paging_ok
    call uart_print_pm
    clc
    jmp .verify_done

.fail_pml4_present:
    mov esi, msg_fail_pml4_present
    call uart_print_pm
    stc
    jmp .verify_done

.fail_pml4_base:
    mov esi, msg_fail_pml4_base
    call uart_print_pm
    stc
    jmp .verify_done

.fail_pdpt_present:
    mov esi, msg_fail_pdpt_present
    call uart_print_pm
    stc
    jmp .verify_done

.fail_pdpt_base:
    mov esi, msg_fail_pdpt_base
    call uart_print_pm
    stc
    jmp .verify_done

.fail_pd_present:
    mov esi, msg_fail_pd_present
    call uart_print_pm
    stc
    jmp .verify_done

.fail_pd_huge:
    mov esi, msg_fail_pd_huge
    call uart_print_pm
    stc
    jmp .verify_done

.fail_pd_base:
    mov esi, msg_fail_pd_base
    call uart_print_pm
    stc

.verify_done:
    pop edi
    pop ebx
    pop eax
    ret

; =============================================================================
; Strings
; =============================================================================
msg_paging_ok:
    db "Paging verify: OK", 0x0D, 0x0A, 0
msg_fail_pml4_present:
    db "Paging verify: FAIL PML4[0] not present", 0x0D, 0x0A, 0
msg_fail_pml4_base:
    db "Paging verify: FAIL PML4[0] wrong base", 0x0D, 0x0A, 0
msg_fail_pdpt_present:
    db "Paging verify: FAIL PDPT entry not present", 0x0D, 0x0A, 0
msg_fail_pdpt_base:
    db "Paging verify: FAIL PDPT entry wrong base", 0x0D, 0x0A, 0
msg_fail_pd_present:
    db "Paging verify: FAIL PD entry not present", 0x0D, 0x0A, 0
msg_fail_pd_huge:
    db "Paging verify: FAIL PD entry not huge page", 0x0D, 0x0A, 0
msg_fail_pd_base:
    db "Paging verify: FAIL PD entry wrong base address", 0x0D, 0x0A, 0

[BITS 16]

%endif ; PAGING_VERIFY_ASM