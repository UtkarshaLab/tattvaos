; =============================================================================
; Tattva OS — lib/mem/virt/hmm_metrics.asm
; =============================================================================
; Dynamic Page Migration Metrics Subsystem (Milestone 23.6).
; Tracks CPU and GPU read/write access counts for unified memory pages and
; dynamically migrates hot pages between host RAM and GPU VRAM.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HMM_METRICS_ASM
%define LIB_MEM_VIRT_HMM_METRICS_ASM

[BITS 64]

; HMM Paging Migration Threshold
MIGRATION_THRESHOLD     equ 10

; hmm_metric_t structure definition
struc hmm_metric_t
    .vaddr         resq 1      ; Virtual page base address (4KB aligned)
    .cpu_reads     resq 1      ; CPU Read access counter
    .cpu_writes    resq 1      ; CPU Write access counter
    .gpu_reads     resq 1      ; GPU Read access counter
    .gpu_writes    resq 1      ; GPU Write access counter
    .residency     resd 1      ; Residency: 0 = Host RAM, 1 = GPU VRAM
    .next          resq 1      ; Pointer to next metric descriptor in list
endstruc

section .text

; External memory, VMA, and migration symbols
extern heap_alloc
extern heap_free
extern vma_find
extern phys_state
extern hmm_handle_page_fault
extern hmm_migrate_to_gpu

; -----------------------------------------------------------------------------
; hmm_get_metrics — Searches the metric tracking list for a GVA
; Input:
;   RDI = Virtual Address (page-aligned)
; Output:
;   RAX = pointer to hmm_metric_t structure, or 0 if not tracked
; -----------------------------------------------------------------------------
global hmm_get_metrics
hmm_get_metrics:
    mov rax, [hmm_metrics_list_head]
.loop:
    test rax, rax
    jz .done

    cmp [rax + hmm_metric_t.vaddr], rdi
    je .done                        ; found!

    mov rax, [rax + hmm_metric_t.next]
    jmp .loop
.done:
    ret

; -----------------------------------------------------------------------------
; hmm_update_metrics — Records memory access and triggers dynamic page migration
; Input:
;   RDI = Virtual Address (must be 4KB page-aligned)
;   RSI = Access Type:
;         0 = CPU Read, 1 = CPU Write
;         2 = GPU Read, 3 = GPU Write
; Output:
;   RAX = 1 if page was migrated, 0 if residency remained unchanged
; -----------------------------------------------------------------------------
global hmm_update_metrics
hmm_update_metrics:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = virtual address
    mov r13, rsi                    ; R13 = access type

    ; 1. Alignment check
    test r12, 4095
    jnz .fail

    ; 2. Lookup metrics structure
    mov rdi, r12
    call hmm_get_metrics
    test rax, rax
    jnz .have_metrics

    ; Metrics not found: allocate a new tracking structure
    push rbx
    mov rdi, hmm_metric_t_size
    call heap_alloc
    pop rbx
    test rax, rax
    jz .fail

    ; Initialize structure
    mov [rax + hmm_metric_t.vaddr], r12
    mov qword [rax + hmm_metric_t.cpu_reads], 0
    mov qword [rax + hmm_metric_t.cpu_writes], 0
    mov qword [rax + hmm_metric_t.gpu_reads], 0
    mov qword [rax + hmm_metric_t.gpu_writes], 0
    mov dword [rax + hmm_metric_t.residency], 0    ; start on Host RAM
    mov qword [rax + hmm_metric_t.next], 0

    ; Link to global tracking list (head insertion)
    mov rdx, [hmm_metrics_list_head]
    mov [rax + hmm_metric_t.next], rdx
    mov [hmm_metrics_list_head], rax

.have_metrics:
    mov r14, rax                    ; R14 = pointer to hmm_metric_t

    ; 3. Increment access counter
    cmp r13, 0
    je .inc_cpu_read
    cmp r13, 1
    je .inc_cpu_write
    cmp r13, 2
    je .inc_gpu_read
    cmp r13, 3
    je .inc_gpu_write
    jmp .fail                       ; invalid access type

