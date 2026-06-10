; =============================================================================
; str/inspect/char_class.asm
; Classify a Unicode codepoint into a character class bitmask.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_alpha.asm   (str_is_alpha_cp)
;   inspect/is_numeric.asm (str_is_decimal_cp, str_is_numeric_cp)
;   inspect/is_space.asm   (str_is_space_cp)
;   inspect/is_upper.asm   (str_is_upper_cp)
;   inspect/is_lower.asm   (str_is_lower_cp)
;   inspect/is_print.asm   (str_is_print_cp)
;   inspect/is_blank.asm   (str_is_blank_cp)
;   utf8/decode.asm        (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; Character class bitmask constants (CHAR_CLASS_*):
;
;   Bit 0  CC_ALPHA    alphabetic
;   Bit 1  CC_DIGIT    ASCII decimal digit (0-9)
;   Bit 2  CC_DECIMAL  Unicode decimal digit (Nd)
;   Bit 3  CC_SPACE    Unicode whitespace
;   Bit 4  CC_BLANK    horizontal whitespace only
;   Bit 5  CC_UPPER    uppercase letter
;   Bit 6  CC_LOWER    lowercase letter
;   Bit 7  CC_PRINT    printable
;   Bit 8  CC_ASCII    ASCII (0x00..0x7F)
;   Bit 9  CC_ALNUM    alpha or decimal digit
;   Bit 10 CC_CONTROL  control character (C0/DEL/C1)
;   Bit 11 CC_PUNCT    punctuation (printable, not alnum, not space)
;
; Usage:
;   mov  edi, GREEK_LOWER_ALPHA
;   call str_char_class
;   ; rax has bitmask — test CC_ALPHA, CC_LOWER etc.
;   test eax, CC_ALPHA
;   jnz  .is_letter
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_is_alpha_cp
extern str_is_decimal_cp
extern str_is_numeric_cp
extern str_is_space_cp
extern str_is_blank_cp
extern str_is_upper_cp
extern str_is_lower_cp
extern str_is_print_cp
extern str_utf8_decode_unchecked

section .rodata

; Character class bitmask constants
CC_ALPHA    equ (1 << 0)    ; alphabetic
CC_DIGIT    equ (1 << 1)    ; ASCII 0-9
CC_DECIMAL  equ (1 << 2)    ; Unicode decimal digit (Nd)
CC_SPACE    equ (1 << 3)    ; Unicode whitespace
CC_BLANK    equ (1 << 4)    ; horizontal whitespace
CC_UPPER    equ (1 << 5)    ; uppercase letter
CC_LOWER    equ (1 << 6)    ; lowercase letter
CC_PRINT    equ (1 << 7)    ; printable character
CC_ASCII    equ (1 << 8)    ; in ASCII range (0x00..0x7F)
CC_ALNUM    equ (1 << 9)    ; alpha or decimal digit
CC_CONTROL  equ (1 << 10)   ; control character
CC_PUNCT    equ (1 << 11)   ; punctuation

section .text

; -----------------------------------------------------------------------------
; str_char_class
;
; Return the full character class bitmask for a codepoint.
;
; Signature:
;   uint64_t str_char_class(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  — bitmask of CC_* flags (never negative)
; -----------------------------------------------------------------------------

STR_FUNC str_char_class

    push_regs rbx, r12, r13, r14, r15

    mov     ebx, edi            ; ebx = codepoint (preserved across calls)
    xor     r15d, r15d          ; r15 = accumulating bitmask

    ; --- CC_ASCII ---
    cmp     ebx, ASCII_MAX
    ja      .skip_ascii
    or      r15d, CC_ASCII

.skip_ascii:
    ; --- CC_PRINT ---
    mov     edi, ebx
    call    str_is_print_cp
    test    eax, eax
    jz      .skip_print
    or      r15d, CC_PRINT

.skip_print:
    ; --- CC_CONTROL: not printable AND (0x00..0x1F or 0x7F or 0x80..0x9F) ---
    test    r15d, CC_PRINT
    jnz     .skip_control
    cmp     ebx, 0x1F
    jbe     .is_control
    cmp     ebx, 0x7F
    je      .is_control
    cmp     ebx, 0x80
    jb      .skip_control
    cmp     ebx, 0x9F
    ja      .skip_control
.is_control:
    or      r15d, CC_CONTROL

.skip_control:
    ; --- CC_SPACE ---
    mov     edi, ebx
    call    str_is_space_cp
    test    eax, eax
    jz      .skip_space
    or      r15d, CC_SPACE

.skip_space:
    ; --- CC_BLANK ---
    mov     edi, ebx
    call    str_is_blank_cp
    test    eax, eax
    jz      .skip_blank
    or      r15d, CC_BLANK

.skip_blank:
    ; --- CC_ALPHA ---
    mov     edi, ebx
    call    str_is_alpha_cp
    test    eax, eax
    jz      .skip_alpha
    or      r15d, CC_ALPHA

.skip_alpha:
    ; --- CC_UPPER ---
    mov     edi, ebx
    call    str_is_upper_cp
    test    eax, eax
    jz      .skip_upper
    or      r15d, CC_UPPER

.skip_upper:
    ; --- CC_LOWER ---
    mov     edi, ebx
    call    str_is_lower_cp
    test    eax, eax
    jz      .skip_lower
    or      r15d, CC_LOWER

.skip_lower:
    ; --- CC_DIGIT (ASCII 0-9 only) ---
    cmp     ebx, '0'
    jb      .skip_digit
    cmp     ebx, '9'
    ja      .skip_digit
    or      r15d, CC_DIGIT

.skip_digit:
    ; --- CC_DECIMAL (Unicode Nd) ---
    mov     edi, ebx
    call    str_is_decimal_cp
    test    eax, eax
    jz      .skip_decimal
    or      r15d, CC_DECIMAL

.skip_decimal:
    ; --- CC_ALNUM: alpha OR decimal ---
    mov     eax, r15d
    and     eax, CC_ALPHA | CC_DECIMAL
    jz      .skip_alnum
    or      r15d, CC_ALNUM

.skip_alnum:
    ; --- CC_PUNCT: printable AND not alnum AND not space ---
    mov     eax, r15d
    test    eax, CC_PRINT
    jz      .skip_punct
    test    eax, CC_ALNUM
    jnz     .skip_punct
    test    eax, CC_SPACE
    jnz     .skip_punct
    or      r15d, CC_PUNCT

.skip_punct:
    mov     eax, r15d

    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_char_class

; -----------------------------------------------------------------------------
; str_char_class_ascii
;
; Fast ASCII-only classification using a precomputed 128-entry table.
; For bytes 0x00..0x7F only — returns 0 for anything >= 0x80.
;
; Signature:
;   uint64_t str_char_class_ascii(uint8_t byte)
;
; Arguments:
;   DIL  — byte (only 0x00..0x7F meaningful)
;
; Returns:
;   RAX  — CC_* bitmask
; -----------------------------------------------------------------------------

STR_FUNC str_char_class_ascii

    movzx   eax, dil

    cmp     al, 0x7F
    ja      .out_of_range

    ; look up precomputed table
    lea     rcx, [rel .ascii_class_table]
    movzx   eax, word [rcx + rax * 2]

    pop     rbp
    ret

.out_of_range:
    xor     eax, eax
    pop     rbp
    ret

; Precomputed 16-bit class table for bytes 0x00..0x7F
; Each entry is the CC_* bitmask for that byte
section .rodata
.ascii_class_table:
    ; 0x00..0x1F — control characters
    %rep 32
        dw CC_CONTROL
    %endrep
    ; 0x20 — space
    dw CC_SPACE | CC_BLANK | CC_PRINT | CC_ASCII
    ; 0x21..0x2F — punctuation !"#$%&'()*+,-./
    %rep 15
        dw CC_PUNCT | CC_PRINT | CC_ASCII
    %endrep
    ; 0x30..0x39 — digits 0-9
    %rep 10
        dw CC_DIGIT | CC_DECIMAL | CC_ALNUM | CC_PRINT | CC_ASCII
    %endrep
    ; 0x3A..0x40 — punctuation :;<=>?@
    %rep 7
        dw CC_PUNCT | CC_PRINT | CC_ASCII
    %endrep
    ; 0x41..0x5A — uppercase A-Z
    %rep 26
        dw CC_ALPHA | CC_UPPER | CC_ALNUM | CC_PRINT | CC_ASCII
    %endrep
    ; 0x5B..0x60 — punctuation [\]^_`
    %rep 6
        dw CC_PUNCT | CC_PRINT | CC_ASCII
    %endrep
    ; 0x61..0x7A — lowercase a-z
    %rep 26
        dw CC_ALPHA | CC_LOWER | CC_ALNUM | CC_PRINT | CC_ASCII
    %endrep
    ; 0x7B..0x7E — punctuation {|}~
    %rep 4
        dw CC_PUNCT | CC_PRINT | CC_ASCII
    %endrep
    ; 0x7F — DEL
    dw CC_CONTROL | CC_ASCII

section .text

; -----------------------------------------------------------------------------
; str_is_punct_cp
;
; Check if a codepoint is punctuation.
; Printable AND not alphanumeric AND not whitespace.
;
; Signature:
;   int64_t str_is_punct_cp(uint32_t cp)
; -----------------------------------------------------------------------------

STR_FUNC str_is_punct_cp

    push_regs rbx
    mov     ebx, edi

    call    str_is_print_cp
    test    eax, eax
    jz      .not_punct

    mov     edi, ebx
    call    str_is_alpha_cp
    test    eax, eax
    jnz     .not_punct

    mov     edi, ebx
    call    str_is_decimal_cp
    test    eax, eax
    jnz     .not_punct

    mov     edi, ebx
    call    str_is_space_cp
    test    eax, eax
    jnz     .not_punct

    pop_regs rbx
    mov     eax, STR_TRUE
    pop     rbp
    ret

.not_punct:
    pop_regs rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_is_punct_cp

; -----------------------------------------------------------------------------
; str_char_class_name
;
; Return a pointer to a null-terminated ASCII string naming the primary
; class of a codepoint. For debugging and error messages.
;
; Signature:
;   const char *str_char_class_name(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  — pointer to static string: "alpha", "digit", "space",
;           "blank", "punct", "control", "other"
; -----------------------------------------------------------------------------

section .rodata

.name_alpha:    db "alpha",   0
.name_digit:    db "digit",   0
.name_space:    db "space",   0
.name_blank:    db "blank",   0
.name_punct:    db "punct",   0
.name_control:  db "control", 0
.name_other:    db "other",   0

section .text

STR_FUNC str_char_class_name

    push_regs rbx
    mov     ebx, edi

    call    str_char_class
    mov     ecx, eax            ; ecx = bitmask

    ; priority order: control > alpha > digit > space > blank > punct > other
    test    ecx, CC_CONTROL
    jnz     .name_ctrl

    test    ecx, CC_ALPHA
    jnz     .name_alp

    test    ecx, CC_DIGIT
    jnz     .name_dgt

    test    ecx, CC_SPACE
    jnz     .name_spc

    test    ecx, CC_BLANK
    jnz     .name_blk

    test    ecx, CC_PUNCT
    jnz     .name_pct

    lea     rax, [rel .name_other]
    pop_regs rbx
    pop     rbp
    ret

.name_ctrl: lea rax, [rel .name_control] ; jmp .done
            jmp .done
.name_alp:  lea rax, [rel .name_alpha]
            jmp .done
.name_dgt:  lea rax, [rel .name_digit]
            jmp .done
.name_spc:  lea rax, [rel .name_space]
            jmp .done
.name_blk:  lea rax, [rel .name_blank]
            jmp .done
.name_pct:  lea rax, [rel .name_punct]

.done:
    pop_regs rbx
    pop     rbp
    ret

STR_ENDFUNC str_char_class_name