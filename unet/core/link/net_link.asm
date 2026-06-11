; =============================================================================
; Tattva OS — unet/core/link/net_link.asm
; =============================================================================
; Top-level wrapper for the modular zero-copy network link layer subsystem.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UNET_CORE_LINK_NET_LINK_ASM
%define UNET_CORE_LINK_NET_LINK_ASM

[BITS 64]

; 1. Base Shared Include Declarations
%include "unet/core/link/net_ring.inc"

; 2. Modular Subsystems
%include "unet/core/link/net_ring.asm"
%include "unet/core/link/ring.asm"
%include "unet/core/link/pci.asm"
%include "unet/core/link/loan.asm"
%include "unet/core/link/sbuf.asm"
%include "unet/core/link/recycle.asm"
%include "unet/core/link/rss.asm"

%endif ; UNET_CORE_LINK_NET_LINK_ASM
