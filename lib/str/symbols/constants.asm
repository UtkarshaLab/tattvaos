; =============================================================================
; str/symbols/constants.asm
; Named codepoint constants for all Unicode symbol categories
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 (primary)
; Assembler: NASM
;
; Usage:
;   %include "arch/common/types.inc"
;   %include "symbols/constants.asm"
;
;   mov eax, MATH_SYM_PI        ; eax = 0x03C0
;   call str_utf8_encode        ; encode π into output buffer
;
; All constants are 32-bit Unicode codepoints (U+XXXX or U+XXXXX).
; Store in resd / dd. Pass in 32-bit registers (EAX, ECX, EDX...).
; =============================================================================

%ifndef STR_SYMBOLS_CONSTANTS_ASM
%define STR_SYMBOLS_CONSTANTS_ASM

; -----------------------------------------------------------------------------
; Greek lowercase  (U+03B1..U+03C9)
; -----------------------------------------------------------------------------

GREEK_LOWER_ALPHA       equ 0x03B1  ; α
GREEK_LOWER_BETA        equ 0x03B2  ; β
GREEK_LOWER_GAMMA       equ 0x03B3  ; γ
GREEK_LOWER_DELTA       equ 0x03B4  ; δ
GREEK_LOWER_EPSILON     equ 0x03B5  ; ε
GREEK_LOWER_ZETA        equ 0x03B6  ; ζ
GREEK_LOWER_ETA         equ 0x03B7  ; η
GREEK_LOWER_THETA       equ 0x03B8  ; θ
GREEK_LOWER_IOTA        equ 0x03B9  ; ι
GREEK_LOWER_KAPPA       equ 0x03BA  ; κ
GREEK_LOWER_LAMBDA      equ 0x03BB  ; λ
GREEK_LOWER_MU          equ 0x03BC  ; μ
GREEK_LOWER_NU          equ 0x03BD  ; ν
GREEK_LOWER_XI          equ 0x03BE  ; ξ
GREEK_LOWER_OMICRON     equ 0x03BF  ; ο
GREEK_LOWER_PI          equ 0x03C0  ; π
GREEK_LOWER_RHO         equ 0x03C1  ; ρ
GREEK_LOWER_SIGMA_FINAL equ 0x03C2  ; ς  (word-final sigma)
GREEK_LOWER_SIGMA       equ 0x03C3  ; σ
GREEK_LOWER_TAU         equ 0x03C4  ; τ
GREEK_LOWER_UPSILON     equ 0x03C5  ; υ
GREEK_LOWER_PHI         equ 0x03C6  ; φ
GREEK_LOWER_CHI         equ 0x03C7  ; χ
GREEK_LOWER_PSI         equ 0x03C8  ; ψ
GREEK_LOWER_OMEGA       equ 0x03C9  ; ω

; -----------------------------------------------------------------------------
; Greek uppercase  (U+0391..U+03A9)
; -----------------------------------------------------------------------------

GREEK_UPPER_ALPHA       equ 0x0391  ; Α
GREEK_UPPER_BETA        equ 0x0392  ; Β
GREEK_UPPER_GAMMA       equ 0x0393  ; Γ
GREEK_UPPER_DELTA       equ 0x0394  ; Δ
GREEK_UPPER_EPSILON     equ 0x0395  ; Ε
GREEK_UPPER_ZETA        equ 0x0396  ; Ζ
GREEK_UPPER_ETA         equ 0x0397  ; Η
GREEK_UPPER_THETA       equ 0x0398  ; Θ
GREEK_UPPER_IOTA        equ 0x0399  ; Ι
GREEK_UPPER_KAPPA       equ 0x039A  ; Κ
GREEK_UPPER_LAMBDA      equ 0x039B  ; Λ
GREEK_UPPER_MU          equ 0x039C  ; Μ
GREEK_UPPER_NU          equ 0x039D  ; Ν
GREEK_UPPER_XI          equ 0x039E  ; Ξ
GREEK_UPPER_OMICRON     equ 0x039F  ; Ο
GREEK_UPPER_PI          equ 0x03A0  ; Π
GREEK_UPPER_RHO         equ 0x03A1  ; Ρ
GREEK_UPPER_SIGMA       equ 0x03A3  ; Σ  (0x03A2 unassigned)
GREEK_UPPER_TAU         equ 0x03A4  ; Τ
GREEK_UPPER_UPSILON     equ 0x03A5  ; Υ
GREEK_UPPER_PHI         equ 0x03A6  ; Φ
GREEK_UPPER_CHI         equ 0x03A7  ; Χ
GREEK_UPPER_PSI         equ 0x03A8  ; Ψ
GREEK_UPPER_OMEGA       equ 0x03A9  ; Ω

; -----------------------------------------------------------------------------
; Mathematical operators  (U+2200..U+22FF)
; -----------------------------------------------------------------------------

