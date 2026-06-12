; =============================================================================
; Tattva OS — lib/mem/virt/sched_affinity.asm
; =============================================================================
; Thread CPU Affinity Scheduler & Dynamic NUMA Core Migration.
; Maps CPU cores to NUMA nodes, tracks threads, and migrates thread CPU
; affinities to the closest CPU cores when a new NUMA memory node is inserted.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_SCHED_AFFINITY_ASM
%define LIB_MEM_VIRT_SCHED_AFFINITY_ASM

[BITS 64]

; External symbols
extern numa_get_distance
extern smp_active_cores
extern uart_print_str
extern uart_print_hex64
extern uart_print_dec

; Thread Structure Definition (32 bytes)
struc thread_t
    .thread_id          resq 1      ; Unique thread ID
    .cpu_affinity_mask  resq 1      ; Bitmask of allowed CPUs
    .preferred_node     resd 1      ; Target NUMA node ID
    .current_cpu        resd 1      ; Current execution CPU ID
    .flags              resq 1      ; Thread flags (bit 0 = Active)
endstruc

section .text

; -----------------------------------------------------------------------------
; sched_affinity_init — Initializes CPU-to-Node maps and sets up mock threads
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global sched_affinity_init
sched_affinity_init:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rsi, msg_sched_init_start
    call uart_print_str

    ; Initialize default CPU-to-Node mapping:
    ; CPUs 0-7 mapped to Node 0, CPUs 8-15 mapped to Node 1
    lea rdi, [cpu_to_node]
    xor rcx, rcx
.cpu_loop:
    cmp rcx, 8
    jae .node1
    mov byte [rdi + rcx], 0         ; CPUs 0-7 on Node 0
    jmp .cpu_next
.node1:
    mov byte [rdi + rcx], 1         ; CPUs 8-15 on Node 1
