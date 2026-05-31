# Tattva OS — lib/io/ Complete File Structure

> Raw I/O primitives. Device abstraction. DMA. Interrupts.
> Depends on: mem only.
> Everything above depends on this.

---

## Full Directory + File List

```
lib/io/
│
├── Makefile                        ← build io module
├── io.asm                          ← top level, includes all below
├── io.inc                          ← public API, structs, constants
│
├── fd/                             ← file descriptor primitives
│   ├── fd.asm                      ← fd table management
│   ├── fd_table.asm                ← fd table (fixed array of fd_t)
│   ├── fd_alloc.asm                ← allocate new fd slot
│   ├── fd_free.asm                 ← release fd slot
│   ├── fd_get.asm                  ← get fd_t from fd number
│   └── fd_dup.asm                  ← duplicate fd
│
├── read/                           ← read operations
│   ├── read.asm                    ← main read dispatcher
│   │                                  dispatches to device driver
│   │                                  based on fd type
│   ├── read_buf.asm                ← buffered read
│   │                                  maintains read buffer per fd
│   │                                  reduces device calls
│   ├── read_exact.asm              ← read exactly N bytes
│   │                                  loops until done or error
│   └── readv.asm                   ← scatter read
│                                      read into multiple buffers
│
├── write/                          ← write operations
│   ├── write.asm                   ← main write dispatcher
│   ├── write_buf.asm               ← buffered write
│   │                                  accumulate writes in buffer
│   │                                  flush when full or explicit
│   ├── write_exact.asm             ← write exactly N bytes
│   └── writev.asm                  ← gather write
│                                      write from multiple buffers
│
├── open/                           ← open + close operations
│   ├── open.asm                    ← open device/file → fd
│   ├── close.asm                   ← close fd, release resources
│   ├── flags.asm                   ← O_RDONLY O_WRONLY O_RDWR
│   │                                  O_CREAT O_TRUNC O_APPEND
│   └── modes.asm                   ← file permission modes
│
├── seek/                           ← seek + tell operations
│   ├── seek.asm                    ← seek to position in fd
│   │                                  SEEK_SET SEEK_CUR SEEK_END
│   └── tell.asm                    ← get current position
│
├── flush/                          ← flush + sync operations
│   ├── flush.asm                   ← flush write buffer to device
│   └── sync.asm                    ← sync to persistent storage
│                                      like fsync
│
├── poll/                           ← poll + select (wait for ready)
│   ├── poll.asm                    ← wait for fd events
│   │                                  POLLIN POLLOUT POLLERR
│   └── poll_table.asm              ← poll event table management
│
├── device/                         ← device abstraction layer
│   ├── device.asm                  ← device registry
│   ├── device_register.asm         ← register a device driver
│   ├── device_find.asm             ← find device by name/type
│   │
│   ├── types/                      ← device type definitions
│   │   ├── block.asm               ← block device interface
│   │   │                              read_block, write_block
│   │   │                              used by disk drivers
│   │   ├── char.asm                ← character device interface
│   │   │                              read_byte, write_byte
│   │   │                              used by UART, keyboard
│   │   └── net.asm                 ← network device interface
│   │                                  send_packet, recv_packet
│   │                                  used by NIC drivers
│   │
│   └── drivers/                    ← device drivers
│       ├── uart/                   ← UART serial driver
│       │   ├── uart.asm            ← UART init + detect
│       │   ├── uart_read.asm       ← read byte from UART
│       │   ├── uart_write.asm      ← write byte to UART
│       │   ├── uart_16550.asm      ← 16550 UART chip support
│       │   └── uart_regs.asm       ← UART register constants
│       │                              COM1=0x3F8 COM2=0x2F8
│       │
│       ├── disk/                   ← disk drivers
│       │   ├── ata.asm             ← ATA/IDE PIO mode driver
│       │   │                          simplest disk driver possible
│       │   │                          used for early boot
│       │   ├── ata_read.asm        ← ATA read sectors
│       │   ├── ata_write.asm       ← ATA write sectors
│       │   ├── ata_identify.asm    ← ATA IDENTIFY command
│       │   ├── ahci.asm            ← AHCI SATA driver
│       │   │                          faster than ATA PIO
│       │   ├── ahci_init.asm       ← AHCI controller init
│       │   ├── ahci_read.asm       ← AHCI DMA read
│       │   ├── ahci_write.asm      ← AHCI DMA write
│       │   └── nvme/               ← NVMe driver (unvme)
│       │       ├── nvme.asm        ← NVMe controller init
│       │       ├── nvme_queue.asm  ← submission + completion queues
│       │       ├── nvme_read.asm   ← NVMe read command
│       │       ├── nvme_write.asm  ← NVMe write command
│       │       └── nvme_regs.asm   ← NVMe register constants
│       │
│       ├── keyboard/               ← PS/2 keyboard driver
│       │   ├── kbd.asm             ← keyboard init
│       │   ├── kbd_read.asm        ← read scancode
│       │   └── kbd_scancode.asm    ← scancode → ASCII translation
│       │
│       └── vga/                    ← VGA text mode driver
│           ├── vga.asm             ← VGA init
│           ├── vga_write.asm       ← write char to VGA buffer
│           ├── vga_scroll.asm      ← scroll VGA screen
│           └── vga_clear.asm       ← clear VGA screen
│
├── dma/                            ← DMA operations
│   ├── dma.asm                     ← DMA controller init
│   ├── dma_alloc.asm               ← allocate DMA-safe buffer
│   │                                  must be physically contiguous
│   │                                  must be below 4GB for 32-bit DMA
│   ├── dma_free.asm                ← free DMA buffer
│   ├── dma_map.asm                 ← map buffer for DMA transfer
│   ├── dma_unmap.asm               ← unmap after transfer complete
│   └── dma_sync.asm                ← sync CPU cache with DMA buffer
│
├── irq/                            ← Interrupt handling
│   ├── irq.asm                     ← IRQ handler dispatch table
│   ├── irq_register.asm            ← register handler for IRQ N
│   ├── irq_enable.asm              ← enable specific IRQ
│   ├── irq_disable.asm             ← disable specific IRQ
│   ├── irq_eoi.asm                 ← send End Of Interrupt to PIC/APIC
│   │
│   ├── pic/                        ← Legacy 8259 PIC
│   │   ├── pic.asm                 ← PIC init + remap to IRQ 32+
│   │   ├── pic_mask.asm            ← mask/unmask IRQ lines
│   │   └── pic_eoi.asm             ← send EOI to PIC
│   │
│   └── apic/                       ← Advanced PIC (modern hardware)
│       ├── apic.asm                ← Local APIC init
│       ├── apic_timer.asm          ← APIC timer setup
│       ├── apic_eoi.asm            ← send EOI to APIC
│       ├── ioapic.asm              ← I/O APIC init
│       └── ioapic_route.asm        ← route IRQ to CPU
│
├── buf/                            ← I/O buffer management
│   ├── buf.asm                     ← buffer pool
│   ├── buf_alloc.asm               ← get buffer from pool
│   ├── buf_free.asm                ← return buffer to pool
│   ├── buf_chain.asm               ← chain multiple buffers
│   │                                  for scatter/gather I/O
│   └── buf_copy.asm                ← copy between buffers
│
├── pipe/                           ← In-kernel pipes
│   ├── pipe.asm                    ← pipe create
│   ├── pipe_read.asm               ← read from pipe
│   ├── pipe_write.asm              ← write to pipe
│   └── pipe_ring.asm               ← ring buffer backing pipe
│
├── mmap/                           ← Memory mapped I/O
│   ├── mmio.asm                    ← map device registers to memory
│   ├── mmio_read8.asm              ← read 8-bit MMIO register
│   ├── mmio_read16.asm             ← read 16-bit MMIO register
│   ├── mmio_read32.asm             ← read 32-bit MMIO register
│   ├── mmio_read64.asm             ← read 64-bit MMIO register
│   ├── mmio_write8.asm             ← write 8-bit MMIO register
│   ├── mmio_write16.asm            ← write 16-bit MMIO register
│   ├── mmio_write32.asm            ← write 32-bit MMIO register
│   └── mmio_write64.asm            ← write 64-bit MMIO register
│
├── port/                           ← x86 I/O port operations
│   ├── port.asm                    ← inb/outb/inw/outw/inl/outl
│   ├── port_in8.asm                ← inb — read byte from port
│   ├── port_in16.asm               ← inw — read word from port
│   ├── port_in32.asm               ← inl — read dword from port
│   ├── port_out8.asm               ← outb — write byte to port
│   ├── port_out16.asm              ← outw — write word to port
│   └── port_out32.asm              ← outl — write dword to port
│
└── tests/                          ← I/O subsystem tests
    ├── test_fd.asm                 ← fd alloc/free/dup tests
    ├── test_uart.asm               ← UART read/write tests
    ├── test_disk.asm               ← disk read/write tests
    │                                  read sector, verify contents
    ├── test_dma.asm                ← DMA alloc/transfer tests
    ├── test_irq.asm                ← IRQ register/fire tests
    ├── test_pipe.asm               ← pipe read/write tests
    └── test_buf.asm                ← buffer pool tests
```

