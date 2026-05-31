# Tattva OS

> *Every layer between your code and the hardware costs something.*
> *We eliminate all of it. Then we measure what's left.*

---

## What is this?

Tattva OS is an assembly-native unikernel built specifically for AI inference.

The thesis is simple. A normal inference stack looks like this:

```
your model
    ↓ Python
    ↓ PyTorch / framework dispatch
    ↓ CUDA runtime
    ↓ OS scheduler
    ↓ glibc / system calls
    ↓ hardware
```

Every arrow is overhead. Every layer adds latency, jitter, memory pressure.
Tattva OS collapses the entire stack to:

```
your model
    ↓ hardware
```

No Python. No framework. No runtime. No general-purpose OS.
One thing, done as fast as the silicon allows.

---

## Current goal

Beat [llama.cpp](https://github.com/ggerganov/llama.cpp) tokens/sec on x86-64 CPU.
Same hardware. Same model. Same quantization. Different stack.

**Status:** pre-benchmark · active development

---

## Why assembly?

Because every abstraction above assembly is a choice someone else made
for a workload that isn't yours.

The C compiler makes assumptions. The OS scheduler makes assumptions.
PyTorch makes assumptions. None of them know you're running a transformer.

We do.

---

## What's novel here?

**Register-convention memory safety** — ownership baked into the calling
convention itself, not into a type system. Owned pointers travel in one
register class, borrowed in another. The assembler enforces this statically.
Zero runtime overhead. No type theory. No borrow checker fights.

This is new. Nobody has done ownership at the ISA calling convention level.

---

## Architecture targets

| Architecture | Status | Notes |
|---|---|---|
| x86-64 | active | first benchmark target |
| AArch64 | planned | Apple Silicon, Morello/CHERI |
| RISC-V | planned | CHERI-RISC-V research |

---

## Stack

The full module reference is in [`STACK.html`](STACK.html).  
The directory structure is in [`PROJECTSTRUCTURE.md`](PROJECTSTRUCTURE.md).

Minimal build list for first benchmark:

```
boot/       → bootloader, x86-64 BIOS path
lib/mem/    → physical memory, heap, arena
lib/io/     → UART, disk, device abstraction  
lib/umath/  → GEMM, AVX2
ai/umodel/  → GGUF weight loader
ai/utok/    → BPE tokenizer
ai/uattn/   → attention kernel
ai/uffn/    → FFN kernel
ai/unorm/   → RMSNorm
ai/uembed/  → embeddings + RoPE
ai/udecode/ → greedy decoding
ai/uinfer/  → the inference loop
```

Everything else — networking, database, distributed training,
multi-architecture — comes after the first benchmark number exists.

---

## Roadmap

```
now → 3 months    boot + mem + io + GEMM kernel
3   → 6 months    first end-to-end inference, benchmark published
6   → 9 months    optimize, AArch64 port begins
9   → 12 months   paper, PhD application
```

---

## Why Nepal?

Most of the world can't afford $20/month inference subscriptions.
Training costs are the ceiling that keeps AI out of reach for most
researchers, universities, and companies outside wealthy markets.

The goal is to reduce that ceiling significantly — through a stack
that eliminates software overhead, runs on hardware people actually own,
and makes serious AI work accessible without depending on hyperscaler
infrastructure.

Tattva OS is the foundation that makes that possible.

---

## Built by

**Utkarsha Labs** - *Engineering the Foundation of Tomorrow*

Kathmandu, Nepal · Founded 2026

[utkarshalab.com](https://utkarshalab.com)
[raj@utkarshalab.com](mailto:[raj@utkarshalab.com]) · [info@utkarshalab.com](mailto:[info@utkarshalab.com])

---

*This is a long project. The vision is large. The first milestone is small:*  
*one number, on one machine, faster than the alternative.*  
*Everything else follows from that.*
