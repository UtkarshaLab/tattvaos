; =============================================================================
; Tattva OS — lib/mem/virt/acpi_hotplug.asm
; =============================================================================
; ACPI Memory Hot-Plug Interceptor & Dynamic NUMA Rebalancing.
; Traps SCI interrupts, parses FADT/FACP table for GPE/IRQ configurations,
; handles SCI event status, and updates NUMA ranges dynamically on memory insertion.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ACPI_HOTPLUG_ASM
%define LIB_MEM_VIRT_ACPI_HOTPLUG_ASM

[BITS 64]

; External symbols
extern boot_info_ptr
extern register_idt_handler
extern numa_ranges
extern numa_range_count
extern uart_print_str
extern uart_print_hex64
extern uart_print_dec

; Structure for ACPI memory device update (for namespace parsing)
struc acpi_mem_device_t
    .device_name        resb 8      ; Device name string (e.g., "MEM0")
    .phys_addr          resq 1      ; Base physical address
    .length             resq 1      ; Length of memory in bytes
    .proximity_domain   resd 1      ; Proximity domain / Node ID
    .flags              resd 1      ; Event flags (bit 0 = Enabled)
endstruc

section .text

; -----------------------------------------------------------------------------
; acpi_hotplug_init — Scan ACPI tables, register SCI handler, program IOAPIC
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global acpi_hotplug_init
acpi_hotplug_init:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r10
    push r11
    push r12

    mov rsi, msg_hotplug_init_start
    call uart_print_str

    ; 1. Walk ACPI to locate FADT (Fixed ACPI Description Table, signature "FACP")
    mov rdi, [boot_info_ptr]
    test rdi, rdi
    jz .use_defaults

    mov rsi, [rdi + 24]              ; load RSDP address from boot_info (offset 24)
    test rsi, rsi
    jz .use_defaults

    ; Verify RSDP signature "RSD PTR "
    mov rbx, [rsi]
    mov rcx, 0x2052545020445352      ; "RSD PTR "
    cmp rbx, rcx
    jne .use_defaults

    ; Determine revision to choose RSDT or XSDT
    movzx eax, byte [rsi + 15]       ; Revision byte
    cmp al, 2
    jl .use_rsdt                     ; ACPI 1.0 -> Use RSDT

    ; ACPI 2.0+ -> Use XSDT
    mov rdi, [rsi + 24]              ; XsdtAddress
    test rdi, rdi
    jz .use_rsdt

    ; Verify XSDT Signature "XSDT"
    mov ebx, [rdi]
    cmp ebx, 0x54445358              ; "XSDT"
    jne .use_rsdt

    ; Parse XSDT
    mov r10d, [rdi + 4]              ; XSDT Length
    cmp r10d, 36
    jbe .use_defaults
    sub r10d, 36
    shr r10d, 3                      ; Number of 64-bit pointers
    lea rbx, [rdi + 36]              ; First pointer offset
    xor rcx, rcx                     ; Index i = 0

.xsdt_loop:
    cmp rcx, r10
    jae .use_defaults
    mov rsi, [rbx + rcx * 8]         ; Load 64-bit table address
    test rsi, rsi
    jz .xsdt_next
    mov eax, [rsi]                   ; Load signature
    cmp eax, 0x50434146              ; "FACP" (FADT)
    je .found_fadt
.xsdt_next:
    inc rcx
    jmp .xsdt_loop

.use_rsdt:
    ; RSDT Table scanning
    mov rdi, [rsi + 16]              ; RsdtAddress (32-bit pointer)
    test rdi, rdi
    jz .use_defaults
    mov ebx, [rdi]
    cmp ebx, 0x54445352              ; "RSDT"
    jne .use_defaults

    ; Parse RSDT
    mov r10d, [rdi + 4]              ; RSDT Length
    cmp r10d, 36
    jbe .use_defaults
    sub r10d, 36
    shr r10d, 2                      ; Number of 32-bit pointers
    lea rbx, [rdi + 36]              ; First pointer offset
    xor rcx, rcx

.rsdt_loop:
    cmp rcx, r10
    jae .use_defaults
    movzx rsi, dword [rbx + rcx * 4]  ; Load 32-bit table address
    test rsi, rsi
    jz .rsdt_next
    mov eax, [rsi]                   ; Load signature
    cmp eax, 0x50434146              ; "FACP"
    je .found_fadt
