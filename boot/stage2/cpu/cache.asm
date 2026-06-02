; =============================================================================
; Tattva OS — boot/stage2/cpu/cache.asm
; =============================================================================
; Detect L1 Data, L2, and L3 cache sizes in kilobytes (KB).
; Supports both Intel (deterministic cache) and AMD extended topologies.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef CACHE_ASM
%define CACHE_ASM

[BITS 16]

; =============================================================================
; cpu_get_cache — detect L1 Data, L2, and L3 cache sizes in KB
; Input:  none
; Output: EAX = L1 Data Cache size in KB
;         EBX = L2 Cache size in KB
;         ECX = L3 Cache size in KB
; =============================================================================
cpu_get_cache:
    push edi
    push esi
    push edx

    ; 1. Quick check of vendor string to determine AMD vs Intel topology
    push eax
    push ebx
    push ecx
    push edx
    xor eax, eax
    cpuid                           ; leaf 0
    mov [bp_vendor], ebx            ; save Genu/Auth indicator
    pop edx
    pop ecx
    pop ebx
    pop eax

    cmp dword [bp_vendor], 0x756e6547 ; "Genu" (Intel)
    je .intel_cache

    ; AMD Extended Cache Detection
    ; Check max extended leaf
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000006
    jb .no_cache

    ; AMD L1 Data Cache (Extended leaf 0x80000005)
    mov eax, 0x80000005
    cpuid
    ; ECX bits 31:24 = L1 D-Cache size in KB
    shr ecx, 24
    mov [cache_l1], ecx

    ; AMD L2 and L3 Cache (Extended leaf 0x80000006)
    mov eax, 0x80000006
    cpuid
    ; ECX bits 31:16 = L2 Cache size in KB
    mov edx, ecx
    shr edx, 16
    mov [cache_l2], edx

    ; EDX bits 31:18 = L3 Cache size in 512KB blocks
    mov edx, edi                    ; save EDI (just in case)
    mov edx, [esp + 0]              ; retrieve EDX from stack push context
    mov eax, 0x80000006
    cpuid
    shr edx, 18
    and edx, 0x3FFF                 ; mask to 14 bits
    shl edx, 9                      ; multiply by 512 to get KB
    mov [cache_l3], edx
    jmp .done

.intel_cache:
    ; Intel Deterministic Cache Parameters (Leaf 4)
    xor eax, eax
    cpuid
    cmp eax, 4                      ; leaf 4 supported?
    jb .no_cache

    mov dword [cache_l1], 0
    mov dword [cache_l2], 0
    mov dword [cache_l3], 0

    mov edi, 0                      ; ECX loop index (sub-leaf index)

.intel_loop:
    mov eax, 4
    mov ecx, edi
    cpuid
    
    mov edx, eax
    and edx, 0x1F                   ; bits 4:0 = Cache Type (0 = end)
    jz .done

    ; Save EAX (flags/level)
    push eax
    
    ; Compute: (Ways + 1) * (Partitions + 1) * (LineSize + 1) * (Sets + 1)
    ; EBX bits 31:22 = Ways - 1
    ; EBX bits 21:12 = Partitions - 1
    ; EBX bits 11:0  = LineSize - 1
    ; ECX            = Sets - 1
    mov eax, ebx
    shr eax, 22
    and eax, 0x3FF
    inc eax                         ; EAX = Ways

    mov esi, ebx
    shr esi, 12
    and esi, 0x3FF
    inc esi                         ; ESI = Partitions
    mul esi                         ; EAX = Ways * Partitions

    mov esi, ebx
    and esi, 0xFFF
    inc esi                         ; ESI = LineSize
    mul esi                         ; EAX = Ways * Partitions * LineSize

    inc ecx                         ; ECX = Sets
    mul ecx                         ; EAX = Size in Bytes

    shr eax, 10                     ; EAX = Size in KB
    mov esi, eax                    ; ESI = size in KB

    pop eax                         ; restore EAX
    mov edx, eax
    shr edx, 5
    and edx, 0x07                   ; EDX = Cache Level (1, 2, 3)

    cmp edx, 1
    jne .check_l2
    
    ; check if data or unified cache
    mov edx, eax
    and edx, 0x1F
    cmp edx, 2                      ; type 2 = Instruction Cache
    je .next_intel                  ; skip instruction cache for L1 Data
    mov [cache_l1], esi
    jmp .next_intel

.check_l2:
    cmp edx, 2
    jne .check_l3
    mov [cache_l2], esi
    jmp .next_intel

.check_l3:
    cmp edx, 3
    jne .next_intel
    mov [cache_l3], esi

.next_intel:
    inc edi
    cmp edi, 32                     ; safety bound
    jl .intel_loop
    jmp .done

.no_cache:
    mov dword [cache_l1], 0
    mov dword [cache_l2], 0
    mov dword [cache_l3], 0

.done:
    mov eax, [cache_l1]
    mov ebx, [cache_l2]
    mov ecx, [cache_l3]

    pop edx
    pop esi
    pop edi
    ret

; =============================================================================
; Data
; =============================================================================
bp_vendor:  dd 0
cache_l1:   dd 0
cache_l2:   dd 0
cache_l3:   dd 0

%endif ; CACHE_ASM
