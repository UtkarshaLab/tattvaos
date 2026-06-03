; =============================================================================
; Tattva OS — kernel/arch/x86_64/cpu.asm
; =============================================================================
; CPU feature verification, hardware initialization, memory cache activation,
; processor security policies, thread-local base, and SIMD/FPU setup (25 Steps).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef KERNEL_ARCH_X86_64_CPU_ASM
%define KERNEL_ARCH_X86_64_CPU_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; cpu_init_hardware — perform complete 25-step CPU & platform initialization
; Input:  none (expects boot_info_ptr to be populated)
; Output: none (halts on critical errors)
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
cpu_init_hardware:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9

    ; 1. Disable legacy Intel 8259 PIC (Mask all lines)
    mov al, 0xFF
    out 0x21, al                    ; Mask master PIC
    out 0xA1, al                    ; Mask slave PIC

    ; 2. Enable L1/L2/L3 Write-Back CPU Caching (Clear CD and NW in CR0)
    mov rax, cr0
    and rax, ~((1 << 30) | (1 << 29)) ; clear CD (bit 30) & NW (bit 29)
    mov cr0, rax

    ; 3. Disable Alignment Check Exceptions (Clear CR0.AM and RFLAGS.AC)
    mov rax, cr0
    and rax, ~(1 << 18)             ; clear AM (bit 18)
    mov cr0, rax
    pushfq
    pop rax
    and rax, ~(1 << 17)             ; clear AC (bit 17) flag
    push rax
    popfq

    ; 4. Disable early NMIs (Non-Maskable Interrupts)
    in al, 0x70
    or al, 0x80                     ; set bit 7 (disable NMI)
    out 0x70, al

    ; 5. Silence PC Speaker (Turn off timer gate and data speaker)
    in al, 0x61
    and al, 0xFC                    ; clear bits 0 and 1
    out 0x61, al

    ; 6. Enable Write Protection for Read-Only Pages (Set CR0.WP)
    mov rax, cr0
    or rax, 1 << 16                 ; set WP (bit 16)
    mov cr0, rax

    ; 7. Enable Page Global Cache Sharing (Set CR4.PGE)
    mov rax, cr4
    or rax, 1 << 7                  ; set PGE (bit 7)
    mov cr4, rax

    ; 8. Enable SMEP and SMAP (Supervisor Execution/Access Prevention) if supported
    mov eax, 7
    xor ecx, ecx
    cpuid                           ; EBX contains features
    test ebx, 1 << 7                ; Check SMEP support
    jz .no_smep
    mov rax, cr4
    or rax, 1 << 20                 ; set SMEP (bit 20)
    mov cr4, rax
    jmp .check_smap
.no_smep:
    mov rsi, msg_warn_smep
    call uart_print_str
.check_smap:
    test ebx, 1 << 20               ; Check SMAP support
    jz .no_smap
    mov rax, cr4
    or rax, 1 << 21                 ; set SMAP (bit 21)
    mov cr4, rax
    jmp .smap_done
.no_smap:
    mov rsi, msg_warn_smap
    call uart_print_str
.smap_done:

    ; 9. Configure User-Space TSC Access (Clear CR4.TSD for direct RDTSC)
    mov rax, cr4
    and rax, ~(1 << 2)              ; clear TSD (bit 2)
    mov cr4, rax

    ; 10. Enable User-Space FSGSBASE instructions if supported
    test ebx, 1 << 0                ; Check FSGSBASE support (EBX bit 0)
    jz .no_fsgsbase
    mov rax, cr4
    or rax, 1 << 16                 ; set FSGSBASE (bit 16)
    mov cr4, rax
    jmp .fsgsbase_done
.no_fsgsbase:
    mov rsi, msg_warn_fsgsbase
    call uart_print_str
.fsgsbase_done:

    ; 10b. Enable Process Context Identifiers (CR4.PCIDE) if supported
    mov eax, 1
    cpuid
    test ecx, 1 << 17               ; Check PCID support (ECX bit 17)
    jz .no_pcid
    mov rax, cr4
    or rax, 1 << 17                 ; set PCIDE (bit 17)
    mov cr4, rax
    mov rsi, msg_init_pcid
    call uart_print_str
    jmp .pcid_done
