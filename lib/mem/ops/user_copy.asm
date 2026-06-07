; =============================================================================
; Tattva OS — lib/mem/ops/user_copy.asm
; =============================================================================
; Safe user memory copy functions that bypass SMAP checks using stac/clac.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_OPS_USER_COPY_ASM
%define LIB_MEM_OPS_USER_COPY_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; copy_from_user — copies data from user space to kernel space, bypassing SMAP
; Input:
;   RDI = destination kernel pointer
;   RSI = source user pointer
;   RDX = byte count
; Output:
;   RAX = destination kernel pointer (RDI)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11, YMM0
; -----------------------------------------------------------------------------
global copy_from_user
copy_from_user:
    test rdx, rdx
    jz .done_from

    ; Check if SMAP is supported and active
    cmp byte [cpu_has_smap], 0
    jz .no_smap_from

    stac                            ; Disable SMAP checks (set AC flag)
    call memcpy
    clac                            ; Enable SMAP checks (clear AC flag)
    ret

.no_smap_from:
    call memcpy
.done_from:
    ret

; -----------------------------------------------------------------------------
; copy_to_user — copies data from kernel space to user space, bypassing SMAP
; Input:
;   RDI = destination user pointer
;   RSI = source kernel pointer
;   RDX = byte count
; Output:
;   RAX = destination user pointer (RDI)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11, YMM0
; -----------------------------------------------------------------------------
global copy_to_user
copy_to_user:
    test rdx, rdx
    jz .done_to

    ; Check if SMAP is supported and active
    cmp byte [cpu_has_smap], 0
    jz .no_smap_to

    stac                            ; Disable SMAP checks (set AC flag)
    call memcpy
    clac                            ; Enable SMAP checks (clear AC flag)
    ret

.no_smap_to:
    call memcpy
.done_to:
    ret

%endif ; LIB_MEM_OPS_USER_COPY_ASM