---

## Public API (io.inc)

```asm
; ─────────────────────────────────────────────────────
; File descriptors
; ─────────────────────────────────────────────────────
; fd_open(rdi=device_name, rsi=flags) → rax = fd | -1 error
;   → open device, return fd number
;
; fd_close(rdi=fd) → rax = 0 | -1 error
;   → close fd, release resources
;
; fd_read(rdi=fd, rsi=buf, rdx=len) → rax = bytes_read | -1
;   → read up to len bytes into buf
;
; fd_write(rdi=fd, rsi=buf, rdx=len) → rax = bytes_written | -1
;   → write len bytes from buf
;
; fd_seek(rdi=fd, rsi=offset, rdx=whence) → rax = new_pos | -1
;   → seek to position (SEEK_SET=0, SEEK_CUR=1, SEEK_END=2)
;
; fd_tell(rdi=fd) → rax = position | -1
;   → get current position
;
; fd_flush(rdi=fd) → rax = 0 | -1
;   → flush write buffer

; ─────────────────────────────────────────────────────
; Device
; ─────────────────────────────────────────────────────
; device_register(rdi=device_t ptr) → rax = 0 | -1
;   → register device driver
;
; device_find(rdi=name_ptr) → rax = device_t ptr | 0
;   → find device by name

; ─────────────────────────────────────────────────────
; DMA
; ─────────────────────────────────────────────────────
; dma_alloc(rdi=size) → rax = phys_addr | 0
;   → allocate DMA-safe physically contiguous buffer
;
; dma_free(rdi=phys_addr, rsi=size)
;   → free DMA buffer

; ─────────────────────────────────────────────────────
; IRQ
; ─────────────────────────────────────────────────────
; irq_register(rdi=irq_num, rsi=handler_fn)
;   → register interrupt handler
;
; irq_enable(rdi=irq_num)
; irq_disable(rdi=irq_num)

; ─────────────────────────────────────────────────────
; x86 I/O ports
; ─────────────────────────────────────────────────────
; port_in8(rdi=port) → rax = byte
; port_out8(rdi=port, rsi=byte)
; port_in16(rdi=port) → rax = word
; port_out16(rdi=port, rsi=word)
; port_in32(rdi=port) → rax = dword
; port_out32(rdi=port, rsi=dword)

; ─────────────────────────────────────────────────────
; Pipe
; ─────────────────────────────────────────────────────
; pipe_create(rdi=size) → rax = pipe_t ptr | 0
;   → create pipe with ring buffer of given size
;
; pipe_read(rdi=pipe, rsi=buf, rdx=len) → rax = bytes | -1
; pipe_write(rdi=pipe, rsi=buf, rdx=len) → rax = bytes | -1
```

