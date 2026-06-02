; =============================================================================
; Tattva OS — boot/stage1/entry.asm
; =============================================================================
; MBR bootloader entry point.
; BIOS loads this to 0x7C00, executes from here.
; Must fit in 446 bytes total with all includes.
;
; Responsibilities:
;   1. Initialize segment registers + stack
;   2. Save boot drive number (DL)
;   3. Relocate self to 0x0600 (free up 0x7C00 for stage2 stack)
;   4. Enable A20 line (fast method only, stage2 handles fallbacks)
;   5. Load stage2 from disk to 0x8000
;   6. Verify stage2 magic number
;   7. Jump to stage2
;
; Memory layout at entry:
;   0x0000 - 0x04FF   BIOS data area (do not touch)
;   0x0500 - 0x05FF   free
;   0x0600 - 0x07FF   we relocate here
;   0x7C00 - 0x7DFF   BIOS loaded us here (512 bytes)
;   0x7E00 - 0x7FFF   free
;   0x8000 - 0xFFFF   stage2 loads here
;
; Author:  Utkarsha Labs
; Target:  x86-64, BIOS boot, real mode (16-bit)
; Syntax:  NASM
; =============================================================================

[BITS 16]
[ORG 0x7C00]

; -----------------------------------------------------------------------------
; includes — constants and storage first
; -----------------------------------------------------------------------------
%include "config.asm"
%include "boot_drive.asm"

; =============================================================================
; entry — first instruction the CPU executes after BIOS handoff
; =============================================================================
entry:
    ; -------------------------------------------------------------------------
    ; STEP 1: Initialize segment registers and stack
    ; -------------------------------------------------------------------------
    ; BIOS leaves registers in undefined state.
    ; Must initialize BEFORE anything else.
    ; Works in QEMU without this. Fails on real hardware without this.
    ; -------------------------------------------------------------------------
    cli                             ; disable interrupts during setup

    xor ax, ax                      ; ax = 0
    mov ds, ax                      ; data segment = 0x0000
    mov es, ax                      ; extra segment = 0x0000
    mov ss, ax                      ; stack segment = 0x0000
    mov sp, STACK_REAL              ; stack pointer = 0x7C00
                                    ; stack grows DOWN from here
                                    ; safe: we relocate MBR before using stack heavily

    sti                             ; re-enable interrupts

    ; -------------------------------------------------------------------------
    ; STEP 2: Save boot drive number from DL
    ; -------------------------------------------------------------------------
    ; BIOS puts boot drive number in DL at entry.
    ; ANY INT call can overwrite DL.
    ; Save it to memory IMMEDIATELY — before any INT call of any kind.
    ; This is the #1 cause of bootloaders failing on real hardware.
    ; -------------------------------------------------------------------------
    mov [boot_drive], dl            ; save drive number now

    ; -------------------------------------------------------------------------
    ; STEP 3: Relocate MBR from 0x7C00 to 0x0600
    ; -------------------------------------------------------------------------
    ; Why: BIOS loads stage2 to 0x8000. Stage2 needs stack space below 0x8000.
    ;      If MBR stays at 0x7C00, the stack would collide with it.
    ;      Relocating to 0x0600 frees the 0x7C00-0x7FFF region for the stack.
    ;
    ; How: Copy 512 bytes from 0x7C00 to 0x0600.
    ;      Far jump to relocated code.
    ; -------------------------------------------------------------------------
    mov si, 0x7C00                  ; source: current MBR location
    mov di, STAGE1_RELOC            ; dest:   0x0600
    mov cx, 512                     ; copy 512 bytes (full MBR)
    rep movsb                       ; copy SI → DI, decrement CX

    ; far jump to relocated code
    ; 0x0000:relocated_entry = physical address of relocated_entry after copy
    jmp 0x0000:relocated_entry

; =============================================================================
; relocated_entry — continues execution from 0x0600
; All addresses here are relative to ORG 0x7C00 but executing at 0x0600.
; NASM resolves labels relative to ORG so we adjust manually with STAGE1_RELOC.
; =============================================================================
relocated_entry:
    ; -------------------------------------------------------------------------
    ; Re-initialize segments after relocation
    ; CS is now pointing into the 0x0600 region via far jump.
    ; DS/ES/SS still point to 0x0000 which is correct.
    ; Stack is safe — we relocated before heavy stack use.
    ; -------------------------------------------------------------------------
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK_REAL              ; stack at 0x7C00 (MBR region now free)

    ; -------------------------------------------------------------------------
    ; STEP 4: Quick A20 enable (fast port 0x92 method)
    ; -------------------------------------------------------------------------
    ; We try the fast method here in stage1 for speed.
    ; Stage2 will do full A20 verification + fallbacks.
    ; This handles QEMU and most modern hardware immediately.
    ; -------------------------------------------------------------------------
    in al, 0x92                     ; read port 0x92
    test al, 0x02                   ; check if A20 already enabled
    jnz .a20_done                   ; if bit 1 set, already enabled
    or al, 0x02                     ; set bit 1 (A20 enable)
    and al, 0xFE                    ; clear bit 0 (do not reset system)
    out 0x92, al                    ; write back

