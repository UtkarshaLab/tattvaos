; =============================================================================
; str/arch/common/types.inc
; Core type definitions for the str library
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 (primary), aarch64/riscv stubs follow
; Assembler: NASM
;
; Invariant: every StrSlice contains valid UTF-8 bytes.
;            Validation happens at ingestion. Trust the type after that.
; =============================================================================

%ifndef STR_TYPES_INC
%define STR_TYPES_INC

; -----------------------------------------------------------------------------
; Codepoint limits
; -----------------------------------------------------------------------------

UTF8_MAX_BYTES      equ 4           ; max bytes per UTF-8 encoded codepoint
CODEPOINT_MAX       equ 0x10FFFF   ; highest valid Unicode codepoint
CODEPOINT_REPLACE   equ 0xFFFD     ; U+FFFD replacement character
CODEPOINT_BOM       equ 0xFEFF     ; U+FEFF byte order mark

; Surrogate range — invalid in UTF-8
SURROGATE_HIGH_MIN  equ 0xD800
SURROGATE_LOW_MAX   equ 0xDFFF

; ASCII boundary
ASCII_MAX           equ 0x7F

; -----------------------------------------------------------------------------
; StrSlice — immutable view into a UTF-8 string
;
;   ptr  dq  — pointer to first byte (not null-terminated, never owned)
;   len  dq  — byte length (not codepoint count)
;
; Layout: 16 bytes, 8-byte aligned
;
; Usage:
;   %define mystr.ptr  [rbp + StrSlice.ptr]
;   %define mystr.len  [rbp + StrSlice.len]
; -----------------------------------------------------------------------------

struc StrSlice
    .ptr    resq 1      ; *u8  — pointer to UTF-8 bytes
    .len    resq 1      ; u64  — byte length
endstruc

STRSLICE_SIZE   equ 16  ; sizeof(StrSlice)

; -----------------------------------------------------------------------------
; StrBuf — owned, growable UTF-8 string buffer
;
;   ptr  dq  — pointer to heap allocation
;   len  dq  — current byte length (written bytes)
;   cap  dq  — total allocated capacity in bytes
;
; Layout: 24 bytes, 8-byte aligned
;
; Invariant: len <= cap always. ptr is owned — caller manages lifetime.
; -----------------------------------------------------------------------------

struc StrBuf
    .ptr    resq 1      ; *u8  — pointer to allocation
    .len    resq 1      ; u64  — current byte length
    .cap    resq 1      ; u64  — allocated capacity
endstruc

STRBUF_SIZE     equ 24  ; sizeof(StrBuf)

; -----------------------------------------------------------------------------
; StrIter — UTF-8 codepoint iterator
;
;   ptr     dq  — pointer to current position in UTF-8 bytes
;   end     dq  — pointer to one past last byte
;   cp      dd  — last decoded codepoint (U+0000..U+10FFFF)
;   _pad    dd  — padding for alignment
;
; Layout: 24 bytes, 8-byte aligned
;
; Usage: call str_iter_next; result in .cp, advance .ptr
; -----------------------------------------------------------------------------

struc StrIter
    .ptr    resq 1      ; *u8  — current position
    .end    resq 1      ; *u8  — one past end
    .cp     resd 1      ; u32  — last decoded codepoint
    ._pad   resd 1      ; padding
endstruc

STRITER_SIZE    equ 24  ; sizeof(StrIter)

; -----------------------------------------------------------------------------
; Codepoint type alias — semantic marker, stored as 32-bit
;
; Always use resd / dd when storing a single codepoint.
; Valid range: 0x0000..0x10FFFF excluding surrogates 0xD800..0xDFFF
; -----------------------------------------------------------------------------

; Codepoint is just a u32 — no struc needed.
; Convention: codepoints live in EAX/ECX/EDX (low 32 bits of 64-bit regs)

CODEPOINT_SIZE  equ 4   ; sizeof(Codepoint) — one dword

; -----------------------------------------------------------------------------
; Return value convention
;
; All str functions follow:
;   RAX = 0              on success   (STR_OK)
;   RAX = negative i64   on error     (STR_ERR_*)
;
; Result values are returned via pointer arguments (out-params),
; not in RAX, so RAX is always free for the error code.
;
; Exception: pure predicate functions (is_ascii, is_utf8, etc.)
;   RAX = 1  → true
;   RAX = 0  → false
;   RAX < 0  → error (e.g. null pointer)
; -----------------------------------------------------------------------------

STR_TRUE        equ 1
STR_FALSE       equ 0

; -----------------------------------------------------------------------------
; Alignment constants
; -----------------------------------------------------------------------------

ALIGN_8         equ 8
ALIGN_16        equ 16
ALIGN_32        equ 32      ; AVX2 boundary
ALIGN_64        equ 64      ; AVX-512 / cache line boundary

; -----------------------------------------------------------------------------
; Null sentinel
; -----------------------------------------------------------------------------

STR_NULL        equ 0

%endif ; STR_TYPES_INC