.no_pcid:
    mov rsi, msg_warn_pcid
    call uart_print_str
.pcid_done:

    ; 11. Enable SSE/AVX Coprocessor Execution
    mov rax, cr0
    or rax, 1 << 1                  ; set MP (bit 1)
    and rax, ~(1 << 2)              ; clear EM (bit 2)
    mov cr0, rax
    mov rax, cr4
    or rax, (1 << 9) | (1 << 10)    ; set OSFXSR (bit 9) and OSXMMEXCPT (bit 10)
    mov cr4, rax

    ; 12. Initialize User Thread-Local Base (MSR_FS_BASE) to 0
    mov ecx, 0xC0000100             ; MSR_FS_BASE
    xor eax, eax
    xor rdx, rdx
    wrmsr

    ; 13. Initialize Kernel GS Base MSR (MSR_KERNEL_GS_BASE) to 0
    mov ecx, 0xC0000102             ; MSR_KERNEL_GS_BASE
    wrmsr

    ; 14. Enable EFER.NXE (No-Execute) if supported
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 20               ; Check NX support (EDX bit 20)
    jz .no_nx
    mov ecx, 0xC0000080             ; EFER MSR
    rdmsr
    or eax, 1 << 11                 ; set NXE (bit 11)
    wrmsr
    jmp .nx_done
.no_nx:
    mov rsi, msg_warn_nx
    call uart_print_str
.nx_done:

    ; 15. Configure System Call MSRs (STAR, LSTAR, SFMASK)
    mov ecx, 0xC0000081             ; STAR
    xor eax, eax
    mov edx, 0x00130008             ; User base selector=0x10 (RPL=3 -> 0x13), Kernel CS=0x08
    wrmsr
    
    mov ecx, 0xC0000082             ; LSTAR (64-bit Entry address)
    mov rax, sys_handler
    mov rdx, rax
    shr rdx, 32                     ; EDX:EAX = sys_handler
    wrmsr
    
    mov ecx, 0xC0000084             ; SFMASK
    mov eax, 0x00000200             ; mask IF flag (disable interrupts on syscall)
    xor rdx, rdx
    wrmsr

    ; 16. Initialize Page Attribute Table (PAT MSR 0x277)
    mov ecx, 0x277
    mov eax, 0x00070406             ; PAT3=UC, PAT2=UC-, PAT1=WT, PAT0=WB
    mov edx, 0x00070105             ; PAT7=UC, PAT6=UC-, PAT5=WP, PAT4=WC
    wrmsr

    ; 17. Configure Machine Check Architecture (MCA) (CR4.MCE & Bank Control)
    mov rax, cr4
    or rax, 1 << 6                  ; set MCE (bit 6)
    mov cr4, rax
    
    mov ecx, 0x179                  ; IA32_MCG_CAP
    rdmsr
    and eax, 0xFF                   ; EAX = count of hardware error banks
    mov r8d, eax
    xor r9d, r9d
.mca_loop:
    cmp r9d, r8d
    jge .mca_done
    mov ecx, 0x400                  ; MC0_CTL (control register bank base)
    mov eax, r9d
    shl eax, 2                      ; bank * 4
    add ecx, eax                    ; ECX = 0x400 + bank * 4
    mov eax, 0xFFFFFFFF
    mov edx, 0xFFFFFFFF             ; write 1s to enable all logs
    wrmsr
    inc r9d
    jmp .mca_loop
.mca_done:

    ; 18. Verify Memory Type Range Registers (MTRRs)
    mov ecx, 0x2FF                  ; IA32_MTRR_DEF_TYPE
    rdmsr
    test eax, 1 << 11               ; Check if MTRRs are enabled (E bit 11)
    jnz .mtrr_ok
    mov rsi, msg_warn_mtrr
    call uart_print_str
