#!/bin/bash
# run_all.sh - Run all sanity check tests
# Usage: ./tests/run_all.sh

SAGE_DIR="$(cd "$(dirname "$0")/../../sagelang" && pwd)"
SAGE="$SAGE_DIR/sage"
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$SAGE" ]; then
    echo "Error: sage binary not found at $SAGE"
    exit 1
fi

cd "$ENGINE_DIR"

PASS=0
FAIL=0
TOTAL=0

for test in tests/test_*.sage; do
    TOTAL=$((TOTAL + 1))
    echo "--- Running: $test ---"
    if "$SAGE" "$test" 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "^^^ FAILED ^^^"
    fi
    echo ""
done

echo "=============================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo "All tests passed!"
