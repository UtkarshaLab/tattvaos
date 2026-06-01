#!/bin/bash
# boot/tests/test_stage1_size.sh
# Verify stage1 binary is <= 446 bytes
# Run automatically by Makefile — fails build if over limit

STAGE1_BIN=../stage1/stage1.bin
MAX=446

if [ ! -f "$STAGE1_BIN" ]; then
    echo "FAIL: $STAGE1_BIN not found — run make first"
    exit 1
fi

SIZE=$(wc -c < "$STAGE1_BIN")

if [ "$SIZE" -gt "$MAX" ]; then
    echo "FAIL: stage1 is $SIZE bytes, max is $MAX bytes"
    echo "      $((SIZE - MAX)) bytes over limit"
    exit 1
fi

echo "PASS: stage1 size = $SIZE / $MAX bytes"
exit 0
