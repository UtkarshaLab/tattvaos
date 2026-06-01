# kernel — Kernel Category

> The core of Tattva OS. Assembly-native unikernel.
> Runs in ring 0. No user space. No process isolation.

---

## Projects

| Project | Description |
|---|---|
| [`entry/`](entry/) | Kernel entry point — first code executed after bootloader hands off |
| [`arch/`](arch/) | Architecture-specific code — x86-64, AArch64, RISC-V |
| [`mm/`](mm/) | Memory management — physical allocator, virtual memory, huge pages |
| [`sched/`](sched/) | Scheduler — cooperative and preemptive, core affinity |
| [`ipc/`](ipc/) | Inter-process communication — message queues, shared memory |
| [`syscall/`](syscall/) | System call interface — minimal syscall table |
| [`drivers/`](drivers/) | Device drivers — NVMe, UART, network cards |
| [`ebpf/`](ebpf/) | eBPF runtime — safe dynamic instrumentation |
| [`power/`](power/) | Power management — CPU frequency scaling, sleep states |
| [`security/`](security/) | Security primitives — capability checks, seccomp-style filtering |
| [`tests/`](tests/) | Kernel unit and integration tests |

---

## Design

Single address space. All code in ring 0.
Unikernel — one workload per image.
Built with utasm (NASM during bootstrap).