MATH_SYM_FOR_ALL        equ 0x2200  ; ∀  for all
MATH_SYM_PARTIAL        equ 0x2202  ; ∂  partial differential
MATH_SYM_THERE_EXISTS   equ 0x2203  ; ∃  there exists
MATH_SYM_THERE_NOT_EXISTS equ 0x2204 ; ∄ there does not exist
MATH_SYM_EMPTY_SET      equ 0x2205  ; ∅  empty set
MATH_SYM_NABLA          equ 0x2207  ; ∇  nabla / del
MATH_SYM_ELEMENT_OF     equ 0x2208  ; ∈  element of
MATH_SYM_NOT_ELEMENT_OF equ 0x2209  ; ∉  not element of
MATH_SYM_CONTAINS       equ 0x220B  ; ∋  contains as member
MATH_SYM_PRODUCT        equ 0x220F  ; ∏  n-ary product
MATH_SYM_COPRODUCT      equ 0x2210  ; ∐  n-ary coproduct
MATH_SYM_SIGMA          equ 0x2211  ; ∑  n-ary summation
MATH_SYM_MINUS          equ 0x2212  ; −  minus sign
MATH_SYM_PLUS_MINUS     equ 0x00B1  ; ±  plus-minus sign
MATH_SYM_SQRT           equ 0x221A  ; √  square root
MATH_SYM_CBRT           equ 0x221B  ; ∛  cube root
MATH_SYM_FOURTHRT       equ 0x221C  ; ∜  fourth root
MATH_SYM_PROPORTIONAL   equ 0x221D  ; ∝  proportional to
MATH_SYM_INF            equ 0x221E  ; ∞  infinity
MATH_SYM_ANGLE          equ 0x2220  ; ∠  angle
MATH_SYM_AND            equ 0x2227  ; ∧  logical and
MATH_SYM_OR             equ 0x2228  ; ∨  logical or
MATH_SYM_INTERSECT      equ 0x2229  ; ∩  intersection
MATH_SYM_UNION          equ 0x222A  ; ∪  union
MATH_SYM_INTEGRAL       equ 0x222B  ; ∫  integral
MATH_SYM_DOUBLE_INT     equ 0x222C  ; ∬  double integral
MATH_SYM_TRIPLE_INT     equ 0x222D  ; ∭  triple integral
MATH_SYM_CONTOUR_INT    equ 0x222E  ; ∮  contour integral
MATH_SYM_APPROX         equ 0x2248  ; ≈  almost equal to
MATH_SYM_NOT_EQUAL      equ 0x2260  ; ≠  not equal to
MATH_SYM_IDENTICAL      equ 0x2261  ; ≡  identical to
MATH_SYM_LESS_EQ        equ 0x2264  ; ≤  less than or equal
MATH_SYM_GREATER_EQ     equ 0x2265  ; ≥  greater than or equal
MATH_SYM_SUBSET         equ 0x2282  ; ⊂  subset of
MATH_SYM_SUPERSET       equ 0x2283  ; ⊃  superset of
MATH_SYM_SUBSET_EQ      equ 0x2286  ; ⊆  subset of or equal
MATH_SYM_SUPERSET_EQ    equ 0x2287  ; ⊇  superset of or equal
MATH_SYM_OPLUS          equ 0x2295  ; ⊕  circled plus (direct sum)
MATH_SYM_OMINUS         equ 0x2296  ; ⊖  circled minus
MATH_SYM_OTIMES         equ 0x2297  ; ⊗  circled times (tensor product)
MATH_SYM_ODOT           equ 0x2299  ; ⊙  circled dot
MATH_SYM_PERP           equ 0x22A5  ; ⊥  perpendicular / bottom
MATH_SYM_TURNSTILE      equ 0x22A2  ; ⊢  right tack (proves)
MATH_SYM_MODELS         equ 0x22A8  ; ⊨  true / models
MATH_SYM_CDOT           equ 0x22C5  ; ⋅  dot operator
MATH_SYM_STAR           equ 0x22C6  ; ⋆  star operator

; -----------------------------------------------------------------------------
; Arrows  (U+2190..U+21FF, U+27F5..U+27FF, U+2900..U+297F)
; -----------------------------------------------------------------------------

ARROW_LEFT              equ 0x2190  ; ←
ARROW_UP                equ 0x2191  ; ↑
ARROW_RIGHT             equ 0x2192  ; →
ARROW_DOWN              equ 0x2193  ; ↓
ARROW_LEFT_RIGHT        equ 0x2194  ; ↔
ARROW_UP_DOWN           equ 0x2195  ; ↕
ARROW_DOUBLE_LEFT       equ 0x21D0  ; ⇐
ARROW_DOUBLE_RIGHT      equ 0x21D2  ; ⇒
ARROW_DOUBLE_LR         equ 0x21D4  ; ⇔
ARROW_MAPS_TO           equ 0x21A6  ; ↦
ARROW_LONG_RIGHT        equ 0x27F6  ; ⟶
ARROW_LONG_LEFT         equ 0x27F5  ; ⟵
ARROW_LONG_LR           equ 0x27F7  ; ⟷
ARROW_LONG_DOUBLE_RIGHT equ 0x27F9  ; ⟹
ARROW_LONG_DOUBLE_LR    equ 0x27FA  ; ⟺
ARROW_LONG_MAPS_TO      equ 0x27FC  ; ⟼
ANGLE_LEFT              equ 0x27E8  ; ⟨  mathematical left angle bracket
ANGLE_RIGHT             equ 0x27E9  ; ⟩  mathematical right angle bracket

; -----------------------------------------------------------------------------
; Blackboard bold — number sets  (U+2115, U+2124, U+211A, U+211D, U+2102...)
; -----------------------------------------------------------------------------

BB_NATURALS             equ 0x2115  ; ℕ  natural numbers
BB_INTEGERS             equ 0x2124  ; ℤ  integers
BB_RATIONALS            equ 0x211A  ; ℚ  rationals
BB_REALS                equ 0x211D  ; ℝ  reals
BB_COMPLEX              equ 0x2102  ; ℂ  complex numbers
BB_QUATERNIONS          equ 0x210D  ; ℍ  quaternions
BB_PRIMES               equ 0x2119  ; ℙ  primes

; Blackboard bold capital letters  (U+1D538..U+1D56B, Mathematical Alphanumeric)
BB_A                    equ 0x1D538 ; 𝔸
BB_B                    equ 0x1D539 ; 𝔹
BB_C                    equ 0x2102  ; ℂ  (canonical form)
BB_D                    equ 0x1D53B ; 𝔻
BB_E                    equ 0x1D53C ; 𝔼
BB_F                    equ 0x1D53D ; 𝔽
BB_G                    equ 0x1D53E ; 𝔾
BB_H                    equ 0x210D  ; ℍ  (canonical form)
BB_I                    equ 0x1D540 ; 𝕀
BB_J                    equ 0x1D541 ; 𝕁
BB_K                    equ 0x1D542 ; 𝕂
BB_L                    equ 0x1D543 ; 𝕃
BB_M                    equ 0x1D544 ; 𝕄
BB_N                    equ 0x2115  ; ℕ  (canonical form)
BB_O                    equ 0x1D546 ; 𝕆
BB_P                    equ 0x2119  ; ℙ  (canonical form)
BB_Q                    equ 0x211A  ; ℚ  (canonical form)
BB_R                    equ 0x211D  ; ℝ  (canonical form)
BB_S                    equ 0x1D54A ; 𝕊
BB_T                    equ 0x1D54B ; 𝕋
BB_Z                    equ 0x2124  ; ℤ  (canonical form)

