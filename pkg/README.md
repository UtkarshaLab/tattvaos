# pkg — Package Management Category

> UPM — the Utkarsha Package Manager.
> Binary package format, registry, and tooling for Tattva OS software.

---

## Projects

| Project | Description |
|---|---|
| [`format/`](format/) | `.upk` binary package format specification and parser |
| [`registry/`](registry/) | Package registry — index, publish, resolve, download |
| [`packages/`](packages/) | Built-in packages bundled with Tattva OS |

---

## Package Format

Packages use the `.upk` binary format — compact, integrity-checked, no compression overhead.
Each package contains: metadata header, symbol exports, binary payload.
