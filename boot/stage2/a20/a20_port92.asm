; =============================================================================
; Tattva OS — boot/stage2/a20/a20_port92.asm
; =============================================================================
; Enable A20 line via port 0x92 (System Control Port A).
; This is the fastest method. Works on most modern hardware and QEMU.
;
; Port 0x92 bits:
;   Bit 0: System reset (write 1 = reset! do NOT set this)
;   Bit 1: A20 gate    (write 1 = enable A20)
;   Bits 2-7: reserved
;
; Caution:
;   Some old hardware (PS/2) does not have port 0x92.
;   On those systems this is a no-op (port ignored).
;   Always verify with a20_verify after this call.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef A20_PORT92_ASM
%define A20_PORT92_ASM

; =============================================================================
; a20_port92 — enable A20 via port 0x92
; Input:  nothing
; Output: nothing (call a20_verify to check if it worked)
; Clobbers: AL
; =============================================================================
a20_port92:
    in al, 0x92                     ; read current value of port 0x92

    test al, 0x02                   ; check if A20 bit already set
    jnz .already_set                ; if set, nothing to do

    or al, 0x02                     ; set bit 1 (A20 enable)
    and al, 0xFE                    ; clear bit 0 (do NOT reset system)
    out 0x92, al                    ; write back

    ; small delay to let hardware settle
    in al, 0x80                     ; dummy read port 0x80 (diagnostic port)
    in al, 0x80                     ; twice for safety

.already_set:
    ret

%endif ; A20_PORT92_ASM