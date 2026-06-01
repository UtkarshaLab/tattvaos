# obs — Observability Category

> Observability infrastructure for Tattva OS.
> Metrics, traces, profiling, dashboards — all native, no agents.

---

## Projects

| Project | Description |
|---|---|
| [`umetric/`](umetric/) | Metrics collection — counters, gauges, histograms |
| [`utrace/`](utrace/) | Distributed tracing — span collection, trace export |
| [`uprof/`](uprof/) | CPU profiler — sampling profiler, flame graph data |
| [`uflame/`](uflame/) | Flame graph renderer — SVG output from profiler data |
| [`uleak/`](uleak/) | Memory leak detector — tracks allocations, finds leaks |
| [`usym/`](usym/) | Symbol table inspector — resolve addresses to source |
| [`umap_proc/`](umap_proc/) | Process memory map visualizer |
| [`umark/`](umark/) | Benchmark marker — annotate code sections for profiling |
| [`utopology/`](utopology/) | Hardware topology visualizer — NUMA, cores, cache |
| [`utui/`](utui/) | Terminal UI for live metrics display |
| [`udash/`](udash/) | Dashboard — web-based metrics and health view |

---

## Philosophy

Observability is built into the kernel, not bolted on.
Zero overhead when not active. Exact measurements, not estimates.
