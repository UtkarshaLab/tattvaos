# lib — Standard Libraries Category

> Core runtime libraries for Tattva OS.
> No libc. No glibc. Everything reimplemented from scratch in assembly.

---

## Projects

| Project | Description |
|---|---|
| [`mem/`](mem/) | Memory allocator — slab, buddy, arena allocators |
| [`io/`](io/) | I/O primitives — read, write, buffered I/O |
| [`str/`](str/) | String operations — copy, compare, format, search |
| [`umath/`](umath/) | Math library — integer, float, SIMD-vectorized operations |
| [`ulog/`](ulog/) | Logging — structured log output, ring buffer |
| [`urand/`](urand/) | Cryptographic RNG — feeds from hardware entropy |
| [`ufile/`](ufile/) | File abstraction over uFS |
| [`ulib/`](ulib/) | General-purpose library — data structures, algorithms |
| [`utf8/`](utf8/) | UTF-8 encoding/decoding |
| [`time/`](time/) | Time and clock primitives — nanosecond resolution |
| [`cal/`](cal/) | Calendar and date utilities |
| [`ucmp/`](ucmp/) | Compression — LZ4, Zstd, fast block compression |
| [`regex/`](regex/) | Regex engine — minimal, no backtracking |
| [`uparser/`](uparser/) | Parser combinators for config and protocol formats |
| [`hw/`](hw/) | Hardware utility library — shared across drivers |

---

## Philosophy

Zero dependencies. Everything compiles to assembly.
No dynamic linking. All libraries are statically included.