.rsdt_next:
    inc rcx
    jmp .rsdt_loop

.found_fadt:
    ; 2. Parse FADT
    mov [acpi_fadt_addr], rsi
    mov rsi, msg_hotplug_fadt_found
    call uart_print_str
    
    mov rsi, [acpi_fadt_addr]
    ; Extract SCI_INT (offset 46, 2 bytes)
    movzx eax, word [rsi + 46]
    mov [acpi_sci_irq], al

    ; Extract GPE0_BLK (offset 80, 4 bytes)
    mov eax, [rsi + 80]
    mov [acpi_gpe0_blk], ax

    ; Extract GPE0_BLK_LEN (offset 92, 1 byte)
    mov al, [rsi + 92]
    mov [acpi_gpe0_blk_len], al

    ; Extract GPE1_BLK (offset 84, 4 bytes)
    mov eax, [rsi + 84]
    mov [acpi_gpe1_blk], ax

    ; Extract GPE1_BLK_LEN (offset 93, 1 byte)
    mov al, [rsi + 93]
    mov [acpi_gpe1_blk_len], al
    jmp .setup_interrupts

.use_defaults:
    mov rsi, msg_hotplug_defaults
    call uart_print_str

.setup_interrupts:
    ; Print SCI parameters
    mov rsi, msg_sci_irq_prefix
    call uart_print_str
    movzx rax, byte [acpi_sci_irq]
    call uart_print_dec
    mov rsi, msg_gpe0_prefix
    call uart_print_str
    movzx rax, word [acpi_gpe0_blk]
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 3. Hook SCI Interrupt Vector
    movzx ecx, byte [acpi_sci_irq]
    add ecx, 32                      ; IRQ map offset
    mov [acpi_sci_vector], cl

    movzx rdi, cl                    ; vector index
    mov rsi, acpi_sci_isr            ; ISR handler address
    xor rdx, rdx                     ; no IST stack
    call register_idt_handler

    ; 4. Program IOAPIC Redirection Table for SCI IRQ
    ; Standard IOAPIC Base physical address: 0xFEC00000
    mov rdi, 0xFEC00000
    movzx ecx, byte [acpi_sci_irq]
    shl ecx, 1
    add ecx, 0x10                    ; Redirection entry offset: 0x10 + 2 * IRQ

    ; Write low 32 bits
    mov eax, ecx
    mov [rdi], eax                   ; Select register
    movzx eax, byte [acpi_sci_vector]
    ; Set bit 13 (active low) and bit 15 (level trigger) for standard SCI
    or eax, 0x0000A000
    mov [rdi + 0x10], eax            ; Write redirection table entry (low)

    ; Write high 32 bits (destination APIC ID = 0)
    inc ecx
    mov eax, ecx
    mov [rdi], eax
    xor eax, eax
    mov [rdi + 0x10], eax            ; Write redirection table entry (high)

    ; 5. Enable GPE0 Memory Hot-Plug event (Event bit 3)
    ; Enable register is located at: GPE0_BLK + GPE0_BLK_LEN / 2
    movzx dx, word [acpi_gpe0_blk]
    test dx, dx
    jz .done
    movzx ax, byte [acpi_gpe0_blk_len]
    shr ax, 1                        ; divide by 2
    add dx, ax                       ; DX = GPE0 Enable register base
    
    in al, dx
    or al, 0x08                      ; Enable event bit 3 (hotplug)
    out dx, al

    mov rsi, msg_hotplug_gpe0_ok
    call uart_print_str

.done:
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
; acpi_sci_isr — Assembly Interrupt Service Routine for SCI
; -----------------------------------------------------------------------------
global acpi_sci_isr
acpi_sci_isr:
    ; Save all registers
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    ; Check if GPE0 memory hotplug event is set
    movzx dx, word [acpi_gpe0_blk]
    in al, dx
    
    ; Merge with simulated GPE status if any
    or al, [simulated_gpe_status_bit]
    
    test al, 0x08                    ; Check bit 3 (Memory Hotplug Event)
    jz .not_our_event

    ; Clear GPE status bit (write-1-to-clear)
    mov al, 0x08
    out dx, al
    
    ; Clear simulated status bit
    mov byte [simulated_gpe_status_bit], 0

    ; Dispatch event handling
    call acpi_handle_hotplug_event

