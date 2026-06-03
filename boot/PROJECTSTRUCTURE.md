# Tattva OS — boot/ Complete File Structure

> Bootloader for Tattva OS.
> Targets: x86-64 (BIOS + UEFI), AArch64 (UEFI), RISC-V (OpenSBI)
> Build first: x86-64 BIOS path only. Everything else later.
> Written in NASM first. Replaced by utasm when utasm is ready.

---

## Full Directory + File List

```
boot/
│
├── Makefile                        ← build all boot stages
│                                     targets: all, run, debug, check, clean
│                                     enforces 446 byte stage1 limit
│                                     two QEMU targets: i386 (debug) + x86_64 (run)
│
├── boot.asm                        ← top level entry, includes stage1
├── config.asm                      ← ALL constants in one place
│                                     STAGE1_LOAD     equ 0x7C00
│                                     STAGE1_RELOC    equ 0x0600
│                                     STAGE2_LOAD     equ 0x8000
│                                     KERNEL_LOAD     equ 0x100000
│                                     STACK_TOP       equ 0x7C00
│                                     SURVIVE_PAGE    equ 0x9000
│                                     PANIC_VECTOR    equ 0x500
│                                     never scatter constants across files
│
├── magic.asm                       ← magic numbers for stage verification
│                                     TATTVA_MAGIC    equ 0x54415456
│                                     placed at start of each stage binary
│                                     verified before jumping to next stage
│                                     catches corrupt/wrong stage loads
│
├── linker.ld                       ← linker script for boot binary
│
├── stage1/                         ← MBR bootloader, exactly 512 bytes
│   │                                 HARD LIMIT: 446 bytes for code + data
│   │                                 bytes 446-509: partition table (16 bytes x 4)
│   │                                 bytes 510-511: 0x55AA signature
│   │                                 Makefile enforces this automatically
│   │
│   ├── entry.asm                   ← MBR entry point, org 0x7C00
│   │                                 FIRST INSTRUCTIONS MUST BE:
│   │                                   cli
│   │                                   xor ax, ax
│   │                                   mov ds, ax       ; segment = 0
│   │                                   mov es, ax       ; segment = 0
│   │                                   mov ss, ax       ; segment = 0
│   │                                   mov sp, 0x7C00   ; stack grows down
│   │                                   sti
│   │                                   mov [boot_drive], dl  ; save IMMEDIATELY
│   │                                 segment init BEFORE anything else
│   │                                 DL saved BEFORE any INT call
│   │                                 works in QEMU without this
│   │                                 fails on real hardware without this
│   │
│   ├── boot_drive.asm              ← save + restore boot drive number (DL)
│   │                                 boot_drive db 0
│   │                                 every INT 13h call uses [boot_drive]
│   │                                 never assume DL is still valid
│   │                                 #1 cause of real hardware failures
│   │
│   ├── error.asm                   ← centralized error handler
│   │                                 print error code via UART + VGA
│   │                                 print which operation failed
│   │                                 retry logic for disk reads (3 attempts)
│   │                                 halt on unrecoverable error
│   │                                 without this bugs are invisible
│   │
│   ├── verify.asm                  ← stage1 sanity checks
│   │                                 verify magic number after load
│   │                                 verify stack not corrupted
│   │                                 verify stage2 loaded at right address
│   │
│   ├── disk_read.asm               ← BIOS int 13h LBA read (primary)
│   │                                 always try LBA first (simpler + reliable)
│   │                                 fallback to CHS only if LBA unavailable
│   │                                 retry 3 times on failure before error
│   │                                 use [boot_drive] not DL directly
│   │
│   ├── lba_detect.asm              ← detect LBA extensions support
│   │                                 INT 13h AH=41h BX=55AAh
│   │                                 sets flag for disk_read.asm
│   │
│   ├── load_stage2.asm             ← find stage2 on disk, load to 0x8000
│   │                                 verify magic number after load
│   │                                 jump only if magic matches
│   │
│   ├── relocate.asm                ← relocate MBR self to 0x0600
│   │                                 MUST happen before setting stack
│   │                                 copy 512 bytes 0x7C00 to 0x0600
│   │                                 far jump to 0x0600 + offset
│   │                                 then set stack, not before
│   │
│   ├── print.asm                   ← BIOS int 10h print (debug only)
│   │                                 remove before final build
│   │                                 UART is preferred for debug
│   │
│   └── signature.asm               ← 0x55AA boot signature + padding
│                                     pads stage1 to exactly 512 bytes
│                                     0x55AA at bytes 510-511
│                                     partition table space at 446-509
│
├── stage2/                         ← real mode to protected to long mode
│   ├── entry.asm                   ← stage2 entry point at 0x8000
│   │                                 verify magic number first
│   │                                 re-init segments (do not trust stage1)
│   │                                 set up larger stage2 stack at 0x9C000
│   │
│   ├── main.asm                    ← main stage2 flow, calls in order:
│   │                                 1.  verify magic
│   │                                 2.  init UART (debug output first)
│   │                                 3.  check + enable A20
│   │                                 4.  detect CPU features
│   │                                 5.  detect memory (E820)
│   │                                 6.  setup GDT
│   │                                 7.  setup IDT
│   │                                 8.  setup paging
│   │                                 9.  enable SSE/AVX
│   │                                 10. find + load kernel
│   │                                 11. jump to kernel
│   │
│   ├── stage2_entry_check.asm      ← verify stage2 loaded correctly
│   │                                 check magic number at binary start
│   │                                 check load address is 0x8000
│   │                                 halt with error if wrong
│   │
│   ├── a20/                        ← A20 line enabling
│   │   ├── a20.asm                 ← main A20 handler
│   │   │                             EXECUTION ORDER (strict):
│   │   │                             1. a20_verify first
│   │   │                                QEMU enables A20 by default
│   │   │                                skip all if already enabled
│   │   │                             2. try a20_port92 (fast, simple)
│   │   │                             3. a20_verify, continue if on
│   │   │                             4. try a20_bios
│   │   │                             5. a20_verify, continue if on
│   │   │                             6. try a20_kbd (slowest)
│   │   │                             7. a20_verify, halt if still off
│   │   │                             never skip verify between attempts
│   │   │
│   │   ├── a20_bios.asm            ← BIOS int 15h AX=2401 method
│   │   ├── a20_port92.asm          ← port 0x92 fast A20 method (try first)
│   │   ├── a20_kbd.asm             ← keyboard controller 8042 (slowest)
│   │   └── a20_verify.asm          ← verify A20 actually enabled
│   │                                 compare 0000:7DFE with FFFF:7E0E
│   │                                 rotate value to rule out coincidence
│   │                                 called between EVERY enable attempt
│   │
│   ├── cpu/                        ← CPU feature detection
│   │   ├── cpuid.asm               ← CPUID instruction wrapper
│   │   │                             safe CPUID call with feature check
│   │   │                             stores results for other modules
│   │   │
│   │   ├── longmode.asm            ← check + enable long mode (LME bit)
│   │   │                             verify CPU supports long mode first
│   │   │                             halt with error if not supported
│   │   │
│   │   ├── longmode_sequence.asm   ← EXACT ordered steps for long mode
│   │   │                             MUST follow this order, no shortcuts:
│   │   │                             1. set PAE bit in CR4 (bit 5)
│   │   │                             2. load PML4 address into CR3
│   │   │                             3. set LME bit in EFER MSR 0xC0000080
│   │   │                             4. enable paging + PM in CR0 together
│   │   │                             5. far jump to 64-bit code segment
│   │   │                             any other order = triple fault
│   │   │
│   │   ├── simd_enable.asm         ← enable SSE/AVX before kernel handoff
│   │   │                             kernel uses SIMD from first instruction
│   │   │                             must be done in bootloader not kernel
│   │   │                             clear CR0.EM, set CR0.MP
│   │   │                             set CR4.OSFXSR, CR4.OSXMMEXCPT
│   │   │                             enable AVX via XSETBV if available
│   │   │
│   │   ├── features.asm            ← detect SSE/AVX/AVX2/AVX512/NX/AMX
│   │   │                             store feature flags at FEATURES_DEST
│   │   │                             kernel reads these on startup
│   │   │
│   │   ├── vendor.asm              ← detect Intel vs AMD vs other
│   │   ├── cores.asm               ← logical core count detection
│   │   ├── cache.asm               ← L1/L2/L3 cache size detection
│   │   └── msr.asm                 ← MSR read/write helpers
│   │                                 rdmsr/wrmsr wrappers
│   │                                 used by longmode + features
│   │
│   ├── gdt/                        ← Global Descriptor Table
│   │   ├── gdt.asm                 ← GDT definition and data
│   │   │                             MUST be 8-byte aligned:
│   │   │                               align 8
│   │   │                               gdt_start:
│   │   │                                 dq 0  ; null descriptor
│   │   │                             misalignment causes subtle failures
│   │   │                             on real hardware, works in QEMU
│   │   │
│   │   ├── gdt_load.asm            ← lgdt instruction + far jump
│   │   │                             after far jump reload ALL segments:
│   │   │                               mov ax, DATA_SEG    ; 0x10
│   │   │                               mov ds, ax
│   │   │                               mov es, ax
│   │   │                               mov fs, ax
│   │   │                               mov gs, ax
│   │   │                               mov ss, ax
│   │   │                               mov esp, 0x90000
│   │   │                             forgetting ANY = subtle bugs
│   │   │                             segment caches hold real mode values
│   │   │                             until explicitly reloaded
│   │   │
│   │   ├── gdt_verify.asm          ← verify GDT loaded correctly
│   │   │                             read back descriptor values
│   │   │                             check code + data segment flags
│   │   │                             halt if wrong
│   │   │
│   │   └── selectors.asm           ← segment selector constants
│   │                                 SEL_CODE64  equ 0x08
│   │                                 SEL_DATA64  equ 0x10
│   │                                 SEL_CODE16  equ 0x18
│   │
│   ├── idt/                        ← Interrupt Descriptor Table
│   │   ├── idt.asm                 ← IDT definition and data
│   │   ├── idt_load.asm            ← lidt instruction
│   │   └── idt_handlers.asm        ← basic exception handlers for boot
│   │                                 handler for every exception 0-31
│   │                                 print exception number via UART
│   │                                 halt, do not silently ignore
│   │                                 triple fault = no IDT loaded
│   │
│   ├── paging/                     ← Page table setup
│   │   ├── paging.asm              ← main paging setup, identity map
│   │   │                             identity map first 4GB
│   │   │                             map kernel at high address
│   │   │                             uses 2MB huge pages for speed
│   │   │
│   │   ├── paging_map.asm          ← map virtual to physical regions
│   │   ├── paging_huge.asm         ← 2MB huge page support
│   │   │                             PD entry bit 7 = page size bit
│   │   │                             simpler than 4KB pages
│   │   │                             sufficient for boot stage
│   │   │
│   │   ├── paging_nx.asm           ← NX/XD bit enforcement
│   │   │                             mark non-code pages non-executable
│   │   │                             requires NX support in EFER
│   │   │                             check CPU supports NX first
│   │   │
│   │   └── paging_verify.asm       ← verify page table correctness
│   │                                 walk table, check key mappings
│   │                                 verify kernel address mapped
│   │                                 halt if wrong before jumping
│   │
│   ├── memory/                     ← Physical memory detection
│   │   ├── e820.asm                ← full e820 implementation
│   │   │
│   │   └── mtrr.asm                ← MTRR detection and setup
│   │                                 mark video memory write-combining
│   │                                 optional for benchmark, do later
│   │
│   ├── fs/                         ← Filesystem detection + kernel load
│   │   ├── fs.asm                  ← main FS handler
│   │   │                             tries in strict priority order
│   │   │                             verify magic after each load attempt
│   │   │
│   │   ├── bxp.asm                 ← BXP native format (priority 1)
│   │   ├── gpt.asm                 ← GPT partition table (priority 2)
│   │   │                             protective MBR at LBA 0
│   │   │                             GPT header at LBA 1
│   │   │                             partition entries at LBA 2+
│   │   │
│   │   ├── mbr_part.asm            ← MBR partition table (priority 3)
│   │   ├── fat32.asm               ← FAT32 read (priority 4)
│   │   │                             read BPB, find root cluster
│   │   │                             follow cluster chain
│   │   │                             find kernel file by name
│   │   │
│   │   └── ext2.asm                ← ext2 read (priority 5)
│   │                                 read superblock
│   │                                 find inode for kernel path
│   │                                 load file data blocks
│   │
│   └── hw/                         ← Hardware drivers for boot stage
│       └── uart/                   ← UART serial output
│           ├── uart.asm            ← UART init + send byte
│           │                         init COM1 at 115200 baud 8N1
│           │                         polling mode, no IRQ needed
│           │                         first thing to init in stage2
│           │
│           ├── uart_print.asm      ← print null-terminated string via UART
│           └── uart_hex.asm        ← print hex value via UART
│                                     for printing addresses + error codes
│
├── uefi/                           ← UEFI boot path (x86-64 + AArch64)
│   │                                 build after BIOS path works
│   │
│   ├── entry.asm                   ← UEFI entry point EFI_MAIN
│   ├── protocol.asm                ← UEFI protocol handling
│   ├── console.asm                 ← UEFI console output
│   ├── memory.asm                  ← UEFI GetMemoryMap
│   ├── file.asm                    ← UEFI SimpleFileSystem protocol
│   ├── gop.asm                     ← UEFI Graphics Output Protocol
│   └── handoff.asm                 ← ExitBootServices + jump to kernel
│                                     MUST call ExitBootServices before
│                                     any kernel memory operations
│
├── survive/                        ← Panic recovery — unique to Tattva
│   │                                 build after basic boot works
│   │
│   ├── snapshot.asm                ← snapshot all hardware state to 4KB page
│   │                                 save all registers
│   │                                 save CR0/CR2/CR3/CR4
│   │                                 save EFER, GDTR, IDTR
│   │                                 save stack contents
│   │                                 checksum the snapshot after saving
│   │
│   ├── checksum.asm                ← checksum the snapshot page
│   │                                 CRC32 of snapshot data
│   │                                 verify before any recovery attempt
│   │                                 corrupt snapshot = hard reset
│   │                                 without this recover loads garbage
│   │
│   ├── hide.asm                    ← hide snapshot page from E820 map
│   │                                 modify E820 entries in memory
│   │                                 mark SURVIVE_PAGE as reserved
│   │                                 kernel cannot see or use this page
│   │
│   ├── vector.asm                  ← install panic vector at known address
│   │                                 write handler address to PANIC_VECTOR
│   │                                 kernel writes panic info here on crash
│   │                                 bootloader reads on wakeup
│   │
│   ├── wakeup.asm                  ← panic handler entry point
│   │                                 entered when kernel panics
│   │                                 read panic info from PANIC_VECTOR
│   │                                 log reason, attempt recovery
│   │
│   ├── diff.asm                    ← diff current vs snapshot state
│   │                                 compare all saved registers
│   │                                 identify what changed on panic
│   │                                 log diffs via UART
│   │
│   ├── recover.asm                 ← attempt warm kernel reload
│   │                                 verify snapshot checksum first
│   │                                 reload kernel from disk
│   │                                 restore hardware state from snapshot
│   │                                 jump to kernel entry
│   │
│   ├── reset.asm                   ← hard reset as absolute last resort
│   │                                 keyboard controller reset method
│   │                                 triple fault method as fallback
│   │
│   └── log/
│       └── log.asm                 ← log panic reason to reserved memory
│                                     write to known physical address
│                                     survives warm reset
│                                     read on next boot for diagnostics
│
├── tpm/                            ← TPM 2.0 integration
│   │                                 build after survive/ works
│   │
│   ├── tpm.asm                     ← TPM detect + init
│   ├── tpm_measure.asm             ← measure boot stages into PCRs
│   └── tpm_extend.asm              ← PCR extend operation
│
└── tests/                          ← Boot stage tests
    ├── run_all.sh                  ← run all tests in QEMU automatically
    │                                 boots QEMU, captures UART output
    │                                 compares to expected output
    │                                 exits 0 on pass, 1 on fail
    │                                 run before every git commit
    │
    ├── test_stage1_size.sh         ← verify stage1 binary <= 446 bytes
    │                                 run automatically by Makefile
    │                                 fails build if over limit
    │
    ├── test_boot_qemu.sh           ← boot in QEMU, check UART output
    │                                 expected: "Tattva Boot OK"
    │                                 expected: "A20 enabled"
    │                                 expected: "Long mode OK"
    │
    ├── test_a20_methods.sh         ← test all three A20 methods
    │                                 force each method via config flag
    │                                 verify each works independently
    │
    ├── expected_output/            ← expected UART output per stage
    │   ├── uart_stage1.txt         ← what stage1 should print
    │   └── uart_stage2.txt         ← what stage2 should print
    │
    ├── test_a20.asm                ← verify A20 enable works
    ├── test_paging.asm             ← verify page tables correct
    ├── test_e820.asm               ← verify memory map parsed correctly
    ├── test_fat32.asm              ← verify FAT32 read works
    ├── test_survive.asm            ← verify survive/ snapshot + recover
    └── test_uart.asm               ← verify UART output works
```

