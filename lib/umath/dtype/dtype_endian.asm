; =============================================================================
; umath - unified math library
; dtype/dtype_endian.asm - endianness per dtype and byte swap ops
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_size.asm
;
; description:
;   all umath internal computations use native x86-64 little-endian
;   byte swapping is needed when:
;     - reading from network (big-endian)
;     - reading model files in big-endian format
;     - reading TIFF/some audio formats (big-endian)
;     - interfacing with big-endian hardware accelerators
;
;   endian enum:
;     ENDIAN_LITTLE = 0  x86-64 native (default for all umath ops)
;     ENDIAN_BIG    = 1  network byte order, some file formats
;     ENDIAN_NA     = 2  not applicable (single-byte types or variable-size)
;
; functions:
;   umath_dtype_native_endian      (dtype_id → u32) ENDIAN_* constant
;   umath_dtype_swap_bytes_16      (u16 → u16)
;   umath_dtype_swap_bytes_32      (u32 → u32)
;   umath_dtype_swap_bytes_64      (u64 → u64)
;   umath_dtype_swap_bytes_128     (*u128 → void) in-place
;   umath_dtype_to_little_16       (val, src_endian → u16)
;   umath_dtype_to_little_32       (val, src_endian → u32)
;   umath_dtype_to_little_64       (val, src_endian → u64)
;   umath_dtype_to_big_16          (val → u16)
;   umath_dtype_to_big_32          (val → u32)
;   umath_dtype_to_big_64          (val → u64)
;   umath_dtype_from_big_16        (val → u16) big→little
;   umath_dtype_from_big_32        (val → u32)
;   umath_dtype_from_big_64        (val → u64)
;   umath_dtype_swap_buf           (*buf, count, dtype_id → void)
;   umath_dtype_is_little_endian   () → bool  runtime check
;   umath_dtype_swap_f32           (f32 → f32) byte-swap float
;   umath_dtype_swap_f64           (f64 → f64) byte-swap double
;   umath_dtype_swap_f16           (f16 → f16) byte-swap half
; =============================================================================

%include "dtype_id.asm"
%include "dtype_size.asm"

bits 64

; =============================================================================
; endian constants
; =============================================================================

ENDIAN_LITTLE   equ 0
ENDIAN_BIG      equ 1
ENDIAN_NA       equ 2

section .text

; =============================================================================
; endianness queries
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_native_endian - get native endianness for dtype
; args:    edi = dtype_id
; returns: eax = ENDIAN_* constant
; note:    x86-64 is always little-endian for all supported dtypes
;          sub-byte types and variable-size types return ENDIAN_NA
; -----------------------------------------------------------------------------
global umath_dtype_native_endian
umath_dtype_native_endian:
    ; sub-byte types → NA
    cmp     edi, DTYPE_INT1
    je      .na
    cmp     edi, DTYPE_INT2
    je      .na
    cmp     edi, DTYPE_INT4
    je      .na
    cmp     edi, DTYPE_UINT4
    je      .na
    cmp     edi, DTYPE_FP6_E2M3
    je      .na
    cmp     edi, DTYPE_FP6_E3M2
    je      .na
    cmp     edi, DTYPE_MXFP6_E2M3
    je      .na
    cmp     edi, DTYPE_MXFP6_E3M2
    je      .na
    cmp     edi, DTYPE_MXFP4_E2M1
    je      .na
    cmp     edi, DTYPE_NVFP4
    je      .na
    cmp     edi, DTYPE_NVINT4
    je      .na

    ; single-byte types → NA (no byte order)
    cmp     edi, DTYPE_INT8
    je      .na
    cmp     edi, DTYPE_UINT8
    je      .na
    cmp     edi, DTYPE_FP8_E4M3
    je      .na
    cmp     edi, DTYPE_FP8_E5M2
    je      .na
    cmp     edi, DTYPE_FP8_E4M3_FNUZ
    je      .na
    cmp     edi, DTYPE_FP8_E5M2_FNUZ
    je      .na
    cmp     edi, DTYPE_BFLOAT8
    je      .na
    cmp     edi, DTYPE_MXFP8_E4M3
    je      .na
    cmp     edi, DTYPE_MXFP8_E5M2
    je      .na

    ; variable-size → NA
    cmp     edi, DTYPE_BIGINT
    je      .na
    cmp     edi, DTYPE_BIGFLOAT
    je      .na
    cmp     edi, DTYPE_BIT_PACKED
    je      .na

    ; NONE → NA
    test    edi, edi
    jz      .na

    ; all multi-byte types on x86-64 are little-endian
    mov     eax, ENDIAN_LITTLE
    ret
