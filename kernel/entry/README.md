# kernel/entry — Kernel Entry Point

> First code executed after the bootloader hands off to the kernel.

Initializes: GS base, kernel stack, early console output,
calls into mm → sched → drivers → serve in order.

Part of the `kernel/` category in Tattva OS.
