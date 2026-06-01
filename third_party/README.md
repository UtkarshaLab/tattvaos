# third_party — Third Party Dependencies

> External code vendored into the Tattva OS repository.
> Kept minimal — everything possible is written in-house.

---

## Contents

| Directory | Description |
|---|---|
| [`nasm/`](nasm/) | NASM assembler — used during bootstrap before utasm is ready |

---

## Policy

- All third-party code is vendored at a specific version
- No network fetches at build time
- License must be compatible (GPL-2.0+, MIT, BSD, Apache-2.0)
- Each entry documents its version and upstream URL
