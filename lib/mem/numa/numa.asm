; =============================================================================
; Tattva OS — lib/mem/numa/numa.asm
; =============================================================================
; NUMA Range structures and Node ID lookup functions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_NUMA_NUMA_ASM
%define LIB_MEM_NUMA_NUMA_ASM

[BITS 64]

; NUMA memory range mapping structure
struc numa_range_t
    .base       resq 1          ; Base physical address (64-bit)
    .length     resq 1          ; Range length in bytes (64-bit)
    .node_id    resd 1          ; Proximity Domain / Node ID (32-bit)
    .flags      resd 1          ; Flags (bit 0 = Enabled)
endstruc

; Maximum memory ranges we support parsing from SRAT
NUMA_MAX_RANGES equ 32

; NUMA node distance matrix constants
NUMA_MAX_NODES equ 8
NUMA_DEFAULT_LOCAL_DISTANCE equ 10
NUMA_DEFAULT_REMOTE_DISTANCE equ 20

section .text

; -----------------------------------------------------------------------------
; numa_get_node_by_phys — finds the NUMA Node ID for a physical address
; Input:
;   RDI = physical address
; Output:
;   RAX = Node ID (32-bit), or 0 if not found / UMA fallback
; -----------------------------------------------------------------------------
global numa_get_node_by_phys
numa_get_node_by_phys:
    push rbx
    push rcx
    push rdx

    mov rcx, [numa_range_count]
    test rcx, rcx
    jz .fallback

    lea rbx, [numa_ranges]
    xor rdx, rdx                    ; index i = 0

.loop:
    cmp rdx, rcx
    jge .fallback

    ; Calculate offset of range entry
    mov rax, rdx
    imul rax, numa_range_t_size
    lea r8, [rbx + rax]

    ; Check if entry is enabled (flags bit 0)
    mov eax, [r8 + numa_range_t.flags]
    test al, 1
    jz .next

    ; Check if RDI >= base
    mov rax, [r8 + numa_range_t.base]
    cmp rdi, rax
    jb .next

    ; Check if RDI < base + length
    add rax, [r8 + numa_range_t.length]
    cmp rdi, rax
    jb .found

.next:
    inc rdx
    jmp .loop

.found:
    movzx rax, dword [r8 + numa_range_t.node_id]
    jmp .exit

.fallback:
    xor rax, rax                    ; default to Node 0

.exit:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_get_distance — gets relative memory distance between two nodes
; Input:
;   RDI = node_from (Node ID)
;   RSI = node_to (Node ID)
; Output:
;   RAX = relative distance (e.g. 10 = local, 20 = default remote, 255 = unreachable)
; -----------------------------------------------------------------------------
global numa_get_distance
numa_get_distance:
    push rbx
    push rcx
    push rdx

    ; 1. Check bounds against numa_node_count
    mov rcx, [numa_node_count]
    test rcx, rcx
    jz .local_check                 ; if count is 0 (uninitialized), do UMA check

    cmp rdi, rcx
    jae .out_of_bounds
    cmp rsi, rcx
    jae .out_of_bounds

    ; Calculate index: node_from * numa_node_count + node_to
    mov rax, rdi
    imul rax, rcx
    add rax, rsi                    ; RAX = index
    
    ; Load distance byte from matrix
    lea rbx, [numa_distance_matrix]
    movzx rax, byte [rbx + rax]
    jmp .exit

.local_check:
    ; Fallback UMA check: if node_from == node_to, distance is 10, else 255
    cmp rdi, rsi
    je .local
    mov rax, 255
    jmp .exit
.local:
    mov rax, NUMA_DEFAULT_LOCAL_DISTANCE
    jmp .exit

.out_of_bounds:
    mov rax, 255                    ; unreachable/invalid

.exit:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Data Section — NUMA ranges array and count
; -----------------------------------------------------------------------------
section .data

align 8
global numa_ranges
global numa_range_count
global numa_node_count
global numa_distance_matrix

numa_ranges:          times NUMA_MAX_RANGES * numa_range_t_size db 0
numa_range_count:     dq 0
numa_node_count:      dq 0
numa_distance_matrix: times NUMA_MAX_NODES * NUMA_MAX_NODES db 0

%endif ; LIB_MEM_NUMA_NUMA_ASM
