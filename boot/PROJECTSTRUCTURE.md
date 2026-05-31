# Tattva OS — boot/ Complete File Structure

> Bootloader for Tattva OS.
> Targets: x86-64 (BIOS + UEFI), AArch64 (UEFI), RISC-V (OpenSBI)
> Build first: x86-64 BIOS path only. Everything else later.

---

## Full Directory + File List

```
boot/
│
├── Makefile                        ← build all boot stages
├── boot.asm                        ← top level entry, includes stage1
├── linker.ld                       ← linker script for boot binary
│
├── stage1/                         ← MBR bootloader, exactly 512 bytes
│   ├── entry.asm                   ← MBR entry point, org 0x7C00
│   ├── disk_read.asm               ← BIOS int 13h CHS + LBA read
│   ├── lba_detect.asm              ← detect LBA extensions support
│   ├── load_stage2.asm             ← find stage2 on disk, load to 0x8000
│   ├── relocate.asm                ← relocate MBR self to 0x0600
│   ├── print.asm                   ← BIOS int 10h print (debug only)
│   └── signature.asm               ← 0x55AA boot signature, padding
│
├── stage2/                         ← real mode → protected → long mode
│   ├── entry.asm                   ← stage2 entry point at 0x8000
│   ├── main.asm                    ← main stage2 flow, calls all below
│   │
│   ├── a20/                        ← A20 line enabling
│   │   ├── a20.asm                 ← main A20 handler, tries all methods
│   │   ├── a20_bios.asm            ← BIOS int 15h AX=2401 method
│   │   ├── a20_port92.asm          ← port 0x92 fast A20 method
│   │   ├── a20_kbd.asm             ← keyboard controller 8042 method
│   │   └── a20_verify.asm          ← verify A20 is actually enabled
│   │
│   ├── cpu/                        ← CPU feature detection
│   │   ├── cpuid.asm               ← CPUID instruction wrapper
│   │   ├── longmode.asm            ← check + enable long mode (LME bit)
│   │   ├── features.asm            ← detect SSE/AVX/AVX2/AVX512/NX/AMX
│   │   ├── vendor.asm              ← detect Intel vs AMD vs other
│   │   ├── cores.asm               ← logical core count detection
│   │   ├── cache.asm               ← L1/L2/L3 cache size detection
│   │   └── msr.asm                 ← MSR read/write helpers
│   │
│   ├── gdt/                        ← Global Descriptor Table
│   │   ├── gdt.asm                 ← GDT definition and data
│   │   ├── gdt_load.asm            ← lgdt instruction + far jump
│   │   └── selectors.asm           ← segment selector constants
│   │
│   ├── idt/                        ← Interrupt Descriptor Table
│   │   ├── idt.asm                 ← IDT definition and data
│   │   ├── idt_load.asm            ← lidt instruction
│   │   └── idt_handlers.asm        ← basic exception handlers for boot
│   │
│   ├── paging/                     ← Page table setup
│   │   ├── paging.asm              ← main paging setup, identity map
│   │   ├── paging_map.asm          ← map specific regions
│   │   ├── paging_huge.asm         ← 2MB huge page support
│   │   ├── paging_nx.asm           ← NX/XD bit enforcement
│   │   └── paging_verify.asm       ← verify page table correctness
│   │
│   ├── memory/                     ← Physical memory detection
│   │   ├── e820.asm                ← BIOS int 15h E820 memory map
│   │   ├── e820_parse.asm          ← parse E820 entries, find usable RAM
│   │   ├── e820_print.asm          ← debug print memory map
│   │   └── mtrr.asm                ← MTRR detection and setup
│   │
│   ├── fs/                         ← Filesystem detection + kernel load
│   │   ├── fs.asm                  ← main FS handler, tries in priority order
│   │   ├── bxp.asm                 ← BXP native format (priority 1)
│   │   ├── gpt.asm                 ← GPT partition table (priority 2)
│   │   ├── mbr_part.asm            ← MBR partition table (priority 3)
│   │   ├── fat32.asm               ← FAT32 read (priority 4)
│   │   └── ext2.asm                ← ext2 read (priority 5)
│   │
│   └── hw/                         ← Hardware drivers for boot stage
│       └── uart/                   ← UART serial output
│           ├── uart.asm            ← UART init + send byte
│           ├── uart_print.asm      ← print string via UART
│           └── uart_hex.asm        ← print hex value via UART
│
├── uefi/                           ← UEFI boot path (x86-64 + AArch64)
│   ├── entry.asm                   ← UEFI entry point EFI_MAIN
│   ├── protocol.asm                ← UEFI protocol handling
│   ├── console.asm                 ← UEFI console output
│   ├── memory.asm                  ← UEFI GetMemoryMap
│   ├── file.asm                    ← UEFI SimpleFileSystem protocol
│   ├── gop.asm                     ← UEFI Graphics Output Protocol
│   └── handoff.asm                 ← ExitBootServices + jump to kernel
│
├── riscv/                          ← RISC-V OpenSBI boot path
│   ├── entry.asm                   ← OpenSBI entry point
│   ├── sbi.asm                     ← SBI ecall wrappers
│   ├── sbi_console.asm             ← SBI console output
│   └── handoff.asm                 ← jump to kernel
│
├── survive/                        ← Panic recovery — unique to Tattva
│   ├── snapshot.asm                ← snapshot all hardware state to 4KB page
│   ├── hide.asm                    ← hide snapshot page from E820 map
│   ├── vector.asm                  ← install panic vector at known address
│   ├── wakeup.asm                  ← panic handler entry point
│   ├── diff.asm                    ← diff current vs snapshot hardware state
│   ├── recover.asm                 ← attempt warm kernel reload
│   ├── reset.asm                   ← hard reset as last resort
│   └── log/
│       └── log.asm                 ← log panic reason to reserved memory
│
├── tpm/                            ← TPM 2.0 integration
│   ├── tpm.asm                     ← TPM detect + init
│   ├── tpm_measure.asm             ← measure boot stages into PCRs
│   └── tpm_extend.asm              ← PCR extend operation
│
└── tests/                          ← Boot stage tests
    ├── test_a20.asm                ← verify A20 enable works
    ├── test_paging.asm             ← verify page tables correct
    ├── test_e820.asm               ← verify memory map parsed correctly
    ├── test_fat32.asm              ← verify FAT32 read works
    ├── test_survive.asm            ← verify survive/ snapshot + recover
    └── test_uart.asm               ← verify UART output works
```

