; =============================================================================
; Tattva OS — lib/mem/virt/zswap.asm
; =============================================================================
; Zswap compressed cache pool and PackBits Run-Length Encoding.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ZSWAP_ASM
%define LIB_MEM_VIRT_ZSWAP_ASM

[BITS 64]

; Zswap configuration
ZSWAP_MAX_SLOTS   equ 256
ZSWAP_MAX_FRAMES  equ (ZSWAP_MAX_SLOTS / 2)  ; 128 frames (2 slots per frame)
ZSWAP_SLOT_SIZE   equ 2048

section .text

; External symbols
extern phys_alloc_page
extern phys_free_page
extern memcpy

; -----------------------------------------------------------------------------
; zswap_init — initializes the Zswap cache metadata
; -----------------------------------------------------------------------------
global zswap_init
zswap_init:
    push rdi
    push rcx
    push rax

    ; Set zswap_compressed_pages to 0
    mov qword [zswap_compressed_pages], 0

    ; Zero-out zswap_in_use
    lea rdi, [zswap_in_use]
    mov rcx, ZSWAP_MAX_SLOTS
    xor rax, rax
    cld
    rep stosb

    ; Zero-out zswap_sizes
    lea rdi, [zswap_sizes]
    mov rcx, ZSWAP_MAX_SLOTS
    rep stosw

    ; Zero-out zswap_frames
    lea rdi, [zswap_frames]
    mov rcx, ZSWAP_MAX_FRAMES
    rep stosq

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; zswap_compress_and_store — attempts to compress a page and store in zpool
; Input:
;   RDI = src_phys (source physical address of the 4KB page)
; Output:
;   RAX = slot index (0-255) on success, or -1 on failure/uncompressible
; -----------------------------------------------------------------------------
global zswap_compress_and_store
zswap_compress_and_store:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = src_phys

    ; 1. Compress the page into the scratch buffer
    mov rdi, r12                    ; src
    lea rsi, [zswap_scratch]        ; dest
    mov rdx, ZSWAP_SLOT_SIZE        ; max_len (2048)
    call rle_compress               ; RAX = compressed size, or 0 if exceeded

    test rax, rax
    jz .failed                      ; compression failed or size > 2048

    mov r13, rax                    ; R13 = compressed size

    ; 2. Find a free slot in the zpool
    xor rbx, rbx                    ; RBX = slot index loop counter
.slot_loop:
    cmp rbx, ZSWAP_MAX_SLOTS
    jge .failed                     ; no free slot!

    lea rcx, [zswap_in_use]
    mov al, [rcx + rbx]
    test al, al
    jz .slot_found                  ; found unused slot

    inc rbx
    jmp .slot_loop

.slot_found:
    ; R14 = F = S / 2 (frame index)
    mov r14, rbx
    shr r14, 1                      ; r14 = frame index
    
    ; R15 = O = (S % 2) * 2048 (offset)
    mov r15, rbx
    and r15, 1                      ; S % 2
    shl r15, 11                     ; multiply by 2048

    ; Check if the frame is allocated
    lea rcx, [zswap_frames]
    mov r8, [rcx + r14 * 8]
    test r8, r8
    jnz .frame_allocated

    ; Allocate physical frame for pair
    call phys_alloc_page
    test rax, rax
    jz .failed                      ; OOM!
    
    lea rcx, [zswap_frames]
    mov [rcx + r14 * 8], rax
    mov r8, rax                     ; R8 = new frame physical address

.frame_allocated:
    ; Dest address = frame + offset
    add r8, r15                     ; R8 = dest address

    ; Copy compressed data from scratch to zpool slot
    mov rdi, r8                     ; dest
    lea rsi, [zswap_scratch]        ; src
    mov rdx, r13                    ; size
    call memcpy

    ; Update slot metadata
    lea rcx, [zswap_in_use]
    mov byte [rcx + rbx], 1         ; mark slot in use
    
    lea rcx, [zswap_sizes]
    mov [rcx + rbx * 2], r13w       ; save compressed size (word)

    inc qword [zswap_compressed_pages] ; increment telemetry

    mov rax, rbx                    ; return slot index
    jmp .done