; -----------------------------------------------------------------------------
; Fraktur — Lie algebras, etc.  (U+1D504..U+1D537)
; -----------------------------------------------------------------------------

FRAK_A                  equ 0x1D504 ; 𝔄
FRAK_B                  equ 0x1D505 ; 𝔅
FRAK_C                  equ 0x212D  ; ℭ  (canonical form)
FRAK_D                  equ 0x1D507 ; 𝔇
FRAK_E                  equ 0x1D508 ; 𝔈
FRAK_F                  equ 0x1D509 ; 𝔉
FRAK_G                  equ 0x1D50A ; 𝔊
FRAK_H                  equ 0x210C  ; ℌ  (canonical form)
FRAK_I                  equ 0x2111  ; ℑ  (canonical form, imaginary part)
FRAK_J                  equ 0x1D50D ; 𝔍
FRAK_K                  equ 0x1D50E ; 𝔎
FRAK_L                  equ 0x1D50F ; 𝔏
FRAK_M                  equ 0x1D510 ; 𝔐
FRAK_N                  equ 0x1D511 ; 𝔑
FRAK_P                  equ 0x1D513 ; 𝔓
FRAK_R                  equ 0x211C  ; ℜ  (canonical form, real part)
FRAK_Z                  equ 0x2128  ; ℨ  (canonical form)

; Fraktur lowercase — common Lie algebra letters
FRAK_LOWER_G            equ 0x1D524 ; 𝔤  Lie algebra g
FRAK_LOWER_H            equ 0x1D525 ; 𝔥  Cartan subalgebra h
FRAK_LOWER_B            equ 0x1D51F ; 𝔟  Borel subalgebra b
FRAK_LOWER_N            equ 0x1D52B ; 𝔫  nilradical n
FRAK_LOWER_P            equ 0x1D52D ; 𝔭  parabolic subalgebra p
FRAK_LOWER_M            equ 0x1D52A ; 𝔪  maximal ideal m
FRAK_LOWER_K            equ 0x1D528 ; 𝔨  compact real form k
FRAK_LOWER_SL           equ 0x1D530 ; 𝔰  𝔩 — use FRAK_LOWER_S + FRAK_LOWER_L
FRAK_LOWER_S            equ 0x1D530 ; 𝔰
FRAK_LOWER_L            equ 0x1D529 ; 𝔩

; -----------------------------------------------------------------------------
; Script / calligraphic — sheaves, categories  (U+1D49C..U+1D4CF)
; -----------------------------------------------------------------------------

SCRIPT_A                equ 0x1D49C ; 𝒜
SCRIPT_B                equ 0x212C  ; ℬ  (canonical form)
SCRIPT_C                equ 0x1D49E ; 𝒞
SCRIPT_D                equ 0x1D49F ; 𝒟
SCRIPT_E                equ 0x2130  ; ℰ  (canonical form)
SCRIPT_F                equ 0x2131  ; ℱ  (canonical form)
SCRIPT_G                equ 0x1D4A2 ; 𝒢
SCRIPT_H                equ 0x210B  ; ℋ  (canonical form, Hamiltonian)
SCRIPT_I                equ 0x2110  ; ℐ  (canonical form)
SCRIPT_J                equ 0x1D4A5 ; 𝒥
SCRIPT_K                equ 0x1D4A6 ; 𝒦
SCRIPT_L                equ 0x2112  ; ℒ  (canonical form, Lagrangian)
SCRIPT_M                equ 0x2133  ; ℳ  (canonical form)
SCRIPT_N                equ 0x1D4A9 ; 𝒩
SCRIPT_O                equ 0x1D4AA ; 𝒪  sheaf of regular functions
SCRIPT_P                equ 0x1D4AB ; 𝒫  power set
SCRIPT_Q                equ 0x1D4AC ; 𝒬
SCRIPT_R                equ 0x211B  ; ℛ  (canonical form)
SCRIPT_S                equ 0x1D4AE ; 𝒮
SCRIPT_T                equ 0x1D4AF ; 𝒯
SCRIPT_U                equ 0x1D4B0 ; 𝒰
SCRIPT_V                equ 0x1D4B1 ; 𝒱
SCRIPT_W                equ 0x1D4B2 ; 𝒲
SCRIPT_X                equ 0x1D4B3 ; 𝒳
SCRIPT_Y                equ 0x1D4B4 ; 𝒴
SCRIPT_Z                equ 0x1D4B5 ; 𝒵

; -----------------------------------------------------------------------------
; Subscript digits and letters  (U+2080..U+2099)
; -----------------------------------------------------------------------------

SUB_0                   equ 0x2080  ; ₀
SUB_1                   equ 0x2081  ; ₁
SUB_2                   equ 0x2082  ; ₂
SUB_3                   equ 0x2083  ; ₃
SUB_4                   equ 0x2084  ; ₄
SUB_5                   equ 0x2085  ; ₅
SUB_6                   equ 0x2086  ; ₆
SUB_7                   equ 0x2087  ; ₇
SUB_8                   equ 0x2088  ; ₈
SUB_9                   equ 0x2089  ; ₉
SUB_PLUS                equ 0x208A  ; ₊
SUB_MINUS               equ 0x208B  ; ₋
SUB_EQUAL               equ 0x208C  ; ₌
SUB_LPAREN              equ 0x208D  ; ₍
SUB_RPAREN              equ 0x208E  ; ₎
SUB_A                   equ 0x2090  ; ₐ
SUB_E                   equ 0x2091  ; ₑ
SUB_O                   equ 0x2092  ; ₒ
SUB_X                   equ 0x2093  ; ₓ
SUB_SCHWA               equ 0x2094  ; ₔ
SUB_H                   equ 0x2095  ; ₕ
SUB_K                   equ 0x2096  ; ₖ
SUB_L                   equ 0x2097  ; ₗ
SUB_M                   equ 0x2098  ; ₘ
SUB_N                   equ 0x2099  ; ₙ
SUB_P                   equ 0x209A  ; ₚ
SUB_S                   equ 0x209B  ; ₛ
SUB_T                   equ 0x209C  ; ₜ

