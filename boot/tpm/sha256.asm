; =============================================================================
; Tattva OS — boot/tpm/sha256.asm
; =============================================================================
; Standalone SHA-256 implementation in x86-64 assembly.
;
; Author:  Utkarsha Labs
; Target:  x86-64 long mode
; =============================================================================

%ifndef SHA256_ASM
%define SHA256_ASM

[BITS 64]

; =============================================================================
; sha256_hash — Compute SHA-256 hash of a buffer
; Input:  RSI = pointer to input data
;         RCX = length of input data (bytes)
;         RDI = pointer to 32-byte output buffer
; Output: none
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8-R15
; =============================================================================
sha256_hash:
    push rbp
    mov rbp, rsp
    sub rsp, 384                     ; Local stack allocation
                                     ; [rbp-32]:  state (H0..H7, 8 dwords = 32 bytes)
                                     ; [rbp-40]:  remaining bytes (8 bytes)
                                     ; [rbp-48]:  current data pointer (8 bytes)
                                     ; [rbp-304]: W array (64 dwords = 256 bytes)
                                     ; [rbp-312]: original length (8 bytes)
                                     ; [rbp-320]: original output pointer (8 bytes)
                                     ; [rbp-384]: block buffer (64 bytes)

    ; Save inputs
    mov [rbp-320], rdi
    mov [rbp-312], rcx
    mov [rbp-48], rsi
    mov [rbp-40], rcx

    ; Initialize state H0..H7
    mov dword [rbp-32],  0x6a09e667
    mov dword [rbp-28],  0xbb67ae85
    mov dword [rbp-24],  0x3c6ef372
    mov dword [rbp-20],  0xa54ff53a
    mov dword [rbp-16],  0x510e527f
    mov dword [rbp-12],  0x9b05688c
    mov dword [rbp-8],   0x1f83d9ab
    mov dword [rbp-4],   0x5be0cd19

.loop_blocks:
    mov rcx, [rbp-40]
    cmp rcx, 64
    jb .padding                      ; less than 64 bytes left

    ; Copy 64 bytes to block buffer [rbp-384]
    mov rsi, [rbp-48]
    lea rdi, [rbp-384]
    mov ecx, 16                      ; 16 dwords = 64 bytes
    rep movsd

    ; Advance pointers
    add qword [rbp-48], 64
    sub qword [rbp-40], 64

    ; Process block
    call sha256_process_block
    jmp .loop_blocks

.padding:
    ; Copy remaining bytes
    lea rdi, [rbp-384]
    mov rsi, [rbp-48]
    mov rcx, [rbp-40]
    test rcx, rcx
    jz .padding_start
    rep movsb

.padding_start:
    ; Append 0x80 byte
    mov rax, [rbp-40]
    lea rdi, [rbp-384]
    mov byte [rdi + rax], 0x80
    inc rax

    ; Check room for 8-byte length
    cmp rax, 56
    jbe .fill_zeros

    ; No room. Pad current block with zeros, process, and use a new block.
.fill_first_block_zeros:
    cmp rax, 64
    jae .process_overflow_block
    mov byte [rdi + rax], 0
    inc rax
    jmp .fill_first_block_zeros

.process_overflow_block:
    call sha256_process_block
    xor rax, rax                     ; new block starts at index 0

.fill_zeros:
    lea rdi, [rbp-384]
.fill_loop:
    cmp rax, 56
    jae .write_len
    mov byte [rdi + rax], 0
    inc rax
    jmp .fill_loop

.write_len:
    ; Write length in bits as a 64-bit big-endian integer
    mov rax, [rbp-312]
    shl rax, 3                       ; convert to bits
    bswap rax
    mov [rdi + 56], rax

    call sha256_process_block

    ; Copy final state to output buffer
    mov rdi, [rbp-320]
    lea rsi, [rbp-32]
    mov ecx, 8                       ; 8 dwords = 32 bytes
    rep movsd

    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; sha256_process_block — Process 64-byte block in [rbp-384]
; =============================================================================
sha256_process_block:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    ; 1. Load and swap 16 dwords from [rbp-384] into W[0..15] at [rbp-304]
    lea rsi, [rbp-384]
    lea rdi, [rbp-304]
    mov ecx, 16
.load_w:
    lodsd
    bswap eax
    stosd
    loop .load_w

    ; 2. Extend W[16..63]
    mov ecx, 16