---

## Key Structs (io.inc)

```asm
; File descriptor entry
struc fd_t
    .type       resd 1          ; FD_BLOCK FD_CHAR FD_NET FD_PIPE
    .flags      resd 1          ; O_RDONLY O_WRONLY O_RDWR
    .device     resq 1          ; pointer to device_t
    .position   resq 1          ; current seek position
    .buf        resq 1          ; pointer to read/write buffer
    .buf_pos    resq 1          ; buffer current position
    .buf_len    resq 1          ; buffer valid bytes
    .private    resq 1          ; driver private data
endstruc

; Device driver interface
struc device_t
    .name       resb 32         ; device name string
    .type       resd 1          ; DEVICE_BLOCK DEVICE_CHAR DEVICE_NET
    .open       resq 1          ; fn pointer: open() → fd
    .close      resq 1          ; fn pointer: close(fd)
    .read       resq 1          ; fn pointer: read(fd, buf, len) → n
    .write      resq 1          ; fn pointer: write(fd, buf, len) → n
    .seek       resq 1          ; fn pointer: seek(fd, off, whence)
    .ioctl      resq 1          ; fn pointer: ioctl(fd, cmd, arg)
    .private    resq 1          ; driver private data
endstruc

; DMA buffer descriptor
struc dma_buf_t
    .phys_addr  resq 1          ; physical address (for device)
    .virt_addr  resq 1          ; virtual address (for CPU)
    .size       resq 1          ; buffer size in bytes
    .flags      resd 1          ; DMA_TO_DEVICE DMA_FROM_DEVICE
endstruc

; I/O buffer
struc iobuf_t
    .data       resq 1          ; pointer to data
    .len        resq 1          ; valid data length
    .cap        resq 1          ; total capacity
    .next       resq 1          ; next buffer in chain
endstruc

; Pipe
struc pipe_t
    .buf        resq 1          ; ring buffer pointer
    .size       resq 1          ; ring buffer size
    .read_pos   resq 1          ; read position
    .write_pos  resq 1          ; write position
    .count      resq 1          ; bytes available to read
endstruc
```

