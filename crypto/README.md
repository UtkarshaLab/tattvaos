# crypto — Cryptography Category

&gt; Cryptographic primitives and protocols for Tattva OS.
&gt; Built for zero-copy, constant-time, unikernel-native operation.

---

## Projects

| Project | Description |
|---|---|
| [`ucrypt/`](ucrypt/) | Encryption — symmetric, asymmetric, KDF, MAC, PQC |
| [`uhash/`](uhash/) | Hash functions — BLAKE3, SHA-256, SHA-512 |
| [`ukdf/`](ukdf/) | Key derivation — HKDF, PBKDF2, Argon2 |
| [`urand/`](urand/) | CSPRNG — hardware RNG, Fortuna, ChaCha20-based |
| [`usign/`](usign/) | Digital signatures — RSA, ECDSA, Ed25519 |
| [`utls/`](utls/) | TLS 1.2/1.3 — handshake, record layer, session management |
| [`uutils/`](uutils/) | Constant-time utilities — secure memcmp, memset, zero |
| [`ux509/`](ux509/) | X.509 — ASN.1 parser, certificate chain validation, CRL/OCSP |

---

## ucrypt/ Structure

| Subdir | Description |
|--------|-------------|
| `asymmetric/` | RSA, ECC key exchange |
| `kdf/` | Key derivation functions |
| `mac/` | Message authentication — HMAC, CMAC, Poly1305 |
| `pqc/` | Post-quantum cryptography |
| `symmetric/` | AES, ChaCha20, AES-GCM, ChaCha20-Poly1305 |

---

## uhash/ Structure

| Subdir | Description |
|--------|-------------|
| `blake3/` | BLAKE3 hash |
| `sha256/` | SHA-256 |
| `sha512/` | SHA-512 |

---

## Design

- **No dynamic allocation** — all crypto operations use caller-provided buffers
- **Constant-time by default** — side-channel resistant compare, copy, modular exponentiation
- **Hardware acceleration** — AES-NI, SHA-NI, RDRAND/RDSEED when available
- **Assembly-native** — hand-optimized primitives, no external dependencies

---

## Dependencies

| Consumer | Uses |
|----------|------|
| `unet/utls/` | `ucrypt/`, `uhash/`, `usign/`, `ukdf/`, `urand/`, `ux509/` |
| `unet/ssh/` | `ucrypt/`, `uhash/`, `usign/`, `ukdf/`, `urand/` |
| `unet/dns/` (DoH/DoT) | `utls/` |
| `unet/http/` (HTTPS) | `utls/` |
| `unet/smtp/`, `unet/imap/` (SMTPS/IMAPS) | `utls/` |

---a# crypto — Cryptography Category

&gt; Cryptographic primitives and protocols for Tattva OS.
&gt; Built for zero-copy, constant-time, unikernel-native operation.

---

## Projects

| Project | Description |
|---|---|
| [`ucrypt/`](ucrypt/) | Encryption — symmetric, asymmetric, KDF, MAC, PQC |
| [`uhash/`](uhash/) | Hash functions — BLAKE3, BLAKE2, SHA-256, SHA-512, SHA-3 |
| [`ukdf/`](ukdf/) | Key derivation — HKDF, PBKDF2, Argon2, scrypt |
| [`urand/`](urand/) | CSPRNG — hardware RNG, Fortuna, ChaCha20-based |
| [`usign/`](usign/) | Digital signatures — RSA, ECDSA, Ed25519 |
| [`utls/`](utls/) | TLS 1.2/1.3 — handshake, record layer, session management |
| [`uutils/`](uutils/) | Constant-time utilities — secure memcmp, memset, zero |
| [`ux509/`](ux509/) | X.509 — ASN.1 parser, certificate chain validation, CRL/OCSP |

---

## ucrypt/ Structure

| Subdir | Description |
|--------|-------------|
| `asymmetric/` | RSA, ECC, X25519/X448 key exchange |
| `kdf/` | Key derivation — HKDF, PBKDF2, Argon2, scrypt |
| `mac/` | Message authentication — HMAC, CMAC, KMAC, Poly1305 |
| `pqc/` | Post-quantum cryptography — ML-KEM, ML-DSA |
| `symmetric/` | AES, ChaCha20, AES-GCM, ChaCha20-Poly1305 |

---

## uhash/ Structure

| Subdir | Description |
|--------|-------------|
| `blake3/` | BLAKE3 hash |
| `blake2/` | BLAKE2b/BLAKE2s |
| `sha256/` | SHA-256 |
| `sha512/` | SHA-512 |
| `sha3/` | SHA-3 (256/384/512) |

---

## Design

- **No dynamic allocation** — all crypto operations use caller-provided buffers
- **Constant-time by default** — side-channel resistant compare, copy, modular exponentiation
- **Hardware acceleration** — AES-NI, SHA-NI, RDRAND/RDSEED when available
- **Assembly-native** — hand-optimized primitives, no external dependencies
- **Post-quantum ready** — ML-KEM and ML-DSA for future-proofing

---

## Dependencies

| Consumer | Uses |
|----------|------|
| `unet/utls/` | `ucrypt/`, `uhash/`, `usign/`, `ukdf/`, `urand/`, `ux509/` |
| `unet/ssh/` | `ucrypt/`, `uhash/`, `usign/`, `ukdf/`, `urand/` |
| `unet/dns/` (DoH/DoT) | `utls/` |
| `unet/http/` (HTTPS) | `utls/` |
| `unet/smtp/`, `unet/imap/` (SMTPS/IMAPS) | `utls/` |

---

## Philosophy

Cryptography is not a feature. It is a foundation.
Every byte is assumed hostile until verified.

## Philosophy

Cryptography is not a feature. It is a foundation.
Every byte is assumed hostile until verified.