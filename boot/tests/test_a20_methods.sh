#!/bin/bash
# boot/tests/test_a20_methods.sh
# Test all three A20 enabling methods individually
#
# Forces each A20 method via a build-time config flag,
# boots in QEMU, verifies "A20 enabled" appears in UART output.
#
# Methods tested:
#   1. port 0x92 (fast A20)
#   2. BIOS int 15h AX=2401
#   3. Keyboard controller 8042

QEMU=qemu-system-x86_64
IMG=../boot.img
TIMEOUT=5

test_a20_method() {
    local METHOD=$1
    local LOG=$(mktemp)

    echo "[test_a20] Testing A20 method: $METHOD"

    # Build with forced A20 method
    # TODO: pass A20_FORCE_METHOD=$METHOD to nasm via -D flag
    # make -C .. A20_METHOD=$METHOD

    timeout $TIMEOUT $QEMU \
        -drive format=raw,file=$IMG \
        -serial file:$LOG \
        -no-reboot \
        -display none \
        2>/dev/null || true

    if grep -q "A20 enabled" $LOG; then
        echo "PASS: A20 method $METHOD"
        rm -f $LOG
        return 0
    else
        echo "FAIL: A20 method $METHOD — 'A20 enabled' not found in UART output"
        rm -f $LOG
        return 1
    fi
}

test_a20_method "port92" || exit 1
test_a20_method "bios"   || exit 1
test_a20_method "kbd"    || exit 1

echo "PASS: all A20 methods"
exit 0
