; =============================================================================
; Tattva OS — boot/uefi/handoff.asm
; =============================================================================
; UEFI handoff to kernel. Shuts down boot services and jumps to kernel entry.
; Populates BootInfo structure at 0x7000.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_HANDOFF_ASM
%define UEFI_HANDOFF_ASM

%include "protocol.asm"

[BITS 64]

; =============================================================================
; uefi_handoff — ExitBootServices and jump to kernel
; Input:  RCX = pointer to System Table
;         RDX = ImageHandle
;         R8  = MapKey value from GetMemoryMap
;         R9  = kernel entry address (0x100000)
; Output: RAX = status code (only if ExitBootServices fails)
; =============================================================================
uefi_handoff:
    push rbp
    mov rbp, rsp
    sub rsp, 64                     ; shadow space + local storage (64 bytes, keeping stack 16-byte aligned)

    ; Save inputs
    mov [rbp - 8], rcx              ; System Table pointer
    mov [rbp - 16], rdx             ; ImageHandle
    mov [rbp - 24], r8              ; MapKey
    mov [rbp - 32], r9              ; Kernel Entry Address

    ; Preserve non-volatile registers in the stack frame
    mov [rbp - 48], rbx
    mov [rbp - 56], rsi
    mov [rbp - 64], rdi

    ; 1. Walk ConfigurationTable to find ACPI RSDP pointer
    mov rcx, [rbp - 8]              ; RCX = System Table
    mov rdx, [rcx + 104]            ; RDX = NumberOfTableEntries (offset 104)
    mov rsi, [rcx + 112]            ; RSI = ConfigurationTable pointer (offset 112)
    xor rdi, rdi                    ; RDI = found RSDP address (default 0)

.config_loop:
    test rdx, rdx
    jz .config_loop_end

    mov rax, [rsi]                  ; first 8 bytes of GUID
    mov r10, [rsi + 8]              ; next 8 bytes of GUID

    ; ACPI 2.0 check:
    mov r11, 0x11D3E4F18868E871
    cmp rax, r11
    jne .check_acpi10
    mov r11, 0x81883CC7800022BC
    cmp r10, r11
    je .found_acpi20

.check_acpi10:
    ; ACPI 1.0 check:
    mov r11, 0x11D32D88EB9D2D30
    cmp rax, r11
    jne .next_entry
    mov r11, 0x4DC13F279000169A
    cmp r10, r11
    je .found_acpi10

.next_entry:
    add rsi, 24                     ; next entry (24 bytes)
    dec rdx
    jmp .config_loop

.found_acpi10:
    mov rdi, [rsi + 16]             ; Store ACPI 1.0 RSDP
    jmp .next_entry

.found_acpi20:
    mov rdi, [rsi + 16]             ; Store ACPI 2.0 RSDP (preferred)
    ; We found ACPI 2.0, we can stop scanning
    jmp .config_loop_end

.config_loop_end:
    mov [rbp - 40], rdi             ; save found ACPI RSDP pointer

    ; 2. Zero out the 56-byte BootInfo structure at 0x7000
    cld                             ; Clear direction flag for rep stosq
    mov rdi, 0x7000
    mov rcx, 7                      ; 7 * 8 = 56 bytes
    xor rax, rax
    rep stosq

    ; 3. Populate BootInfo fields
    ; BOOT_INFO_E820_ADDR (0x7000) -> address of uefi_mem_map_buf
    lea rax, [uefi_mem_map_buf]
    mov [0x7000], rax

    ; BOOT_INFO_E820_COUNT (0x7008) -> count = uefi_map_size / uefi_desc_size
    xor rdx, rdx
    mov rax, [uefi_map_size]
    mov rcx, [uefi_desc_size]
    test rcx, rcx
    jz .skip_mem_count
    div rcx
    mov [0x7008], eax               ; store 32-bit count
.skip_mem_count:

    ; BOOT_INFO_DRIVE (0x700C) -> 0 (standard for UEFI)
    mov dword [0x700C], 0

    ; BOOT_INFO_FEATURES (0x7010) -> CPU features bitmask
    mov r9d, 1                      ; Bit 0: Long Mode is always supported in 64-bit UEFI
    
    ; Check SSE, SSE2, AVX
    mov eax, 1
    cpuid
    test edx, 1 << 25               ; SSE?
    jz .no_sse
    or r9d, 1 << 2
.no_sse:
    test edx, 1 << 26               ; SSE2?
    jz .no_sse2
    or r9d, 1 << 3
.no_sse2:
    test ecx, 1 << 28               ; AVX?
    jz .no_avx
    or r9d, 1 << 4
.no_avx:

    ; Check AVX2, AVX-512, AMX
    mov eax, 0
    cpuid
    cmp eax, 7
    jl .no_leaf7
    
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, 1 << 5                ; AVX2?
    jz .no_avx2
    or r9d, 1 << 5
.no_avx2:
    test ebx, 1 << 16               ; AVX-512F?
    jz .no_avx512
    or r9d, 1 << 6
.no_avx512:
    test edx, 1 << 24               ; AMX-TILE?
    jz .no_amx
    or r9d, 1 << 7
.no_amx:
.no_leaf7:

    ; Check NX bit
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jl .no_ext_features
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 20               ; NX/XD bit?
    jz .no_nx
    or r9d, 1 << 1
.no_nx:
.no_ext_features:
    mov [0x7010], r9d               ; store in cpu_features

    ; BOOT_INFO_ACPI_RSDP (0x7018) -> ACPI RSDP physical address
    mov rax, [rbp - 40]
    mov [0x7018], rax

    ; BOOT_INFO_FB_ADDR (0x7020) -> framebuffer base
    mov rax, [uefi_fb_base]
    mov [0x7020], rax

    ; BOOT_INFO_FB_WIDTH (0x7028) -> width
    mov eax, [uefi_fb_width]
    mov [0x7028], eax

    ; BOOT_INFO_FB_HEIGHT (0x702C) -> height
    mov eax, [uefi_fb_height]
    mov [0x702C], eax

    ; BOOT_INFO_FB_PITCH (0x7030) -> pitch
    mov eax, [uefi_fb_pitch]
    mov [0x7030], eax

    ; BOOT_INFO_FB_FORMAT (0x7034) -> BPP format
    mov eax, [uefi_fb_format]
    mov [0x7034], eax

    ; 4. Call ExitBootServices(ImageHandle, MapKey)
    mov rcx, [rbp - 8]              ; RCX = System Table
    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES] ; RAX = BootServices
    
    mov rcx, [rbp - 16]             ; RCX = ImageHandle
    mov rdx, [rbp - 24]             ; RDX = MapKey
    
    mov rax, [rax + BS_EXIT_BOOT_SERVICES]
    call rax                        ; execute ExitBootServices
    test rax, rax
    jnz .failed                     ; failed to exit boot services

    ; Disable interrupts (critical before jumping to kernel)
    cli

    ; Pass BootInfo pointer in RDI (System V ABI)
    mov rdi, 0x7000

    ; Jump directly to the kernel entry point
    mov rax, [rbp - 32]
    jmp rax

.failed:
    ; Restore non-volatile registers and return failure status in RAX
    mov rdi, [rbp - 64]
    mov rsi, [rbp - 56]
    mov rbx, [rbp - 48]
    mov rsp, rbp
    pop rbp
    ret

%endif ; UEFI_HANDOFF_ASM