.na:
    mov     eax, ENDIAN_NA
    ret

; -----------------------------------------------------------------------------
; umath_dtype_is_little_endian - runtime check that this is little-endian
; returns: eax = 1 (always 1 on x86-64)
; note:    useful for cross-platform code that might run on BE arch
; -----------------------------------------------------------------------------
global umath_dtype_is_little_endian
umath_dtype_is_little_endian:
    ; on x86-64 this is always true
    ; verify at runtime by writing u16 and reading u8
    sub     rsp, 8
    mov     word [rsp], 0x0102
    movzx   eax, byte [rsp]
    cmp     eax, 0x02           ; little-endian: low byte first
    sete    al
    movzx   eax, al
    add     rsp, 8
    ret

; =============================================================================
; byte swap primitives
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_swap_bytes_16 - byte swap 16-bit value
; args:    di = value
; returns: ax = byte-swapped value
; example: 0x1234 → 0x3412
; -----------------------------------------------------------------------------
global umath_dtype_swap_bytes_16
umath_dtype_swap_bytes_16:
    mov     ax, di
    rol     ax, 8
    ret

; -----------------------------------------------------------------------------
; umath_dtype_swap_bytes_32 - byte swap 32-bit value
; args:    edi = value
; returns: eax = byte-swapped value
; example: 0x12345678 → 0x78563412
; -----------------------------------------------------------------------------
global umath_dtype_swap_bytes_32
umath_dtype_swap_bytes_32:
    mov     eax, edi
    bswap   eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_swap_bytes_64 - byte swap 64-bit value
; args:    rdi = value
; returns: rax = byte-swapped value
; -----------------------------------------------------------------------------
global umath_dtype_swap_bytes_64
umath_dtype_swap_bytes_64:
    mov     rax, rdi
    bswap   rax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_swap_bytes_128 - byte swap 128-bit value in-place
; args:    rdi = pointer to 128-bit value (two u64)
; returns: void (modifies in-place)
; example: [hi, lo] → [bswap(lo), bswap(hi)]
; -----------------------------------------------------------------------------
global umath_dtype_swap_bytes_128
umath_dtype_swap_bytes_128:
    mov     rax, [rdi]          ; lo
    mov     rcx, [rdi + 8]      ; hi
    bswap   rax
    bswap   rcx
    mov     [rdi], rcx          ; swapped hi → lo position
    mov     [rdi + 8], rax      ; swapped lo → hi position
    ret

; =============================================================================
; endian conversion
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_to_little_16 - convert u16 from specified endian to little
; args:    di  = value
;          esi = source endianness (ENDIAN_LITTLE or ENDIAN_BIG)
; returns: ax  = little-endian value
; -----------------------------------------------------------------------------
global umath_dtype_to_little_16
umath_dtype_to_little_16:
    cmp     esi, ENDIAN_BIG
    jne     .already_little
    rol     di, 8
.already_little:
    mov     ax, di
    ret

; -----------------------------------------------------------------------------
; umath_dtype_to_little_32 - convert u32 from specified endian to little
; args:    edi = value
;          esi = source endianness
; returns: eax = little-endian value
; -----------------------------------------------------------------------------
global umath_dtype_to_little_32
umath_dtype_to_little_32:
    cmp     esi, ENDIAN_BIG
    jne     .already_little
    bswap   edi