.extend_w:
    cmp ecx, 64
    je .extend_w_done

    ; W[i-15]
    mov eax, [rbp-304 + rcx*4 - 15*4]
    ; s0 = (eax ROR 7) ^ (eax ROR 18) ^ (eax SHR 3)
    mov edx, eax
    ror edx, 7
    mov ebx, eax
    ror ebx, 18
    xor edx, ebx
    shr eax, 3
    xor edx, eax                     ; EDX = s0

    ; W[i-2]
    mov eax, [rbp-304 + rcx*4 - 2*4]
    ; s1 = (eax ROR 17) ^ (eax ROR 19) ^ (eax SHR 10)
    mov esi, eax
    ror esi, 17
    mov edi, eax
    ror edi, 19
    xor esi, edi
    shr eax, 10
    xor esi, eax                     ; ESI = s1

    ; W[i] = W[i-16] + s0 + W[i-7] + s1
    mov eax, [rbp-304 + rcx*4 - 16*4]
    add eax, edx
    add eax, [rbp-304 + rcx*4 - 7*4]
    add eax, esi
    mov [rbp-304 + rcx*4], eax

    inc ecx
    jmp .extend_w

.extend_w_done:
    ; 3. Initialize working variables with state
    mov r8d,  [rbp-32]               ; a
    mov r9d,  [rbp-28]               ; b
    mov r10d, [rbp-24]               ; c
    mov r11d, [rbp-20]               ; d
    mov r12d, [rbp-16]               ; e
    mov r13d, [rbp-12]               ; f
    mov r14d, [rbp-8]                ; g
    mov r15d, [rbp-4]                ; h

    ; 4. Compression loop
    xor ecx, ecx
.compress_loop:
    cmp ecx, 64
    je .compress_done

    ; S1 = (e ROR 6) ^ (e ROR 11) ^ (e ROR 25)
    mov edx, r12d
    ror edx, 6
    mov ebx, r12d
    ror ebx, 11
    xor edx, ebx
    mov ebx, r12d
    ror ebx, 25
    xor edx, ebx                     ; EDX = S1

    ; ch = (e & f) ^ (~e & g)
    mov eax, r12d
    and eax, r13d
    mov ebx, r12d
    not ebx
    and ebx, r14d
    xor eax, ebx                     ; EAX = ch

    ; temp1 = h + S1 + ch + K[i] + W[i]
    mov esi, r15d
    add esi, edx
    add esi, eax
    lea rdx, [rel K256]
    add esi, [rdx + rcx*4]
    add esi, [rbp-304 + rcx*4]       ; ESI = temp1

    ; S0 = (a ROR 2) ^ (a ROR 13) ^ (a ROR 22)
    mov edx, r8d
    ror edx, 2
    mov ebx, r8d
    ror ebx, 13
    xor edx, ebx
    mov ebx, r8d
    ror ebx, 22
    xor edx, ebx                     ; EDX = S0

    ; maj = (a & b) ^ (a & c) ^ (b & c)
    mov eax, r8d
    and eax, r9d
    mov ebx, r8d
    and ebx, r10d
    xor eax, ebx
    mov ebx, r9d
    and ebx, r10d
    xor eax, ebx                     ; EAX = maj

    ; temp2 = S0 + maj
    add edx, eax                     ; EDX = temp2

    ; Update state variables
    mov r15d, r14d                   ; h = g
    mov r14d, r13d                   ; g = f
    mov r13d, r12d                   ; f = e
    mov r12d, r11d
    add r12d, esi                    ; e = d + temp1
    mov r11d, r10d                   ; d = c
    mov r10d, r9d                    ; c = b
    mov r9d, r8d                     ; b = a
    mov r8d, esi
    add r8d, edx                     ; a = temp1 + temp2

    inc ecx
    jmp .compress_loop

.compress_done:
    ; 5. Add working variables back to state
    add [rbp-32], r8d
    add [rbp-28], r9d
    add [rbp-24], r10d
    add [rbp-20], r11d
    add [rbp-16], r12d
    add [rbp-12], r13d
    add [rbp-8],  r14d
    add [rbp-4],  r15d

    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; =============================================================================
; SHA-256 Round Constants
; =============================================================================
align 4
K256:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664d, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

%endif ; SHA256_ASM