.mtrr_ok:

    ; 19. Verify and Enable Local APIC (MSR_IA32_APIC_BASE)
    mov ecx, 0x1B
    rdmsr
    or eax, 1 << 11                 ; set APIC Global Enable
    wrmsr

    ; 20. Reset TSC-deadline timer target if supported
    mov eax, 1
    cpuid
    test ecx, 1 << 24               ; Check TSC-Deadline support (ECX bit 24)
    jz .no_tsc_deadline
    mov ecx, 0x6E0                  ; IA32_TSC_DEADLINE
    xor eax, eax
    xor rdx, rdx
    wrmsr
.no_tsc_deadline:

    ; 21. Configure Spectre branch mitigation (SPEC_CTRL) if supported
    mov eax, 7
    xor ecx, ecx
    cpuid
    test edx, 1 << 26               ; Check SPEC_CTRL support (EDX bit 26)
    jz .no_spec_ctrl
    mov ecx, 0x48                   ; IA32_SPEC_CTRL
    mov eax, 3                      ; set IBRS (bit 0) and STIBP (bit 1)
    xor rdx, rdx
    wrmsr
.no_spec_ctrl:

    ; 22. Verify ACPI RSDP Pointer Integrity
    mov rdi, [boot_info_ptr]
    test rdi, rdi
    jz .acpi_done
    mov rsi, [rdi + 24]             ; physical RSDP address from BootInfo
    test rsi, rsi
    jz .acpi_done
    
    ; Verify Signature
    mov rbx, [rsi]
    mov rcx, 0x2052545020445352     ; "RSD PTR "
    cmp rbx, rcx
    jne .acpi_bad
    
    ; Validate 20-byte base structure checksum
    xor rbx, rbx                    ; sum accumulator
    xor rcx, rcx                    ; offset
.acpi_chk_loop:
    cmp rcx, 20
    jge .acpi_chk_done
    movzx rdx, byte [rsi + rcx]
    add rbx, rdx
    inc rcx
    jmp .acpi_chk_loop
.acpi_chk_done:
    and rbx, 0xFF
    jnz .acpi_bad

    ; Check Revision
    movzx eax, byte [rsi + 15]
    cmp al, 2
    jl .acpi_done                   ; skip extended checksum for ACPI 1.0

    ; Validate 36-byte extended checksum (ACPI 2.0+)
    xor rbx, rbx
    xor rcx, rcx
.acpi_ext_loop:
    cmp rcx, 36
    jge .acpi_ext_done
    movzx rdx, byte [rsi + rcx]
    add rbx, rdx
    inc rcx
    jmp .acpi_ext_loop
.acpi_ext_done:
    and rbx, 0xFF
    jnz .acpi_bad
    jmp .acpi_done
.acpi_bad:
    mov rsi, msg_err_acpi
    call uart_print_str
    cli
.halt_acpi:
    hlt
    jmp .halt_acpi
.acpi_done:

    ; 23. Verify mandatory math instruction support (SSE3, AVX, AVX2, FMA3)
    call cpu_verify_features

    ; 24. Initialize FPU state
    fninit

    ; 25. Initialize SIMD floating-point state with optimized MXCSR settings
    ldmxcsr [default_mxcsr]

    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; cpu_verify_features — check for mandatory vector instruction sets
; Input:  none
; Output: none (halts on failure)
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
cpu_verify_features:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    ; Query CPUID Leaf 1 (Feature Information)
    mov eax, 1
    cpuid                           ; clobbers EAX, EBX, ECX, EDX

    ; Check SSE3: ECX bit 0
    test ecx, 1 << 0
    jz .err_sse3

    ; Check FMA3: ECX bit 12
    test ecx, 1 << 12
    jz .err_fma

    ; Check AVX: ECX bit 28
    test ecx, 1 << 28
    jz .err_avx

    ; Query CPUID Leaf 7, Sub-leaf 0 (Extended Features)
    mov eax, 7
    xor ecx, ecx
    cpuid                           ; clobbers EAX, EBX, ECX, EDX

    ; Check AVX2: EBX bit 5
    test ebx, 1 << 5
    jz .err_avx2

    ; If all checks pass, print confirmation and return
    mov rsi, msg_cpu_ok
    call uart_print_str

    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

.err_sse3:
    mov rsi, msg_err_sse3
    jmp .panic
