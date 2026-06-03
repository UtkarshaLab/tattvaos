; =============================================================================
; Tattva OS — boot/uefi/gop.asm
; =============================================================================
; UEFI Graphics Output Protocol (GOP) initialization and query helpers.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_GOP_ASM
%define UEFI_GOP_ASM

%include "protocol.asm"

[BITS 64]

; GOP interface structure offset fields we care about
GOP_MODE_OFFSET             equ 24      ; pointer to EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE

; Mode structure offsets
GOP_MODE_MAX_MODE           equ 0
GOP_MODE_CURRENT_MODE       equ 4
GOP_MODE_INFO               equ 8       ; pointer to info structure
GOP_MODE_INFO_SIZE          equ 16
GOP_MODE_FB_BASE            equ 24      ; physical address of frame buffer (uint64)
GOP_MODE_FB_SIZE            equ 32      ; size of frame buffer (uint64)

; Mode Info structure offsets
GOP_INFO_HORIZ_RES          equ 4       ; horizontal resolution
GOP_INFO_VERT_RES           equ 8       ; vertical resolution
GOP_INFO_PIXEL_FORMAT       equ 12      ; pixel format enum

; =============================================================================
; uefi_gop_init — locate GOP and retrieve frame buffer details
; Input:  RCX = pointer to System Table
; Output: RAX = physical address of frame buffer, or 0 if failed
;         RDX = width (high 32 bits) and height (low 32 bits)
; =============================================================================
uefi_gop_init:
    push rbp
    mov rbp, rsp
    sub rsp, 48                     ; shadow space + local storage for interface pointer

    ; Get BootServices: SystemTable->BootServices (offset 88)
    mov r9, [rcx + SYS_TABLE_BOOT_SERVICES]

    ; Call LocateProtocol(gop_guid, NULL, &gop_interface)
    ; RCX = gop_guid address
    ; RDX = NULL (Registration)
    ; R8  = address of local variable (&gop_interface)
    lea rcx, [gop_guid]
    xor rdx, rdx
    lea r8, [rbp - 8]               ; address of local pointer variable
    
    mov rax, [r9 + BS_LOCATE_PROTOCOL]
    call rax                        ; execute LocateProtocol
    test rax, rax
    jnz .failed                     ; non-zero is an error status

    ; Retrieve the located GOP interface pointer
    mov rcx, [rbp - 8]              ; RCX = GOP interface pointer
    test rcx, rcx
    jz .failed

    ; Get Mode: GOP->Mode (offset 24)
    mov rdx, [rcx + GOP_MODE_OFFSET]
    test rdx, rdx
    jz .failed

    ; Get Frame Buffer Base Address: Mode->FrameBufferBase (offset 24 of Mode)
    mov rax, [rdx + GOP_MODE_FB_BASE]
    mov [uefi_fb_base], rax

    ; Get Frame Buffer Size: Mode->FrameBufferSize (offset 32 of Mode)
    mov r8, [rdx + GOP_MODE_FB_SIZE]
    mov [uefi_fb_size], r8

    ; Get Mode Info: Mode->Info (offset 8 of Mode)
    mov rdx, [rdx + GOP_MODE_INFO]
    test rdx, rdx
    jz .failed
    mov r8d, [rdx + GOP_INFO_HORIZ_RES]
    mov [uefi_fb_width], r8d
    mov r9d, [rdx + GOP_INFO_VERT_RES]
    mov [uefi_fb_height], r9d

    ; Get PixelsPerScanLine (offset 32 of Mode Info structure)
    mov eax, [rdx + 32]
    shl eax, 2                      ; multiply by 4 bytes per pixel (32bpp)
    mov [uefi_fb_pitch], eax
    mov dword [uefi_fb_format], 32  ; 32bpp format

    ; Format output: RDX = width in high 32 bits, height in low 32 bits
    shl r8, 32
    or r8, r9
    mov rdx, r8

    mov rax, [uefi_fb_base]         ; Restore RAX to physical address of frame buffer
    jmp .done

.failed:
    xor rax, rax
    xor rdx, rdx

.done:
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; Data variables to store graphics info
; =============================================================================
uefi_fb_base:   dq 0
uefi_fb_size:   dq 0
uefi_fb_width:  dd 0
uefi_fb_height: dd 0
uefi_fb_pitch:  dd 0
uefi_fb_format: dd 0

%endif ; UEFI_GOP_ASM