---

## Makefile (complete)

```makefile
ASM     = nasm
QEMU64  = qemu-system-x86_64
QEMU32  = qemu-system-i386

STAGE1_MAX = 446

all: boot.img check

# Stage 1
stage1/stage1.bin:
	$(ASM) -f bin stage1/entry.asm \
		-i stage1/ -i . \
		-o stage1/stage1.bin

# Stage 2
stage2/stage2.bin:
	$(ASM) -f bin stage2/entry.asm \
		-i stage2/ -i stage2/a20/ -i stage2/cpu/ \
		-i stage2/gdt/ -i stage2/idt/ -i stage2/paging/ \
		-i stage2/memory/ -i stage2/fs/ -i stage2/hw/uart/ \
		-i . \
		-o stage2/stage2.bin

# Disk image
boot.img: stage1/stage1.bin stage2/stage2.bin
	dd if=/dev/zero of=boot.img bs=512 count=2880
	dd if=stage1/stage1.bin of=boot.img conv=notrunc
	dd if=stage2/stage2.bin of=boot.img bs=512 seek=1 conv=notrunc

# Enforce 446 byte limit — never disable this
check: stage1/stage1.bin
	@size=$$(wc -c < stage1/stage1.bin); \
	if [ $$size -gt $(STAGE1_MAX) ]; then \
		echo "ERROR: stage1 is $$size bytes, max is $(STAGE1_MAX)"; \
		exit 1; \
	fi
	@echo "stage1 size OK: $$(wc -c < stage1/stage1.bin) / $(STAGE1_MAX) bytes"

# Run normally (64-bit)
run: boot.img
	$(QEMU64) -drive format=raw,file=boot.img -serial stdio -no-reboot

# Debug real mode (16-bit — use i386 not x86_64)
debug: boot.img
	$(QEMU32) -drive format=raw,file=boot.img -serial stdio -s -S &
	gdb -ex "set architecture i8086" \
	    -ex "target remote :1234" \
	    -ex "break *0x7C00" \
	    -ex "continue"

# Debug stage2 (32-bit protected mode)
debug32: boot.img
	$(QEMU32) -drive format=raw,file=boot.img -serial stdio -s -S &
	gdb -ex "set architecture i386" \
	    -ex "target remote :1234" \
	    -ex "break *0x8000" \
	    -ex "continue"

# Run tests
test: boot.img
	bash tests/run_all.sh

clean:
	rm -f boot.img stage1/stage1.bin stage2/stage2.bin
```

