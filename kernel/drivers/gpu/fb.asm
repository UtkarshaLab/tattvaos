; =============================================================================
; Tattva OS — kernel/drivers/gpu/fb.asm
; =============================================================================
; GPU Framebuffer Driver and Caching Benchmarks (Subfeature 8.3).
; Configures fast write-combining video transfers for linear framebuffers.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef KERNEL_DRIVERS_GPU_FB_ASM
%define KERNEL_DRIVERS_GPU_FB_ASM

[BITS 64]

; Virtual Mapping bases
FB_VIRT_BASE    equ 0x8000000000    ; 512GB mark for WC Framebuffer mapping
FB_VIRT_UC_BASE equ 0x8010000000    ; Uncached Framebuffer mapping base for testing

; Benchmark block size (1MB to timing test)
BENCH_SIZE_BYTES equ 1024 * 1024
BENCH_SIZE_DWORDS equ BENCH_SIZE_BYTES / 4

section .text

; External references
extern boot_info_ptr
extern vma_create
extern vma_destroy
extern virt_map
extern virt_unmap
extern pat_supported
extern pat_find_entry
extern uart_print_str
extern uart_print_hex64

; -----------------------------------------------------------------------------
; fb_init — initializes framebuffer parameters and maps it under Write-Combining
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global fb_init
fb_init:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; 1. Load BootInfo pointer
    mov rdi, [boot_info_ptr]
    test rdi, rdi
    jz .fail_no_bootinfo

    ; 2. Retrieve Framebuffer parameters (offsets from config.asm)
    ; BOOT_INFO_FB_ADDR (offset 32)
    mov rax, [rdi + 32]
    mov [fb_phys_addr], rax
    test rax, rax
    jz .fail_no_fb

    ; BOOT_INFO_FB_WIDTH (offset 40)
    mov ecx, [rdi + 40]
    mov [fb_width], ecx

    ; BOOT_INFO_FB_HEIGHT (offset 44)
    mov edx, [rdi + 44]
    mov [fb_height], edx

    ; BOOT_INFO_FB_PITCH (offset 48)
    mov r8d, [rdi + 48]
    mov [fb_pitch], r8d

    ; BOOT_INFO_FB_FORMAT (offset 52)
    mov r9d, [rdi + 52]
    mov [fb_format], r9d

    ; 3. Print Framebuffer detected info
    mov rsi, msg_fb_detect
    call uart_print_str
    
    mov rax, [fb_phys_addr]
    call uart_print_hex64
    
    mov rsi, msg_fb_res
    call uart_print_str
    
    mov eax, [fb_width]
    call uart_print_hex64
    
    mov rsi, msg_x
    call uart_print_str
    
    mov eax, [fb_height]
    call uart_print_hex64
    
    mov rsi, msg_crlf
    call uart_print_str

    ; 4. Calculate size in bytes
    mov eax, [fb_height]
    mov ecx, [fb_pitch]
    mul ecx                         ; EDX:EAX = height * pitch
    shl rdx, 32
    or rax, rdx                     ; RAX = total size in bytes
    
    ; Page-align size
    add rax, 4095
    and rax, -4096
    mov [fb_size], rax

    ; 5. Find Write-Combining index dynamically via PAT configuration
    mov rdi, 1                      ; type 1 = Write-Combining (WC)
    call pat_find_entry
    cmp rax, -1
    je .no_wc_found

    ; Decode PAT index into caching flags
    ; RAX holds index (0-7)
    xor r12, r12                    ; R12 = paging flags accumulator
    
    test rax, 1                     ; PWT (bit 0 of PAT index)
    jz .pwt_clear
    or r12, PAGE_PWT
.pwt_clear:
    test rax, 2                     ; PCD (bit 1 of PAT index)
    jz .pcd_clear
    or r12, PAGE_PCD
.pcd_clear:
    test rax, 4                     ; PAT (bit 2 of PAT index)
    jz .pat_clear
    or r12, PAGE_PAT
.pat_clear:
    mov [fb_wc_flags], r12
    jmp .create_wc_vma

.no_wc_found:
    ; Fallback to standard Uncached Minus / Uncached (PCD=1, PWT=1 -> PAT index 3)
    mov rsi, msg_fb_no_wc
    call uart_print_str
    mov r12, PAGE_PCD | PAGE_PWT
    mov [fb_wc_flags], r12

.create_wc_vma:
    ; 6. Create VMA for WC mapping range
    mov rdi, FB_VIRT_BASE
    mov rsi, [fb_size]
    mov rdx, 3                      ; VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .fail_vma
    mov [fb_wc_vma], rax

    ; 7. Map virtual pages
    xor r13, r13                    ; R13 = byte offset
    mov r14, [fb_phys_addr]         ; R14 = physical base
    mov r15, [fb_size]              ; R15 = total size

