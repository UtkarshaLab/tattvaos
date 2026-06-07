# asm/safety — utasm Safety Checker

> Enforces memory and register safety rules at assemble time.

Verifies: stack pointer alignment, callee-saved register preservation,
no writes to read-only regions, correct syscall register usage.

Part of the `asm/` category in Tattva OS.
