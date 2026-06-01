# crypto — Cryptography Category

> Cryptographic primitives for Tattva OS.
> SIMD-accelerated. Zero external dependencies. Assembly-native.

---

## Projects

| Project | Description |
|---|---|
| [`uhash/`](uhash/) | Hashing — SHA-256, SHA-3, BLAKE3, hardware-accelerated |
| [`uSSL/`](uSSL/) | TLS 1.3 implementation — full handshake, record layer |
| [`ucrypt/`](ucrypt/) | Symmetric encryption — AES-GCM, ChaCha20-Poly1305 |
| [`usign/`](usign/) | Digital signatures — Ed25519, sign and verify binaries |
| [`umtls/`](umtls/) | Mutual TLS — client certificates, identity verification |

---

## Philosophy

All primitives are constant-time by default.
No heap allocations in the hot path.
AES-NI and SHA extensions used automatically when available.
