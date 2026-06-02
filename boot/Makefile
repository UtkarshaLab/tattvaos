ASM     = nasm
QEMU64  = qemu-system-x86_64
QEMU32  = qemu-system-i386

STAGE1_MAX = 446

all: boot.img check

# Stage 1
stage1/stage1.bin: stage1/entry.asm
	$(ASM) -f bin stage1/entry.asm \
		-i stage1/ -i . \
		-o stage1/stage1.bin

# Stage 2
stage2/stage2.bin: stage2/entry.asm
	$(ASM) -f bin stage2/entry.asm \
		-i stage2/ -i stage2/a20/ -i stage2/cpu/ \
		-i stage2/gdt/ -i stage2/idt/ -i stage2/paging/ \
		-i stage2/memory/ -i stage2/fs/ -i stage2/hw/uart/ \
		-i stage1/ \
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