---

## Build Priority — x86-64 BIOS First

```
Phase 1 — Get to long mode (build this first)
    stage1/entry.asm
    stage1/disk_read.asm
    stage1/load_stage2.asm
    stage1/signature.asm
    stage2/entry.asm
    stage2/a20/a20.asm + a20_port92.asm    ← simplest A20 method first
    stage2/cpu/cpuid.asm + longmode.asm
    stage2/gdt/gdt.asm + gdt_load.asm
    stage2/paging/paging.asm + paging_huge.asm
    stage2/memory/e820.asm + e820_parse.asm
    stage2/hw/uart/uart.asm                 ← debug output
    → milestone: print "Tattva Boot OK" via UART in long mode

Phase 2 — Load kernel from disk
    stage2/fs/fat32.asm                     ← simplest FS first
    stage2/fs/gpt.asm                       ← find partition
    → milestone: find + load kernel binary from FAT32 partition

Phase 3 — Survive/ panic recovery
    survive/snapshot.asm
    survive/hide.asm
    survive/vector.asm
    survive/wakeup.asm
    survive/recover.asm
    → milestone: panic → warm reload works

Phase 4 — Additional A20 methods
    stage2/a20/a20_bios.asm
    stage2/a20/a20_kbd.asm
    stage2/a20/a20_verify.asm
    → milestone: robust A20 on all hardware

Phase 5 — UEFI path
    uefi/ (all files)
    → milestone: boots on modern UEFI hardware

Phase 6 — RISC-V path
    riscv/ (all files)
    → milestone: boots on RISC-V hardware

Phase 7 — TPM
    tpm/ (all files)
    → milestone: measured boot chain

Phase 8 — Tests
    tests/ (all files)
    → milestone: all boot stages verified
```

---

## Key Constants

```asm
; Memory layout
STAGE1_LOAD     equ 0x7C00      ; BIOS loads MBR here
STAGE1_RELOC    equ 0x0600      ; MBR relocates itself here
STAGE2_LOAD     equ 0x8000      ; Stage2 loads here
KERNEL_LOAD     equ 0x100000    ; Kernel loads at 1MB mark
STACK_TOP       equ 0x7C00      ; Stack grows down from here
SURVIVE_PAGE    equ 0x9000      ; Hardware snapshot page (hidden from E820)
PANIC_VECTOR    equ 0x500       ; Panic handler address written here

; GDT selectors
SEL_CODE64      equ 0x08        ; 64-bit code segment
SEL_DATA64      equ 0x10        ; 64-bit data segment
SEL_CODE16      equ 0x18        ; 16-bit code (for real mode return if needed)

; UART (COM1)
UART_PORT       equ 0x3F8       ; COM1 base port

; Filesystem priority
FS_BXP          equ 1
FS_GPT          equ 2
FS_MBR          equ 3
FS_FAT32        equ 4
FS_EXT2         equ 5
```

---

## File Sizes (approximate targets)

```
stage1/         → total must be < 446 bytes (MBR constraint)
                  entry.asm + disk_read + load_stage2 + signature
                  signature.asm pads to exactly 512 bytes with 0x55AA

stage2/         → no size constraint, loaded by stage1
                  target < 32KB total for fast load

survive/        → target < 4KB (fits in one snapshot page)

uefi/           → no constraint, UEFI handles loading

Total boot/     → < 64KB ideal
```

---

## Notes

```
1. stage1/ is the hardest — must fit in 446 bytes
   Write disk_read.asm first, it's the most critical
   Use LBA mode, not CHS (simpler, works on all modern hardware)

2. UART is your best friend during development
   Add uart debug prints everywhere
   Remove them before final build
   Serial output visible in QEMU: -serial stdio

3. Test in QEMU first, real hardware later
   qemu-system-x86_64 -drive format=raw,file=boot.img -serial stdio
   Saves enormous time vs flashing real hardware

4. survive/ is novel — implement after basic boot works
   Don't let it block getting to long mode

5. x86-64 BIOS path is what you build NOW
   UEFI, RISC-V, TPM all come later
   Don't create those files yet
   Empty folders are fine as placeholders

6. uboot name conflict resolved — this is just boot/
   Module referred to as tboot internally if needed
```
