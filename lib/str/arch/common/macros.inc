; =============================================================================
; str/arch/common/macros.inc
; Calling convention and utility macros for the str library
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 (System V AMD64 ABI)
; Assembler: NASM
;
; System V AMD64 ABI quick reference:
;   Args:       RDI, RSI, RDX, RCX, R8, R9  (integers/pointers)
;   Return:     RAX (and RDX for 128-bit)
;   Caller-saved:  RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
;   Callee-saved:  RBX, RBP, R12, R13, R14, R15
;   Stack:      16-byte aligned at CALL instruction
; =============================================================================

%ifndef STR_MACROS_INC
%define STR_MACROS_INC

%include "error.inc"

; -----------------------------------------------------------------------------
; STR_FUNC name
; Standard function prologue.
; Sets up stack frame, saves RBP.
;
; Usage:
;   STR_FUNC str_utf8_len
;       ... body ...
;   STR_ENDFUNC str_utf8_len
; -----------------------------------------------------------------------------

%macro STR_FUNC 1
global %1
%1:
    push    rbp
    mov     rbp, rsp
%endmacro

; -----------------------------------------------------------------------------
; STR_ENDFUNC name
; Standard function epilogue — restores frame and returns.
; -----------------------------------------------------------------------------

%macro STR_ENDFUNC 1
    pop     rbp
    ret
%endmacro

; -----------------------------------------------------------------------------
; STR_FUNC_ALIGN name
; Like STR_FUNC but aligns stack to 16 bytes for SSE/AVX safety.
; Use for any function that touches XMM/YMM/ZMM registers.
; -----------------------------------------------------------------------------

%macro STR_FUNC_ALIGN 1
global %1
%1:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
%endmacro

%macro STR_ENDFUNC_ALIGN 1
    mov     rsp, rbp
    pop     rbp
    ret
%endmacro

; -----------------------------------------------------------------------------
; ret_ok
; Zero RAX (STR_OK) and return.
; -----------------------------------------------------------------------------

%macro ret_ok 0
    xor     eax, eax
    pop     rbp
    ret
%endmacro

; -----------------------------------------------------------------------------
; ret_err code
; Load signed error code into RAX and return.
; code must be one of the STR_ERR_* constants from error.inc.
;
; Usage:
;   ret_err STR_ERR_NULL
; -----------------------------------------------------------------------------

%macro ret_err 1
    mov     rax, %1
    pop     rbp
    ret
%endmacro

; -----------------------------------------------------------------------------
; ret_bool reg
; Return a boolean result: RAX = 1 if reg != 0, RAX = 0 otherwise.
; Clobbers RAX only.
;
; Usage:
;   ret_bool rcx
; -----------------------------------------------------------------------------

%macro ret_bool 1
    test    %1, %1
    setnz   al
    movzx   eax, al
    pop     rbp
    ret
%endmacro

; -----------------------------------------------------------------------------
; guard_null reg, errcode
; If reg == 0 (null pointer), return errcode immediately.
;
; Usage:
;   guard_null rdi, STR_ERR_NULL    ; guard input pointer
;   guard_null rsi, STR_ERR_NULL    ; guard output pointer
; -----------------------------------------------------------------------------

%macro guard_null 2
    test    %1, %1
    jnz     %%not_null
    ret_err %2
    %%not_null:
%endmacro

; -----------------------------------------------------------------------------
; guard_null2 reg1, reg2, errcode
; Guard two pointers at once.
; -----------------------------------------------------------------------------

%macro guard_null2 3
    test    %1, %1
    jz      %%is_null
    test    %2, %2
    jnz     %%not_null
    %%is_null:
    ret_err %3
    %%not_null:
%endmacro

; -----------------------------------------------------------------------------
; push_regs reg [, reg ...]
; Push a list of callee-saved registers.
; Pair with pop_regs (in reverse order) at function exit.
;
; Usage:
;   push_regs rbx, r12, r13
;   ...
;   pop_regs r13, r12, rbx
; -----------------------------------------------------------------------------

%macro push_regs 1-*
    %rep %0
        push %1
        %rotate 1
    %endrep
%endmacro

%macro pop_regs 1-*
    %rep %0
        pop %1
        %rotate 1
    %endrep
%endmacro

; -----------------------------------------------------------------------------
; save_regs / restore_regs
; Aliases for push_regs / pop_regs — for readability in prologue/epilogue.
; -----------------------------------------------------------------------------

%macro save_regs 1-*
    push_regs %{1:-1}
%endmacro

%macro restore_regs 1-*
    pop_regs %{1:-1}
%endmacro

; -----------------------------------------------------------------------------
; align_stack
; Ensures RSP is 16-byte aligned before a CALL.
; Saves alignment delta in R11 (caller-saved — safe to clobber).
; Pair with restore_stack after the call.
;
; Usage:
;   align_stack
;   call    some_function
;   restore_stack
; -----------------------------------------------------------------------------

%macro align_stack 0
    mov     r11, rsp
    and     rsp, -16
    sub     rsp, 8          ; compensate for the push rbp already done
%endmacro

%macro restore_stack 0
    mov     rsp, r11
%endmacro

; -----------------------------------------------------------------------------
; STR_SECTION_TEXT
; STR_SECTION_RODATA
; Consistent section declarations across all str modules.
; -----------------------------------------------------------------------------

%macro STR_SECTION_TEXT 0
    section .text
%endmacro

%macro STR_SECTION_RODATA 0
    section .rodata
%endmacro

; -----------------------------------------------------------------------------
; STR_EXTERN name
; Declare an external str library symbol.
;
; Usage:
;   STR_EXTERN str_utf8_charlen
; -----------------------------------------------------------------------------

%macro STR_EXTERN 1
    extern %1
%endmacro

; -----------------------------------------------------------------------------
; CODEPOINT_IS_VALID cp_reg
; Sets ZF=0 if cp_reg holds a valid codepoint, ZF=1 if invalid.
; Clobbers: nothing beyond flags.
;
; Valid means: 0x0000..0x10FFFF and not 0xD800..0xDFFF (surrogates)
;
; Usage:
;   CODEPOINT_IS_VALID eax
;   jz .invalid
; -----------------------------------------------------------------------------

%macro CODEPOINT_IS_VALID 1
    cmp     %1, CODEPOINT_MAX
    ja      %%invalid
    cmp     %1, SURROGATE_HIGH_MIN
    jb      %%valid
    cmp     %1, SURROGATE_LOW_MAX
    jbe     %%invalid
    %%valid:
    test    %1, %1          ; set ZF=0 (nonzero = valid)
    jmp     %%done
    %%invalid:
    xor     %1, %1          ; ZF=1 signals invalid
    %%done:
%endmacro

; -----------------------------------------------------------------------------
; UTF8_LEADING_ONES reg
; Count leading 1-bits in a UTF-8 leading byte to determine sequence length.
; Result in reg: 0=ASCII, 2=2-byte, 3=3-byte, 4=4-byte, else invalid.
;
; Caller must AND reg with 0xFF first if it came from memory.
; -----------------------------------------------------------------------------

%macro UTF8_LEADING_ONES 1
    ; Handled inline in charlen.s — this is a documentation stub.
    ; See str/utf8/charlen.s for the actual implementation.
%endmacro

%endif ; STR_MACROS_INC