---

## Key Constants (config.asm)

```asm
; Memory layout — all in one place, never scatter
STAGE1_LOAD     equ 0x7C00      ; BIOS loads MBR here
STAGE1_RELOC    equ 0x0600      ; MBR relocates self here
STAGE2_LOAD     equ 0x8000      ; stage2 loaded here
KERNEL_LOAD     equ 0x100000    ; kernel at 1MB mark
STACK_REAL      equ 0x7C00      ; real mode stack (grows down)
STACK_PROT      equ 0x9C000     ; protected mode stack
STACK_LONG      equ 0x9C000     ; long mode stack
SURVIVE_PAGE    equ 0x9000      ; panic snapshot (hidden from E820)
PANIC_VECTOR    equ 0x500       ; panic handler address lives here
E820_DEST       equ 0x6000      ; E820 entries stored here
FEATURES_DEST   equ 0x5000      ; CPU feature flags stored here

; GDT selectors
SEL_NULL        equ 0x00
SEL_CODE64      equ 0x08        ; 64-bit code
SEL_DATA64      equ 0x10        ; 64-bit data
SEL_CODE16      equ 0x18        ; 16-bit code
SEL_CODE32      equ 0x20        ; 32-bit code

; UART
UART_COM1       equ 0x3F8       ; COM1 base port
UART_BAUD       equ 115200

; Magic numbers
TATTVA_MAGIC    equ 0x54415456  ; "TATV"
STAGE1_MAGIC    equ 0x31535442  ; "BTS1"
STAGE2_MAGIC    equ 0x32535442  ; "BTS2"

; Filesystem priority
FS_BXP          equ 1
FS_GPT          equ 2
FS_MBR_PART     equ 3
FS_FAT32        equ 4
FS_EXT2         equ 5

; Disk
DISK_RETRY      equ 3           ; retry count for disk reads
```

