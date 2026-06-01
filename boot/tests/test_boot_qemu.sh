#!/bin/bash
# boot/tests/test_boot_qemu.sh
# Boot Tattva OS in QEMU and verify UART output
#
# Expected output (in order):
#   "Tattva Boot OK"
#   "A20 enabled"
#   "Long mode OK"
#
# Uses qemu-system-i386 for real mode stage1 debugging
# Uses qemu-system-x86_64 for long mode verification

QEMU64=qemu-system-x86_64
IMG=../boot.img
TIMEOUT=10
LOG=$(mktemp)

echo "[test_boot_qemu] Booting in QEMU..."

timeout $TIMEOUT $QEMU64 \
    -drive format=raw,file=$IMG \
    -serial file:$LOG \
    -no-reboot \
    -display none \
    2>/dev/null || true

echo "[test_boot_qemu] UART output:"
cat $LOG

# Check expected strings appear in output
PASS=1

grep -q "Tattva Boot OK" $LOG || { echo "FAIL: missing 'Tattva Boot OK'"; PASS=0; }
grep -q "A20 enabled"    $LOG || { echo "FAIL: missing 'A20 enabled'"; PASS=0; }
grep -q "Long mode OK"   $LOG || { echo "FAIL: missing 'Long mode OK'"; PASS=0; }

rm -f $LOG

if [ $PASS -eq 1 ]; then
    echo "PASS: boot test"
    exit 0
else
    exit 1
fi