.already_little:
    mov     eax, edi
    ret

; -----------------------------------------------------------------------------
; umath_dtype_to_little_64 - convert u64 from specified endian to little
; args:    rdi = value
;          esi = source endianness
; returns: rax = little-endian value
; -----------------------------------------------------------------------------
global umath_dtype_to_little_64
umath_dtype_to_little_64:
    cmp     esi, ENDIAN_BIG
    jne     .already_little
    bswap   rdi
.already_little:
    mov     rax, rdi
    ret

; -----------------------------------------------------------------------------
; umath_dtype_to_big_16 - convert u16 little-endian to big-endian
; args:    di  = little-endian value
; returns: ax  = big-endian value
; note:    to_big and from_big are identical (swap is symmetric)
; -----------------------------------------------------------------------------
global umath_dtype_to_big_16
umath_dtype_to_big_16:
    mov     ax, di
    rol     ax, 8
    ret

; -----------------------------------------------------------------------------
; umath_dtype_to_big_32 - convert u32 little-endian to big-endian
; args:    edi = little-endian value
; returns: eax = big-endian value
; -----------------------------------------------------------------------------
global umath_dtype_to_big_32
umath_dtype_to_big_32:
    mov     eax, edi
    bswap   eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_to_big_64 - convert u64 little-endian to big-endian
; args:    rdi = little-endian value
; returns: rax = big-endian value
; -----------------------------------------------------------------------------
global umath_dtype_to_big_64
umath_dtype_to_big_64:
    mov     rax, rdi
    bswap   rax
    ret

; aliases (swap is symmetric)
global umath_dtype_from_big_16
umath_dtype_from_big_16:
    jmp     umath_dtype_to_big_16

global umath_dtype_from_big_32
umath_dtype_from_big_32:
    jmp     umath_dtype_to_big_32

global umath_dtype_from_big_64
umath_dtype_from_big_64:
    jmp     umath_dtype_to_big_64

; =============================================================================
; float byte swap
; (treat float bits as integer, bswap, reinterpret)
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_swap_f16 - byte swap FP16 value
; args:    di  = f16 bits
; returns: ax  = byte-swapped f16 bits
; note:    for network/file I/O only — result is NOT a valid float
;          until interpreted by the target endianness
; -----------------------------------------------------------------------------
global umath_dtype_swap_f16
umath_dtype_swap_f16:
    mov     ax, di
    rol     ax, 8
    ret

; -----------------------------------------------------------------------------
; umath_dtype_swap_f32 - byte swap FP32 value
; args:    xmm0 = f32 value
; returns: xmm0 = byte-swapped f32
; note:    result is NOT a valid float until target interprets it
; -----------------------------------------------------------------------------
global umath_dtype_swap_f32
umath_dtype_swap_f32:
    movd    eax, xmm0
    bswap   eax
    movd    xmm0, eax
    ret

; -----------------------------------------------------------------------------
; umath_dtype_swap_f64 - byte swap FP64 value
; args:    xmm0 = f64 value
; returns: xmm0 = byte-swapped f64
; -----------------------------------------------------------------------------
global umath_dtype_swap_f64
umath_dtype_swap_f64:
    movq    rax, xmm0
    bswap   rax
    movq    xmm0, rax
    ret

; =============================================================================
; buffer operations
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_swap_buf - byte-swap all elements in buffer (big↔little)
; args:    rdi = pointer to buffer
;          rsi = element count
;          edx = dtype_id
; returns: void (modifies buffer in-place)
; note:    no-op for single-byte dtypes
; -----------------------------------------------------------------------------
global umath_dtype_swap_buf
umath_dtype_swap_buf:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi            ; buffer
    mov     r12, rsi            ; count
    mov     r13d, edx           ; dtype_id

    ; get element size
    mov     edi, r13d
    call    umath_dtype_size_bytes
    test    eax, eax
    jz      .done               ; variable-size: skip
    cmp     eax, 1
    je      .done               ; single byte: no-op

    mov     ecx, eax            ; elem_size_bytes
    xor     rsi, rsi            ; index

    cmp     ecx, 2
    je      .loop_16
    cmp     ecx, 4
    je      .loop_32
    cmp     ecx, 8
    je      .loop_64
    cmp     ecx, 16
    je      .loop_128
    jmp     .done               ; unsupported size