.inc_cpu_read:
    inc qword [r14 + hmm_metric_t.cpu_reads]
    jmp .evaluate_migration
.inc_cpu_write:
    inc qword [r14 + hmm_metric_t.cpu_writes]
    jmp .evaluate_migration
.inc_gpu_read:
    inc qword [r14 + hmm_metric_t.gpu_reads]
    jmp .evaluate_migration
.inc_gpu_write:
    inc qword [r14 + hmm_metric_t.gpu_writes]

.evaluate_migration:
    ; 4. Evaluate migration policy
    mov eax, [r14 + hmm_metric_t.residency]
    test eax, eax
    jnz .resident_gpu

    ; Case A: Page is currently resident in CPU Host RAM (residency == 0)
    ; Check if GPU access metrics exceed migration threshold
    mov rcx, [r14 + hmm_metric_t.gpu_reads]
    add rcx, [r14 + hmm_metric_t.gpu_writes]
    cmp rcx, MIGRATION_THRESHOLD
    jb .no_migration

    ; Migrate Host RAM -> GPU VRAM
    ; Compute a safe VRAM physical address (256MB above host RAM limit)
    mov r15, [phys_state + 32]       ; r15 = max_phys_addr
    add r15, 0x10000000              ; base offset (256MB)
    add r15, [gpu_vram_phys_alloc]   ; add current allocator offset
    add qword [gpu_vram_phys_alloc], 4096 ; increment allocator offset

    ; Call page migration API
    mov rdi, r12                    ; virtual address
    mov rsi, r15                    ; VRAM destination page
    call hmm_migrate_to_gpu
    test rax, rax
    jz .fail_alloc_rollback

    ; Update metrics residency
    mov dword [r14 + hmm_metric_t.residency], 1 ; residency is now VRAM
    mov qword [r14 + hmm_metric_t.cpu_reads], 0
    mov qword [r14 + hmm_metric_t.cpu_writes], 0
    mov qword [r14 + hmm_metric_t.gpu_reads], 0
    mov qword [r14 + hmm_metric_t.gpu_writes], 0

    mov rax, 1                      ; return 1 (migrated)
    jmp .exit

.resident_gpu:
    ; Case B: Page is currently resident in GPU VRAM (residency == 1)
    ; Check if CPU access metrics exceed migration threshold
    mov rcx, [r14 + hmm_metric_t.cpu_reads]
    add rcx, [r14 + hmm_metric_t.cpu_writes]
    cmp rcx, MIGRATION_THRESHOLD
    jb .no_migration

    ; Migrate GPU VRAM -> Host RAM
    ; Find matching VMA node
    mov rdi, r12
    call vma_find
    test rax, rax
    jz .no_migration

    ; Call page fault synchronization (RDI = virtual address, RSI = VMA, RDX = 0 error code)
    mov rdi, r12
    mov rsi, rax
    xor rdx, rdx
    call hmm_handle_page_fault
    test rax, rax
    jz .no_migration

    ; Update metrics residency
    mov dword [r14 + hmm_metric_t.residency], 0 ; residency is now Host RAM
    mov qword [r14 + hmm_metric_t.cpu_reads], 0
    mov qword [r14 + hmm_metric_t.cpu_writes], 0
    mov qword [r14 + hmm_metric_t.gpu_reads], 0
    mov qword [r14 + hmm_metric_t.gpu_writes], 0

    mov rax, 1                      ; return 1 (migrated)
    jmp .exit

.fail_alloc_rollback:
    sub qword [gpu_vram_phys_alloc], 4096 ; rollback allocator offset
.fail:
.no_migration:
    xor rax, rax                    ; return 0 (no migration or failure)
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data

align 8
global hmm_metrics_list_head
hmm_metrics_list_head: dq 0

align 8
gpu_vram_phys_alloc:   dq 0        ; current GPU physical VRAM allocator offset

%endif ; LIB_MEM_VIRT_HMM_METRICS_ASM
