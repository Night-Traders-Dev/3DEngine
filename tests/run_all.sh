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

run_test() {
    local test="$1"
    TOTAL=$((TOTAL + 1))
    echo "--- Running: $test ---"
    if [[ "$test" == *.sh ]]; then
        if bash "$test" 2>&1; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
            echo "^^^ FAILED ^^^"
        fi
    else
        if "$SAGE" "$test" 2>&1; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
            echo "^^^ FAILED ^^^"
        fi
    fi
    echo ""
}

for test in tests/test_*.sage; do
    run_test "$test"
done

for test in tests/test_*.sh; do
    if [ -e "$test" ]; then
        run_test "$test"
    fi
done

echo "=============================="
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo "All tests passed!"