; -----------------------------------------------------------------------------
; Superscript digits and letters  (U+00B2, U+00B3, U+00B9, U+2070..U+207F)
; -----------------------------------------------------------------------------

SUP_0                   equ 0x2070  ; ⁰
SUP_1                   equ 0x00B9  ; ¹  (Latin-1)
SUP_2                   equ 0x00B2  ; ²  (Latin-1)
SUP_3                   equ 0x00B3  ; ³  (Latin-1)
SUP_4                   equ 0x2074  ; ⁴
SUP_5                   equ 0x2075  ; ⁵
SUP_6                   equ 0x2076  ; ⁶
SUP_7                   equ 0x2077  ; ⁷
SUP_8                   equ 0x2078  ; ⁸
SUP_9                   equ 0x2079  ; ⁹
SUP_PLUS                equ 0x207A  ; ⁺
SUP_MINUS               equ 0x207B  ; ⁻
SUP_EQUAL               equ 0x207C  ; ⁼
SUP_LPAREN              equ 0x207D  ; ⁽
SUP_RPAREN              equ 0x207E  ; ⁾
SUP_N                   equ 0x207F  ; ⁿ
SUP_I                   equ 0x2071  ; ⁱ

; -----------------------------------------------------------------------------
; Logical / set operators (aliases — for readability in proof-style code)
; -----------------------------------------------------------------------------

LOGIC_NOT               equ 0x00AC  ; ¬  logical not
LOGIC_AND               equ 0x2227  ; ∧  (same as MATH_SYM_AND)
LOGIC_OR                equ 0x2228  ; ∨  (same as MATH_SYM_OR)
LOGIC_XOR               equ 0x22BB  ; ⊻  xor
LOGIC_TOP               equ 0x22A4  ; ⊤  true / top
LOGIC_BOT               equ 0x22A5  ; ⊥  false / bottom (same as MATH_SYM_PERP)
LOGIC_PROVES            equ 0x22A2  ; ⊢  (same as MATH_SYM_TURNSTILE)
LOGIC_MODELS            equ 0x22A8  ; ⊨  (same as MATH_SYM_MODELS)
LOGIC_THEREFORE         equ 0x2234  ; ∴  therefore
LOGIC_BECAUSE           equ 0x2235  ; ∵  because

; -----------------------------------------------------------------------------
; Commonly used named aliases (short forms for frequently used symbols)
; -----------------------------------------------------------------------------

SYM_PI                  equ GREEK_LOWER_PI      ; π  0x03C0
SYM_TAU                 equ GREEK_LOWER_TAU     ; τ  0x03C4
SYM_PHI                 equ GREEK_LOWER_PHI     ; φ  0x03C6 (golden ratio)
SYM_ALPHA               equ GREEK_LOWER_ALPHA   ; α  0x03B1
SYM_BETA                equ GREEK_LOWER_BETA    ; β  0x03B2
SYM_GAMMA               equ GREEK_LOWER_GAMMA   ; γ  0x03B3
SYM_DELTA               equ GREEK_LOWER_DELTA   ; δ  0x03B4
SYM_EPSILON             equ GREEK_LOWER_EPSILON ; ε  0x03B5
SYM_LAMBDA              equ GREEK_LOWER_LAMBDA  ; λ  0x03BB
SYM_MU                  equ GREEK_LOWER_MU      ; μ  0x03BC
SYM_SIGMA               equ GREEK_LOWER_SIGMA   ; σ  0x03C3
SYM_OMEGA               equ GREEK_LOWER_OMEGA   ; ω  0x03C9
SYM_INF                 equ MATH_SYM_INF        ; ∞  0x221E
SYM_NABLA               equ MATH_SYM_NABLA      ; ∇  0x2207
SYM_PARTIAL             equ MATH_SYM_PARTIAL    ; ∂  0x2202
SYM_INTEGRAL            equ MATH_SYM_INTEGRAL   ; ∫  0x222B
SYM_SUM                 equ MATH_SYM_SIGMA      ; ∑  0x2211
SYM_PRODUCT             equ MATH_SYM_PRODUCT    ; ∏  0x220F
SYM_SQRT                equ MATH_SYM_SQRT       ; √  0x221A
SYM_APPROX              equ MATH_SYM_APPROX     ; ≈  0x2248
SYM_IDENTICAL           equ MATH_SYM_IDENTICAL  ; ≡  0x2261
SYM_OPLUS               equ MATH_SYM_OPLUS      ; ⊕  0x2295
SYM_OTIMES              equ MATH_SYM_OTIMES     ; ⊗  0x2297
SYM_ODOT                equ MATH_SYM_ODOT       ; ⊙  0x2299
SYM_REALS               equ BB_REALS            ; ℝ  0x211D
SYM_COMPLEX             equ BB_COMPLEX          ; ℂ  0x2102
SYM_NATURALS            equ BB_NATURALS         ; ℕ  0x2115
SYM_INTEGERS            equ BB_INTEGERS         ; ℤ  0x2124
SYM_SHEAF               equ SCRIPT_O            ; 𝒪  0x1D4AA
SYM_LAGRANGIAN          equ SCRIPT_L            ; ℒ  0x2112
SYM_HAMILTONIAN         equ SCRIPT_H            ; ℋ  0x210B

