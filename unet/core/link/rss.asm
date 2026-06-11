; =============================================================================
; Tattva OS — unet/core/link/rss.asm
; =============================================================================
; RSS hardware flow affinity processor mapping.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_RSS_ASM
%define UNET_CORE_LINK_RSS_ASM

[BITS 64]

%include "unet/core/link/net_ring.inc"

section .text

; -----------------------------------------------------------------------------
; net_flow_affinity_map — Binds flow hash to a target active CPU core
; Input:
;   RDI = RSS flow hash
; Output:
;   RAX = Target CPU core ID
; -----------------------------------------------------------------------------
global net_flow_affinity_map
net_flow_affinity_map:
    xor rdx, rdx
    mov rax, rdi                    ; RAX = flow hash
    
    ; Load active CPU cores
    mov ecx, [smp_active_cores]
    test ecx, ecx
    jnz .divide
    mov ecx, 1                      ; avoid divide-by-zero
.divide:
    div rcx                         ; RDX = RAX % RCX
    mov rax, rdx                    ; RAX = target core ID
    ret

%endif ; UNET_CORE_LINK_RSS_ASM
