; =============================================================================
; Tattva OS — boot/uefi/memory.asm
; =============================================================================
; Retrieve UEFI memory map using BootServices->GetMemoryMap.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_MEMORY_ASM
%define UEFI_MEMORY_ASM

%include "protocol.asm"

[BITS 64]

; =============================================================================
; uefi_get_memory_map — query GetMemoryMap
; Input:  RCX = pointer to System Table
;         RDX = pointer to destination memory map buffer
;         R8  = pointer to MemoryMapSize variable
; Output: RAX = status code (0 on success)
;         RDX = MapKey value
; =============================================================================
uefi_get_memory_map:
    push rbp
    mov rbp, rsp
    sub rsp, 48                     ; shadow space + local storage

    mov r10, rcx                    ; R10 = System Table
    mov r11, rdx                    ; R11 = MemoryMap buffer pointer

    ; Get BootServices: SystemTable->BootServices (offset 88)
    mov rdx, [r10 + SYS_TABLE_BOOT_SERVICES]
    mov [rbp - 8], rdx              ; store BootServices

    ; Call GetMemoryMap(MemoryMapSize, MemoryMap, MapKey, DescriptorSize, DescriptorVersion)
    ; Microsoft x64 Calling Convention:
    ;   RCX = &MemoryMapSize (passed in R8)
    ;   RDX = MemoryMap buffer (passed in R11)
    ;   R8  = &MapKey (local address &uefi_map_key)
    ;   R9  = &DescriptorSize (local address &uefi_desc_size)
    ;   Stack [ESP + 32] = &DescriptorVersion (local address &uefi_desc_version)
    
    mov rcx, r8                     ; RCX = &MemoryMapSize
    mov rdx, r11                    ; RDX = MemoryMap buffer
    lea r8, [uefi_map_key]          ; R8 = &MapKey
    lea r9, [uefi_desc_size]        ; R9 = &DescriptorSize
    
    lea rax, [uefi_desc_version]
    mov [rsp + 32], rax             ; 5th argument at stack offset 32

    mov rax, [rbp - 8]              ; RAX = BootServices
    mov rax, [rax + BS_GET_MEMORY_MAP]
    call rax                        ; execute GetMemoryMap

    mov rdx, [uefi_map_key]         ; return MapKey value in RDX

    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; Data variables to store memory map parameters
; =============================================================================
align 8
uefi_map_key:       dq 0
uefi_desc_size:     dq 0
uefi_desc_version:  dd 0

%endif ; UEFI_MEMORY_ASM
