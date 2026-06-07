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

    ; Initialize table address holders to 0
    xor r14, r14                    ; R14 = SRAT physical address
    xor r15, r15                    ; R15 = SLIT physical address

    mov rdi, [boot_info_ptr]
    test rdi, rdi
    jz .parse_tables

    ; 1. Load RSDP address from BootInfo (offset 24)
    mov rsi, [rdi + 24]
    test rsi, rsi
    jz .parse_tables

    ; Verify RSDP signature "RSD PTR "
    mov rbx, [rsi]
    mov rcx, 0x2052545020445352     ; "RSD PTR "
    cmp rbx, rcx
    jne .parse_tables

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
    jbe .parse_tables

    sub r10d, 36
    shr r10d, 3                     ; number of 64-bit pointers
    lea rbx, [rdi + 36]             ; first pointer
    xor rcx, rcx                    ; entry index

.xsdt_loop:
    cmp rcx, r10
    jae .parse_tables

    mov rsi, [rbx + rcx * 8]         ; 64-bit physical address of table
    test rsi, rsi
    jz .xsdt_next

    ; Check table signature
    mov eax, [rsi]
    cmp eax, 0x54415253             ; "SRAT"
    jne .xsdt_check_slit
    mov r14, rsi
    jmp .xsdt_next
.xsdt_check_slit:
    cmp eax, 0x54494C53             ; "SLIT"
    jne .xsdt_next
    mov r15, rsi

.xsdt_next:
    inc rcx
    jmp .xsdt_loop

.use_rsdt:
    ; RSDT Table walking
    mov rdi, [rsi + 16]             ; RsdtAddress (32-bit pointer)
    test rdi, rdi
    jz .parse_tables

    mov rbx, [rdi]                  ; Signature
    mov ecx, 0x54445352             ; "RSDT"
    cmp ebx, ecx
    jne .parse_tables

    ; Parse RSDT
    mov r10d, [rdi + 4]             ; RSDT Length
    cmp r10d, 36
    jbe .parse_tables

    sub r10d, 36
    shr r10d, 2                     ; number of 32-bit pointers
    lea rbx, [rdi + 36]             ; first pointer
    xor rcx, rcx

.rsdt_loop:
    cmp rcx, r10
    jae .parse_tables

    movzx rsi, dword [rbx + rcx * 4] ; 32-bit physical address of table
    test rsi, rsi
    jz .rsdt_next

    ; Check table signature
    mov eax, [rsi]
    cmp eax, 0x54415253             ; "SRAT"
    jne .rsdt_check_slit
    mov r14, rsi
    jmp .rsdt_next
.rsdt_check_slit:
    cmp eax, 0x54494C53             ; "SLIT"
    jne .rsdt_next
    mov r15, rsi

.rsdt_next:
    inc rcx
    jmp .rsdt_loop

.parse_tables:
    ; =========================================================================
    ; 1. Parse SRAT
    ; =========================================================================
    test r14, r14
    jz .srat_fallback

    mov rdi, r14
    mov r10d, [rdi + 4]             ; SRAT Length
    cmp r10d, 48
    jbe .srat_fallback

    lea r11, [rdi + 48]             ; current entry pointer
    lea r12, [rdi + r10]            ; end of table
    xor r13, r13                    ; range index count = 0

.srat_entry_loop:
    cmp r11, r12
    jae .srat_done

    movzx eax, byte [r11]           ; Type
    movzx ecx, byte [r11 + 1]       ; Length
    cmp ecx, 2
    jb .srat_done                   ; sanity check

    cmp eax, 1                      ; Type 1 = Memory Affinity
    jne .next_srat_entry
    cmp ecx, 40
    jne .next_srat_entry

    mov edx, [r11 + 28]             ; Flags
    test dl, 1                      ; Enabled
    jz .next_srat_entry

    mov r8, [r11 + 8]               ; Base address
    mov r9, [r11 + 16]              ; Length
    test r9, r9
    jz .next_srat_entry

    ; Read split Proximity Domain (Node ID)
    movzx eax, byte [r11 + 2]
    mov r14d, [r11 + 4]
    and r14d, 0x00FFFFFF
    shl r14d, 8
    or r14d, eax                    ; full 32-bit Node ID

    ; Store range
    cmp r13, NUMA_MAX_RANGES
    jae .srat_done

    mov rax, r13
    imul rax, numa_range_t_size
    lea r15, [numa_ranges + rax]

    mov [r15 + numa_range_t.base], r8
    mov [r15 + numa_range_t.length], r9
    mov [r15 + numa_range_t.node_id], r14d
    mov [r15 + numa_range_t.flags], edx
    inc r13

