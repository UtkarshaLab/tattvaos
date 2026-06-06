; =============================================================================
; Tattva OS — lib/hw/ucpu/mtrr.asm
; =============================================================================
; Memory Type Range Registers (MTRR) cache controls (Subfeature 8.1).
; Configures caching properties (UC, WC, WT, WP, WB) for physical memory ranges.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UCPU_MTRR_ASM
%define LIB_HW_UCPU_MTRR_ASM

[BITS 64]

; MTRR MSR Addresses
IA32_MTRRCAP          equ 0x0FE
IA32_MTRR_DEF_TYPE    equ 0x2FF

IA32_MTRR_PHYSBASE0   equ 0x200
IA32_MTRR_PHYSMASK0   equ 0x201

section .text

; External UART printer if needed (declared as extern in entry point)
extern uart_print_str

; -----------------------------------------------------------------------------
; mtrr_supported — checks standard MTRR capability via CPUID
; Output:
;   RAX = 1 if supported, 0 otherwise
; Clobbers: RAX, RBX, RCX, RDX
; -----------------------------------------------------------------------------
global mtrr_supported
mtrr_supported:
    mov eax, 1
    cpuid                           ; clobbers EAX, EBX, ECX, EDX
    test edx, 1 << 12               ; EDX bit 12: MTRR support
    jz .no_support
    mov rax, 1
    ret
.no_support:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; mtrr_get_vcnt — queries the count of variable-range MTRRs
; Output:
;   RAX = count of variable MTRRs (VCNT)
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global mtrr_get_vcnt
mtrr_get_vcnt:
    call mtrr_supported
    test rax, rax
    jz .no_mtrr

    mov ecx, IA32_MTRRCAP
    rdmsr                           ; EDX:EAX = MTRRCAP MSR
    and eax, 0xFF                   ; bits 0-7 = VCNT
    ret
.no_mtrr:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; mtrr_has_fixed — checks fixed-range MTRR support
; Output:
;   RAX = 1 if supported, 0 otherwise
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global mtrr_has_fixed
mtrr_has_fixed:
    call mtrr_supported
    test rax, rax
    jz .no_mtrr

    mov ecx, IA32_MTRRCAP
    rdmsr
    test eax, 1 << 8                ; bit 8 = FIX support
    jz .no_fixed
    mov rax, 1
    ret
.no_fixed:
.no_mtrr:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; mtrr_has_wc — checks Write-Combining (WC) type support
; Output:
;   RAX = 1 if supported, 0 otherwise
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global mtrr_has_wc
mtrr_has_wc:
    call mtrr_supported
    test rax, rax
    jz .no_mtrr

    mov ecx, IA32_MTRRCAP
    rdmsr
    test eax, 1 << 10               ; bit 10 = WC support
    jz .no_wc
    mov rax, 1
    ret
.no_wc:
.no_mtrr:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; mtrr_set_variable — programs a variable MTRR slot
; Input:
;   RDI = slot index
;   RSI = base physical address (must be page-aligned)
;   RDX = size of range (must be a power of 2, >= 4KB, base-aligned)
;   RCX = memory type (0=UC, 1=WC, 4=WT, 5=WP, 6=WB)
; Output:
;   RAX = 1 on success, 0 on validation failure or unsupported operation
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global mtrr_set_variable
mtrr_set_variable:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = slot
    mov r13, rsi                    ; R13 = base
    mov r14, rdx                    ; R14 = size
    mov r15, rcx                    ; R15 = type

    ; 1. Verify general MTRR support
    call mtrr_supported
    test rax, rax
    jz .fail

    ; 2. Verify slot index < VCNT
    call mtrr_get_vcnt
    cmp r12, rax
    jae .fail

    ; 3. Verify memory type validity
    cmp r15, 0                      ; UC
    je .type_ok
    cmp r15, 1                      ; WC
    je .type_wc
    cmp r15, 4                      ; WT
    je .type_ok
    cmp r15, 5                      ; WP
    je .type_ok
    cmp r15, 6                      ; WB
    je .type_ok
    jmp .fail
