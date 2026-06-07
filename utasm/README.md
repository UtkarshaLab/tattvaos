# asm — utasm Toolchain Category

> The utasm assembler/linker toolchain — the primary build tool for Tattva OS.
> Written in assembly. Replaces NASM as the codebase matures.

---

## Projects

| Project | Description |
|---|---|
| [`assembler/`](assembler/) | Core assembler — parses `.s` / `.asm` source, emits machine code |
| [`disassembler/`](disassembler/) | Disassembler — takes binary, emits human-readable assembly |
| [`linker/`](linker/) | Linker — resolves symbols, produces final ELF/flat binary |
| [`linter/`](linter/) | Static linter — catches common assembly bugs before assembly |
| [`annotations/`](annotations/) | Annotation parser — structured comments for tooling |
| [`safety/`](safety/) | Safety checker — enforces memory and register safety rules |
| [`tests/`](tests/) | Test suite for the entire utasm toolchain |

---

## Targets

- x86-64
- AArch64
- RISC-V (rv64gc)

## Status

NASM is used first. utasm replaces it incrementally as each component matures.
