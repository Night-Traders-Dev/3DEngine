#!/bin/bash
# test_runtime_stability.sh - Longer runtime coverage for editor and key demos

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

run_stability_case() {
    local label="$1"
    local script_path="$2"
    local expected="$3"
    local duration="$4"

    local output
    output="$(cd "$ROOT_DIR" && stdbuf -oL -eL timeout "$duration" ./run.sh "$script_path" 2>&1)"
    local status=$?

    if [[ "$output" == *"Runtime Error:"* ]] || [[ "$output" == *"signal 11"* ]]; then
        check_fail "$label has no runtime error or crash"
    else
        check_pass
    fi

    if [[ "$output" == *"$expected"* ]]; then
        check_pass
    else
        check_fail "$label reached expected runtime marker"
    fi

    if [[ $status -eq 124 ]]; then
        check_pass
    else
        check_fail "$label stays alive until timeout instead of exiting early"
    fi
}

echo "=== Runtime Stability Checks ==="

run_stability_case "editor stability" "editor.sage" "Font loaded:" 8
run_stability_case "asset demo stability" "examples/demo_assets.sage" "Scene: 24 entities" 8
run_stability_case "voxel demo stability" "examples/demo_voxel.sage" "Voxel world bootstrap:" 8

echo ""
echo "Results: $pass_count passed, $fail_count failed"
if [[ $fail_count -gt 0 ]]; then
    exit 1
fi
echo "All runtime stability checks passed!"