%endif ; STR_SYMBOLS_CONSTANTS_ASM; =============================================================================
; str/symbols/constants.asm
; Named codepoint constants for all Unicode symbol categories
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 (primary)
; Assembler: NASM
;
; Usage:
;   %include "arch/common/types.inc"
;   %include "symbols/constants.asm"
;
;   mov eax, MATH_SYM_PI        ; eax = 0x03C0
;   call str_utf8_encode        ; encode π into output buffer
;
; All constants are 32-bit Unicode codepoints (U+XXXX or U+XXXXX).
; Store in resd / dd. Pass in 32-bit registers (EAX, ECX, EDX...).
; =============================================================================

%ifndef STR_SYMBOLS_CONSTANTS_ASM
%define STR_SYMBOLS_CONSTANTS_ASM

; -----------------------------------------------------------------------------
; Greek lowercase  (U+03B1..U+03C9)
; -----------------------------------------------------------------------------

GREEK_LOWER_ALPHA       equ 0x03B1  ; α
GREEK_LOWER_BETA        equ 0x03B2  ; β
GREEK_LOWER_GAMMA       equ 0x03B3  ; γ
GREEK_LOWER_DELTA       equ 0x03B4  ; δ
GREEK_LOWER_EPSILON     equ 0x03B5  ; ε
GREEK_LOWER_ZETA        equ 0x03B6  ; ζ
GREEK_LOWER_ETA         equ 0x03B7  ; η
GREEK_LOWER_THETA       equ 0x03B8  ; θ
GREEK_LOWER_IOTA        equ 0x03B9  ; ι
GREEK_LOWER_KAPPA       equ 0x03BA  ; κ
GREEK_LOWER_LAMBDA      equ 0x03BB  ; λ
GREEK_LOWER_MU          equ 0x03BC  ; μ
GREEK_LOWER_NU          equ 0x03BD  ; ν
GREEK_LOWER_XI          equ 0x03BE  ; ξ
GREEK_LOWER_OMICRON     equ 0x03BF  ; ο
GREEK_LOWER_PI          equ 0x03C0  ; π
GREEK_LOWER_RHO         equ 0x03C1  ; ρ
GREEK_LOWER_SIGMA_FINAL equ 0x03C2  ; ς  (word-final sigma)
GREEK_LOWER_SIGMA       equ 0x03C3  ; σ
GREEK_LOWER_TAU         equ 0x03C4  ; τ
GREEK_LOWER_UPSILON     equ 0x03C5  ; υ
GREEK_LOWER_PHI         equ 0x03C6  ; φ
GREEK_LOWER_CHI         equ 0x03C7  ; χ
GREEK_LOWER_PSI         equ 0x03C8  ; ψ
GREEK_LOWER_OMEGA       equ 0x03C9  ; ω

; -----------------------------------------------------------------------------
; Greek uppercase  (U+0391..U+03A9)
; -----------------------------------------------------------------------------

GREEK_UPPER_ALPHA       equ 0x0391  ; Α
GREEK_UPPER_BETA        equ 0x0392  ; Β
GREEK_UPPER_GAMMA       equ 0x0393  ; Γ
GREEK_UPPER_DELTA       equ 0x0394  ; Δ
GREEK_UPPER_EPSILON     equ 0x0395  ; Ε
GREEK_UPPER_ZETA        equ 0x0396  ; Ζ
GREEK_UPPER_ETA         equ 0x0397  ; Η
GREEK_UPPER_THETA       equ 0x0398  ; Θ
GREEK_UPPER_IOTA        equ 0x0399  ; Ι
GREEK_UPPER_KAPPA       equ 0x039A  ; Κ
GREEK_UPPER_LAMBDA      equ 0x039B  ; Λ
GREEK_UPPER_MU          equ 0x039C  ; Μ
GREEK_UPPER_NU          equ 0x039D  ; Ν
GREEK_UPPER_XI          equ 0x039E  ; Ξ
GREEK_UPPER_OMICRON     equ 0x039F  ; Ο
GREEK_UPPER_PI          equ 0x03A0  ; Π
GREEK_UPPER_RHO         equ 0x03A1  ; Ρ
GREEK_UPPER_SIGMA       equ 0x03A3  ; Σ  (0x03A2 unassigned)
GREEK_UPPER_TAU         equ 0x03A4  ; Τ
GREEK_UPPER_UPSILON     equ 0x03A5  ; Υ
GREEK_UPPER_PHI         equ 0x03A6  ; Φ
GREEK_UPPER_CHI         equ 0x03A7  ; Χ
GREEK_UPPER_PSI         equ 0x03A8  ; Ψ
GREEK_UPPER_OMEGA       equ 0x03A9  ; Ω

; -----------------------------------------------------------------------------
; Mathematical operators  (U+2200..U+22FF)
; -----------------------------------------------------------------------------

