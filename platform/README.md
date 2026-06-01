# platform — Platform Support Category

> Architecture-specific implementations for Tattva OS.
> One subdirectory per supported ISA.

---

## Projects

| Project | Description |
|---|---|
| [`x86_64/`](x86_64/) | x86-64 platform — primary target, BIOS and UEFI boot |
| [`aarch64/`](aarch64/) | AArch64 platform — UEFI boot, Apple Silicon and server ARM |
| [`riscv/`](riscv/) | RISC-V platform — OpenSBI boot, rv64gc baseline |

---

## Build Priority

x86-64 first. AArch64 second. RISC-V third.

Each platform directory contains:
- CPU initialization
- Interrupt controller setup
- Timer configuration
- Platform-specific syscall ABI