---

## Build Priority

```
Phase 1 — Print "Tattva Boot OK" via UART (week 1-2)
    config.asm + magic.asm
    stage1/entry.asm            ← segment init + DL save first
    stage1/boot_drive.asm
    stage1/error.asm
    stage1/relocate.asm
    stage1/disk_read.asm
    stage1/load_stage2.asm
    stage1/signature.asm
    stage2/entry.asm
    stage2/hw/uart/ (all)       ← init UART as first thing in stage2
    → milestone: "Tattva Boot OK" in QEMU terminal

Phase 2 — Reach long mode (week 3-4)
    stage2/a20/ (all)           ← verify first, then enable
    stage2/cpu/cpuid.asm
    stage2/cpu/longmode.asm
    stage2/cpu/longmode_sequence.asm
    stage2/cpu/simd_enable.asm
    stage2/gdt/ (all)           ← align 8, reload all segs after jump
    stage2/idt/ (all)
    stage2/paging/ (all)
    stage2/memory/e820.asm
    stage2/memory/e820_parse.asm
    stage2/memory/e820_sort.asm
    stage2/memory/e820_merge.asm
    → milestone: "Long mode OK" via UART

Phase 3 — Load kernel from disk (week 5-6)
    stage2/fs/fat32.asm         ← simplest FS, implement first
    stage2/fs/gpt.asm
    stage2/fs/fs.asm
    → milestone: kernel binary loaded and jumped to

Phase 4 — Robustness (week 7-8)
    stage1/verify.asm
    stage2/stage2_entry_check.asm
    stage2/a20/a20_bios.asm     ← additional A20 fallbacks
    stage2/a20/a20_kbd.asm
    stage2/cpu/features.asm
    stage2/cpu/vendor.asm
    stage2/cpu/cores.asm
    stage2/cpu/cache.asm
    stage2/cpu/msr.asm
    stage2/gdt/gdt_verify.asm
    stage2/paging/paging_verify.asm
    stage2/paging/paging_nx.asm
    stage2/memory/e820_print.asm
    → milestone: robust on real hardware

Phase 5 — survive/ panic recovery (week 9-10)
    survive/snapshot.asm
    survive/checksum.asm        ← before recover, always
    survive/hide.asm
    survive/vector.asm
    survive/wakeup.asm
    survive/diff.asm
    survive/recover.asm
    survive/reset.asm
    survive/log/log.asm
    → milestone: panic causes warm reload not hard reset

Phase 6 — Tests (ongoing from week 1)
    tests/run_all.sh
    tests/test_stage1_size.sh
    tests/test_boot_qemu.sh
    tests/expected_output/
    tests/test_*.asm
    → milestone: automated regression testing

Phase 7 — UEFI (after BIOS solid)
Phase 8 — RISC-V (PhD research)
Phase 9 — TPM (security)
```