.not_our_event:
    ; Send End-Of-Interrupt to LAPIC
    mov dword [0xFEE00000 + 0x0B0], 0

    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

; -----------------------------------------------------------------------------
; acpi_handle_hotplug_event — process discovered hotplug events
; -----------------------------------------------------------------------------
acpi_handle_hotplug_event:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; Increment event counter
    inc qword [hotplug_event_counter]

    mov rsi, msg_hotplug_event_rx
    call uart_print_str

    ; Parse ACPI updates
    call acpi_parse_namespace_update
    test rax, rax
    jz .no_device

    ; A memory device has been parsed successfully (device details in acpi_parsed_device)
    mov rsi, msg_hotplug_dev_found
    call uart_print_str

    ; Print device address and size
    mov rsi, msg_hotplug_addr_label
    call uart_print_str
    mov rax, [acpi_parsed_device + acpi_mem_device_t.phys_addr]
    call uart_print_hex64
    
    mov rsi, msg_hotplug_size_label
    call uart_print_str
    mov rax, [acpi_parsed_device + acpi_mem_device_t.length]
    call uart_print_hex64
    
    mov rsi, msg_hotplug_node_label
    call uart_print_str
    movzx rax, dword [acpi_parsed_device + acpi_mem_device_t.proximity_domain]
    call uart_print_dec
    mov rsi, msg_crlf
    call uart_print_str

    ; Save details for tracking
    mov rax, [acpi_parsed_device + acpi_mem_device_t.phys_addr]
    mov [last_hotplug_addr], rax
    mov rax, [acpi_parsed_device + acpi_mem_device_t.length]
    mov [last_hotplug_size], rax
    movzx eax, dword [acpi_parsed_device + acpi_mem_device_t.proximity_domain]
    mov [last_hotplug_node], eax

    ; Dynamic NUMA range update: Add to numa_ranges list
    mov rcx, [numa_range_count]
    cmp rcx, NUMA_MAX_RANGES
    jae .ranges_full

    ; Calculate dest offset in numa_ranges array
    mov rax, rcx
    imul rax, numa_range_t_size
    lea rdi, [numa_ranges + rax]

    ; Populate entry
    mov rax, [acpi_parsed_device + acpi_mem_device_t.phys_addr]
    mov [rdi + numa_range_t.base], rax
    mov rax, [acpi_parsed_device + acpi_mem_device_t.length]
    mov [rdi + numa_range_t.length], rax
    mov eax, dword [acpi_parsed_device + acpi_mem_device_t.proximity_domain]
    mov [rdi + numa_range_t.node_id], eax
    mov dword [rdi + numa_range_t.flags], 1   ; Enabled = 1

    ; Increment count
    inc qword [numa_range_count]

    mov rsi, msg_hotplug_numa_ok
    call uart_print_str
    jmp .done

.ranges_full:
    mov rsi, msg_hotplug_err_full
    call uart_print_str
    jmp .done

.no_device:
    mov rsi, msg_hotplug_no_dev
    call uart_print_str

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_parse_namespace_update — simulated/mock namespace parser
; Output: RAX = 1 on success, 0 if no update found
; -----------------------------------------------------------------------------
acpi_parse_namespace_update:
    ; Check if simulated update block is valid
    mov rax, [simulated_acpi_update_valid]
    test rax, rax
    jz .no_update

    ; Copy simulated values into parsed device block
    mov rax, [simulated_acpi_update_phys]
    mov [acpi_parsed_device + acpi_mem_device_t.phys_addr], rax

    mov rax, [simulated_acpi_update_size]
    mov [acpi_parsed_device + acpi_mem_device_t.length], rax

    mov eax, [simulated_acpi_update_node]
    mov [acpi_parsed_device + acpi_mem_device_t.proximity_domain], eax

    ; Store device name
    mov qword [acpi_parsed_device + acpi_mem_device_t.device_name], 0x00304D454D5F5F   ; "__MEM0\0"
    mov dword [acpi_parsed_device + acpi_mem_device_t.flags], 1

    ; Reset simulated valid flag
    mov qword [simulated_acpi_update_valid], 0

    mov rax, 1
    ret

