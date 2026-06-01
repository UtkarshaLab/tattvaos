; boot/stage2/cpu/longmode_sequence.asm
; Exact ordered steps for entering 64-bit long mode
;
; MUST follow this exact order — any other order = triple fault:
;   1. Set PAE bit in CR4 (bit 5)
;   2. Load PML4 address into CR3
;   3. Set LME bit in EFER MSR 0xC0000080
;   4. Enable paging + protected mode in CR0 together (bits 31 + 0)
;   5. Far jump to 64-bit code segment

longmode_sequence:
    ; Step 1: Enable PAE in CR4
    ; TODO: mov eax, cr4 / or eax, (1 << 5) / mov cr4, eax

    ; Step 2: Load PML4 into CR3
    ; TODO: mov eax, PML4_ADDR / mov cr3, eax

    ; Step 3: Set EFER.LME
    ; TODO: mov ecx, 0xC0000080 / rdmsr / or eax, (1 << 8) / wrmsr

    ; Step 4: Enable paging + PM in CR0 atomically
    ; TODO: mov eax, cr0 / or eax, (1 << 31) | 1 / mov cr0, eax

    ; Step 5: Far jump to 64-bit code segment
    ; TODO: jmp SEL_CODE64:long_mode_entry

    ret