.map_loop:
    cmp r13, r15
    jae .map_done

    mov rdi, FB_VIRT_BASE
    add rdi, r13                    ; RDI = virtual page address
    mov rsi, r14
    add rsi, r13                    ; RSI = physical page address
    mov rdx, PAGE_PRESENT | PAGE_WRITABLE
    or rdx, [fb_wc_flags]           ; RDX = map flags
    call virt_map
    test rax, rax
    jz .fail_map

    add r13, 4096
    jmp .map_loop

.map_done:
    mov qword [fb_virt_addr], FB_VIRT_BASE
    mov byte [fb_mapped_wc], 1
    
    mov rsi, msg_fb_mapped_wc
    call uart_print_str
    mov rax, FB_VIRT_BASE
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str
    
    mov rax, 1
    jmp .done

.fail_no_bootinfo:
    mov rsi, msg_err_bootinfo
    call uart_print_str
    xor rax, rax
    jmp .done

.fail_no_fb:
    mov rsi, msg_err_no_fb
    call uart_print_str
    mov rax, 2                      ; 2 = skipped gracefully
    jmp .done

.fail_vma:
    mov rsi, msg_err_vma
    call uart_print_str
    xor rax, rax
    jmp .done

.fail_map:
    mov rsi, msg_err_map
    call uart_print_str
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fb_map_uc — maps the framebuffer in Uncached (UC) mode
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global fb_map_uc
fb_map_uc:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; 1. Find UC index dynamically in PAT
    mov rdi, 0                      ; type 0 = Uncached (UC)
    call pat_find_entry
    cmp rax, -1
    je .no_uc_found

    xor r12, r12
    test rax, 1
    jz .pwt_clear
    or r12, PAGE_PWT
.pwt_clear:
    test rax, 2
    jz .pcd_clear
    or r12, PAGE_PCD
.pcd_clear:
    test rax, 4
    jz .pat_clear
    or r12, PAGE_PAT
.pat_clear:
    mov [fb_uc_flags], r12
    jmp .create_uc_vma

.no_uc_found:
    ; Fallback to default UC MSR index flags (PCD=1, PWT=1)
    mov r12, PAGE_PCD | PAGE_PWT
    mov [fb_uc_flags], r12

.create_uc_vma:
    mov rdi, FB_VIRT_UC_BASE
    mov rsi, [fb_size]
    mov rdx, 3
    call vma_create
    test rax, rax
    jz .fail
    mov [fb_uc_vma], rax

    ; Map pages
    xor r13, r13
    mov r14, [fb_phys_addr]
    mov r15, [fb_size]

.map_loop:
    cmp r13, r15
    jae .map_done

    mov rdi, FB_VIRT_UC_BASE
    add rdi, r13
    mov rsi, r14
    add rsi, r13
    mov rdx, PAGE_PRESENT | PAGE_WRITABLE
    or rdx, [fb_uc_flags]
    call virt_map
    test rax, rax
    jz .fail

    add r13, 4096
    jmp .map_loop

.map_done:
    mov byte [fb_mapped_uc], 1
    mov rax, 1
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fb_unmap_uc — unmaps the Uncached framebuffer and destroys its VMA
; -----------------------------------------------------------------------------
global fb_unmap_uc
fb_unmap_uc:
    push r13
    push r15

    cmp byte [fb_mapped_uc], 1
    jne .done

    xor r13, r13
    mov r15, [fb_size]

.unmap_loop:
    cmp r13, r15
    jae .unmap_done

    mov rdi, FB_VIRT_UC_BASE
    add rdi, r13
    call virt_unmap

    add r13, 4096
    jmp .unmap_loop

.unmap_done:
    ; Destroy VMA
    mov rdi, [fb_uc_vma]
    test rdi, rdi
    jz .no_vma
    call vma_destroy
    mov qword [fb_uc_vma], 0

.no_vma:
    mov byte [fb_mapped_uc], 0

.done:
    pop r15
    pop r13
    ret

; -----------------------------------------------------------------------------
; fb_benchmark — timing benchmark for Write-Combining vs Uncached writes
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global fb_benchmark
fb_benchmark:
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    ; 1. Ensure WC mapping exists
    cmp byte [fb_mapped_wc], 1
    je .have_wc
    call fb_init
    test rax, rax
    jz .error