---

## I/O Port Constants (x86-64)

```asm
; Common I/O ports
PORT_PIC1_CMD   equ 0x20        ; PIC1 command
PORT_PIC1_DATA  equ 0x21        ; PIC1 data
PORT_PIC2_CMD   equ 0xA0        ; PIC2 command
PORT_PIC2_DATA  equ 0xA1        ; PIC2 data
PORT_PIT_CH0    equ 0x40        ; PIT channel 0
PORT_PIT_CMD    equ 0x43        ; PIT command
PORT_KBD_DATA   equ 0x60        ; PS/2 keyboard data
PORT_KBD_CMD    equ 0x64        ; PS/2 keyboard command
PORT_UART_COM1  equ 0x3F8       ; COM1 UART base
PORT_UART_COM2  equ 0x2F8       ; COM2 UART base
PORT_ATA_PRI    equ 0x1F0       ; Primary ATA base
PORT_ATA_SEC    equ 0x170       ; Secondary ATA base
PORT_VGA_IDX    equ 0x3D4       ; VGA CRTC index
PORT_VGA_DATA   equ 0x3D5       ; VGA CRTC data

; IRQ numbers (after PIC remap to IRQ 32+)
IRQ_TIMER       equ 32          ; PIT timer
IRQ_KEYBOARD    equ 33          ; PS/2 keyboard
IRQ_SERIAL2     equ 35          ; COM2
IRQ_SERIAL1     equ 36          ; COM1
IRQ_DISK        equ 46          ; Primary ATA
IRQ_SPURIOUS    equ 39          ; Spurious IRQ
```

---

## Build Priority

```
Phase 1 — Absolute minimum (build first)
    port/port_in8.asm           ← needed for UART immediately
    port/port_out8.asm          ← needed for UART immediately
    device/drivers/uart/uart.asm        ← debug output first
    device/drivers/uart/uart_write.asm  ← print to serial
    → milestone: can print debug output

Phase 2 — Interrupt infrastructure
    irq/pic/pic.asm             ← remap PIC to avoid conflicts
    irq/irq.asm                 ← dispatch table
    irq/apic/apic.asm           ← modern interrupt controller
    → milestone: interrupts working

Phase 3 — Disk I/O
    device/drivers/disk/ata.asm         ← simplest disk driver
    device/drivers/disk/ata_read.asm    ← read sectors
    device/drivers/disk/ahci.asm        ← faster SATA
    → milestone: can read from disk

Phase 4 — File descriptor layer
    fd/fd.asm                   ← fd table
    fd/fd_alloc.asm
    fd/fd_free.asm
    open/open.asm
    open/close.asm
    read/read.asm
    write/write.asm
    → milestone: open/read/write via fd

Phase 5 — Buffered I/O
    read/read_buf.asm           ← buffered reads
    write/write_buf.asm         ← buffered writes
    buf/buf.asm                 ← buffer pool
    → milestone: efficient buffered I/O

Phase 6 — DMA
    dma/dma.asm
    dma/dma_alloc.asm
    dma/dma_map.asm
    → milestone: DMA transfers working

Phase 7 — NVMe (critical for model loading)
    device/drivers/nvme/nvme.asm
    device/drivers/nvme/nvme_read.asm
    → milestone: fast NVMe model weight loading

Phase 8 — Tests
    tests/ (all files)
    → milestone: all I/O verified
```

---

## Notes

```
1. UART first — always
   Before anything else works you need debug output
   uart_write.asm is ~20 lines
   It will save you weeks of debugging
   Add uart_print calls everywhere during development

2. ATA PIO before AHCI
   ATA PIO mode is slow but simple (~100 lines)
   Get disk reads working first
   Replace with AHCI DMA later for speed
   Don't let perfect be enemy of working

3. NVMe is critical path for inference
   Model weights are large (gigabytes)
   NVMe is the only way to load them fast enough
   Prioritize nvme/ when doing AI work
   AHCI is too slow for large model loading

4. Device driver interface is the key abstraction
   Everything above talks to device_t not specific hardware
   Adding new hardware = implement device_t interface
   Clean separation, worth getting right first

5. IRQ vs polling
   For early development use polling not IRQs
   Polling is simpler, no interrupt setup needed
   ATA PIO is naturally polling
   Switch to IRQ-driven I/O later for efficiency

6. Buffer pool sizing
   For inference workload:
   buf_alloc returns 4KB buffers by default
   For model weight loading use 1MB buffers
   Make buffer size configurable in buf_create

7. The pipe implementation
   Used for inter-component communication
   Sagar → Garuda communication uses pipes
   Ring buffer backing is cache-friendly
   Size should be power of 2 for fast modulo
```
