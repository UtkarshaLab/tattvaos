; =============================================================================
; Tattva OS — boot/stage2/cpu/vendor.asm
; =============================================================================
; Detect CPU vendor string and match it against Intel / AMD.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit) / protected mode (32-bit)
; =============================================================================

%ifndef VENDOR_ASM
%define VENDOR_ASM

[BITS 16]

; =============================================================================
; cpu_get_vendor — query CPUID for vendor string
; Input:  none
; Output: ESI = pointer to vendor string buffer (13 bytes)
;         EAX = 1 if Intel, 2 if AMD, 0 otherwise
; =============================================================================
cpu_get_vendor:
    push ebx
    push ecx
    push edx

    xor eax, eax
    cpuid                           ; leaf 0 returns vendor string in EBX, EDX, ECX

    mov [cpu_vendor_str], ebx
    mov [cpu_vendor_str + 4], edx
    mov [cpu_vendor_str + 8], ecx
    mov byte [cpu_vendor_str + 12], 0 ; null terminator

    ; Match Intel ("GenuineIntel")
    ; EBX = 0x756e6547 ("Genu"), EDX = 0x49656e69 ("ineI"), ECX = 0x6c65746e ("ntel")
    cmp ebx, 0x756e6547
    jne .check_amd
    cmp edx, 0x49656e69
    jne .check_amd
    cmp ecx, 0x6c65746e
    jne .check_amd
    mov eax, 1                      ; Intel
    jmp .done

.check_amd:
    ; Match AMD ("AuthenticAMD")
    ; EBX = 0x68747541 ("Auth"), EDX = 0x69746e65 ("enti"), ECX = 0x444d4163 ("cAMD")
    cmp ebx, 0x68747541
    jne .unknown
    cmp edx, 0x69746e65
    jne .unknown
    cmp ecx, 0x444d4163
    jne .unknown
    mov eax, 2                      ; AMD
    jmp .done

.unknown:
    xor eax, eax                    ; Unknown vendor

.done:
    mov esi, cpu_vendor_str
    pop edx
    pop ecx
    pop ebx
    ret

; =============================================================================
; Data
; =============================================================================
cpu_vendor_str: times 13 db 0

%endif ; VENDOR_ASM
