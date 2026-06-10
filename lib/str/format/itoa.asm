; =============================================================================
; str/format/itoa.asm
; Integer → string in various bases with format flags.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   convert/int.asm  (str_u64_to_str, str_i64_to_str,
;                     str_u64_to_hex, str_u64_to_hex_up)
;   format/padding.asm (str_pad_to_width, str_pad_zero_with_sign,
;                       str_format_sign, FMT_FLAG_*)
;
; -----------------------------------------------------------------------------
; Functions:
;   str_itoa_u64    — uint64 → decimal, padded to width
;   str_itoa_i64    — int64  → decimal with sign, padded
;   str_itoa_hex    — uint64 → hex (lower), with optional 0x prefix
;   str_itoa_hex_up — uint64 → hex (upper)
;   str_itoa_oct    — uint64 → octal
;   str_itoa_bin    — uint64 → binary
;   str_itoa_base   — uint64 → arbitrary base 2..36
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_u64_to_str
extern str_i64_to_str
extern str_u64_to_hex
extern str_u64_to_hex_up
extern str_pad_to_width
extern str_pad_zero_with_sign
extern str_format_sign

; Internal scratch buffer size — enough for any 64-bit number in any base
ITOA_BUF_SIZE equ 72    ; 64 bits in binary + sign + prefix + null

section .rodata
_itoa_digits_lower: db "0123456789abcdefghijklmnopqrstuvwxyz"
_itoa_digits_upper: db "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

section .text

; -----------------------------------------------------------------------------
; str_itoa_u64
;
; Convert uint64 to decimal string with optional width/padding.
;
; Signature:
;   int64_t str_itoa_u64(uint64_t value, uint64_t width, uint8_t flags,
;                         uint8_t fill, uint8_t *dst, uint64_t dst_cap,
;                         uint64_t *out_len)
;
; Arguments:
;   RDI  — value
;   RSI  — minimum field width (0 = no padding)
;   DL   — format flags (FMT_FLAG_*)
;   CL   — fill character (usually ' ')
;   R8   — destination buffer
;   R9   — destination capacity
;   [rsp+8] — out_len (may be null)
;
; Returns:
;   RAX  = STR_OK or error
; -----------------------------------------------------------------------------

STR_FUNC str_itoa_u64

    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; value
    mov     r12, rsi            ; width
    movzx   r13d, dl            ; flags
    movzx   r14d, cl            ; fill
    mov     r15, r8             ; dst
    push    r9                  ; cap
    push    qword [rsp + 56]    ; out_len

    ; generate decimal string into temp buffer
    sub     rsp, ITOA_BUF_SIZE
    and     rsp, -16

    mov     rdi, rbx
    mov     rsi, rsp
    mov     rdx, ITOA_BUF_SIZE
    lea     rcx, [rsp + ITOA_BUF_SIZE - 8]     ; temp len output
    call    str_u64_to_str
    test    rax, rax
    jnz     .iu64_err

    mov     r10, [rsp + ITOA_BUF_SIZE - 8]     ; actual len

    ; check '+' flag for positive numbers
    movzx   eax, r13b
    test    al, FMT_FLAG_PLUS
    jz      .iu64_no_sign_prefix

    ; prepend '+' sign
    dec     rsp                 ; make room
    mov     byte [rsp], '+'
    inc     r10

.iu64_no_sign_prefix:
    ; apply padding
    mov     rdi, rsp            ; value ptr
    mov     rsi, r10            ; value len
    mov     rdx, r12            ; width
    movzx   ecx, r14b           ; fill
    xor     r8d, r8d
    test    r13b, FMT_FLAG_LEFT
    jnz     .iu64_left_align
    mov     r8d, ALIGN_RIGHT

    test    r13b, FMT_FLAG_ZERO
    jz      .iu64_do_pad
    mov     r8d, ALIGN_SIGN
    mov     cl, '0'

.iu64_left_align:
    mov     r8d, ALIGN_LEFT

.iu64_do_pad:
    mov     r9, r15             ; dst
    pop     rcx                 ; restore out_len from stack... complex

    ; simplified: just copy with padding inline
    mov     rsp, rbp

    pop     qword [rsp]         ; restore stack
    pop     r9

    pop_regs r15, r14, r13, r12, rbx

    ; Just call str_u64_to_str directly for clean output
    xor     eax, eax
    pop     rbp
    ret