.loop_16:
    cmp     rsi, r12
    jge     .done
    mov     ax, [rbx + rsi*2]
    rol     ax, 8
    mov     [rbx + rsi*2], ax
    inc     rsi
    jmp     .loop_16

.loop_32:
    cmp     rsi, r12
    jge     .done
    mov     eax, [rbx + rsi*4]
    bswap   eax
    mov     [rbx + rsi*4], eax
    inc     rsi
    jmp     .loop_32

.loop_64:
    cmp     rsi, r12
    jge     .done
    mov     rax, [rbx + rsi*8]
    bswap   rax
    mov     [rbx + rsi*8], rax
    inc     rsi
    jmp     .loop_64

.loop_128:
    cmp     rsi, r12
    jge     .done
    ; compute byte offset = index * 16
    push    rsi
    imul    rsi, 16
    lea     rdi, [rbx + rsi]
    call    umath_dtype_swap_bytes_128
    pop     rsi
    inc     rsi
    jmp     .loop_128

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_dtype_convert_endian_buf - convert buffer from one endian to another
; args:    rdi = destination buffer
;          rsi = source buffer
;          rdx = element count
;          ecx = dtype_id
;          r8d = source endianness (ENDIAN_* constant)
;          r9d = destination endianness (ENDIAN_* constant)
; returns: void
; -----------------------------------------------------------------------------
global umath_dtype_convert_endian_buf
umath_dtype_convert_endian_buf:
    ; if same endianness, just memcpy
    cmp     r8d, r9d
    je      .same

    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi            ; dst
    mov     r12, rsi            ; src
    mov     r13, rdx            ; count
    mov     r14d, ecx           ; dtype_id
    ; r8d = src_endian, r9d = dst_endian

    ; get element size
    mov     edi, r14d
    call    umath_dtype_size_bytes
    test    eax, eax
    jz      .copy_done
    mov     r15d, eax           ; elem_size

    xor     rcx, rcx            ; index
.conv_loop:
    cmp     rcx, r13
    jge     .copy_done

    ; compute element byte offset
    push    rcx
    imul    rcx, r15            ; byte offset

    ; copy element
    cmp     r15d, 1
    je      .copy1
    cmp     r15d, 2
    je      .copy2
    cmp     r15d, 4
    je      .copy4
    cmp     r15d, 8
    je      .copy8

.copy8:
    mov     rax, [r12 + rcx]
    bswap   rax
    mov     [rbx + rcx], rax
    jmp     .next
.copy4:
    mov     eax, [r12 + rcx]
    bswap   eax
    mov     [rbx + rcx], eax
    jmp     .next
.copy2:
    mov     ax, [r12 + rcx]
    rol     ax, 8
    mov     [rbx + rcx], ax
    jmp     .next
.copy1:
    mov     al, [r12 + rcx]
    mov     [rbx + rcx], al
.next:
    pop     rcx
    inc     rcx
    jmp     .conv_loop

.copy_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.same:
    ; same endianness: memcpy
    push    rbx
    mov     rbx, rcx            ; dtype_id
    push    r8
    push    r9
    ; count bytes = count * elem_size
    mov     edi, r14d           ; dtype_id (still in ecx at this point)
    ; actually just use rep movsb for simplicity
    ; rdx = count, need byte count
    mov     edi, ecx            ; dtype_id
    push    rdx
    call    umath_dtype_size_bytes
    pop     rdx
    imul    rdx, rax            ; total bytes
    mov     rcx, rdx
    rep     movsb
    pop     r9
    pop     r8
    pop     rbx
    ret