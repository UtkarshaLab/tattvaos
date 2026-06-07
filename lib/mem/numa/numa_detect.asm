; =============================================================================
; Tattva OS — lib/mem/numa/numa_detect.asm
; =============================================================================
; ACPI SRAT (Static Resource Affinity Table) parser.
; Maps physical memory range boundaries to Node IDs.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_NUMA_NUMA_DETECT_ASM
%define LIB_MEM_NUMA_NUMA_DETECT_ASM

[BITS 64]

section .text

; External symbols
extern boot_info_ptr
extern phys_state
extern numa_ranges
extern numa_range_count
extern uart_print_str
extern uart_print_hex64

; -----------------------------------------------------------------------------
; numa_detect_init — detects NUMA nodes and memory affinities via ACPI SRAT
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global numa_detect_init
numa_detect_init:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov rdi, [boot_info_ptr]
    test rdi, rdi
    jz .fallback

    ; 1. Load RSDP address from BootInfo (offset 24)
    mov rsi, [rdi + 24]
    test rsi, rsi
    jz .fallback

    ; Verify RSDP signature "RSD PTR "
    mov rbx, [rsi]
    mov rcx, 0x2052545020445352     ; "RSD PTR "
    cmp rbx, rcx
    jne .fallback

    ; 2. Determine revision
    movzx eax, byte [rsi + 15]      ; Revision
    cmp al, 2
    jl .use_rsdt                    ; ACPI 1.0 -> Use RSDT

    ; ACPI 2.0+ -> Use XSDT if non-zero
    mov rdi, [rsi + 24]             ; XsdtAddress
    test rdi, rdi
    jz .use_rsdt

    ; XSDT Table walking
    mov rbx, [rdi]                  ; Signature
    mov ecx, 0x54445358             ; "XSDT"
    cmp ebx, ecx
    jne .use_rsdt

    ; Parse XSDT
    mov r10d, [rdi + 4]             ; XSDT Length
    cmp r10d, 36
    jbe .fallback

    sub r10d, 36
    shr r10d, 3                     ; number of 64-bit pointers (Length - 36) / 8
    lea rbx, [rdi + 36]             ; first pointer
    xor rcx, rcx                    ; entry index

.xsdt_loop:
    cmp rcx, r10
    jae .fallback

    mov rsi, [rbx + rcx * 8]         ; 64-bit physical address of table
    test rsi, rsi
    jz .xsdt_next

    ; Check table signature
    mov eax, [rsi]
    cmp eax, 0x54415253             ; "SRAT" (little-endian representation of "SRAT" = 'S' 'R' 'A' 'T')
    je .found_srat

.xsdt_next:
    inc rcx
    jmp .xsdt_loop

.use_rsdt:
    ; RSDT Table walking
    mov rdi, [rsi + 16]             ; RsdtAddress (32-bit pointer)
    test rdi, rdi
    jz .fallback

    mov rbx, [rdi]                  ; Signature
    mov ecx, 0x54445352             ; "RSDT"
    cmp ebx, ecx
    jne .fallback

    ; Parse RSDT
    mov r10d, [rdi + 4]             ; RSDT Length
    cmp r10d, 36
    jbe .fallback

    sub r10d, 36
    shr r10d, 2                     ; number of 32-bit pointers (Length - 36) / 4
    lea rbx, [rdi + 36]             ; first pointer
    xor rcx, rcx

.rsdt_loop:
    cmp rcx, r10
    jae .fallback

    movzx rsi, dword [rbx + rcx * 4] ; 32-bit physical address of table
    test rsi, rsi
    jz .rsdt_next

    ; Check table signature
    mov eax, [rsi]
    cmp eax, 0x54415253             ; "SRAT"
    je .found_srat

.rsdt_next:
    inc rcx
    jmp .rsdt_loop

.found_srat:
    ; RSI points to the SRAT table!
    mov rdi, rsi
    mov r10d, [rdi + 4]             ; SRAT Length
    cmp r10d, 48
    jbe .fallback

    ; Iterate over static resource affinity structures
    ; Skip header (36 bytes) + reserved (12 bytes) = 48 bytes offset
    lea r11, [rdi + 48]             ; current entry pointer
    lea r12, [rdi + r10]            ; end of table

    xor r13, r13                    ; range index count = 0

.srat_entry_loop:
    cmp r11, r12
    jae .parsing_done

    movzx eax, byte [r11]           ; Type
    movzx ecx, byte [r11 + 1]       ; Length
    cmp ecx, 2
    jb .parsing_done                ; sanity check to prevent infinite loop

    cmp eax, 1                      ; Type 1 = Memory Affinity Structure
    jne .next_srat_entry

    cmp ecx, 40                     ; Memory affinity entry length must be 40
    jne .next_srat_entry

    ; Read flags
    mov edx, [r11 + 28]             ; Flags
    test dl, 1                      ; bit 0 = Enabled
    jz .next_srat_entry

    ; Read base address and length
    mov r8, [r11 + 8]               ; Base physical address (64-bit)
    mov r9, [r11 + 16]              ; Length in bytes (64-bit)
    test r9, r9
    jz .next_srat_entry             ; skip zero-length ranges

    ; Read Node ID (Proximity Domain)
    ; Proximity Domain is split: Domain[7:0] at offset 2, Domain[31:8] at offset 4 (3 bytes)
    movzx eax, byte [r11 + 2]       ; EAX = Proximity Domain [7:0]
    mov r14d, [r11 + 4]             ; R14D = Proximity Domain [31:8] + extra byte
    and r14d, 0x00FFFFFF            ; only keep lower 3 bytes
    shl r14d, 8                     ; shift to correct position (bits 31:8)
    or r14d, eax                    ; R14D = full 32-bit Proximity Domain

    ; Store range
    cmp r13, NUMA_MAX_RANGES
    jae .parsing_done               ; list full

    mov rax, r13
    imul rax, numa_range_t_size
    lea r15, [numa_ranges + rax]

    mov [r15 + numa_range_t.base], r8
    mov [r15 + numa_range_t.length], r9
    mov [r15 + numa_range_t.node_id], r14d
    mov [r15 + numa_range_t.flags], edx

    inc r13

.next_srat_entry:
    add r11, rcx                    ; advance entry pointer
    jmp .srat_entry_loop

.parsing_done:
    test r13, r13
    jz .fallback

    mov [numa_range_count], r13

    mov rsi, msg_numa_srat_ok
    call uart_print_str
    jmp .exit

.fallback:
    ; Fallback to single-range UMA (Node 0)
    mov rdx, [phys_state + phys_state_t.max_phys_addr]
    test rdx, rdx
    jnz .fallback_store
    mov rdx, 0x100000000            ; default to 4GB if max_phys_addr is 0

.fallback_store:
    lea r15, [numa_ranges]
    mov qword [r15 + numa_range_t.base], 0
    mov [r15 + numa_range_t.length], rdx
    mov dword [r15 + numa_range_t.node_id], 0
    mov dword [r15 + numa_range_t.flags], 1 ; Enabled

    mov qword [numa_range_count], 1

    mov rsi, msg_numa_fallback
    call uart_print_str

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Messages
; -----------------------------------------------------------------------------
section .data

msg_numa_srat_ok:   db "NUMA: ACPI SRAT table parsing successful.", 0x0D, 0x0A, 0
msg_numa_fallback:  db "NUMA: SRAT not found or invalid. Defaulting to UMA (Node 0).", 0x0D, 0x0A, 0

%endif ; LIB_MEM_NUMA_NUMA_DETECT_ASM