MATH_SYM_FOR_ALL        equ 0x2200  ; ∀  for all
MATH_SYM_PARTIAL        equ 0x2202  ; ∂  partial differential
MATH_SYM_THERE_EXISTS   equ 0x2203  ; ∃  there exists
MATH_SYM_THERE_NOT_EXISTS equ 0x2204 ; ∄ there does not exist
MATH_SYM_EMPTY_SET      equ 0x2205  ; ∅  empty set
MATH_SYM_NABLA          equ 0x2207  ; ∇  nabla / del
MATH_SYM_ELEMENT_OF     equ 0x2208  ; ∈  element of
MATH_SYM_NOT_ELEMENT_OF equ 0x2209  ; ∉  not element of
MATH_SYM_CONTAINS       equ 0x220B  ; ∋  contains as member
MATH_SYM_PRODUCT        equ 0x220F  ; ∏  n-ary product
MATH_SYM_COPRODUCT      equ 0x2210  ; ∐  n-ary coproduct
MATH_SYM_SIGMA          equ 0x2211  ; ∑  n-ary summation
MATH_SYM_MINUS          equ 0x2212  ; −  minus sign
MATH_SYM_PLUS_MINUS     equ 0x00B1  ; ±  plus-minus sign
MATH_SYM_SQRT           equ 0x221A  ; √  square root
MATH_SYM_CBRT           equ 0x221B  ; ∛  cube root
MATH_SYM_FOURTHRT       equ 0x221C  ; ∜  fourth root
MATH_SYM_PROPORTIONAL   equ 0x221D  ; ∝  proportional to
MATH_SYM_INF            equ 0x221E  ; ∞  infinity
MATH_SYM_ANGLE          equ 0x2220  ; ∠  angle
MATH_SYM_AND            equ 0x2227  ; ∧  logical and
MATH_SYM_OR             equ 0x2228  ; ∨  logical or
MATH_SYM_INTERSECT      equ 0x2229  ; ∩  intersection
MATH_SYM_UNION          equ 0x222A  ; ∪  union
MATH_SYM_INTEGRAL       equ 0x222B  ; ∫  integral
MATH_SYM_DOUBLE_INT     equ 0x222C  ; ∬  double integral
MATH_SYM_TRIPLE_INT     equ 0x222D  ; ∭  triple integral
MATH_SYM_CONTOUR_INT    equ 0x222E  ; ∮  contour integral
MATH_SYM_APPROX         equ 0x2248  ; ≈  almost equal to
MATH_SYM_NOT_EQUAL      equ 0x2260  ; ≠  not equal to
MATH_SYM_IDENTICAL      equ 0x2261  ; ≡  identical to
MATH_SYM_LESS_EQ        equ 0x2264  ; ≤  less than or equal
MATH_SYM_GREATER_EQ     equ 0x2265  ; ≥  greater than or equal
MATH_SYM_SUBSET         equ 0x2282  ; ⊂  subset of
MATH_SYM_SUPERSET       equ 0x2283  ; ⊃  superset of
MATH_SYM_SUBSET_EQ      equ 0x2286  ; ⊆  subset of or equal
MATH_SYM_SUPERSET_EQ    equ 0x2287  ; ⊇  superset of or equal
MATH_SYM_OPLUS          equ 0x2295  ; ⊕  circled plus (direct sum)
MATH_SYM_OMINUS         equ 0x2296  ; ⊖  circled minus
MATH_SYM_OTIMES         equ 0x2297  ; ⊗  circled times (tensor product)
MATH_SYM_ODOT           equ 0x2299  ; ⊙  circled dot
MATH_SYM_PERP           equ 0x22A5  ; ⊥  perpendicular / bottom
MATH_SYM_TURNSTILE      equ 0x22A2  ; ⊢  right tack (proves)
MATH_SYM_MODELS         equ 0x22A8  ; ⊨  true / models
MATH_SYM_CDOT           equ 0x22C5  ; ⋅  dot operator
MATH_SYM_STAR           equ 0x22C6  ; ⋆  star operator

; -----------------------------------------------------------------------------
; Arrows  (U+2190..U+21FF, U+27F5..U+27FF, U+2900..U+297F)
; -----------------------------------------------------------------------------

ARROW_LEFT              equ 0x2190  ; ←
ARROW_UP                equ 0x2191  ; ↑
ARROW_RIGHT             equ 0x2192  ; →
ARROW_DOWN              equ 0x2193  ; ↓
ARROW_LEFT_RIGHT        equ 0x2194  ; ↔
ARROW_UP_DOWN           equ 0x2195  ; ↕
ARROW_DOUBLE_LEFT       equ 0x21D0  ; ⇐
ARROW_DOUBLE_RIGHT      equ 0x21D2  ; ⇒
ARROW_DOUBLE_LR         equ 0x21D4  ; ⇔
ARROW_MAPS_TO           equ 0x21A6  ; ↦
ARROW_LONG_RIGHT        equ 0x27F6  ; ⟶
ARROW_LONG_LEFT         equ 0x27F5  ; ⟵
ARROW_LONG_LR           equ 0x27F7  ; ⟷
ARROW_LONG_DOUBLE_RIGHT equ 0x27F9  ; ⟹
ARROW_LONG_DOUBLE_LR    equ 0x27FA  ; ⟺
ARROW_LONG_MAPS_TO      equ 0x27FC  ; ⟼
ANGLE_LEFT              equ 0x27E8  ; ⟨  mathematical left angle bracket
ANGLE_RIGHT             equ 0x27E9  ; ⟩  mathematical right angle bracket

; -----------------------------------------------------------------------------
; Blackboard bold — number sets  (U+2115, U+2124, U+211A, U+211D, U+2102...)
; -----------------------------------------------------------------------------

BB_NATURALS             equ 0x2115  ; ℕ  natural numbers
BB_INTEGERS             equ 0x2124  ; ℤ  integers
BB_RATIONALS            equ 0x211A  ; ℚ  rationals
BB_REALS                equ 0x211D  ; ℝ  reals
BB_COMPLEX              equ 0x2102  ; ℂ  complex numbers
BB_QUATERNIONS          equ 0x210D  ; ℍ  quaternions
BB_PRIMES               equ 0x2119  ; ℙ  primes

; Blackboard bold capital letters  (U+1D538..U+1D56B, Mathematical Alphanumeric)
BB_A                    equ 0x1D538 ; 𝔸
BB_B                    equ 0x1D539 ; 𝔹
BB_C                    equ 0x2102  ; ℂ  (canonical form)
BB_D                    equ 0x1D53B ; 𝔻
BB_E                    equ 0x1D53C ; 𝔼
BB_F                    equ 0x1D53D ; 𝔽
BB_G                    equ 0x1D53E ; 𝔾
BB_H                    equ 0x210D  ; ℍ  (canonical form)
BB_I                    equ 0x1D540 ; 𝕀
BB_J                    equ 0x1D541 ; 𝕁
BB_K                    equ 0x1D542 ; 𝕂
BB_L                    equ 0x1D543 ; 𝕃
BB_M                    equ 0x1D544 ; 𝕄
BB_N                    equ 0x2115  ; ℕ  (canonical form)
BB_O                    equ 0x1D546 ; 𝕆
BB_P                    equ 0x2119  ; ℙ  (canonical form)
BB_Q                    equ 0x211A  ; ℚ  (canonical form)
BB_R                    equ 0x211D  ; ℝ  (canonical form)
BB_S                    equ 0x1D54A ; 𝕊
BB_T                    equ 0x1D54B ; 𝕋
BB_Z                    equ 0x2124  ; ℤ  (canonical form)