---

## Critical Rules — Never Violate

```
1. Segment registers initialized FIRST in entry.asm
   before ANY other instruction
   QEMU works without, real hardware does not

2. DL (boot drive) saved IMMEDIATELY after segment init
   before any INT call of any kind
   any BIOS INT can overwrite DL silently

3. A20 verified BEFORE attempting to enable
   QEMU enables A20 by default
   always check first, skip if already enabled

4. GDT must be align 8
   misalignment works in QEMU
   causes failures on some real hardware

5. ALL segment registers reloaded after GDT far jump
   ds, es, fs, gs, ss — every single one
   segment descriptor cache holds real mode values
   until explicitly reloaded with new selector

6. Long mode sequence is STRICTLY ordered
   PAE in CR4 → CR3 → EFER.LME → CR0.PG+PE → far jump
   any other order = triple fault, no error message

7. E820 entries must be sorted then merged
   QEMU returns clean sorted map
   real hardware returns out of order with overlaps
   reserved beats usable in all overlap conflicts

8. stage1 binary MUST be <= 446 bytes
   Makefile enforces automatically
   never disable the size check ever

9. SSE/AVX enabled in bootloader before kernel handoff
   kernel uses SIMD from first instruction
   cannot enable after jumping to kernel

10. survive/checksum.asm runs before recover.asm
    corrupt snapshot + no checksum = loading garbage registers
    always verify checksum before attempting recovery

11. Use qemu-system-i386 for real mode debugging
    qemu-system-x86_64 has GDB issues in 16-bit mode
    use i386 variant for stage1 debugging only

12. BXP is priority 1 in fs.asm
    even though FAT32 is implemented first for development
    priority list in fs.asm never changes
    BXP first, always
```