.a20_done:
    ; -------------------------------------------------------------------------
    ; STEP 5: Detect LBA support
    ; -------------------------------------------------------------------------
    ; LBA is simpler and more reliable than CHS.
    ; Almost all hardware made after 1996 supports LBA.
    ; We try LBA first, fall back to CHS if not available.
    ; -------------------------------------------------------------------------
    mov ah, 0x41                    ; INT 13h AH=41h: check LBA extensions
    mov bx, 0x55AA                  ; magic value required by BIOS
    mov dl, [boot_drive]            ; boot drive
    int 0x13                        ; call BIOS
    jc .no_lba                      ; carry set = LBA not supported
    cmp bx, 0xAA55                  ; BIOS should flip magic value
    jne .no_lba                     ; if not flipped, LBA not real
    mov byte [lba_supported], 1     ; LBA supported
    jmp .lba_detected

.no_lba:
    mov byte [lba_supported], 0     ; CHS fallback required

.lba_detected:
    ; -------------------------------------------------------------------------
    ; STEP 6: Load stage2 from disk
    ; -------------------------------------------------------------------------
    ; Stage2 starts at LBA sector 1 (sector after MBR).
    ; We load STAGE2_SECTORS sectors to STAGE2_LOAD (0x8000).
    ; -------------------------------------------------------------------------
    cmp byte [lba_supported], 1
    je .load_lba
    jmp .load_chs                   ; fallback to CHS

    ; --- LBA load ---
.load_lba:
    mov si, lba_packet              ; point to disk address packet
    mov ah, 0x42                    ; INT 13h AH=42h: extended read
    mov dl, [boot_drive]
    int 0x13
    jc .disk_error                  ; carry = error
    jmp .load_done

    ; --- CHS load (fallback) ---
.load_chs:
    mov ah, 0x02                    ; INT 13h AH=02h: read sectors
    mov al, STAGE2_SECTORS          ; number of sectors to read
    mov ch, 0                       ; cylinder 0
    mov cl, 2                       ; sector 2 (1-indexed, sector 1 = MBR)
    mov dh, 0                       ; head 0
    mov dl, [boot_drive]
    mov bx, STAGE2_LOAD             ; load to ES:BX = 0x0000:0x8000
    int 0x13
    jc .disk_error
    jmp .load_done

.disk_error:
    ; print error and halt
    ; E = disk Error
    mov si, msg_disk_error
    call print_str
    jmp .halt

.load_done:
    ; -------------------------------------------------------------------------
    ; STEP 7: Verify stage2 magic number
    ; -------------------------------------------------------------------------
    ; Read first 4 bytes of loaded stage2.
    ; Must match STAGE2_MAGIC or we loaded garbage.
    ; -------------------------------------------------------------------------
    mov eax, [STAGE2_LOAD]          ; read first dword of stage2
    cmp eax, STAGE2_MAGIC           ; compare to expected magic
    jne .magic_error                ; mismatch = wrong data loaded

    ; -------------------------------------------------------------------------
    ; STEP 8: Jump to stage2
    ; -------------------------------------------------------------------------
    ; Pass boot_drive in DL (stage2 convention).
    ; Stage2 will re-save it immediately on entry.
    ; -------------------------------------------------------------------------
    mov dl, [boot_drive]            ; restore DL for stage2
    jmp STAGE2_LOAD + 4             ; jump to 0x8004 (skip magic number)

.magic_error:
    mov si, msg_magic_error
    call print_str
    jmp .halt

.halt:
    cli                             ; disable interrupts
    hlt                             ; halt CPU
    jmp .halt                       ; if NMI wakes us, halt again

; =============================================================================
; print_str — print null-terminated string via BIOS INT 10h
; Input: SI = pointer to string
; Clobbers: AX, BX, SI
; Note: debug only, remove in final build
; =============================================================================
print_str:
    mov ah, 0x0E                    ; BIOS teletype output
    mov bh, 0                       ; page 0
    mov bl, 0x07                    ; light grey on black

.loop:
    lodsb                           ; load byte from SI, advance SI
    test al, al                     ; check for null terminator
    jz .done
    int 0x10                        ; print character
    jmp .loop

.done:
    ret

; =============================================================================
; Data
; =============================================================================

; LBA disk address packet for INT 13h AH=42h
align 2
lba_packet:
    db 0x10                         ; packet size = 16 bytes
    db 0x00                         ; reserved, must be 0
    dw STAGE2_SECTORS               ; number of sectors to read
    dw STAGE2_LOAD                  ; memory offset  (0x8000)
    dw 0x0000                       ; memory segment (0x0000)
    dq 0x0000000000000001           ; LBA start sector = 1 (after MBR)

; LBA support flag
lba_supported:
    db 0

; Error messages (keep short — we are counting bytes)
msg_disk_error:
    db "Disk err", 0x0D, 0x0A, 0

msg_magic_error:
    db "Bad magic", 0x0D, 0x0A, 0

; =============================================================================
; includes — signature must be last, pads to exactly 512 bytes
; =============================================================================
%include "signature.asm"

; =============================================================================
; End of entry.asm
; Total must be exactly 512 bytes after NASM assembles.
; Makefile checks stage1.bin <= 446 bytes (code + data only).
; signature.asm pads to 512 with partition table space + 0x55AA.
; =============================================================================