; -----------------------------------------------------------------------------
; Fraktur — Lie algebras, etc.  (U+1D504..U+1D537)
; -----------------------------------------------------------------------------

FRAK_A                  equ 0x1D504 ; 𝔄
FRAK_B                  equ 0x1D505 ; 𝔅
FRAK_C                  equ 0x212D  ; ℭ  (canonical form)
FRAK_D                  equ 0x1D507 ; 𝔇
FRAK_E                  equ 0x1D508 ; 𝔈
FRAK_F                  equ 0x1D509 ; 𝔉
FRAK_G                  equ 0x1D50A ; 𝔊
FRAK_H                  equ 0x210C  ; ℌ  (canonical form)
FRAK_I                  equ 0x2111  ; ℑ  (canonical form, imaginary part)
FRAK_J                  equ 0x1D50D ; 𝔍
FRAK_K                  equ 0x1D50E ; 𝔎
FRAK_L                  equ 0x1D50F ; 𝔏
FRAK_M                  equ 0x1D510 ; 𝔐
FRAK_N                  equ 0x1D511 ; 𝔑
FRAK_P                  equ 0x1D513 ; 𝔓
FRAK_R                  equ 0x211C  ; ℜ  (canonical form, real part)
FRAK_Z                  equ 0x2128  ; ℨ  (canonical form)

; Fraktur lowercase — common Lie algebra letters
FRAK_LOWER_G            equ 0x1D524 ; 𝔤  Lie algebra g
FRAK_LOWER_H            equ 0x1D525 ; 𝔥  Cartan subalgebra h
FRAK_LOWER_B            equ 0x1D51F ; 𝔟  Borel subalgebra b
FRAK_LOWER_N            equ 0x1D52B ; 𝔫  nilradical n
FRAK_LOWER_P            equ 0x1D52D ; 𝔭  parabolic subalgebra p
FRAK_LOWER_M            equ 0x1D52A ; 𝔪  maximal ideal m
FRAK_LOWER_K            equ 0x1D528 ; 𝔨  compact real form k
FRAK_LOWER_SL           equ 0x1D530 ; 𝔰  𝔩 — use FRAK_LOWER_S + FRAK_LOWER_L
FRAK_LOWER_S            equ 0x1D530 ; 𝔰
FRAK_LOWER_L            equ 0x1D529 ; 𝔩

; -----------------------------------------------------------------------------
; Script / calligraphic — sheaves, categories  (U+1D49C..U+1D4CF)
; -----------------------------------------------------------------------------

SCRIPT_A                equ 0x1D49C ; 𝒜
SCRIPT_B                equ 0x212C  ; ℬ  (canonical form)
SCRIPT_C                equ 0x1D49E ; 𝒞
SCRIPT_D                equ 0x1D49F ; 𝒟
SCRIPT_E                equ 0x2130  ; ℰ  (canonical form)
SCRIPT_F                equ 0x2131  ; ℱ  (canonical form)
SCRIPT_G                equ 0x1D4A2 ; 𝒢
SCRIPT_H                equ 0x210B  ; ℋ  (canonical form, Hamiltonian)
SCRIPT_I                equ 0x2110  ; ℐ  (canonical form)
SCRIPT_J                equ 0x1D4A5 ; 𝒥
SCRIPT_K                equ 0x1D4A6 ; 𝒦
SCRIPT_L                equ 0x2112  ; ℒ  (canonical form, Lagrangian)
SCRIPT_M                equ 0x2133  ; ℳ  (canonical form)
SCRIPT_N                equ 0x1D4A9 ; 𝒩
SCRIPT_O                equ 0x1D4AA ; 𝒪  sheaf of regular functions
SCRIPT_P                equ 0x1D4AB ; 𝒫  power set
SCRIPT_Q                equ 0x1D4AC ; 𝒬
SCRIPT_R                equ 0x211B  ; ℛ  (canonical form)
SCRIPT_S                equ 0x1D4AE ; 𝒮
SCRIPT_T                equ 0x1D4AF ; 𝒯
SCRIPT_U                equ 0x1D4B0 ; 𝒰
SCRIPT_V                equ 0x1D4B1 ; 𝒱
SCRIPT_W                equ 0x1D4B2 ; 𝒲
SCRIPT_X                equ 0x1D4B3 ; 𝒳
SCRIPT_Y                equ 0x1D4B4 ; 𝒴
SCRIPT_Z                equ 0x1D4B5 ; 𝒵

; -----------------------------------------------------------------------------
; Subscript digits and letters  (U+2080..U+2099)
; -----------------------------------------------------------------------------

SUB_0                   equ 0x2080  ; ₀
SUB_1                   equ 0x2081  ; ₁
SUB_2                   equ 0x2082  ; ₂
SUB_3                   equ 0x2083  ; ₃
SUB_4                   equ 0x2084  ; ₄
SUB_5                   equ 0x2085  ; ₅
SUB_6                   equ 0x2086  ; ₆
SUB_7                   equ 0x2087  ; ₇
SUB_8                   equ 0x2088  ; ₈
SUB_9                   equ 0x2089  ; ₉
SUB_PLUS                equ 0x208A  ; ₊
SUB_MINUS               equ 0x208B  ; ₋
SUB_EQUAL               equ 0x208C  ; ₌
SUB_LPAREN              equ 0x208D  ; ₍
SUB_RPAREN              equ 0x208E  ; ₎
SUB_A                   equ 0x2090  ; ₐ
SUB_E                   equ 0x2091  ; ₑ
SUB_O                   equ 0x2092  ; ₒ
SUB_X                   equ 0x2093  ; ₓ
SUB_SCHWA               equ 0x2094  ; ₔ
SUB_H                   equ 0x2095  ; ₕ
SUB_K                   equ 0x2096  ; ₖ
SUB_L                   equ 0x2097  ; ₗ
SUB_M                   equ 0x2098  ; ₘ
SUB_N                   equ 0x2099  ; ₙ
SUB_P                   equ 0x209A  ; ₚ
SUB_S                   equ 0x209B  ; ₛ
SUB_T                   equ 0x209C  ; ₜ

