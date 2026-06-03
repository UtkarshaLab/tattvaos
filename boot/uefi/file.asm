; =============================================================================
; Tattva OS — boot/uefi/file.asm
; =============================================================================
; UEFI file loading routines using SimpleFileSystem protocol.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_FILE_ASM
%define UEFI_FILE_ASM

%include "protocol.asm"

[BITS 64]

; SimpleFileSystem offsets
SFS_OPEN_VOLUME             equ 8       ; OpenVolume member pointer

; File Protocol offsets (accounting for 8-byte Revision prefix)
FILE_OPEN                   equ 8       ; Open member pointer
FILE_CLOSE                  equ 16      ; Close member pointer
FILE_READ                   equ 32      ; Read member pointer

; File Open modes
FILE_MODE_READ              equ 0x0000000000000001

; =============================================================================
; uefi_file_load — locate filesystem, open "kernel.ulf", and read it
; Input:  RCX = pointer to System Table
;         RDX = pointer to unicode UTF-16LE filename string
;         R8  = pointer to destination buffer
; Output: RAX = file size in bytes, or 0 if failed
; =============================================================================
uefi_file_load:
    push rbp
    mov rbp, rsp
    sub rsp, 80                     ; shadow space + local interfaces storage

    mov [rbp - 8], r8               ; save destination buffer
    mov [rbp - 16], rdx             ; save filename pointer

    ; Get BootServices: SystemTable->BootServices (offset 88)
    mov r9, [rcx + SYS_TABLE_BOOT_SERVICES]

    ; 1. Locate SimpleFileSystem protocol
    lea rcx, [sfs_guid]
    xor rdx, rdx
    lea r8, [rbp - 24]              ; &sfs_interface pointer
    mov rax, [r9 + BS_LOCATE_PROTOCOL]
    call rax
    test rax, rax
    jnz .failed_no_close

    ; 2. Open Root Volume
    mov rcx, [rbp - 24]             ; RCX = SFS interface
    lea rdx, [rbp - 32]             ; RDX = &root_handle
    mov rax, [rcx + SFS_OPEN_VOLUME]
    call rax
    test rax, rax
    jnz .failed_no_close

    ; 3. Open file
    mov rcx, [rbp - 32]             ; RCX = root_handle
    lea rdx, [rbp - 40]             ; RDX = &file_handle
    mov r8, [rbp - 16]              ; R8 = filename pointer
    mov r9, FILE_MODE_READ          ; R9 = OpenMode
    mov qword [rsp + 32], 0         ; 5th arg: Attributes (0 for read)
    mov rax, [rcx + FILE_OPEN]
    call rax
    test rax, rax
    jnz .failed_close_root

    ; 4. Read File directly into target buffer
    mov qword [rbp - 48], 1048576   ; limit size read to 1MB
    mov rcx, [rbp - 40]             ; RCX = file_handle
    lea rdx, [rbp - 48]             ; RDX = &read_size
    mov r8, [rbp - 8]               ; R8 = target destination buffer
    mov rax, [rcx + FILE_READ]
    call rax
    test rax, rax
    jnz .failed_close_all

    ; Success path: close both file and root handles
    mov rcx, [rbp - 40]             ; RCX = file_handle
    mov rax, [rcx + FILE_CLOSE]
    call rax

    mov rcx, [rbp - 32]             ; RCX = root_handle
    mov rax, [rcx + FILE_CLOSE]
    call rax

    mov rax, [rbp - 48]             ; return actual file size read in RAX
    jmp .done

.failed_close_all:
    mov rcx, [rbp - 40]             ; RCX = file_handle
    mov rax, [rcx + FILE_CLOSE]
    call rax

.failed_close_root:
    mov rcx, [rbp - 32]             ; RCX = root_handle
    mov rax, [rcx + FILE_CLOSE]
    call rax

.failed_no_close:
    xor rax, rax

.done:
    mov rsp, rbp
    pop rbp
    ret

%endif ; UEFI_FILE_ASM
