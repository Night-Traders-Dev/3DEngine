#!/bin/bash
# test_startup_smoke.sh - Runtime startup smoke coverage for editor and demos

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pass_count=0
fail_count=0

check_pass() {
    pass_count=$((pass_count + 1))
}

check_fail() {
    echo "  FAIL: $1"
    fail_count=$((fail_count + 1))
}

run_smoke_case() {
    local label="$1"
    local script_path="$2"
    local expected="$3"

    local output
    output="$(cd "$ROOT_DIR" && stdbuf -oL -eL timeout 5 ./run.sh "$script_path" 2>&1)"
    local status=$?

    if [[ "$output" == *"Runtime Error:"* ]]; then
        check_fail "$label has no runtime error"
    else
        check_pass
    fi

    if [[ "$output" == *"$expected"* ]]; then
        check_pass
    else
        check_fail "$label reached expected startup marker"
    fi

    if [[ $status -eq 0 || $status -eq 124 ]]; then
        check_pass
    else
        check_fail "$label exits cleanly or times out after boot"
    fi
}

echo "=== Startup Smoke Checks ==="

run_smoke_case "editor boot" "editor.sage" "Font loaded:"
run_smoke_case "asset demo boot" "examples/demo_assets.sage" "Scene: 24 entities"
run_smoke_case "voxel demo boot" "examples/demo_voxel.sage" "Voxel world bootstrap:"

echo ""
echo "Results: $pass_count passed, $fail_count failed"
if [[ $fail_count -gt 0 ]]; then
    exit 1
fi
echo "All startup smoke checks passed!"