.type_wc:
    ; Verify WC support
    call mtrr_has_wc
    test rax, rax
    jz .fail
.type_ok:

    ; 4. Verify base is page-aligned (4KB)
    test r13, 0xFFF
    jnz .fail

    ; 5. Verify size is page-aligned (>= 4KB)
    cmp r14, 4096
    jb .fail
    test r14, 0xFFF
    jnz .fail

    ; 6. Verify size is a power of 2
    mov rax, r14
    dec rax
    test rax, r14
    jnz .fail                       ; (size & (size-1)) != 0

    ; 7. Verify base is aligned to size
    mov rax, r14
    dec rax
    test r13, rax
    jnz .fail                       ; (base & (size-1)) != 0

    ; --- Inputs Validated. Read Physical Address Width ---
    ; Query max input value for extended CPUID
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000008
    jl .default_width
    
    mov eax, 0x80000008
    cpuid
    and eax, 0xFF                   ; EAX bits 0-7: physical address width W
    jmp .width_found
.default_width:
    mov eax, 36                     ; standard default fallback width
.width_found:
    mov r8, rax                     ; R8 = physical address width W

    ; Calculate mask: mask = ~(size - 1) & ((1 << W) - 1)
    mov rcx, r8
    mov rax, 1
    shl rax, cl
    dec rax                         ; RAX = phys_mask = (1 << W) - 1
    
    mov r9, r14                     ; R9 = size
    dec r9
    not r9                          ; R9 = ~(size - 1)
    and r9, rax                     ; R9 = mask masked to phys_mask
    and r9, 0xFFFFFFFFFFFFF000      ; isolate page bits

    ; Set Valid bit (bit 11) in mask
    or r9, 0x800                    ; R9 = mask value

    ; Base value: (base & 0xFFFFFFFFFFFFF000) | (type & 0xFF)
    mov r10, r13
    and r10, 0xFFFFFFFFFFFFF000
    and r15, 0xFF
    or r10, r15                     ; R10 = base value

    ; --- Safe Programming Protocol ---
    ; Save interrupts state
    pushfq
    cli

    ; 1. Enter Cache Disable (CD) state: CR0.CD=1, CR0.NW=0
    mov rax, cr0
    or rax, 1 << 30                 ; CD bit
    and rax, ~(1 << 29)             ; NW bit
    mov cr0, rax

    ; 2. Flush internal processor caches
    wbinvd

    ; 3. Globally disable MTRRs: clear E (bit 11) in DEF_TYPE
    mov ecx, IA32_MTRR_DEF_TYPE
    rdmsr
    mov r11, rax                    ; save original DEF_TYPE low 32 bits
    and eax, ~(1 << 11)             ; clear E bit
    wrmsr

    ; 4. Program Variable MTRR register pair
    ; Base Register
    mov rax, r12
    shl rax, 1                      ; slot * 2
    lea rcx, [IA32_MTRR_PHYSBASE0 + rax] ; MSR base register
    mov eax, r10d                   ; low 32 bits of base
    mov rdx, r10
    shr rdx, 32                     ; high 32 bits of base
    wrmsr

    ; Mask Register
    inc rcx                         ; PHYSBASE + 1 = PHYSMASK
    mov eax, r9d                    ; low 32 bits of mask
    mov rdx, r9
    shr rdx, 32                     ; high 32 bits of mask
    wrmsr

    ; 5. Flush caches again
    wbinvd

    ; 6. Globally re-enable MTRRs in DEF_TYPE
    mov ecx, IA32_MTRR_DEF_TYPE
    rdmsr
    or eax, 1 << 11                 ; set E bit
    wrmsr

    ; 7. Restore Cache Enable state: CR0.CD=0, CR0.NW=0
    mov rax, cr0
    and rax, ~(1 << 30)             ; clear CD
    mov cr0, rax

    ; Restore interrupts
    popfq

    mov rax, 1                      ; success
    jmp .done