.failed:
    mov rax, -1

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zswap_decompress_and_free — decompresses a slot to page and frees slot
; Input:
;   RDI = slot index S
;   RSI = dest_phys (destination physical address of 4KB page)
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global zswap_decompress_and_free
zswap_decompress_and_free:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = slot index S
    mov r12, rsi                    ; R12 = dest_phys

    ; Validate slot index
    cmp rbx, ZSWAP_MAX_SLOTS
    jae .err

    lea rcx, [zswap_in_use]
    mov al, [rcx + rbx]
    test al, al
    jz .err                         ; slot not in use

    ; F = S / 2 (frame index)
    mov r13, rbx
    shr r13, 1                      ; r13 = frame index

    ; O = (S % 2) * 2048 (offset)
    mov r14, rbx
    and r14, 1
    shl r14, 11                     ; multiply by 2048

    ; Get physical address of frame
    lea rcx, [zswap_frames]
    mov r15, [rcx + r13 * 8]
    test r15, r15
    jz .err                         ; frame should be allocated!

    ; Source address = frame + offset
    add r15, r14                    ; R15 = src compressed pointer

    ; Get compressed size
    lea rcx, [zswap_sizes]
    xor rdx, rdx
    mov dx, [rcx + rbx * 2]         ; RDX = size

    ; Decompress
    mov rdi, r15                    ; src
    mov rsi, r12                    ; dest (4KB page)
    call rle_decompress
    test rax, rax
    jz .err                         ; decompression failed!

    ; Free the slot
    mov rdi, rbx
    call zswap_free_slot

    mov rax, 1                      ; success
    jmp .done

.err:
    xor rax, rax                    ; fail

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; zswap_free_slot — releases a slot metadata and companion frame if now empty
; Input:
;   RDI = slot index S
; -----------------------------------------------------------------------------
global zswap_free_slot
zswap_free_slot:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = slot index S

    ; Validate
    cmp rbx, ZSWAP_MAX_SLOTS
    jae .exit

    lea rcx, [zswap_in_use]
    mov al, [rcx + rbx]
    test al, al
    jz .exit                         ; already free

    ; Mark free
    mov byte [rcx + rbx], 0
    dec qword [zswap_compressed_pages] ; decrement telemetry

    ; F = S / 2
    mov r12, rbx
    shr r12, 1                      ; frame index

    ; Check companion slot (S ^ 1)
    mov r13, rbx
    xor r13, 1                      ; companion slot
    mov al, [rcx + r13]
    test al, al
    jnz .exit                       ; companion slot is still in use, keep frame

    ; Companion is also free! Free the physical page frame
    lea rcx, [zswap_frames]
    mov rdi, [rcx + r12 * 8]
    test rdi, rdi
    jz .exit

    call phys_free_page
    
    lea rcx, [zswap_frames]
    mov qword [rcx + r12 * 8], 0

.exit:
    pop r13
    pop r12
    pop rbx
    ret

; =============================================================================
; RLE PackBits Compression & Decompression
; =============================================================================

; -----------------------------------------------------------------------------
; rle_compress — compresses 4096 bytes using PackBits-style RLE
; Input:
;   RDI = src (4KB uncompressed page)
;   RSI = dest (destination buffer)
;   RDX = max_len (limit, 2048)
; Output:
;   RAX = compressed size on success, 0 on overflow/failure
; -----------------------------------------------------------------------------
global rle_compress
rle_compress:
    push r12
    push r13
    push r14
    push r15
    push rbx

    mov r8, rdi                     ; R8 = src pointer
    lea r9, [rdi + 4096]            ; R9 = src end
    mov r10, rsi                    ; R10 = dest pointer
    lea r11, [rsi + rdx]            ; R11 = dest end (max limit)

.loop:
    cmp r8, r9
    jae .done_success

    ; Find run length starting at R8
    mov al, [r8]
    mov rcx, 1                      ; RCX = run count

.find_run:
    mov rdx, r8
    add rdx, rcx
    cmp rdx, r9
    jae .run_found
    cmp rcx, 128                    ; PackBits max run is 128
    jae .run_found

    mov r12b, [rdx]
    cmp r12b, al
    jne .run_found
    inc rcx
    jmp .find_run

.run_found:
    cmp rcx, 3
    jae .write_run

    ; If run length < 3, group into a literal block
    xor rbx, rbx                    ; RBX = literal count

.find_lit:
    mov rdx, r8
    add rdx, rbx
    cmp rdx, r9
    jae .lit_found
    cmp rbx, 128
    jae .lit_found

    ; Check if a run of >= 3 starts at RDX
    mov r13, rdx
    add r13, 1
    cmp r13, r9
    jae .not_a_run
    mov r14, rdx
    add r14, 2
    cmp r14, r9
    jae .not_a_run

    mov r15b, [rdx]
    cmp [rdx + 1], r15b
    jne .not_a_run
    cmp [rdx + 2], r15b
    je .lit_found                   ; found run of >= 3, stop literal block

