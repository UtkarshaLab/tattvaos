# hw — Hardware Abstraction Category

> Direct hardware access and topology discovery for Tattva OS.
> No HAL. No driver model. Direct register access where possible.

---

## Projects

| Project | Description |
|---|---|
| [`ucpu/`](ucpu/) | CPU topology, feature detection, core enumeration |
| [`ugpu/`](ugpu/) | GPU access — PCIe BAR mapping, command queue submission |
| [`uhbm/`](uhbm/) | High-bandwidth memory — HBM2/3 topology and bandwidth |
| [`ucxl/`](ucxl/) | CXL device enumeration and memory-semantic operations |
| [`unuma/`](unuma/) | NUMA topology discovery and memory placement policy |
| [`uhwloc/`](uhwloc/) | Hardware locality — bind threads to cores, memory to nodes |

---

## Philosophy

The kernel knows exactly what hardware it's running on.
No generic driver stack. Configuration is build-time, not runtime.
