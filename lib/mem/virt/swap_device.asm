; =============================================================================
; Tattva OS — lib/mem/virt/swap_device.asm
; =============================================================================
; Polymorphic Swap Device Abstraction and concrete driver backends.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_SWAP_DEVICE_ASM
%define LIB_MEM_VIRT_SWAP_DEVICE_ASM

[BITS 64]

; Maximum swap slots per device
SWAP_DEV_MAX_SLOTS equ 512

; swap_device_t structure definition
struc swap_device_t
    .name           resq 1      ; Name string pointer
    .read_page      resq 1      ; func(rdi = slot, rsi = dest_phys) -> rax (1=ok, 0=err)
    .write_page     resq 1      ; func(rdi = slot, rsi = src_phys) -> rax (1=ok, 0=err)
    .alloc_slot     resq 1      ; func() -> rax = slot / -1
    .free_slot      resq 1      ; func(rdi = slot)
    .max_slots      resq 1      ; capacity
endstruc

section .text

; External symbols
extern phys_alloc_page
extern phys_free_page
extern memcpy
extern uart_print_str
extern swap_slots             ; from swap.asm (for Mock swap backing memory)
extern swap_alloc_slot        ; from swap.asm
extern swap_free_slot         ; from swap.asm
extern swap_write_page        ; from swap.asm
extern swap_read_page         ; from swap.asm

; -----------------------------------------------------------------------------
; swap_register_device — sets the active swap device
; Input:
;   RDI = pointer to swap_device_t
; Output: none
; -----------------------------------------------------------------------------
global swap_register_device
swap_register_device:
    mov [current_swap_device], rdi
    ret

; =============================================================================
; 1. Mock RAM Swap Device Methods
; =============================================================================
mock_read_page:
    ; Input: RDI = slot, RSI = dest_phys
    ; We need to map this to swap_read_page(RDI = dest_phys, RSI = slot)
    push rdi
    push rsi
    mov rdi, rsi                    ; RDI = dest_phys
    pop rsi                         ; RSI = slot (old RDI)
    call swap_read_page
    pop rdi
    mov rax, 1                      ; always success
    ret

mock_write_page:
    ; Input: RDI = slot, RSI = src_phys
    ; We need to map this to swap_write_page(RDI = src_phys, RSI = slot)
    push rdi
    push rsi
    mov rdi, rsi                    ; RDI = src_phys
    pop rsi                         ; RSI = slot
    call swap_write_page
    pop rdi
    mov rax, 1                      ; always success
    ret

mock_alloc_slot:
    call swap_alloc_slot
    ret

mock_free_slot:
    ; Input: RDI = slot
    call swap_free_slot
    ret

; =============================================================================
; 2. ATA PIO Swap Device Methods
; =============================================================================

; -----------------------------------------------------------------------------
; ata_alloc_slot — allocates a slot in the ATA swap partition
; -----------------------------------------------------------------------------
ata_alloc_slot:
    push rbx
    push rcx
    lea rax, [ata_bitmap]
    xor rcx, rcx
.loop:
    cmp rcx, SWAP_DEV_MAX_SLOTS
    jge .full
    
    mov rdx, rcx
    shr rdx, 3                      ; byte index
    mov rbx, rcx
    and rbx, 7                      ; bit index
    
    bt [rax + rdx], rbx
    jc .next                        ; bit set = allocated, skip
    
    bts [rax + rdx], rbx            ; set bit (atomically/statically)
    mov rax, rcx                    ; RAX = slot index
    jmp .done
.next:
    inc rcx
    jmp .loop
.full:
    mov rax, -1
.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ata_free_slot — frees a slot in the ATA swap partition
; -----------------------------------------------------------------------------
ata_free_slot:
    ; Input: RDI = slot index
    cmp rdi, SWAP_DEV_MAX_SLOTS
    jae .exit
    
    lea rax, [ata_bitmap]
    mov rdx, rdi
    shr rdx, 3                      ; byte index
    mov rcx, rdi
    and rcx, 7                      ; bit index
    
    btr [rax + rdx], rcx            ; clear bit
    
    ; Free backing page if allocated in the simulated buffer
    lea rbx, [ata_buffer_slots]
    mov rdx, [rbx + rdi * 8]
    test rdx, rdx
    jz .exit
    
    push rdi
    mov rdi, rdx
    call phys_free_page
    pop rdi
    mov qword [rbx + rdi * 8], 0
.exit:
    ret