.next_srat_entry:
    add r11, rcx
    jmp .srat_entry_loop

.srat_done:
    test r13, r13
    jz .srat_fallback
    mov [numa_range_count], r13
    mov rsi, msg_numa_srat_ok
    call uart_print_str
    jmp .parse_slit

.srat_fallback:
    mov rdx, [phys_state + phys_state_t.max_phys_addr]
    test rdx, rdx
    jnz .srat_fallback_store
    mov rdx, 0x100000000            ; default 4GB

.srat_fallback_store:
    lea r15, [numa_ranges]
    mov qword [r15 + numa_range_t.base], 0
    mov [r15 + numa_range_t.length], rdx
    mov dword [r15 + numa_range_t.node_id], 0
    mov dword [r15 + numa_range_t.flags], 1

    mov qword [numa_range_count], 1
    mov rsi, msg_numa_srat_fallback
    call uart_print_str

.parse_slit:
    ; =========================================================================
    ; 2. Parse SLIT
    ; =========================================================================
    test r15, r15
    jz .slit_fallback

    mov rdi, r15
    mov r10d, [rdi + 4]             ; SLIT Length
    cmp r10d, 44
    jbe .slit_fallback

    ; Read Number of System Localities (64-bit at offset 36)
    mov r10, [rdi + 36]
    test r10, r10
    jz .slit_fallback

    mov r9, r10
    cmp r9, NUMA_MAX_NODES
    jbe .count_ok
    mov r9, NUMA_MAX_NODES
.count_ok:
    mov [numa_node_count], r9

    ; Copy submatrix row by row
    xor rcx, rcx                    ; row index i = 0
.row_loop:
    cmp rcx, r9
    jae .slit_done

    ; Calculate source row address: rdi + 44 + rcx * r10
    mov rax, rcx
    imul rax, r10
    lea rsi, [rdi + 44 + rax]

    ; Calculate dest row address: numa_distance_matrix + rcx * r9
    mov rax, rcx
    imul rax, r9
    lea rdx, [numa_distance_matrix + rax]

    ; Copy r9 bytes
    xor r8, r8                      ; col index j = 0
.col_loop:
    cmp r8, r9
    jae .next_row
    mov al, [rsi + r8]
    mov [rdx + r8], al
    inc r8
    jmp .col_loop

.next_row:
    inc rcx
    jmp .row_loop

.slit_done:
    mov rsi, msg_numa_slit_ok
    call uart_print_str
    jmp .exit

.slit_fallback:
    ; Fallback: 1 node (UMA), distance 10
    mov qword [numa_node_count], 1
    mov byte [numa_distance_matrix], 10

    ; Fill remaining 63 bytes with 255
    lea rdi, [numa_distance_matrix + 1]
    mov rcx, 63
    mov al, 255
    cld
    rep stosb

    mov rsi, msg_numa_slit_fallback
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

msg_numa_srat_ok:       db "NUMA: ACPI SRAT table parsing successful.", 0x0D, 0x0A, 0
msg_numa_srat_fallback: db "NUMA: SRAT not found or invalid. Defaulting to UMA (Node 0).", 0x0D, 0x0A, 0
msg_numa_slit_ok:       db "NUMA: ACPI SLIT table parsing successful.", 0x0D, 0x0A, 0
msg_numa_slit_fallback: db "NUMA: SLIT not found or invalid. Defaulting to UMA distances.", 0x0D, 0x0A, 0

%endif ; LIB_MEM_NUMA_NUMA_DETECT_ASM