.no_update:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; acpi_simulate_hotplug_trigger — Trigger mock hot-plug interrupt via Self-IPI
; Input:
;   RDI = physical base address of memory
;   RSI = size of memory region
;   RDX = proximity domain / NUMA Node ID
; Output: none
; -----------------------------------------------------------------------------
global acpi_simulate_hotplug_trigger
acpi_simulate_hotplug_trigger:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi

    ; Print simulation trigger message
    mov [simulated_acpi_update_phys], rdi
    mov [simulated_acpi_update_size], rsi
    mov [simulated_acpi_update_node], edx
    mov qword [simulated_acpi_update_valid], 1
    mov byte [simulated_gpe_status_bit], 0x08  ; simulated GPE bit 3

    mov rsi, msg_hotplug_sim_trigger
    call uart_print_str

    ; Send Self-IPI to trigger the SCI vector
    ; Local APIC ICR register at 0xFEE00000 + 0x300
    ; 0x00040000 (Shorthand = Self) | vector
    mov eax, 0x00040000
    movzx ecx, byte [acpi_sci_vector]
    or eax, ecx
    mov dword [0xFEE00000 + 0x300], eax

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; -----------------------------------------------------------------------------
; Data Section
; -----------------------------------------------------------------------------
section .data

align 8
global acpi_fadt_addr
global acpi_sci_irq
global acpi_sci_vector
global acpi_gpe0_blk
global acpi_gpe0_blk_len
global acpi_gpe1_blk
global acpi_gpe1_blk_len
global hotplug_event_counter
global last_hotplug_addr
global last_hotplug_size
global last_hotplug_node

acpi_fadt_addr:         dq 0
acpi_sci_irq:           db 9            ; Default SCI IRQ 9
acpi_sci_vector:        db 0
acpi_gpe0_blk:          dw 0x0400       ; Default GPE0 I/O port address
acpi_gpe0_blk_len:      db 4
acpi_gpe1_blk:          dw 0
acpi_gpe1_blk_len:      db 0

hotplug_event_counter:  dq 0
last_hotplug_addr:      dq 0
last_hotplug_size:      dq 0
last_hotplug_node:      dd 0

; Simulation block
global simulated_acpi_update_valid
global simulated_acpi_update_phys
global simulated_acpi_update_size
global simulated_acpi_update_node
simulated_acpi_update_valid: dq 0
simulated_acpi_update_phys:  dq 0
simulated_acpi_update_size:  dq 0
simulated_acpi_update_node:  dd 0
simulated_gpe_status_bit:    db 0

; Parsed device buffer
align 8
acpi_parsed_device:     times acpi_mem_device_t_size db 0

; Messages
msg_hotplug_init_start: db "ACPI: Initializing Memory Hot-Plug Interceptor...", 0x0D, 0x0A, 0
msg_hotplug_fadt_found: db "ACPI: Successfully located FADT (FACP) table.", 0x0D, 0x0A, 0
msg_hotplug_defaults:   db "ACPI: FADT not found. Initializing with fallback defaults.", 0x0D, 0x0A, 0
msg_sci_irq_prefix:     db "ACPI: Configured SCI IRQ = ", 0
msg_gpe0_prefix:        db ", GPE0_BLK = ", 0
msg_hotplug_gpe0_ok:    db "ACPI: GPE0 Memory Hot-Plug event interrupt enabled.", 0x0D, 0x0A, 0

msg_hotplug_sim_trigger:db "ACPI: Simulating hardware memory hot-plug event trigger...", 0x0D, 0x0A, 0
msg_hotplug_event_rx:   db "ACPI SCI: Intercepted hot-plug interrupt event.", 0x0D, 0x0A, 0
msg_hotplug_dev_found:  db "ACPI SCI: Namespace update found memory device.", 0x0D, 0x0A, 0
msg_hotplug_addr_label: db "  Base physical address: ", 0
msg_hotplug_size_label: db "  Region size in bytes:  ", 0
msg_hotplug_node_label: db "  Proximity Node ID:     ", 0
msg_hotplug_numa_ok:    db "ACPI SCI: Dynamic NUMA memory range registered successfully.", 0x0D, 0x0A, 0
msg_hotplug_err_full:   db "ACPI SCI: Error - NUMA range array is full, cannot add range.", 0x0D, 0x0A, 0
msg_hotplug_no_dev:     db "ACPI SCI: Warning - SCI triggered but no namespace update block found.", 0x0D, 0x0A, 0

msg_crlf:               db 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_ACPI_HOTPLUG_ASM