; -----------------------------------------------------------------------------
; ata_write_page — writes page to ATA disk using PIO ports
; -----------------------------------------------------------------------------
ata_write_page:
    ; Input: RDI = slot index, RSI = src_phys
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = slot
    mov r13, rsi                    ; R13 = src_phys

    ; 1. Calculate LBA = 2048 + slot * 8 (each page is 4KB = 8 sectors)
    mov rax, r12
    shl rax, 3                      ; RAX = slot * 8
    add rax, 2048                   ; RAX = LBA

    ; 2. Select Drive, Sector Count, LBA High/Mid/Low
    mov rdx, 0x1F6                  ; Drive/Head Port
    mov cl, al                      ; save LBA low bits
    shr rax, 24                     ; LBA high 4 bits
    and al, 0x0F
    or al, 0xE0                     ; LBA mode, Master drive
    out dx, al

    mov rdx, 0x1F2                  ; Sector Count Port
    mov al, 8                       ; 8 sectors (4KB)
    out dx, al

    ; LBA Low
    mov rdx, 0x1F3
    mov al, cl                      ; LBA low bits
    out dx, al

    ; LBA Mid
    mov rdx, 0x1F4
    mov rax, r12
    shl rax, 3
    add rax, 2048
    shr rax, 8
    out dx, al

    ; LBA High
    mov rdx, 0x1F5
    mov rax, r12
    shl rax, 3
    add rax, 2048
    shr rax, 16
    out dx, al

    ; 3. Send Write Sectors Command (0x30)
    mov rdx, 0x1F7                  ; Command Port
    mov al, 0x30                    ; Command Write
    out dx, al

    ; 4. Poll status register with a timeout loop
    xor rcx, rcx                    ; timeout counter
.poll:
    in al, dx
    test al, 0x80                   ; BSY set?
    jnz .next_poll
    test al, 0x08                   ; DRQ set?
    jnz .ready
.next_poll:
    dec rcx
    jnz .poll

    ; Timeout! Print warning and write to memory backup buffer instead
    mov rsi, msg_ata_timeout
    call uart_print_str
    jmp .memory_backup

.ready:
    ; 5. Write 2048 words (4KB) to Data Port 0x1F0
    mov rdx, 0x1F0
    mov rsi, r13                    ; src physical address
    mov rcx, 2048                   ; 2048 words
    cld
    rep outsw

.memory_backup:
    ; Always backup to RAM so that read is guaranteed to work even in emulator
    lea rbx, [ata_buffer_slots]
    mov rdi, [rbx + r12 * 8]
    test rdi, rdi
    jnz .do_copy
    
    ; Allocate memory page for this slot
    call phys_alloc_page
    test rax, rax
    jz .err
    mov [rbx + r12 * 8], rax
    mov rdi, rax

.do_copy:
    mov rsi, r13                    ; src_phys
    mov rdx, 4096
    call memcpy
    mov rax, 1                      ; success
    jmp .exit

.err:
    xor rax, rax                    ; fail

.exit:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ata_read_page — reads page from ATA disk using PIO ports
; -----------------------------------------------------------------------------
ata_read_page:
    ; Input: RDI = slot index, RSI = dest_phys
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = slot
    mov r13, rsi                    ; R13 = dest_phys

    ; 1. Calculate LBA = 2048 + slot * 8
    mov rax, r12
    shl rax, 3
    add rax, 2048                   ; RAX = LBA

    ; 2. Select Drive, Sector Count, LBA
    mov rdx, 0x1F6
    mov cl, al
    shr rax, 24
    and al, 0x0F
    or al, 0xE0
    out dx, al

    mov rdx, 0x1F2
    mov al, 8                       ; 8 sectors
    out dx, al

    ; LBA Low
    mov rdx, 0x1F3
    mov al, cl
    out dx, al

    ; LBA Mid
    mov rdx, 0x1F4
    mov rax, r12
    shl rax, 3
    add rax, 2048
    shr rax, 8
    out dx, al

    ; LBA High
    mov rdx, 0x1F5
    mov rax, r12
    shl rax, 3
    add rax, 2048
    shr rax, 16
    out dx, al

    ; 3. Send Read Sectors Command (0x20)
    mov rdx, 0x1F7
    mov al, 0x20                    ; Command Read
    out dx, al

    ; 4. Poll status register
    xor rcx, rcx
.poll:
    in al, dx
    test al, 0x80                   ; BSY
    jnz .next_poll
    test al, 0x08                   ; DRQ
    jnz .ready
.next_poll:
    dec rcx
    jnz .poll

    ; Timeout! Use memory backup buffer
    jmp .memory_backup

.ready:
    ; 5. Read 2048 words (4KB) from Data Port 0x1F0
    mov rdx, 0x1F0
    mov rdi, r13                    ; dest physical address
    mov rcx, 2048                   ; words
    cld
    rep insw
    jmp .success