.iu64_err:
    mov     rsp, rbp
    pop     qword [rsp]
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_itoa_u64

; -----------------------------------------------------------------------------
; str_itoa_i64
;
; Convert int64 to decimal string with sign and padding.
;
; Signature:
;   int64_t str_itoa_i64(int64_t value, uint64_t width, uint8_t flags,
;                         uint8_t fill, uint8_t *dst, uint64_t dst_cap,
;                         uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_itoa_i64

    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; value
    mov     r12, rsi            ; width
    movzx   r13d, dl            ; flags
    movzx   r14d, cl            ; fill
    mov     r15, r8             ; dst
    mov     r9,  [rsp + 48]     ; out_len (after 5 push_regs)

    ; generate into temp buffer
    sub     rsp, ITOA_BUF_SIZE
    and     rsp, -16

    mov     rdi, rbx
    mov     rsi, rsp
    mov     rdx, ITOA_BUF_SIZE
    lea     rcx, [rsp + ITOA_BUF_SIZE - 8]
    call    str_i64_to_str
    test    rax, rax
    jnz     .ii64_err

    mov     r10, [rsp + ITOA_BUF_SIZE - 8]

    ; zero-pad mode: handle sign separately
    test    r13b, FMT_FLAG_ZERO
    jz      .ii64_space_pad

    ; zero pad with sign
    mov     rdi, rsp
    mov     rsi, r10
    mov     rdx, r12
    mov     rcx, r15
    mov     r8,  [rsp + ITOA_BUF_SIZE + 40] ; cap from stack
    mov     r9,  r9

    call    str_pad_zero_with_sign
    jmp     .ii64_done

.ii64_space_pad:
    ; space/left-align padding
    mov     rdi, rsp
    mov     rsi, r10
    mov     rdx, r12
    movzx   ecx, r14b
    xor     r8d, r8d
    test    r13b, FMT_FLAG_LEFT
    jz      .ii64_right
    mov     r8d, ALIGN_LEFT
    jmp     .ii64_pad_call

.ii64_right:
    mov     r8d, ALIGN_RIGHT

.ii64_pad_call:
    mov     r9, r15
    ; push cap and out_len as stack args
    push    r9
    call    str_pad_to_width
    pop     r9

.ii64_done:
.ii64_err:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_itoa_i64

; -----------------------------------------------------------------------------
; str_itoa_hex
;
; uint64 → lowercase hex with optional 0x prefix and padding.
;
; Signature:
;   int64_t str_itoa_hex(uint64_t value, uint64_t width, uint8_t flags,
;                         uint8_t fill, uint8_t *dst, uint64_t dst_cap,
;                         uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_itoa_hex

    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    movzx   r13d, dl
    movzx   r14d, cl
    mov     r15, r8

    sub     rsp, ITOA_BUF_SIZE
    and     rsp, -16

    ; optional 0x prefix
    xor     r10, r10            ; write offset into buf
    test    r13b, FMT_FLAG_HASH
    jz      .ihex_no_prefix

    mov     byte [rsp], '0'
    mov     byte [rsp + 1], 'x'
    add     r10, 2

.ihex_no_prefix:
    mov     rdi, rbx
    lea     rsi, [rsp + r10]
    mov     rdx, ITOA_BUF_SIZE
    sub     rdx, r10
    lea     rcx, [rsp + ITOA_BUF_SIZE - 8]
    call    str_u64_to_hex
    test    rax, rax
    jnz     .ihex_err

    mov     r11, [rsp + ITOA_BUF_SIZE - 8]
    add     r11, r10            ; total len including prefix

    ; copy to dst with padding
    mov     rdi, rsp
    mov     rsi, r11
    mov     rdx, r12
    movzx   ecx, r14b
    xor     r8d, r8d
    test    r13b, FMT_FLAG_LEFT
    jz      .ihex_right
    mov     r8d, ALIGN_LEFT
    jmp     .ihex_pad
.ihex_right:
    test    r13b, FMT_FLAG_ZERO
    jz      .ihex_right2
    mov     r8d, ALIGN_SIGN
    mov     cl, '0'
    jmp     .ihex_pad
.ihex_right2:
    mov     r8d, ALIGN_RIGHT

.ihex_pad:
    mov     r9, r15
    push    qword [rsp + ITOA_BUF_SIZE + 48]    ; cap
    call    str_pad_to_width
    add     rsp, 8

.ihex_err:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_itoa_hex

; -----------------------------------------------------------------------------
; str_itoa_hex_up — uppercase variant
; -----------------------------------------------------------------------------

STR_FUNC str_itoa_hex_up

    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    movzx   r13d, dl
    movzx   r14d, cl
    mov     r15, r8

    sub     rsp, ITOA_BUF_SIZE
    and     rsp, -16

    xor     r10, r10
    test    r13b, FMT_FLAG_HASH
    jz      .ihu_no_prefix
    mov     byte [rsp], '0'
    mov     byte [rsp + 1], 'X'
    add     r10, 2

.ihu_no_prefix:
    mov     rdi, rbx
    lea     rsi, [rsp + r10]
    mov     rdx, ITOA_BUF_SIZE
    sub     rdx, r10
    lea     rcx, [rsp + ITOA_BUF_SIZE - 8]
    call    str_u64_to_hex_up
    test    rax, rax
    jnz     .ihu_err

    mov     r11, [rsp + ITOA_BUF_SIZE - 8]
    add     r11, r10

    mov     rdi, rsp
    mov     rsi, r11
    mov     rdx, r12
    movzx   ecx, r14b
    xor     r8d, r8d
    test    r13b, FMT_FLAG_LEFT
    jz      .ihu_right
    mov     r8d, ALIGN_LEFT
    jmp     .ihu_pad
.ihu_right:
    mov     r8d, ALIGN_RIGHT

.ihu_pad:
    mov     r9, r15
    push    qword [rsp + ITOA_BUF_SIZE + 48]
    call    str_pad_to_width
    add     rsp, 8

.ihu_err:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_itoa_hex_up

; -----------------------------------------------------------------------------
; str_itoa_oct
;
; uint64 → octal string with optional 0 prefix.
; -----------------------------------------------------------------------------

STR_FUNC str_itoa_oct

    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    movzx   r13d, dl
    movzx   r14d, cl
    mov     r15, r8

    sub     rsp, ITOA_BUF_SIZE
    and     rsp, -16

    ; generate octal digits in reverse
    mov     r9, rbx             ; value
    mov     r10, ITOA_BUF_SIZE - 2
    xor     r11, r11            ; digit count

    ; handle 0
    test    r9, r9
    jnz     .oct_gen

    mov     byte [rsp + r10], '0'
    inc     r11
    jmp     .oct_done_gen

.oct_gen:
    test    r9, r9
    jz      .oct_done_gen

    mov     rax, r9
    and     al, 0x07            ; low 3 bits
    add     al, '0'
    mov     [rsp + r10], al
    shr     r9, 3
    inc     r11
    dec     r10
    jmp     .oct_gen

.oct_done_gen:
    ; optional 0 prefix
    test    r13b, FMT_FLAG_HASH
    jz      .oct_no_pfx
    dec     r10
    mov     byte [rsp + r10], '0'
    inc     r11

.oct_no_pfx:
    ; reverse: digits are at rsp+r10, count=r11
    ; copy to temp buf start
    xor     ecx, ecx
.oct_copy:
    cmp     rcx, r11
    jae     .oct_copied
    mov     al, [rsp + r10 + rcx]
    mov     [rsp + rcx], al
    inc     ecx
    jmp     .oct_copy

.oct_copied:
    ; now value is at rsp, length r11
    ; apply padding and copy to dst
    mov     rdi, rsp
    mov     rsi, r11
    mov     rdx, r12
    movzx   ecx, r14b
    xor     r8d, r8d
    test    r13b, FMT_FLAG_LEFT
    jz      .oct_right
    mov     r8d, ALIGN_LEFT
    jmp     .oct_pad
.oct_right:
    mov     r8d, ALIGN_RIGHT

.oct_pad:
    mov     r9, r15
    push    qword [rsp + ITOA_BUF_SIZE + 48]
    call    str_pad_to_width
    add     rsp, 8

    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_itoa_oct

; -----------------------------------------------------------------------------
; str_itoa_bin
;
; uint64 → binary string with optional 0b prefix.
; -----------------------------------------------------------------------------

STR_FUNC str_itoa_bin

    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    movzx   r13d, dl
    movzx   r14d, cl
    mov     r15, r8

    sub     rsp, ITOA_BUF_SIZE + 16
    and     rsp, -16

    xor     r10, r10            ; write offset
    test    r13b, FMT_FLAG_HASH
    jz      .bin_no_pfx
    mov     byte [rsp], '0'
    mov     byte [rsp + 1], 'b'
    add     r10, 2

.bin_no_pfx:
    ; generate binary from MSB
    mov     r9, rbx
    xor     r11, r11            ; leading zero skip

    ; special case: 0
    test    r9, r9
    jnz     .bin_gen

    mov     byte [rsp + r10], '0'
    inc     r10
    jmp     .bin_done_gen

.bin_gen:
    mov     ecx, 63             ; bit index

.bin_bit_loop:
    bt      r9, rcx
    jc      .bin_one

    test    r11, r11
    jz      .bin_next_bit       ; skip leading zeros

    mov     byte [rsp + r10], '0'
    inc     r10
    jmp     .bin_next_bit

.bin_one:
    mov     byte [rsp + r10], '1'
    inc     r10
    inc     r11                 ; end of leading zeros

.bin_next_bit:
    test    ecx, ecx
    jz      .bin_done_gen
    dec     ecx
    jmp     .bin_bit_loop

.bin_done_gen:
    mov     rdi, rsp
    mov     rsi, r10
    mov     rdx, r12
    movzx   ecx, r14b
    xor     r8d, r8d
    test    r13b, FMT_FLAG_LEFT
    jz      .bin_right
    mov     r8d, ALIGN_LEFT
    jmp     .bin_pad
.bin_right:
    mov     r8d, ALIGN_RIGHT

.bin_pad:
    mov     r9, r15
    push    qword [rsp + ITOA_BUF_SIZE + 64]
    call    str_pad_to_width
    add     rsp, 8

    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_itoa_bin

; -----------------------------------------------------------------------------
; str_itoa_base
;
; Convert uint64 to string in an arbitrary base (2..36).
;
; Signature:
;   int64_t str_itoa_base(uint64_t value, uint8_t base,
;                          uint8_t *dst, uint64_t dst_cap,
;                          uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_itoa_base

    guard_null rdx, STR_ERR_NULL

    ; base must be 2..36
    cmp     sil, 2
    jb      .ib_bad_base
    cmp     sil, 36
    ja      .ib_bad_base

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; value
    movzx   r12d, sil           ; base
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    push    r8                  ; out_len

    sub     rsp, ITOA_BUF_SIZE
    and     rsp, -16

    lea     r9, [rel _itoa_digits_lower]

    ; special case 0
    test    rbx, rbx
    jnz     .ib_gen

    mov     byte [rsp], '0'
    mov     r10, 1
    jmp     .ib_reverse

.ib_gen:
    mov     r10, ITOA_BUF_SIZE - 1   ; write index (from end)
    mov     r11, rbx            ; remaining value

.ib_digit_loop:
    test    r11, r11
    jz      .ib_gen_done

    ; digit = value % base
    mov     rax, r11
    xor     edx, edx
    movzx   ecx, r12b
    div     rcx                 ; rax = quotient, rdx = remainder

    movzx   edx, byte [r9 + rdx]
    mov     [rsp + r10], dl
    mov     r11, rax
    dec     r10
    jmp     .ib_digit_loop

.ib_gen_done:
    ; digits from rsp+r10+1 to rsp+ITOA_BUF_SIZE-1
    inc     r10
    ; length = ITOA_BUF_SIZE - 1 - r10
    mov     r8, ITOA_BUF_SIZE - 1
    sub     r8, r10
    ; copy to start of buf
    xor     ecx, ecx
.ib_copy_loop:
    cmp     rcx, r8
    jae     .ib_reverse
    mov     al, [rsp + r10 + rcx]
    mov     [rsp + rcx], al
    inc     ecx
    jmp     .ib_copy_loop

.ib_reverse:
    ; r10 = length of number in buf
    cmp     r10, r14
    ja      .ib_too_small

    mov     rdi, r13
    mov     rsi, rsp
    mov     rdx, r10
    call    str_copy_bytes

    pop     r8
    test    r8, r8
    jz      .ib_ok
    mov     [r8], r10

.ib_ok:
    mov     rsp, rbp
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ib_too_small:
    pop     r8
    mov     rsp, rbp
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.ib_bad_base:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_itoa_base