; =============================================================================
; str/arch/common/error.inc
; Error code definitions for the str library
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 (primary)
; Assembler: NASM
;
; Convention: STR_OK = 0, all errors are negative signed 64-bit integers.
;             Return in RAX. Use ret_err / ret_ok macros from macros.inc.
; =============================================================================

%ifndef STR_ERROR_INC
%define STR_ERROR_INC

; -----------------------------------------------------------------------------
; Success
; -----------------------------------------------------------------------------

STR_OK                      equ  0

; -----------------------------------------------------------------------------
; Pointer / argument errors  (-1 .. -9)
; -----------------------------------------------------------------------------

STR_ERR_NULL                equ -1  ; null pointer passed where disallowed
STR_ERR_INVALID_ARG         equ -2  ; argument value is out of valid range
STR_ERR_OUT_OF_BOUNDS       equ -3  ; index or offset exceeds string length

; -----------------------------------------------------------------------------
; UTF-8 / encoding errors  (-10 .. -19)
; -----------------------------------------------------------------------------

STR_ERR_INVALID_UTF8        equ -10 ; byte sequence is not valid UTF-8
STR_ERR_INVALID_CODEPOINT   equ -11 ; codepoint outside 0x0000..0x10FFFF
STR_ERR_SURROGATE           equ -12 ; surrogate half (0xD800..0xDFFF) in UTF-8
STR_ERR_OVERLONG            equ -13 ; overlong UTF-8 encoding detected
STR_ERR_TRUNCATED           equ -14 ; multi-byte sequence cut off at end of input
STR_ERR_ENCODING            equ -15 ; generic encoding conversion failure
STR_ERR_NO_BOM              equ -16 ; expected BOM not found

; -----------------------------------------------------------------------------
; Buffer / memory errors  (-20 .. -29)
; -----------------------------------------------------------------------------

STR_ERR_BUF_TOO_SMALL       equ -20 ; output buffer has insufficient capacity
STR_ERR_OVERFLOW            equ -21 ; arithmetic overflow in length calculation
STR_ERR_ALLOC               equ -22 ; memory allocation failed
STR_ERR_ALIGN               equ -23 ; pointer alignment requirement not met

; -----------------------------------------------------------------------------
; Search / pattern errors  (-30 .. -39)
; -----------------------------------------------------------------------------

STR_ERR_NOT_FOUND           equ -30 ; pattern or substring not found
STR_ERR_INVALID_PATTERN     equ -31 ; malformed regex or glob pattern
STR_ERR_PATTERN_TOO_LONG    equ -32 ; pattern exceeds engine limits

; -----------------------------------------------------------------------------
; Format / parse errors  (-40 .. -49)
; -----------------------------------------------------------------------------

STR_ERR_PARSE               equ -40 ; input could not be parsed
STR_ERR_INVALID_FORMAT      equ -41 ; format string is malformed
STR_ERR_FORMAT_OVERFLOW     equ -42 ; formatted output exceeds buffer

; -----------------------------------------------------------------------------
; Unicode / normalization errors  (-50 .. -59)
; -----------------------------------------------------------------------------

STR_ERR_NORMALIZE           equ -50 ; normalization failed
STR_ERR_INVALID_IDNA        equ -51 ; label violates IDNA2008 rules
STR_ERR_INVALID_PUNYCODE    equ -52 ; malformed Punycode sequence
STR_ERR_BIDI                equ -53 ; bidirectional text rule violation

; -----------------------------------------------------------------------------
; Iterator errors  (-60 .. -69)
; -----------------------------------------------------------------------------

STR_ERR_ITER_END            equ -60 ; iterator exhausted (not really an error)
STR_ERR_ITER_INVALID        equ -61 ; iterator in invalid state

; -----------------------------------------------------------------------------
; I/O / reader-writer errors  (-70 .. -79)
; -----------------------------------------------------------------------------

STR_ERR_READ                equ -70 ; read from StrReader failed
STR_ERR_WRITE               equ -71 ; write to StrWriter failed
STR_ERR_EOF                 equ -72 ; unexpected end of input stream

%endif ; STR_ERROR_INC
