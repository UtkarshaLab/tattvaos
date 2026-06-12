; =============================================================================
; Tattva OS — lib/mem/virt/locality_scorer.asm
; =============================================================================
; Locality-Distance Affinity Scorer.
; Computes NUMA proximity scores dynamically using the ACPI SLIT table metrics.
; Ranks memory nodes for optimal allocation fallbacks based on core distance.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_LOCALITY_SCORER_ASM
%define LIB_MEM_VIRT_LOCALITY_SCORER_ASM

[BITS 64]

; External symbols
extern numa_get_distance
extern numa_node_count
extern numa_nodes
extern cpu_to_node
extern smp_active_cores
extern uart_print_str
extern uart_print_hex64
extern uart_print_dec

section .text

; -----------------------------------------------------------------------------
; numa_compute_affinity_score — Computes proximity score (higher = closer)
; Input:
;   RDI = node_from (NUMA Node ID)
;   RSI = node_to (NUMA Node ID)
; Output:
;   RAX = proximity score (0-245, where local = 245, remote = 235, unreachable = 0)
; -----------------------------------------------------------------------------
global numa_compute_affinity_score
numa_compute_affinity_score:
    push rdi
    push rsi
    
    call numa_get_distance          ; RAX = distance (10, 20, 255)
    
    cmp rax, 255
    jae .unreachable
    
    ; score = 255 - distance
    mov rdx, 255
    sub rdx, rax
    mov rax, rdx
    jmp .exit
    
.unreachable:
    xor rax, rax                    ; score = 0
    
.exit:
    pop rsi
    pop rdi
    ret

; -----------------------------------------------------------------------------
; numa_select_best_node — Returns the closest active memory node for a CPU
; Input:
;   RDI = CPU ID
; Output:
;   RAX = Node ID of the best/closest memory node
; -----------------------------------------------------------------------------
global numa_select_best_node
numa_select_best_node:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = CPU ID

    ; Get core's home node
    lea rax, [cpu_to_node]
    movzx r13d, byte [rax + r12]    ; R13D = home_node_id

    xor rbx, rbx                    ; RBX = current node index i = 0
    xor rcx, rcx                    ; RCX = best_score = 0
    xor rdx, rdx                    ; RDX = best_node = 0

.loop:
    cmp rbx, [numa_node_count]
    jae .done

    ; Verify node is active
    mov rax, rbx
    imul rax, numa_node_t_size
    lea rax, [numa_nodes + rax]
    mov eax, [rax + numa_node_t.flags]
    test eax, 1                     ; Active?
    jz .next

    ; Compute score from home_node (R13) to current node index (RBX)
    mov rdi, r13
    mov rsi, rbx
    call numa_compute_affinity_score ; RAX = score
    
    cmp rax, rcx
    jbe .next
    mov rcx, rax                    ; best_score = score
    mov rdx, rbx                    ; best_node = current node index

.next:
    inc rbx
    jmp .loop

.done:
    mov rax, rdx                    ; return best_node
    
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; numa_rank_nodes_for_cpu — Ranks all active memory nodes by proximity to a CPU
; Input:
;   RDI = CPU ID
;   RSI = destination buffer pointer (must be at least 8 bytes)
; Output:
;   RAX = count of active nodes ranked; destination buffer holds ranked Node IDs
; -----------------------------------------------------------------------------
global numa_rank_nodes_for_cpu
numa_rank_nodes_for_cpu:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi                    ; R12 = dest buffer pointer
    
    ; Get core's home node
    lea rax, [cpu_to_node]
    movzx r13d, byte [rax + rdi]    ; R13D = home_node_id

    ; 1. Collect all active nodes and their scores
    ; We store them as pairs in registers/stack. We can use R14 as active node count.
    xor r14, r14                    ; R14 = count = 0
    xor rbx, rbx                    ; rbx = current node index = 0

.collect_loop:
    cmp rbx, [numa_node_count]
    jae .sort_nodes

    ; Verify node is active
    mov rax, rbx
    imul rax, numa_node_t_size
    lea rax, [numa_nodes + rax]
    mov eax, [rax + numa_node_t.flags]
    test eax, 1
    jz .collect_next

    ; Compute score
    mov rdi, r13
    mov rsi, rbx
    call numa_compute_affinity_score ; RAX = score

    ; Store (node_id, score) in local stack area (using RSP-16-i*16)
    mov rdx, r14
    shl rdx, 4                      ; index * 16
    neg rdx
    lea rdx, [rsp - 16 + rdx]
    mov [rdx], rbx                  ; store node_id
    mov [rdx + 8], rax              ; store score
    inc r14

.collect_next:
    inc rbx
    jmp .collect_loop

.sort_nodes:
    test r14, r14
    jz .done

    ; 2. Bubble sort the collected nodes based on score (descending)
    ; i loop: 0 to count-1
    xor rcx, rcx                    ; RCX = i = 0
.sort_outer:
    mov rax, r14
    dec rax
    cmp rcx, rax
    jae .copy_results

    ; j loop: 0 to count-i-2
    xor rdx, rdx                    ; RDX = j = 0
.sort_inner:
    mov rax, r14
    sub rax, rcx
    dec rax                         ; RAX = count - i - 1
    cmp rdx, rax
    jae .sort_outer_next

    ; Load pair j
    mov rax, rdx
    shl rax, 4
    neg rax
    lea rax, [rsp - 16 + rax]       ; RAX = &pair[j]

    ; Load pair j+1
    mov rsi, rdx
    inc rsi
    shl rsi, 4
    neg rsi
    lea rsi, [rsp - 16 + rsi]       ; RSI = &pair[j+1]

    mov r8, [rax + 8]               ; R8 = score[j]
    mov r9, [rsi + 8]               ; R9 = score[j+1]
    
    cmp r8, r9
    jae .sort_inner_next            ; if score[j] >= score[j+1], no swap

    ; Swap node_ids
    mov r10, [rax]
    mov r11, [rsi]
    mov [rax], r11
    mov [rsi], r10

    ; Swap scores
    mov [rax + 8], r9
    mov [rsi + 8], r8

.sort_inner_next:
    inc rdx
    jmp .sort_inner

.sort_outer_next:
    inc rcx
    jmp .sort_outer

.copy_results:
    ; 3. Copy sorted node IDs to output buffer
    xor rcx, rcx                    ; index
.copy_loop:
    cmp rcx, r14
    jae .done

    mov rax, rcx
    shl rax, 4
    neg rax
    lea rax, [rsp - 16 + rax]
    mov rsi, [rax]                  ; load node_id

    mov [r12 + rcx], sil            ; write node_id byte to dest buffer
    inc rcx
    jmp .copy_loop

.done:
    mov rax, r14                    ; return count of ranked nodes

    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret
