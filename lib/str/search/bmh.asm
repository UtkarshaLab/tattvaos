; =============================================================================
; str/search/bmh.asm
; Boyer-Moore-Horspool fast string search engine.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; Boyer-Moore-Horspool algorithm:
;
;   Preprocessing: build a bad-character shift table from the pattern.
;   For each byte value b, shift[b] = distance to shift when b is the
;   last character of the current window that doesn't match.
;
;   Default shift = pattern length (byte not in pattern at all).
;   For each byte in pattern[0..m-2], shift[b] = m - 1 - i.
;   (Pattern's last byte is NOT put in table — it triggers verification.)
;
;   Search: align pattern at text[0], compare right-to-left.
;   On mismatch, shift window by shift[text[pos + m - 1]].
;   On full match, record position.
;
; Performance:
;   Best case:  O(n/m) — sublinear for long patterns
;   Average:    O(n)
;   Worst case: O(nm) — pathological (e.g. "aaa..." in "aaaa...")
;
; For patterns <= 1 byte, falls back to linear scan.
; For case-insensitive search, call bmh_nocase variants.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Size of bad-character shift table (256 entries, one per byte value)
BMH_TABLE_SIZE  equ 256

section .text

; -----------------------------------------------------------------------------
; str_bmh_build_table
;
; Build the BMH bad-character shift table for a pattern.
; Table must be caller-allocated: uint64_t table[256].
;
; Signature:
;   int64_t str_bmh_build_table(const uint8_t *pat, uint64_t pat_len,
;                                uint64_t *table)
;
; Arguments:
;   RDI  — pattern pointer
;   RSI  — pattern length
;   RDX  — pointer to 256-entry uint64_t table
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL          pat or table is null
;   RAX  = STR_ERR_INVALID_ARG   pat_len == 0
; -----------------------------------------------------------------------------

STR_FUNC str_bmh_build_table

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    test    rsi, rsi
    jz      .err_zero_pat

    push_regs rbx, r12, r13

    mov     rbx, rdi            ; pat
    mov     r12, rsi            ; pat_len
    mov     r13, rdx            ; table

    ; initialize all entries to pat_len (default shift)
    xor     ecx, ecx
.init_loop:
    cmp     rcx, BMH_TABLE_SIZE
    jae     .init_done
    mov     [r13 + rcx * 8], r12
    inc     rcx
    jmp     .init_loop

.init_done:
    ; for i = 0 to pat_len - 2: table[pat[i]] = pat_len - 1 - i
    xor     rcx, rcx

.fill_loop:
    mov     rdx, r12
    dec     rdx                 ; pat_len - 1
    cmp     rcx, rdx            ; stop before last byte
    jae     .fill_done

    movzx   eax, byte [rbx + rcx]   ; pat[i]
    mov     rdx, r12
    dec     rdx
    sub     rdx, rcx            ; pat_len - 1 - i
    mov     [r13 + rax * 8], rdx

    inc     rcx
    jmp     .fill_loop

.fill_done:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.err_zero_pat:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_bmh_build_table

; -----------------------------------------------------------------------------
; str_bmh_search
;
; Search for first occurrence of pattern in text using prebuilt shift table.
;
; Signature:
;   int64_t str_bmh_search(const uint8_t *text, uint64_t text_len,
;                           const uint8_t *pat, uint64_t pat_len,
;                           const uint64_t *table)
;
; Arguments:
;   RDI  — text pointer
;   RSI  — text length
;   RDX  — pattern pointer
;   RCX  — pattern length
;   R8   — shift table (256 * uint64_t)
;
; Returns:
;   RAX >= 0   byte offset of first match
;   RAX  = STR_ERR_NOT_FOUND   pattern not found
;   RAX  = STR_ERR_NULL        null pointer
;   RAX  = STR_ERR_INVALID_ARG pat_len == 0
; -----------------------------------------------------------------------------

STR_FUNC str_bmh_search

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    test    rcx, rcx
    jz      .err_zero

    ; pattern longer than text → not found
    cmp     rcx, rsi
    ja      .not_found

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; text
    mov     r12, rsi            ; text_len
    mov     r13, rdx            ; pat
    mov     r14, rcx            ; pat_len
    mov     r15, r8             ; table

    ; single byte pattern — linear scan (faster than BMH setup)
    cmp     r14, 1
    je      .single_byte

    ; window start position
    xor     r9, r9              ; pos = 0
    mov     r10, r12
    sub     r10, r14            ; last valid pos = text_len - pat_len

.bmh_outer:
    cmp     r9, r10
    ja      .not_found_pop

    ; compare pattern right-to-left
    mov     r11, r14
    dec     r11                 ; j = pat_len - 1

.bmh_inner:
    movzx   eax, byte [rbx + r9 + r11]
    cmp     al, byte [r13 + r11]
    jne     .bmh_shift

    test    r11, r11
    jz      .bmh_match

    dec     r11
    jmp     .bmh_inner

.bmh_match:
    mov     rax, r9             ; return match offset
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.bmh_shift:
    ; shift by table[text[pos + pat_len - 1]]
    movzx   eax, byte [rbx + r9 + r14 - 1]
    mov     rax, [r15 + rax * 8]
    add     r9, rax
    jmp     .bmh_outer

.single_byte:
    ; linear scan for single byte pattern
    movzx   ecx, byte [r13]
    xor     r9, r9

.sb_scan:
    cmp     r9, r12
    jae     .not_found_pop

    movzx   eax, byte [rbx + r9]
    cmp     al, cl
    je      .sb_found

    inc     r9
    jmp     .sb_scan

.sb_found:
    mov     rax, r9
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.not_found_pop:
    pop_regs r15, r14, r13, r12, rbx
.not_found:
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

.err_zero:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_bmh_search

; -----------------------------------------------------------------------------
; str_bmh_search_from
;
; Like str_bmh_search but starts from a given byte offset in text.
;
; Signature:
;   int64_t str_bmh_search_from(const uint8_t *text, uint64_t text_len,
;                                const uint8_t *pat, uint64_t pat_len,
;                                const uint64_t *table, uint64_t from)
;
; Arguments:
;   RDI  — text
;   RSI  — text_len
;   RDX  — pat
;   RCX  — pat_len
;   R8   — table
;   R9   — from (byte offset to start search)
;
; Returns:
;   RAX >= 0   byte offset of match (absolute, not relative to from)
;   RAX  = STR_ERR_NOT_FOUND
; -----------------------------------------------------------------------------

STR_FUNC str_bmh_search_from

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    ; clamp: if from >= text_len → not found
    cmp     r9, rsi
    jae     .not_found_from

    ; adjust text ptr and length
    add     rdi, r9
    sub     rsi, r9

    ; search in adjusted range
    push    r9                  ; save original offset
    call    str_bmh_search
    pop     r9

    ; if found, add back the original offset
    test    rax, rax
    js      .not_found_from_ret ; negative → error (STR_ERR_NOT_FOUND)

    add     rax, r9
    pop     rbp
    ret

.not_found_from:
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

.not_found_from_ret:
    pop     rbp
    ret

STR_ENDFUNC str_bmh_search_from

; -----------------------------------------------------------------------------
; str_bmh_search_all
;
; Find ALL occurrences of pattern in text.
; Writes byte offsets into a caller-supplied uint64_t array.
;
; Signature:
;   int64_t str_bmh_search_all(const uint8_t *text, uint64_t text_len,
;                               const uint8_t *pat, uint64_t pat_len,
;                               const uint64_t *table,
;                               uint64_t *offsets, uint64_t offsets_cap,
;                               uint64_t *out_count)
;
; Arguments:
;   RDI  — text
;   RSI  — text_len
;   RDX  — pat
;   RCX  — pat_len
;   R8   — table
;   R9   — offsets array
;   [rsp+8]  — offsets_cap (7th arg on stack after call)
;   [rsp+16] — out_count
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL  more matches than offsets_cap
; -----------------------------------------------------------------------------

STR_FUNC str_bmh_search_all

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; text
    mov     r12, rsi            ; text_len
    mov     r13, rdx            ; pat
    mov     r14, rcx            ; pat_len
    mov     r15, r8             ; table

    ; stack args (after push_regs: rsp moved down 5*8=40 bytes + rbp=8)
    ; original rsp+8  = offsets_cap  → now at [rsp + 40 + 8 + 8] = [rsp+56]
    ; original rsp+16 = out_count    → now at [rsp + 40 + 8 + 16] = [rsp+64]
    mov     r10, r9             ; offsets array
    mov     r11, [rsp + 56]     ; offsets_cap
    mov     r9,  [rsp + 64]     ; out_count ptr

    xor     ecx, ecx            ; match count
    xor     r8, r8              ; current search pos

.all_loop:
    ; remaining = text_len - pos
    mov     rsi, r12
    sub     rsi, r8
    jz      .all_done
    js      .all_done

    mov     rdi, rbx
    add     rdi, r8
    mov     rdx, r13
    mov     rcx, r14            ; pat_len — also used as counter above, save
    push    rcx
    mov     rcx, r14
    ; rcx = pat_len for search call
    ; rdi = text+pos, rsi = remaining, rdx = pat, rcx = pat_len, r8 = bad: table now gone

    ; we need to call str_bmh_search(text+pos, remaining, pat, pat_len, table)
    push    r8                  ; save pos
    push    r10                 ; save offsets
    push    r11                 ; save cap
    push    r9                  ; save out_count ptr

    mov     r8, r15             ; table
    ; rcx already = pat_len
    call    str_bmh_search

    pop     r9
    pop     r11
    pop     r10
    pop     r8                  ; pos
    pop     rcx                 ; match count

    test    rax, rax
    js      .all_done           ; STR_ERR_NOT_FOUND → done

    ; found at relative offset rax → absolute = r8 + rax
    add     rax, r8

    ; store in offsets array
    cmp     rcx, r11
    jae     .all_too_small

    mov     [r10 + rcx * 8], rax
    inc     rcx

    ; advance pos past this match (non-overlapping)
    mov     r8, rax
    add     r8, r14             ; pos = match_pos + pat_len
    jmp     .all_loop

.all_done:
    test    r9, r9
    jz      .all_ok
    mov     [r9], rcx

.all_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.all_too_small:
    test    r9, r9
    jz      .all_too_small_ret
    mov     [r9], rcx           ; write partial count

.all_too_small_ret:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_bmh_search_all

; -----------------------------------------------------------------------------
; str_bmh_build_table_nocase
;
; Build shift table for case-insensitive search.
; Folds pattern bytes to lowercase before building table.
;
; Signature:
;   int64_t str_bmh_build_table_nocase(const uint8_t *pat, uint64_t pat_len,
;                                       uint64_t *table)
; -----------------------------------------------------------------------------

STR_FUNC str_bmh_build_table_nocase

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    test    rsi, rsi
    jz      .err_nc

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    ; init table to pat_len
    xor     ecx, ecx
.nc_init:
    cmp     rcx, BMH_TABLE_SIZE
    jae     .nc_init_done
    mov     [r13 + rcx * 8], r12
    inc     rcx
    jmp     .nc_init

.nc_init_done:
    xor     rcx, rcx

.nc_fill:
    mov     rdx, r12
    dec     rdx
    cmp     rcx, rdx
    jae     .nc_fill_done

    movzx   eax, byte [rbx + rcx]

    ; fold to lowercase
    cmp     al, 'A'
    jb      .nc_no_fold
    cmp     al, 'Z'
    ja      .nc_no_fold
    or      al, 0x20

.nc_no_fold:
    mov     rdx, r12
    dec     rdx
    sub     rdx, rcx
    mov     [r13 + rax * 8], rdx

    ; also set for uppercase version
    movzx   eax, byte [rbx + rcx]
    cmp     al, 'a'
    jb      .nc_skip_upper
    cmp     al, 'z'
    ja      .nc_skip_upper
    and     al, 0xDF            ; to uppercase
    mov     [r13 + rax * 8], rdx

.nc_skip_upper:
    inc     rcx
    jmp     .nc_fill

.nc_fill_done:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.err_nc:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_bmh_build_table_nocase