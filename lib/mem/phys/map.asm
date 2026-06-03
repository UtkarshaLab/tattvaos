; =============================================================================
; Tattva OS — lib/mem/phys/map.asm
; =============================================================================
; E820 memory map parser. Finds maximum physical RAM and total system pages.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_PHYS_MAP_ASM
%define LIB_MEM_PHYS_MAP_ASM

[BITS 64]

; -----------------------------------------------------------------------------
; phys_parse_e820 — parses the E820 map to locate the maximum usable RAM
;                    address and count total usable physical pages.
; Input:
;   RDI = physical pointer to the E820 map base
;   RSI = number of entries in the E820 map
; Output:
;   RAX = maximum physical RAM address detected
;   RCX = total usable physical pages count
; Clobbers: R8, R9, R10, R11
; -----------------------------------------------------------------------------
phys_parse_e820:
    push rbx
    push rdx

    xor rax, rax                    ; max address (initially 0)
    xor rcx, rcx                    ; total usable page count (initially 0)
    xor rdx, rdx                    ; loop counter (index)

.loop:
    cmp rdx, rsi
    jge .done

    ; Calculate pointer to current entry: RDI + RDX * 24 (sizeof(e820_entry))
    mov r8, rdx
    imul r8, 24
    add r8, rdi

    ; Read entry type (offset 16)
    mov r9d, [r8 + e820_entry.type]
    cmp r9d, 1                      ; type == 1 (usable RAM)?
    jne .next

    ; Read base address (offset 0) and length (offset 8)
    mov r10, [r8 + e820_entry.base]
    mov r11, [r8 + e820_entry.length]

    ; Calculate end address of the region: base + length
    mov rbx, r10
    add rbx, r11

    ; Check if this end address is higher than current max address
    cmp rbx, rax
    jbe .calc_pages
    mov rax, rbx                    ; update max physical address

.calc_pages:
    ; Count usable pages in this entry: length / 4096 (shr 12)
    shr r11, 12
    add rcx, r11

.next:
    inc rdx
    jmp .loop

.done:
    pop rdx
    pop rbx
    ret

%endif ; LIB_MEM_PHYS_MAP_ASM