.have_wc:
    ; 2. Ensure UC mapping exists
    call fb_map_uc
    test rax, rax
    jz .error

    ; 3. Run Benchmark - Write-Combining block copy timing
    mov rsi, msg_bench_start
    call uart_print_str

    ; Perform a cache-invalidate to clear memory system states
    wbinvd

    ; Timing loop WC
    cli                             ; disable interrupts for precise measurement
    
    rdtsc                           ; EDX:EAX = cycle counter
    shl rdx, 32
    or rax, rdx
    mov r12, rax                    ; R12 = start cycles

    ; Fill 1MB block sequentially under WC
    mov rdi, [fb_virt_addr]
    mov rcx, BENCH_SIZE_DWORDS
    mov eax, 0x00FF00FF             ; test color pattern
    cld
    rep stosd                       ; fast block fill

    rdtsc
    shl rdx, 32
    or rax, rdx                     ; RAX = end cycles
    
    sub rax, r12                    ; RAX = WC cycles
    mov [fb_wc_cycles], rax

    ; Timing loop UC
    wbinvd                          ; reset cache/bus state
    
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov r12, rax                    ; R12 = start cycles

    ; Fill 1MB block sequentially under UC
    mov rdi, FB_VIRT_UC_BASE
    mov rcx, BENCH_SIZE_DWORDS
    mov eax, 0x00FF00FF
    cld
    rep stosd

    rdtsc
    shl rdx, 32
    or rax, rdx                     ; RAX = end cycles
    
    sub rax, r12                    ; RAX = UC cycles
    mov [fb_uc_cycles], rax

    sti                             ; re-enable interrupts

    ; 4. Clean up UC mapping
    call fb_unmap_uc

    ; 5. Print results
    mov rsi, msg_wc_res
    call uart_print_str
    mov rax, [fb_wc_cycles]
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    mov rsi, msg_uc_res
    call uart_print_str
    mov rax, [fb_uc_cycles]
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_str

    ; 6. Verify WC is faster
    mov rax, [fb_wc_cycles]
    mov rbx, [fb_uc_cycles]
    cmp rax, rbx
    jae .fail_speed

    mov rsi, msg_bench_passed
    call uart_print_str
    mov rax, 1
    jmp .done

.fail_speed:
    mov rsi, msg_bench_failed
    call uart_print_str
    xor rax, rax
    jmp .done

.error:
    mov rsi, msg_err_bench
    call uart_print_str
    xor rax, rax

.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

section .data

; Variables
global fb_phys_addr
global fb_virt_addr
global fb_size
global fb_width
global fb_height
global fb_pitch
global fb_format

fb_phys_addr:   dq 0
fb_virt_addr:   dq 0
fb_size:        dq 0
fb_width:       dd 0
fb_height:      dd 0
fb_pitch:       dd 0
fb_format:      dd 0

fb_wc_flags:    dq 0
fb_uc_flags:    dq 0

fb_wc_vma:      dq 0
fb_uc_vma:      dq 0

fb_mapped_wc:   db 0
fb_mapped_uc:   db 0

fb_wc_cycles:   dq 0
fb_uc_cycles:   dq 0

; Log Messages
msg_fb_detect:      db "Framebuffer detected at: ", 0
msg_fb_res:         db " resolution: ", 0
msg_x:              db "x", 0
msg_fb_mapped_wc:   db "Framebuffer mapped WC at virtual: ", 0
msg_fb_no_wc:       db "Warning: WC not found in PAT, falling back to UC", 0x0D, 0x0A, 0

msg_bench_start:    db "Running Write-Combining vs Uncached video buffer write benchmark...", 0x0D, 0x0A, 0
msg_wc_res:         db "WC write (1MB): ", 0
msg_uc_res:         db "UC write (1MB): ", 0
msg_bench_passed:   db "Write-Combining benchmark PASSED (WC is faster than UC).", 0x0D, 0x0A, 0
msg_bench_failed:   db "Write-Combining benchmark FAILED (WC is not faster than UC).", 0x0D, 0x0A, 0

msg_err_bootinfo:   db "Error: boot_info_ptr not set.", 0x0D, 0x0A, 0
msg_err_no_fb:      db "Error: Framebuffer not reported by bootloader.", 0x0D, 0x0A, 0
msg_err_vma:        db "Error: Failed to create framebuffer VMA range.", 0x0D, 0x0A, 0
msg_err_map:        db "Error: Page mapping failed during framebuffer initialization.", 0x0D, 0x0A, 0
msg_err_bench:      db "Error: Framebuffer mapping failure during benchmark setup.", 0x0D, 0x0A, 0

msg_crlf:           db 0x0D, 0x0A, 0

%endif ; KERNEL_DRIVERS_GPU_FB_ASM