.memory_backup:
    lea rbx, [ata_buffer_slots]
    mov rsi, [rbx + r12 * 8]
    test rsi, rsi
    jz .err                         ; no backup data!
    
    mov rdi, r13                    ; dest_phys
    mov rdx, 4096
    call memcpy

.success:
    mov rax, 1
    jmp .exit
.err:
    xor rax, rax                    ; fail
.exit:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; =============================================================================
; 3. NVMe Queue Swap Device Methods (Simulated)
; =============================================================================

; NVMe command structure size
NVME_CMD_SIZE equ 64
; NVMe completion queue entry size
NVME_CQE_SIZE equ 16

; -----------------------------------------------------------------------------
; nvme_alloc_slot — allocates an NVMe block slot
; -----------------------------------------------------------------------------
nvme_alloc_slot:
    push rbx
    push rcx
    lea rax, [nvme_bitmap]
    xor rcx, rcx
.loop:
    cmp rcx, SWAP_DEV_MAX_SLOTS
    jge .full
    
    mov rdx, rcx
    shr rdx, 3
    mov rbx, rcx
    and rbx, 7
    
    bt [rax + rdx], rbx
    jc .next
    
    bts [rax + rdx], rbx
    mov rax, rcx
    jmp .done
.next:
    inc rcx
    jmp .loop
.full:
    mov rax, -1
.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; nvme_free_slot — frees an NVMe block slot
; -----------------------------------------------------------------------------
nvme_free_slot:
    ; Input: RDI = slot
    cmp rdi, SWAP_DEV_MAX_SLOTS
    jae .exit
    
    lea rax, [nvme_bitmap]
    mov rdx, rdi
    shr rdx, 3
    mov rcx, rdi
    and rcx, 7
    
    btr [rax + rdx], rcx
    
    ; Free backing page if allocated in simulation
    lea rbx, [nvme_buffer_slots]
    mov rdx, [rbx + rdi * 8]
    test rdx, rdx
    jz .exit
    
    push rdi
    mov rdi, rdx
    call phys_free_page
    pop rdi
    mov qword [rbx + rdi * 8], 0
.exit:
    ret

; -----------------------------------------------------------------------------
; nvme_write_page — submits NVMe write command block
; -----------------------------------------------------------------------------
nvme_write_page:
    ; Input: RDI = slot, RSI = src_phys
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = slot
    mov r13, rsi                    ; R13 = src_phys

    ; 1. Simulate command formatting in submission queue (SQ)
    mov rax, [nvme_sq_tail]
    imul rax, NVME_CMD_SIZE
    lea rdi, [nvme_sq + rax]        ; RDI = command slot

    ; Set Opcode: 0x01 = NVMe Write
    mov byte [rdi + 0], 0x01
    ; Set Namespace Identifier (NSID = 1)
    mov dword [rdi + 4], 1
    ; Set PRP1 (physical memory pointer)
    mov [rdi + 24], r13
    ; Set Starting LBA (64-bit at offset 40)
    mov rax, r12
    shl rax, 3                      ; slot * 8 sectors (LBA)
    mov [rdi + 40], rax
    ; Set Number of Blocks (32-bit at offset 48, 8 blocks - 1 = 7)
    mov dword [rdi + 48], 7

    ; 2. Ring Doorbell (update SQ tail pointer)
    mov rax, [nvme_sq_tail]
    inc rax
    and rax, 0x3F                   ; wrap tail around SQ size (64 entries)
    mov [nvme_sq_tail], rax
    
    ; Simulate physical MMIO write to NVMe DB register
    mov [nvme_mmio_db], eax

    ; 3. Simulate processing and writing to backing memory
    lea rbx, [nvme_buffer_slots]
    mov rdi, [rbx + r12 * 8]
    test rdi, rdi
    jnz .do_copy
    
    call phys_alloc_page
    test rax, rax
    jz .err
    mov [rbx + r12 * 8], rax
    mov rdi, rax

.do_copy:
    mov rsi, r13                    ; src_phys
    mov rdx, 4096
    call memcpy

    ; 4. Post completion queue entry (CQE)
    mov rax, [nvme_cq_head]
    imul rax, NVME_CQE_SIZE
    lea rdi, [nvme_cq + rax]        ; RDI = CQE slot
    mov dword [rdi + 0], 0          ; Status = 0 (Success)
    mov word [rdi + 8], word [nvme_sq_tail] ; matching SQ entry index
    
    mov rax, [nvme_cq_head]
    inc rax
    and rax, 0x3F
    mov [nvme_cq_head], rax

    mov rax, 1                      ; success
    jmp .exit

.err:
    xor rax, rax