.not_a_run:
    inc rbx
    jmp .find_lit

.lit_found:
    ; Write literal block of size RBX
    ; Control byte: count - 1
    mov rdx, r10
    add rdx, rbx
    inc rdx                         ; +1 for control byte
    cmp rdx, r11
    jae .failed                     ; out of space!

    mov r12b, bl
    dec r12b
    mov [r10], r12b
    inc r10

.copy_lit_loop:
    test rbx, rbx
    jz .loop
    mov r12b, [r8]
    mov [r10], r12b
    inc r8
    inc r10
    dec rbx
    jmp .copy_lit_loop

.write_run:
    ; Write run block of size RCX
    ; Control byte: 0x80 | (count - 1)
    mov rdx, r10
    add rdx, 2
    cmp rdx, r11
    jae .failed                     ; out of space!

    mov r12b, cl
    dec r12b
    or r12b, 0x80
    mov [r10], r12b
    inc r10

    mov [r10], al
    inc r10

    add r8, rcx
    jmp .loop

.done_success:
    mov rax, r10
    sub rax, rsi                    ; return size
    jmp .exit

.failed:
    xor rax, rax                    ; return 0

.exit:
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; rle_decompress — decompresses data from PackBits RLE stream to 4096-byte page
; Input:
;   RDI = src (compressed data)
;   RSI = dest (decompressed buffer, 4096 bytes)
;   RDX = compressed_len
; Output:
;   RAX = decompressed size (4096 on success, 0 on failure)
; -----------------------------------------------------------------------------
global rle_decompress
rle_decompress:
    push r12
    push rbx

    mov r8, rdi                     ; R8 = src pointer
    lea r9, [rdi + rdx]            ; R9 = src end
    mov r10, rsi                    ; R10 = dest pointer
    lea r11, [rsi + 4096]           ; R11 = dest end

.loop:
    cmp r8, r9
    jae .done_success

    xor rax, rax
    mov al, [r8]                    ; control byte
    inc r8

    test al, 0x80
    jnz .decompress_run

    ; Literal block: count = al + 1
    mov rcx, rax
    inc rcx

    ; Space checks
    mov rbx, r10
    add rbx, rcx
    cmp rbx, r11
    jae .failed                     ; decompressed size > 4096

    mov rbx, r8
    add rbx, rcx
    cmp rbx, r9
    jae .failed                     ; truncated input

.copy_lit:
    test rcx, rcx
    jz .loop
    mov r12b, [r8]
    mov [r10], r12b
    inc r8
    inc r10
    dec rcx
    jmp .copy_lit

.decompress_run:
    ; Run block: count = (al & 0x7F) + 1
    and al, 0x7F
    mov rcx, rax
    inc rcx

    ; Read value byte
    cmp r8, r9
    jae .failed                     ; missing run value byte
    mov r12b, [r8]
    inc r8

    ; Space checks
    mov rbx, r10
    add rbx, rcx
    cmp rbx, r11
    jae .failed                     ; decompressed size > 4096

.write_run:
    test rcx, rcx
    jz .loop
    mov [r10], r12b
    inc r10
    dec rcx
    jmp .write_run

.done_success:
    mov rax, r10
    sub rax, rsi
    cmp rax, 4096
    jne .failed                     ; must decompress to exactly 4096 bytes

    mov rax, 4096
    jmp .exit

.failed:
    xor rax, rax

.exit:
    pop rbx
    pop r12
    ret

; =============================================================================
; Data and Pools
; =============================================================================
section .data

; Telemetry Counter
global zswap_compressed_pages
align 8
zswap_compressed_pages: dq 0

section .bss

; Slot Allocation Metadata
zswap_in_use:  resb ZSWAP_MAX_SLOTS
align 2
zswap_sizes:   resw ZSWAP_MAX_SLOTS
align 8
zswap_frames:  resq ZSWAP_MAX_FRAMES

; Thread-safe static scratch buffer for compression (page size limit is 2048 for zswap)
align 16
zswap_scratch: resb ZSWAP_SLOT_SIZE

%endif ; LIB_MEM_VIRT_ZSWAP_ASM