.cpu_next:
    inc rcx
    cmp rcx, 16
    jb .cpu_loop

    ; Reset thread count
    mov qword [thread_count], 0

    ; Register mock threads for verification:
    ; Thread 100: affinity = CPU 0, preferred node = 1 (will migrate)
    mov rdi, 100                    ; thread_id
    mov rsi, 0x0001                 ; affinity mask (CPU 0)
    mov rdx, 1                      ; preferred node 1
    call sched_register_thread

    ; Thread 101: affinity = CPU 1, preferred node = 2 (will migrate when Node 2 hotplugged)
    mov rdi, 101
    mov rsi, 0x0002                 ; affinity mask (CPU 1)
    mov rdx, 2                      ; preferred node 2
    call sched_register_thread

    ; Thread 102: affinity = CPU 0, preferred node = 0 (won't migrate because it prefers local Node 0)
    mov rdi, 102
    mov rsi, 0x0001
    mov rdx, 0
    call sched_register_thread

    mov rsi, msg_sched_init_ok
    call uart_print_str

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; sched_register_thread — Registers a thread into the scheduler thread table
; Input:
;   RDI = thread ID
;   RSI = initial CPU affinity mask
;   RDX = preferred node ID
; Output: RAX = index in thread table, or -1 on failure
; -----------------------------------------------------------------------------
global sched_register_thread
sched_register_thread:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rcx, [thread_count]
    cmp rcx, 64
    jae .fail

    ; Calculate slot offset
    mov rax, rcx
    imul rax, thread_t_size
    lea rbx, [thread_table + rax]

    ; Populate structure fields
    mov [rbx + thread_t.thread_id], rdi
    mov [rbx + thread_t.cpu_affinity_mask], rsi
    mov [rbx + thread_t.preferred_node], edx
    mov dword [rbx + thread_t.current_cpu], 0
    mov qword [rbx + thread_t.flags], 1      ; Active = 1

    inc qword [thread_count]
    mov rax, rcx
    jmp .exit

.fail:
    mov rax, -1

.exit:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sched_migrate_threads_for_node — Migrates threads closer to newly added node
; Input:
;   RDI = new memory node ID (proximity domain)
; Output: none
; -----------------------------------------------------------------------------
global sched_migrate_threads_for_node
sched_migrate_threads_for_node:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = new_node_id

    mov rsi, msg_migrate_start
    call uart_print_str
    mov rax, r12
    call uart_print_dec
    mov rsi, msg_crlf
    call uart_print_str

    ; Loop over all registered threads
    mov r13, [thread_count]
    test r13, r13
    jz .done

    xor r14, r14                    ; R14 = thread index i = 0

.thread_loop:
    cmp r14, r13
    jae .done

    ; Calculate thread pointer
    mov rax, r14
    imul rax, thread_t_size
    lea r15, [thread_table + rax]

    ; Check if thread is active
    mov rax, [r15 + thread_t.flags]
    test rax, 1
    jz .next_thread

    ; Check if preferred node matches the newly added node
    mov eax, [r15 + thread_t.preferred_node]
    cmp eax, r12d
    jne .next_thread

    ; Find the best CPU core closest to the new memory node
    ; Best distance starts at 255 (unreachable)
    mov rbp, 255                    ; RBP = best_distance = 255
    xor rbx, rbx                    ; RBX = best_cpu = 0
    xor rcx, rcx                    ; RCX = current CPU index = 0
    mov r8d, [smp_active_cores]     ; total active cores

.find_cpu_loop:
    cmp rcx, r8
    jae .cpu_search_done

    ; Get NUMA node of current CPU
    lea rax, [cpu_to_node]
    movzx eax, byte [rax + rcx]     ; EAX = cpu_node_id

    ; Compute distance from cpu_node_id (EAX) to new_node_id (R12D)
    push rdi
    push rsi
    push rcx
    push r8
    mov rdi, rax                    ; node_from = cpu_node_id
    mov rsi, r12                    ; node_to = new_node_id
    call numa_get_distance
    mov r9, rax                     ; R9 = distance
    pop r8
    pop rcx
    pop rsi
    pop rdi

    ; Compare with best_distance
    cmp r9, rbp
    jae .next_cpu
    mov rbp, r9                     ; best_distance = distance
    mov rbx, rcx                    ; best_cpu = current CPU

.next_cpu:
    inc rcx
    jmp .find_cpu_loop

.cpu_search_done:
    ; We have the best CPU core in RBX and the minimum distance in RBP
    cmp rbp, 255
    je .next_thread                 ; if unreachable, do not migrate

    ; Print migration message
    mov rsi, msg_migrate_msg_prefix
    call uart_print_str
    mov rax, [r15 + thread_t.thread_id]
    call uart_print_dec
    mov rsi, msg_migrate_msg_mid1
    call uart_print_str
    mov rax, rbx
    call uart_print_dec
    mov rsi, msg_migrate_msg_mid2
    call uart_print_str
    mov rax, rbp
    call uart_print_dec
    mov rsi, msg_migrate_msg_suffix
    call uart_print_str

    ; Perform migration: update cpu_affinity_mask to target best CPU core (1 << RBX)
    mov rcx, rbx
    mov rax, 1
    shl rax, cl                     ; RAX = 1 << best_cpu
    mov [r15 + thread_t.cpu_affinity_mask], rax
    mov [r15 + thread_t.current_cpu], ebx

.next_thread:
    inc r14
    jmp .thread_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; Data Section
; -----------------------------------------------------------------------------
section .data

global cpu_to_node
global thread_count
global thread_table

align 8
thread_count:   dq 0

; Array mapping CPU cores to NUMA node IDs
align 16
cpu_to_node:    times 16 db 0       ; Up to 16 CPUs

; Thread table
align 16
thread_table:   times 64 * thread_t_size db 0

; Messages
msg_sched_init_start:   db "Scheduler: Initializing Core Affinity Mappings...", 0x0D, 0x0A, 0
msg_sched_init_ok:      db "Scheduler: Core Affinity & Thread Table Initialized.", 0x0D, 0x0A, 0
msg_migrate_start:      db "Scheduler: Dynamic CPU Affinity balancing for Node ", 0
msg_migrate_msg_prefix: db "  Affinity Migrator: Thread ", 0
msg_migrate_msg_mid1:   db " migrated to CPU ", 0
msg_migrate_msg_mid2:   db " (Distance = ", 0
msg_migrate_msg_suffix: db ")", 0x0D, 0x0A, 0
msg_crlf:               db 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_SCHED_AFFINITY_ASM
