# tests — Test Suite Category

> All tests for Tattva OS. Run before every commit.

---

## Projects

| Project | Description |
|---|---|
| [`unit/`](unit/) | Unit tests — per-function, isolated, no hardware required |
| [`integration/`](integration/) | Integration tests — subsystem interaction, in-process |
| [`e2e/`](e2e/) | End-to-end tests — full boot to inference request |
| [`bench/`](bench/) | Benchmark regression tests — compare against baseline |
| [`fuzz/`](fuzz/) | Fuzz tests — structure-aware fuzzing for parsers and protocols |
| [`qemu/`](qemu/) | QEMU boot tests — automated boot verification in emulator |

---

## Running Tests

```sh
make test          # run unit + integration
make test-e2e      # full boot test in QEMU
make test-bench    # benchmark regression check
```

All tests must pass before pushing.