.fail:
    xor rax, rax                    ; failure

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; mtrr_get_variable — queries variable MTRR range programmed in slot
; Input:
;   RDI = slot index
; Output:
;   RAX = 1 if slot is active/enabled, 0 otherwise
;   RSI = base physical address (out)
;   RDX = size of range (out)
;   RCX = memory type (out)
; Clobbers: RAX, RCX, RDX, RSI, R8-R11
; -----------------------------------------------------------------------------
global mtrr_get_variable
mtrr_get_variable:
    push rbx
    push r12

    mov rbx, rdi                    ; RBX = slot

    ; Verify slot index
    call mtrr_supported
    test rax, rax
    jz .inactive

    call mtrr_get_vcnt
    cmp rbx, rax
    jae .inactive

    ; Read Mask MSR
    mov rax, rbx
    shl rax, 1
    lea rcx, [IA32_MTRR_PHYSMASK0 + rax]
    rdmsr                           ; EDX:EAX = mask register value
    
    mov r10, rdx
    shl r10, 32
    or r10, rax                     ; R10 = 64-bit mask value

    ; Check if Valid bit (bit 11) is set
    test r10, 1 << 11
    jz .inactive

    ; Read Base MSR
    dec rcx                         ; PHYSBASE
    rdmsr                           ; EDX:EAX = base register value
    
    mov r11, rdx
    shl r11, 32
    or r11, rax                     ; R11 = 64-bit base value

    ; Extract Memory Type (bits 0-7)
    mov rcx, r11
    and rcx, 0xFF                   ; RCX = type

    ; Extract Base Address
    mov rsi, r11
    mov rax, 0xFFFFFFFFFFFFF000
    and rsi, rax                    ; RSI = base physical address

    ; Extract Size from mask value R10
    ; Find lowest set bit in mask bits 12-51
    and r10, rax                    ; clear low 12 bits
    bsf r8, r10                     ; R8 = index of first set bit (size boundary)
    jz .inactive                    ; invalid mask if no bits set

    mov rdx, 1
    mov rcx, r8
    shl rdx, cl                     ; RDX = size = 1 << bit_index

    mov rax, 1                      ; return 1 (active)
    jmp .done

.inactive:
    xor rax, rax
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx

.done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; mtrr_disable_variable — disables a variable MTRR slot by clearing valid bit
; Input:
;   RDI = slot index
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global mtrr_disable_variable
mtrr_disable_variable:
    push rbx
    push r12

    mov r12, rdi                    ; R12 = slot

    ; 1. Verify support
    call mtrr_supported
    test rax, rax
    jz .fail

    ; 2. Verify slot index < VCNT
    call mtrr_get_vcnt
    cmp r12, rax
    jae .fail

    ; Calculate register addresses
    mov rax, r12
    shl rax, 1                      ; slot * 2
    lea rbx, [IA32_MTRR_PHYSBASE0 + rax] ; base MSR address
    lea r12, [IA32_MTRR_PHYSMASK0 + rax] ; mask MSR address

    ; --- Safe Programming Protocol ---
    pushfq
    cli

    ; 1. CR0.CD=1, CR0.NW=0
    mov rax, cr0
    or rax, 1 << 30
    and rax, ~(1 << 29)
    mov cr0, rax

    ; 2. Flush
    wbinvd

    ; 3. Globally disable MTRRs
    mov ecx, IA32_MTRR_DEF_TYPE
    rdmsr
    mov r11, rax                    ; save DEF_TYPE low 32 bits
    and eax, ~(1 << 11)             ; clear E
    wrmsr

    ; 4. Clear MTRR MSRs (both PHYSBASE and PHYSMASK to 0)
    mov ecx, ebx                    ; Base MSR
    xor eax, eax
    xor rdx, rdx
    wrmsr

    mov ecx, r12d                   ; Mask MSR
    wrmsr

    ; 5. Flush
    wbinvd

    ; 6. Globally re-enable MTRRs
    mov ecx, IA32_MTRR_DEF_TYPE
    rdmsr
    or eax, 1 << 11                 ; set E
    wrmsr

    ; 7. Re-enable caching
    mov rax, cr0
    and rax, ~(1 << 30)
    mov cr0, rax

    popfq

    mov rax, 1
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r12
    pop rbx
    ret

%endif ; LIB_HW_UCPU_MTRR_ASM
