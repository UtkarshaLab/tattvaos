# storage — Storage Category

> Storage subsystem for Tattva OS.
> Filesystem, database, object storage, and NVMe access.

---

## Projects

| Project | Description |
|---|---|
| [`uFS/`](uFS/) | Tattva filesystem — custom, log-structured, NVMe-optimized |
| [`udb/`](udb/) | Sagar — embedded database, B-tree + LSM, purpose-built |
| [`uobject/`](uobject/) | Sangraha — object storage, S3-compatible API |
| [`ubxp/`](ubxp/) | BXP binary format — serialization for storage and network |
| [`uwal/`](uwal/) | Write-ahead log — durability primitive for Sagar |
| [`ummapf/`](ummapf/) | Memory-mapped file abstraction |
| [`unvme/`](unvme/) | NVMe driver — direct hardware access, no block layer |
| [`utiered/`](utiered/) | Tiered storage — hot/warm/cold data placement |

---

## Philosophy

No VFS. No page cache. Direct NVMe queue access.
The filesystem is a first-class citizen of the kernel, not a plugin.
