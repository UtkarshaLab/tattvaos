; =============================================================================
; Tattva OS — boot/stage2/a20/a20.asm
; =============================================================================
; Main A20 handler. Tries all methods in order.
; Verifies after each attempt before trying next.
;
; Method order (fastest/simplest first):
;   1. Check if already enabled (QEMU enables by default)
;   2. Port 0x92 fast method
;   3. BIOS INT 15h method       (a20_bios.asm — built later)
;   4. Keyboard controller 8042  (a20_kbd.asm  — built later)
;
; Returns:
;   CF=0: A20 successfully enabled
;   CF=1: All methods failed (system should halt)
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef A20_ASM
%define A20_ASM

%include "a20_verify.asm"
%include "a20_port92.asm"

%include "a20_bios.asm"
%include "a20_kbd.asm"

; =============================================================================
; a20_enable — try all A20 methods until one works
; Input:  nothing
; Output: CF=0 success (A20 enabled)
;         CF=1 failure (all methods exhausted)
; Clobbers: AX, BX, CX, ES
; =============================================================================
a20_enable:

    ; -------------------------------------------------------------------------
    ; METHOD 0: Check if already enabled
    ; QEMU enables A20 by default.
    ; Many modern BIOSes also enable it before handoff.
    ; Skip all work if already on.
    ; -------------------------------------------------------------------------
    call a20_verify
    jnc .success                    ; CF=0 means ON — done

    ; -------------------------------------------------------------------------
    ; METHOD 1: Port 0x92 fast method
    ; Works on most modern hardware and QEMU.
    ; Fastest, safest, try first.
    ; -------------------------------------------------------------------------
    call a20_port92
    call a20_verify
    jnc .success                    ; worked? done

    ; -------------------------------------------------------------------------
    ; METHOD 2: BIOS INT 15h AX=2401
    ; Slower but more compatible.
    ; Works on systems where port 0x92 is not present.
    ; -------------------------------------------------------------------------
    call a20_bios
    call a20_verify
    jnc .success

    ; -------------------------------------------------------------------------
    ; METHOD 3: Keyboard controller 8042
    ; Slowest. Most compatible. Last resort.
    ; Works on very old PS/2-style hardware.
    ; -------------------------------------------------------------------------
    call a20_kbd
    call a20_verify
    jnc .success

    ; -------------------------------------------------------------------------
    ; All methods failed
    ; -------------------------------------------------------------------------
    stc                             ; CF=1: failure
    ret

.success:
    clc                             ; CF=0: success
    ret

%endif ; A20_ASM