.err_fma:
    mov rsi, msg_err_fma
    jmp .panic
.err_avx:
    mov rsi, msg_err_avx
    jmp .panic
.err_avx2:
    mov rsi, msg_err_avx2
    jmp .panic

.panic:
    call uart_print_str
    cli
.halt:
    hlt
    jmp .halt

; -----------------------------------------------------------------------------
; cpu_clear_gprs — zero out general purpose registers (except RSP/RDI)
; Input:  none
; Output: none
; Rationale: Called in start.asm to sanitize early register contexts.
; -----------------------------------------------------------------------------
cpu_clear_gprs:
    xor rax, rax
    xor rbx, rbx
    xor rcx, rcx
    xor rdx, rdx
    xor rsi, rsi
    xor rbp, rbp
    xor r8,  r8
    xor r9,  r9
    xor r10, r10
    xor r11, r11
    xor r12, r12
    xor r13, r13
    xor r14, r14
    xor r15, r15
    ret

; -----------------------------------------------------------------------------
; cpu_get_local — get the base address of the current CPU-local structure
; Input:  none
; Output: RAX = pointer to CPU-local structure
; Clobbers: none (preserves all other registers)
; -----------------------------------------------------------------------------
cpu_get_local:
    mov rax, [gs:0]                 ; offset 0 is .self pointer
    ret

; -----------------------------------------------------------------------------
; cpu_get_id — get the CPU ID of the running processor
; Input:  none
; Output: EAX = CPU ID
; Clobbers: none
; -----------------------------------------------------------------------------
cpu_get_id:
    mov eax, [gs:8]                 ; offset 8 is .cpu_id
    ret

; -----------------------------------------------------------------------------
; cpu_get_stack_top — get the kernel stack top of the running processor
; Input:  none
; Output: RAX = stack top address
; Clobbers: none
; -----------------------------------------------------------------------------
cpu_get_stack_top:
    mov rax, [gs:16]                ; offset 16 is .stack_top
    ret

; -----------------------------------------------------------------------------
; Data & Warn Messages
; -----------------------------------------------------------------------------
section .data

align 8
default_mxcsr:      dd 0x9FC0       ; FTZ=1, DAZ=1, masks exceptions, round-to-nearest

msg_cpu_ok:         db "CPU features verified (SSE3, AVX, AVX2, FMA).", 0x0D, 0x0A, 0
msg_warn_smep:      db "[WARN] CPU does not support SMEP (Supervisor Mode Execution Prevention)", 0x0D, 0x0A, 0
msg_warn_smap:      db "[WARN] CPU does not support SMAP (Supervisor Mode Access Prevention)", 0x0D, 0x0A, 0
msg_warn_fsgsbase:  db "[WARN] CPU does not support FSGSBASE instructions", 0x0D, 0x0A, 0
msg_init_pcid:      db "Process Context Identifiers (PCID) enabled.", 0x0D, 0x0A, 0
msg_warn_pcid:      db "[WARN] CPU does not support PCID (Process Context Identifiers)", 0x0D, 0x0A, 0
msg_warn_nx:        db "[WARN] CPU does not support NX (No-Execute) protection", 0x0D, 0x0A, 0
msg_warn_mtrr:      db "[WARN] MTRRs are disabled or not supported", 0x0D, 0x0A, 0
msg_err_acpi:       db "!!! KERNEL PANIC: ACPI RSDP pointer checksum verification failed !!!", 0x0D, 0x0A, 0
msg_err_sse3:       db "!!! KERNEL PANIC: Missing CPU feature: SSE3 required !!!", 0x0D, 0x0A, 0
msg_err_fma:        db "!!! KERNEL PANIC: Missing CPU feature: FMA3 required !!!", 0x0D, 0x0A, 0
msg_err_avx:        db "!!! KERNEL PANIC: Missing CPU feature: AVX required !!!", 0x0D, 0x0A, 0
msg_err_avx2:       db "!!! KERNEL PANIC: Missing CPU feature: AVX2 required !!!", 0x0D, 0x0A, 0

%endif ; KERNEL_ARCH_X86_64_CPU_ASM
