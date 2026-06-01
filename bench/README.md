# bench — Benchmarking Category

> Cycle-accurate benchmarks for every subsystem in Tattva OS.
> Measures real performance, not amortized averages.

---

## Projects

| Project | Description |
|---|---|
| [`database/`](database/) | Sagar database read/write/query throughput benchmarks |
| [`gemm/`](gemm/) | GEMM kernel performance — tokens/sec, FLOPS/cycle |
| [`inference/`](inference/) | End-to-end inference latency — first token, subsequent tokens |
| [`network/`](network/) | Network stack throughput — req/sec, latency distribution |
| [`os/`](os/) | Kernel primitive benchmarks — syscalls, context switches, IPC |

---

## Philosophy

Every benchmark is run with `ubench` — cycle-accurate, no warm-up games.
Results are compared against a baseline before every release.
Regressions block merges.
