#!/bin/bash
# boot/tests/run_all.sh
# Run all boot tests in QEMU automatically
#
# Boots QEMU, captures UART output, compares to expected output.
# Exits 0 on pass, 1 on fail.
# Run before every git commit.

set -e

QEMU=qemu-system-x86_64
IMG=../boot.img
UART_LOG=$(mktemp)

echo "=== Tattva Boot Test Suite ==="

# Build first
make -C .. all

# Run stage1 size check
bash test_stage1_size.sh || exit 1

# Run QEMU boot test
bash test_boot_qemu.sh || exit 1

# Run A20 method tests
bash test_a20_methods.sh || exit 1

echo "=== All tests PASSED ==="
exit 0