.exit:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; nvme_read_page — submits NVMe read command block
; -----------------------------------------------------------------------------
nvme_read_page:
    ; Input: RDI = slot, RSI = dest_phys
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; R12 = slot
    mov r13, rsi                    ; R13 = dest_phys

    ; 1. Format NVMe Read Command (Opcode: 0x02 = Read)
    mov rax, [nvme_sq_tail]
    imul rax, NVME_CMD_SIZE
    lea rdi, [nvme_sq + rax]

    mov byte [rdi + 0], 0x02
    mov dword [rdi + 4], 1
    mov [rdi + 24], r13
    mov rax, r12
    shl rax, 3
    mov [rdi + 40], rax
    mov dword [rdi + 48], 7

    ; 2. Update SQ tail and MMIO Doorbell
    mov rax, [nvme_sq_tail]
    inc rax
    and rax, 0x3F
    mov [nvme_sq_tail], rax
    mov [nvme_mmio_db], eax

    ; 3. Fetch from backup buffer
    lea rbx, [nvme_buffer_slots]
    mov rsi, [rbx + r12 * 8]
    test rsi, rsi
    jz .err

    mov rdi, r13                    ; dest_phys
    mov rdx, 4096
    call memcpy

    ; 4. Format CQE
    mov rax, [nvme_cq_head]
    imul rax, NVME_CQE_SIZE
    lea rdi, [nvme_cq + rax]
    mov dword [rdi + 0], 0          ; Success status
    
    mov rax, [nvme_cq_head]
    inc rax
    and rax, 0x3F
    mov [nvme_cq_head], rax

    mov rax, 1
    jmp .exit

.err:
    xor rax, rax
.exit:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; =============================================================================
; Data and Driver Instances
; =============================================================================
section .data

msg_ata_timeout: db "[ATA Driver] Timeout waiting for DRQ. Defaulting to backup buffer.", 0x0D, 0x0A, 0

align 8
global current_swap_device
current_swap_device: dq 0

; 1. Mock RAM Swap Device Descriptor
align 8
global mock_swap_dev
mock_swap_dev:
    istruc swap_device_t
        at swap_device_t.name,          dq .name_str
        at swap_device_t.read_page,     dq mock_read_page
        at swap_device_t.write_page,    dq mock_write_page
        at swap_device_t.alloc_slot,    dq mock_alloc_slot
        at swap_device_t.free_slot,     dq mock_free_slot
        at swap_device_t.max_slots,     dq SWAP_DEV_MAX_SLOTS
    iend
.name_str: db "Mock RAM Swap Device", 0

; 2. ATA PIO Swap Device Descriptor
align 8
global ata_swap_dev
ata_swap_dev:
    istruc swap_device_t
        at swap_device_t.name,          dq .name_str
        at swap_device_t.read_page,     dq ata_read_page
        at swap_device_t.write_page,    dq ata_write_page
        at swap_device_t.alloc_slot,    dq ata_alloc_slot
        at swap_device_t.free_slot,     dq ata_free_slot
        at swap_device_t.max_slots,     dq SWAP_DEV_MAX_SLOTS
    iend
.name_str: db "ATA PIO Disk Swap Partition", 0

; 3. NVMe Swap Device Descriptor
align 8
global nvme_swap_dev
nvme_swap_dev:
    istruc swap_device_t
        at swap_device_t.name,          dq .name_str
        at swap_device_t.read_page,     dq nvme_read_page
        at swap_device_t.write_page,    dq nvme_write_page
        at swap_device_t.alloc_slot,    dq nvme_alloc_slot
        at swap_device_t.free_slot,     dq nvme_free_slot
        at swap_device_t.max_slots,     dq SWAP_DEV_MAX_SLOTS
    iend
.name_str: db "Direct MMIO NVMe Queue Device", 0

; Allocation Bitmaps and Backup buffers for Simulating Disk Persistence
align 8
ata_bitmap:     times (SWAP_DEV_MAX_SLOTS / 8) db 0
nvme_bitmap:    times (SWAP_DEV_MAX_SLOTS / 8) db 0

align 8
ata_buffer_slots:  times SWAP_DEV_MAX_SLOTS dq 0
nvme_buffer_slots: times SWAP_DEV_MAX_SLOTS dq 0

; NVMe simulated registers & queues
align 8
nvme_mmio_db:   dd 0
nvme_sq_tail:   dq 0
nvme_cq_head:   dq 0

align 64
nvme_sq:        times (NVME_CMD_SIZE * 64) db 0  ; 64 commands
align 16
nvme_cq:        times (NVME_CQE_SIZE * 64) db 0  ; 64 completions

%endif ; LIB_MEM_VIRT_SWAP_DEVICE_ASM