; -----------------------------------------------------------------------------
; Superscript digits and letters  (U+00B2, U+00B3, U+00B9, U+2070..U+207F)
; -----------------------------------------------------------------------------

SUP_0                   equ 0x2070  ; ⁰
SUP_1                   equ 0x00B9  ; ¹  (Latin-1)
SUP_2                   equ 0x00B2  ; ²  (Latin-1)
SUP_3                   equ 0x00B3  ; ³  (Latin-1)
SUP_4                   equ 0x2074  ; ⁴
SUP_5                   equ 0x2075  ; ⁵
SUP_6                   equ 0x2076  ; ⁶
SUP_7                   equ 0x2077  ; ⁷
SUP_8                   equ 0x2078  ; ⁸
SUP_9                   equ 0x2079  ; ⁹
SUP_PLUS                equ 0x207A  ; ⁺
SUP_MINUS               equ 0x207B  ; ⁻
SUP_EQUAL               equ 0x207C  ; ⁼
SUP_LPAREN              equ 0x207D  ; ⁽
SUP_RPAREN              equ 0x207E  ; ⁾
SUP_N                   equ 0x207F  ; ⁿ
SUP_I                   equ 0x2071  ; ⁱ

; -----------------------------------------------------------------------------
; Logical / set operators (aliases — for readability in proof-style code)
; -----------------------------------------------------------------------------

LOGIC_NOT               equ 0x00AC  ; ¬  logical not
LOGIC_AND               equ 0x2227  ; ∧  (same as MATH_SYM_AND)
LOGIC_OR                equ 0x2228  ; ∨  (same as MATH_SYM_OR)
LOGIC_XOR               equ 0x22BB  ; ⊻  xor
LOGIC_TOP               equ 0x22A4  ; ⊤  true / top
LOGIC_BOT               equ 0x22A5  ; ⊥  false / bottom (same as MATH_SYM_PERP)
LOGIC_PROVES            equ 0x22A2  ; ⊢  (same as MATH_SYM_TURNSTILE)
LOGIC_MODELS            equ 0x22A8  ; ⊨  (same as MATH_SYM_MODELS)
LOGIC_THEREFORE         equ 0x2234  ; ∴  therefore
LOGIC_BECAUSE           equ 0x2235  ; ∵  because

; -----------------------------------------------------------------------------
; Commonly used named aliases (short forms for frequently used symbols)
; -----------------------------------------------------------------------------

SYM_PI                  equ GREEK_LOWER_PI      ; π  0x03C0
SYM_TAU                 equ GREEK_LOWER_TAU     ; τ  0x03C4
SYM_PHI                 equ GREEK_LOWER_PHI     ; φ  0x03C6 (golden ratio)
SYM_ALPHA               equ GREEK_LOWER_ALPHA   ; α  0x03B1
SYM_BETA                equ GREEK_LOWER_BETA    ; β  0x03B2
SYM_GAMMA               equ GREEK_LOWER_GAMMA   ; γ  0x03B3
SYM_DELTA               equ GREEK_LOWER_DELTA   ; δ  0x03B4
SYM_EPSILON             equ GREEK_LOWER_EPSILON ; ε  0x03B5
SYM_LAMBDA              equ GREEK_LOWER_LAMBDA  ; λ  0x03BB
SYM_MU                  equ GREEK_LOWER_MU      ; μ  0x03BC
SYM_SIGMA               equ GREEK_LOWER_SIGMA   ; σ  0x03C3
SYM_OMEGA               equ GREEK_LOWER_OMEGA   ; ω  0x03C9
SYM_INF                 equ MATH_SYM_INF        ; ∞  0x221E
SYM_NABLA               equ MATH_SYM_NABLA      ; ∇  0x2207
SYM_PARTIAL             equ MATH_SYM_PARTIAL    ; ∂  0x2202
SYM_INTEGRAL            equ MATH_SYM_INTEGRAL   ; ∫  0x222B
SYM_SUM                 equ MATH_SYM_SIGMA      ; ∑  0x2211
SYM_PRODUCT             equ MATH_SYM_PRODUCT    ; ∏  0x220F
SYM_SQRT                equ MATH_SYM_SQRT       ; √  0x221A
SYM_APPROX              equ MATH_SYM_APPROX     ; ≈  0x2248
SYM_IDENTICAL           equ MATH_SYM_IDENTICAL  ; ≡  0x2261
SYM_OPLUS               equ MATH_SYM_OPLUS      ; ⊕  0x2295
SYM_OTIMES              equ MATH_SYM_OTIMES     ; ⊗  0x2297
SYM_ODOT                equ MATH_SYM_ODOT       ; ⊙  0x2299
SYM_REALS               equ BB_REALS            ; ℝ  0x211D
SYM_COMPLEX             equ BB_COMPLEX          ; ℂ  0x2102
SYM_NATURALS            equ BB_NATURALS         ; ℕ  0x2115
SYM_INTEGERS            equ BB_INTEGERS         ; ℤ  0x2124
SYM_SHEAF               equ SCRIPT_O            ; 𝒪  0x1D4AA
SYM_LAGRANGIAN          equ SCRIPT_L            ; ℒ  0x2112
SYM_HAMILTONIAN         equ SCRIPT_H            ; ℋ  0x210B

%endif ; STR_SYMBOLS_CONSTANTS_ASM